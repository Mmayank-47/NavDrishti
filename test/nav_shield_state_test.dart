import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nav_shield/models/nav_shield_state.dart';
import 'package:nav_shield/models/trip_data.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/settings_service.dart';

void main() {
  group('NavShieldState Model Tests', () {
    test('NavShieldState serialization and deserialization matches backend schema', () {
      final state = NavShieldState.initial();
      final json = state.toJson();

      expect(json['latitude'], equals(12.971598));
      expect(json['longitude'], equals(77.594566));
      expect(json['current_mode'], equals('GNSS_AIDED'));
      expect(json['alignment_status'], equals('CALIBRATED'));
      expect(json['sos_countdown_seconds'], equals(30));

      final fromJson = NavShieldState.fromJson(json);
      expect(fromJson.latitude, equals(state.latitude));
      expect(fromJson.longitude, equals(state.longitude));
      expect(fromJson.currentMode, equals(NavMode.gnssAided));
      expect(fromJson.alignmentStatus, equals(AlignmentStatus.calibrated));
    });

    test('Speed conversion km/h and mph', () {
      final state = NavShieldState.initial().copyWith(
        eastVelocity: 10.0,
        northVelocity: 0.0,
      );
      // 10 m/s * 3.6 = 36 km/h
      expect(state.speedKmh, closeTo(36.0, 0.01));
      expect(state.speedMph, closeTo(22.37, 0.01));
    });

    test('VehicleIconStyle enum parsing and labels', () {
      expect(VehicleIconStyle.fromString('arrow'), equals(VehicleIconStyle.arrow));
      expect(VehicleIconStyle.fromString('car'), equals(VehicleIconStyle.car));
      expect(VehicleIconStyle.fromString('bike'), equals(VehicleIconStyle.bike));
      expect(VehicleIconStyle.fromString('unknown'), equals(VehicleIconStyle.arrow));
    });

    test('Halo color palette strictly excludes red and red-adjacent hues', () {
      for (final option in kAllowedHaloColors) {
        final color = option.color;
        // Verify red is not the overwhelmingly dominant channel with low green/blue (i.e. not red/crimson)
        final isRed = color.r > 0.75 && color.g < 0.3 && color.b < 0.3;
        expect(isRed, isFalse, reason: '${option.name} should not be red');
        expect(color.toARGB32() == 0xFFDC2626, isFalse);
        expect(color.toARGB32() == 0xFFEF4444, isFalse);
      }
    });
  });

  group('MockNavShieldDataService Tests', () {
    test('StateStream emits updates and mode toggles correctly', () async {
      final service = MockNavShieldDataService(autoStart: false);

      expect(service.currentState.currentMode, equals(NavMode.gnssAided));

      service.toggleMode();
      expect(service.currentState.currentMode, equals(NavMode.deadReckoning));

      service.toggleMode();
      expect(service.currentState.currentMode, equals(NavMode.gnssAided));

      service.dispose();
    });

    test('Crash and SOS simulation triggers and cancels cleanly', () {
      final service = MockNavShieldDataService(autoStart: false);

      expect(service.currentState.crashDetected, isFalse);
      expect(service.currentState.sosActive, isFalse);

      service.triggerSimulatedCrash();
      expect(service.currentState.crashDetected, isTrue);
      expect(service.currentState.sosActive, isTrue);
      expect(service.currentState.sosCountdownSeconds, equals(30));

      service.cancelSos();
      expect(service.currentState.crashDetected, isFalse);
      expect(service.currentState.sosActive, isFalse);

      service.dispose();
    });

    test('Trip lifecycle transitions: idle -> destinationSet -> active -> completed', () {
      final service = MockNavShieldDataService(autoStart: false);

      // 1. Initially idle
      expect(service.tripStatus, equals(TripStatus.idle));
      expect(service.currentPlannedRoute, isNull);

      // 2. Set Destination
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road');
      expect(service.tripStatus, equals(TripStatus.destinationSet));
      expect(service.currentPlannedRoute, isNotNull);
      expect(service.currentPlannedRoute!.destinationName, equals('MG Road'));
      expect(service.currentPlannedRoute!.waypoints.length, greaterThan(2));
      expect(service.currentPlannedRoute!.totalDistanceKm, greaterThan(0));

      // 3. Start Trip
      service.startTrip();
      expect(service.tripStatus, equals(TripStatus.active));
      expect(service.currentState.distanceTraveledKm, equals(0.0));
      expect(service.routeHistory, isEmpty);

      // 4. End Trip
      final summary = service.endTrip();
      expect(service.tripStatus, equals(TripStatus.completed));
      expect(summary.destinationName, equals('MG Road'));
      expect(summary.plannedRoute.length, greaterThan(2));

      // 5. Reset Trip returns to idle
      service.resetTrip();
      expect(service.tripStatus, equals(TripStatus.idle));
      expect(service.currentPlannedRoute, isNull);

      service.dispose();
    });
  });
}
