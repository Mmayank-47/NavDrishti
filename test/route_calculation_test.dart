import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nav_shield/services/bengaluru_road_data.dart';
import 'package:nav_shield/services/route_calculation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteCalculationService Road-Following Tests', () {
    test('Embedded Bengaluru road network contains realistic road coordinates', () {
      expect(bengaluruRoadCoordinates.length, 312);
      // Origin near Richmond Circle
      expect(bengaluruRoadCoordinates.first[0], closeTo(12.9716, 0.001));
      expect(bengaluruRoadCoordinates.first[1], closeTo(77.5944, 0.001));
      // Point 51 near MG Road Metro
      expect(bengaluruRoadCoordinates[51][0], closeTo(12.9753, 0.001));
      expect(bengaluruRoadCoordinates[51][1], closeTo(77.6074, 0.001));
    });

    test('calculateRoute towards MG Road Metro strictly follows real road polyline', () {
      const origin = LatLng(12.97162, 77.594461);
      const destination = LatLng(12.9756, 77.6066); // MG Road Metro

      final plannedRoute = RouteCalculationService.calculateRoute(
        origin: origin,
        destination: destination,
        destinationName: 'MG Road Metro',
      );

      // Must have detailed street waypoints (over 40 waypoints along Kasturba & MG Road)
      expect(plannedRoute.waypoints.length, greaterThan(40));
      expect(plannedRoute.destinationName, 'MG Road Metro');

      // The road distance must be ~1.6 - 1.9 km (longer than Euclidean 1.3 km because it follows streets)
      expect(plannedRoute.totalDistanceKm, greaterThan(1.5));
      expect(plannedRoute.totalDistanceKm, lessThan(2.2));

      // Check intermediate coordinates: every waypoint should stay within the road bounding box
      // and not jump diagonally across city blocks
      for (int i = 0; i < plannedRoute.waypoints.length - 1; i++) {
        final wp1 = plannedRoute.waypoints[i];
        final wp2 = plannedRoute.waypoints[i + 1];
        final stepMeters = const Distance().as(LengthUnit.Meter, wp1, wp2);
        // Consecutive waypoints on the road should be close together (never huge 500m diagonal jumps)
        expect(stepMeters, lessThan(250.0), reason: 'Waypoint step $i -> ${i + 1} was $stepMeters m');
      }
    });

    test('calculateRoadRoute gracefully falls back to road network', () async {
      const origin = LatLng(12.97162, 77.594461);
      const destination = LatLng(12.9756, 77.6066);

      final route = await RouteCalculationService.calculateRoadRoute(
        origin: origin,
        destination: destination,
        destinationName: 'MG Road Metro',
      );

      expect(route.waypoints.isNotEmpty, true);
      expect(route.totalDistanceKm, greaterThan(1.5));
      expect(route.estimatedDuration.inMinutes, greaterThan(0));
    });
  });
}
