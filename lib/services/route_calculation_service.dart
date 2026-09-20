import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../config/mapbox_config.dart';
import '../models/trip_data.dart';
import 'bengaluru_road_data.dart';

/// Service for calculating planned navigation routes, distances, and ETAs.
///
/// Principles:
/// - NEVER cuts diagonally through buildings.
/// - Queries Mapbox Directions API for live road routing when online and configured.
/// - Seamlessly falls back to high-resolution road-snapped coordinates from the
///   bundled Bengaluru road network dataset (`bengaluru_demo_route.json` / `bengaluruRoadCoordinates`).
class RouteCalculationService {
  static const Distance _distCalc = Distance();
  static List<LatLng>? _roadNetworkCache;

  /// Ensure road network is initialized in memory from embedded constant.
  static void init() {
    if (_roadNetworkCache == null || _roadNetworkCache!.isEmpty) {
      _roadNetworkCache = bengaluruRoadCoordinates
          .map((c) => LatLng(c[0], c[1]))
          .toList();
    }
  }

  /// Loads full road network from asset if available.
  static Future<void> loadRoadNetwork() async {
    init();
    try {
      final jsonStr = await rootBundle.loadString('assets/data/bengaluru_demo_route.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final points = data['points'] as List<dynamic>;
      _roadNetworkCache = points.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
      }).toList();
    } catch (_) {
      // Fallback already populated by init()
    }
  }

  /// Calculates a road-following planned route using Mapbox Directions API,
  /// falling back to offline road network snapping if offline or unavailable.
  static Future<PlannedRoute> calculateRoadRoute({
    required LatLng origin,
    required LatLng destination,
    required String destinationName,
  }) async {
    // 1. Try Mapbox Directions API if access token is configured
    if (mapboxAccessToken.isNotEmpty &&
        mapboxAccessToken.startsWith('pk.') &&
        !mapboxAccessToken.contains('DemoToken') &&
        mapboxAccessToken.length > 35) {
      try {
        final uri = Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
          '?geometries=geojson&overview=full&access_token=$mapboxAccessToken',
        );

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final request = await client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final routes = data['routes'] as List<dynamic>?;
          if (routes != null && routes.isNotEmpty) {
            final route = routes.first as Map<String, dynamic>;
            final geometry = route['geometry'] as Map<String, dynamic>;
            final coords = geometry['coordinates'] as List<dynamic>;
            final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0.0;
            final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 60.0;

            final waypoints = <LatLng>[];
            for (final c in coords) {
              final lon = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              waypoints.add(LatLng(lat, lon));
            }

            if (waypoints.isNotEmpty) {
              return PlannedRoute(
                destination: destination,
                destinationName: destinationName,
                waypoints: waypoints,
                totalDistanceKm: distanceMeters / 1000.0,
                estimatedDuration: Duration(seconds: durationSeconds.round()),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[RouteCalculationService] Mapbox directions error, falling back to road network: $e');
      }
    }

    // 2. Fallback to offline road network
    return calculateRoute(
      origin: origin,
      destination: destination,
      destinationName: destinationName,
    );
  }

  /// Synchronous route calculation: snaps to real street coordinates
  /// along the Bengaluru road network.
  static PlannedRoute calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required String destinationName,
  }) {
    init();
    final road = _roadNetworkCache!;

    // Find closest index on road to origin and destination
    int bestOriginIdx = 0;
    double minOriginDist = double.infinity;
    int bestDestIdx = 0;
    double minDestDist = double.infinity;

    for (int i = 0; i < road.length; i++) {
      final dOrigin = _distCalc.as(LengthUnit.Meter, origin, road[i]);
      if (dOrigin < minOriginDist) {
        minOriginDist = dOrigin;
        bestOriginIdx = i;
      }
      final dDest = _distCalc.as(LengthUnit.Meter, destination, road[i]);
      if (dDest < minDestDist) {
        minDestDist = dDest;
        bestDestIdx = i;
      }
    }

    final waypoints = <LatLng>[];

    // Build road path between bestOriginIdx and bestDestIdx
    if (bestOriginIdx <= bestDestIdx) {
      waypoints.addAll(road.sublist(bestOriginIdx, bestDestIdx + 1));
    } else {
      // Loop or reverse: check forward distance around loop vs backward
      final forwardLen = (road.length - bestOriginIdx) + bestDestIdx + 1;
      final backwardLen = bestOriginIdx - bestDestIdx + 1;
      if (forwardLen <= backwardLen) {
        waypoints.addAll(road.sublist(bestOriginIdx));
        waypoints.addAll(road.sublist(0, bestDestIdx + 1));
      } else {
        waypoints.addAll(road.sublist(bestDestIdx, bestOriginIdx + 1).reversed);
      }
    }

    // Ensure origin and destination endpoints are smoothly included
    if (waypoints.isEmpty || waypoints.first != origin) {
      if (minOriginDist > 15.0) {
        waypoints.insert(0, origin);
      }
    }
    if (waypoints.last != destination) {
      if (minDestDist > 15.0) {
        waypoints.add(destination);
      }
    }

    // Calculate total polyline distance
    double totalMeters = 0.0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      totalMeters += _distCalc.as(LengthUnit.Meter, waypoints[i], waypoints[i + 1]);
    }

    final totalKm = totalMeters / 1000.0;
    final minutes = math.max(1, (totalKm / (32.0 / 60.0)).round());

    return PlannedRoute(
      destination: destination,
      destinationName: destinationName,
      waypoints: waypoints,
      totalDistanceKm: totalKm,
      estimatedDuration: Duration(minutes: minutes),
    );
  }
}
