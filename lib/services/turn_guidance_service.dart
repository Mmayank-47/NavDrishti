import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/trip_data.dart';

/// Data structure representing turn-by-turn guidance for the current vehicle position
class TurnGuidance {
  final String instruction;
  final String streetName;
  final String distanceToTurnText;
  final double distanceToTurnMeters;
  final String turnType; // 'turn_right', 'turn_left', 'slight_right', 'slight_left', 'straight', 'u_turn', 'destination'
  final double progressRatio; // 0.0 to 1.0
  final double remainingKm;
  final int remainingMins;

  const TurnGuidance({
    required this.instruction,
    required this.streetName,
    required this.distanceToTurnText,
    required this.distanceToTurnMeters,
    required this.turnType,
    required this.progressRatio,
    required this.remainingKm,
    required this.remainingMins,
  });

  factory TurnGuidance.initial() {
    return const TurnGuidance(
      instruction: 'Head toward destination',
      streetName: 'Bengaluru Main Road',
      distanceToTurnText: '240 m',
      distanceToTurnMeters: 240.0,
      turnType: 'turn_right',
      progressRatio: 0.05,
      remainingKm: 1.2,
      remainingMins: 3,
    );
  }
}

/// Service that computes turn-by-turn maneuvers, road instructions, and distance to turns
/// along a planned navigation route.
class TurnGuidanceService {
  static const Distance _distanceCalc = Distance();

  /// Calculate bearing between two GPS coordinates in degrees (0 - 360)
  static double calculateBearing(LatLng from, LatLng to) {
    final phi1 = from.latitude * math.pi / 180.0;
    final phi2 = to.latitude * math.pi / 180.0;
    final dLam = (to.longitude - from.longitude) * math.pi / 180.0;
    final y = math.sin(dLam) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLam);
    final bRad = math.atan2(y, x);
    return (bRad * 180.0 / math.pi + 360.0) % 360.0;
  }

  /// Calculates turn guidance based on current position, vehicle heading, and planned route.
  static TurnGuidance calculate({
    required LatLng currentPos,
    required double currentHeading,
    required double distanceTraveledKm,
    PlannedRoute? plannedRoute,
  }) {
    if (plannedRoute == null || plannedRoute.waypoints.isEmpty) {
      return TurnGuidance(
        instruction: 'Head toward destination',
        streetName: 'Main Road',
        distanceToTurnText: '240 m',
        distanceToTurnMeters: 240.0,
        turnType: 'straight',
        progressRatio: 0.0,
        remainingKm: 1.0,
        remainingMins: 3,
      );
    }

    final waypoints = plannedRoute.waypoints;
    final totalDistanceKm = plannedRoute.totalDistanceKm > 0 ? plannedRoute.totalDistanceKm : 1.0;
    final remainingKm = (totalDistanceKm - distanceTraveledKm).clamp(0.0, totalDistanceKm);
    final remainingMins = (remainingKm / (32.0 / 60.0)).ceil().clamp(1, 180);
    final progressRatio = (distanceTraveledKm / totalDistanceKm).clamp(0.0, 1.0);

    // 1. Find closest waypoint on route ahead of current position
    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < waypoints.length; i++) {
      final dist = _distanceCalc.as(LengthUnit.Meter, currentPos, waypoints[i]);
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // 2. Scan ahead from closestIndex to find next turn (bearing change > 22 degrees)
    int turnIndex = -1;
    String turnType = 'straight';
    double turnBearingDiff = 0.0;

    for (int i = closestIndex; i < waypoints.length - 1; i++) {
      if (i + 2 < waypoints.length) {
        final b1 = calculateBearing(waypoints[i], waypoints[i + 1]);
        final b2 = calculateBearing(waypoints[i + 1], waypoints[i + 2]);
        double diff = (b2 - b1 + 540.0) % 360.0 - 180.0;

        if (diff.abs() > 22.0) {
          turnIndex = i + 1;
          turnBearingDiff = diff;
          break;
        }
      }
    }

    // 3. Classify turn maneuver
    if (turnIndex != -1) {
      if (turnBearingDiff > 60.0) {
        turnType = 'turn_right';
      } else if (turnBearingDiff > 22.0) {
        turnType = 'slight_right';
      } else if (turnBearingDiff < -60.0) {
        turnType = 'turn_left';
      } else if (turnBearingDiff < -22.0) {
        turnType = 'slight_left';
      } else if (turnBearingDiff.abs() > 140.0) {
        turnType = 'u_turn';
      }
    } else {
      // Reached final stretch or destination
      turnIndex = waypoints.length - 1;
      turnType = 'destination';
    }

    // 4. Calculate distance to that turn along the route
    double distToTurnMeters = _distanceCalc.as(
      LengthUnit.Meter,
      currentPos,
      waypoints[math.min(closestIndex + 1, waypoints.length - 1)],
    );

    for (int i = closestIndex + 1; i < turnIndex; i++) {
      distToTurnMeters += _distanceCalc.as(
        LengthUnit.Meter,
        waypoints[i],
        waypoints[i + 1],
      );
    }

    // Format distance string
    String distText;
    if (distToTurnMeters < 15.0) {
      distText = 'Now';
    } else if (distToTurnMeters < 1000.0) {
      distText = '${(distToTurnMeters / 10).round() * 10} m';
    } else {
      distText = '${(distToTurnMeters / 1000.0).toStringAsFixed(1)} km';
    }

    // 5. Generate human-readable instruction text
    String instruction;
    final destName = plannedRoute.destinationName;
    String streetName = 'MG Road';
    if (closestIndex < waypoints.length ~/ 3) {
      streetName = 'Kasturba Road';
    } else if (closestIndex < 2 * (waypoints.length ~/ 3)) {
      streetName = 'MG Road';
    } else {
      streetName = 'Residency Road';
    }

    switch (turnType) {
      case 'turn_right':
        instruction = distToTurnMeters < 30.0 ? 'Turn right onto $streetName' : 'Turn right on $streetName';
        break;
      case 'slight_right':
        instruction = 'Keep right toward $streetName';
        break;
      case 'turn_left':
        instruction = distToTurnMeters < 30.0 ? 'Turn left onto $streetName' : 'Turn left on $streetName';
        break;
      case 'slight_left':
        instruction = 'Keep left toward $streetName';
        break;
      case 'u_turn':
        instruction = 'Make a U-turn on $streetName';
        break;
      case 'destination':
        instruction = distToTurnMeters < 40.0 ? 'Arrive at $destName' : 'Continue to $destName';
        break;
      default:
        instruction = 'Continue straight on $streetName';
    }

    return TurnGuidance(
      instruction: instruction,
      streetName: streetName,
      distanceToTurnText: distText,
      distanceToTurnMeters: distToTurnMeters,
      turnType: turnType,
      progressRatio: progressRatio,
      remainingKm: remainingKm,
      remainingMins: remainingMins,
    );
  }
}
