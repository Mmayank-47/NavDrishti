import 'package:latlong2/latlong.dart';
import 'nav_shield_state.dart';

/// Single historical track point with navigation mode
class RoutePoint {
  final LatLng point;
  final NavMode mode;
  final DateTime timestamp;

  const RoutePoint({
    required this.point,
    required this.mode,
    required this.timestamp,
  });
}

/// Lifecycle state of a navigation trip
enum TripStatus {
  idle,
  destinationSet,
  active,
  completed,
}

/// Pre-calculated route to a selected destination
class PlannedRoute {
  final LatLng destination;
  final String destinationName;
  final List<LatLng> waypoints;
  final double totalDistanceKm;
  final Duration estimatedDuration;

  const PlannedRoute({
    required this.destination,
    required this.destinationName,
    required this.waypoints,
    required this.totalDistanceKm,
    required this.estimatedDuration,
  });
}


/// Trip summary data structure calculated from a completed navigation session
class TripSummary {
  final double totalDistanceKm;
  final Duration totalDuration;
  final Duration gnssAidedDuration;
  final Duration deadReckoningDuration;
  final double maxDriftPercent;
  final List<RoutePoint> route;
  final String destinationName;
  final LatLng? destination;
  final bool destinationReached;
  final List<LatLng> plannedRoute;

  const TripSummary({
    required this.totalDistanceKm,
    required this.totalDuration,
    required this.gnssAidedDuration,
    required this.deadReckoningDuration,
    required this.maxDriftPercent,
    required this.route,
    this.destinationName = 'Unknown Destination',
    this.destination,
    this.destinationReached = false,
    this.plannedRoute = const [],
  });

  /// Ratio of GNSS-denied (Dead Reckoning) time to total trip duration (0.0 to 1.0)
  double get gnssDeniedRatio {
    final totalSec = totalDuration.inSeconds;
    if (totalSec == 0) return 0.0;
    return (deadReckoningDuration.inSeconds / totalSec).clamp(0.0, 1.0);
  }

  /// Ratio of GNSS-aided time to total trip duration (0.0 to 1.0)
  double get gnssAidedRatio {
    final totalSec = totalDuration.inSeconds;
    if (totalSec == 0) return 1.0;
    return (gnssAidedDuration.inSeconds / totalSec).clamp(0.0, 1.0);
  }

  TripSummary copyWith({
    double? totalDistanceKm,
    Duration? totalDuration,
    Duration? gnssAidedDuration,
    Duration? deadReckoningDuration,
    double? maxDriftPercent,
    List<RoutePoint>? route,
    String? destinationName,
    LatLng? destination,
    bool? destinationReached,
    List<LatLng>? plannedRoute,
  }) {
    return TripSummary(
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      totalDuration: totalDuration ?? this.totalDuration,
      gnssAidedDuration: gnssAidedDuration ?? this.gnssAidedDuration,
      deadReckoningDuration: deadReckoningDuration ?? this.deadReckoningDuration,
      maxDriftPercent: maxDriftPercent ?? this.maxDriftPercent,
      route: route ?? this.route,
      destinationName: destinationName ?? this.destinationName,
      destination: destination ?? this.destination,
      destinationReached: destinationReached ?? this.destinationReached,
      plannedRoute: plannedRoute ?? this.plannedRoute,
    );
  }
}
