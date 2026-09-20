import 'dart:async';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import 'nav_shield_data_service.dart';

import 'route_calculation_service.dart';

/// 10Hz Mock Data Service simulating NAV-SHIELD Python Dead Reckoning Engine.
///
/// Simulates:
/// - Smooth 10Hz coordinates along a realistic driving loop or planned route
/// - Proper trip lifecycle (idle -> destinationSet -> active -> completed)
/// - Trip-scoped distance and drift accumulation starting only upon Start Navigation
/// - Auto-toggling between GNSS_AIDED and DEAD_RECKONING every ~25s
/// - Uncertainty ellipse expansion during DEAD_RECKONING and collapse during GNSS_AIDED
/// - Drift accumulation and distance tracking
/// - SOS countdown timer and impact trigger
/// - 10-second calibration routine
class MockNavShieldDataService implements NavShieldDataService {
  final StreamController<NavShieldState> _controller = StreamController<NavShieldState>.broadcast();
  final StreamController<TripStatus> _tripStatusController = StreamController<TripStatus>.broadcast();
  Timer? _ticker;
  Timer? _sosTimer;
  Timer? _calibrationTimer;

  // Trip lifecycle state
  TripStatus _tripStatus = TripStatus.idle;
  PlannedRoute? _currentPlannedRoute;
  int _currentWaypointIndex = 0;

  // Internal simulation state
  NavShieldState _state = NavShieldState.initial();
  final List<RoutePoint> _routeHistory = [];
  DateTime _tripStartTime = DateTime.now();
  int _gnssAidedSeconds = 0;
  int _deadReckoningSeconds = 0;
  double _maxDriftSeen = 0.2;

  // Path simulation variables
  double _simLatitude = 12.97162;
  double _simLongitude = 77.594461;
  double _simHeading = 12.67; // degrees
  double _simSpeedMs = 12.0; // ~43.2 km/h
  int _ticksInCurrentMode = 0;
  final int _ticksPerModeCycle = 250; // 25 seconds @ 10Hz
  int _tickCount = 0;

  // Calibration countdown
  int _calibrationProgressSeconds = 0;

  MockNavShieldDataService({bool autoStart = true}) {
    if (autoStart) {
      start();
    }
  }

  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  @override
  Stream<NavShieldState> get stateStream => _controller.stream;

  @override
  NavShieldState get currentState => _state;

  @override
  List<RoutePoint> get routeHistory => List.unmodifiable(_routeHistory);

  @override
  TripStatus get tripStatus => _tripStatus;

  @override
  Stream<TripStatus> get tripStatusStream => _tripStatusController.stream;

  @override
  PlannedRoute? get currentPlannedRoute => _currentPlannedRoute;

  @override
  void setDestination(LatLng destination, String name) {
    _currentPlannedRoute = RouteCalculationService.calculateRoute(
      origin: LatLng(_simLatitude, _simLongitude),
      destination: destination,
      destinationName: name,
    );
    _currentWaypointIndex = 0;
    _tripStatus = TripStatus.destinationSet;
    _tripStatusController.add(_tripStatus);

    RouteCalculationService.calculateRoadRoute(
      origin: LatLng(_simLatitude, _simLongitude),
      destination: destination,
      destinationName: name,
    ).then((route) {
      if (_tripStatus == TripStatus.destinationSet || _tripStatus == TripStatus.active) {
        _currentPlannedRoute = route;
        _tripStatusController.add(_tripStatus);
      }
    });
  }

  @override
  void startTrip() {
    _tripStatus = TripStatus.active;
    _tripStartTime = DateTime.now();
    _routeHistory.clear();
    _gnssAidedSeconds = 0;
    _deadReckoningSeconds = 0;
    _maxDriftSeen = 0.2;
    _currentWaypointIndex = 0;

    if (_currentPlannedRoute != null && _currentPlannedRoute!.waypoints.isNotEmpty) {
      _simLatitude = _currentPlannedRoute!.waypoints.first.latitude;
      _simLongitude = _currentPlannedRoute!.waypoints.first.longitude;
      if (_currentPlannedRoute!.waypoints.length > 1) {
        _currentWaypointIndex = 1;
        _simHeading = _calculateBearing(
          _simLatitude,
          _simLongitude,
          _currentPlannedRoute!.waypoints[1].latitude,
          _currentPlannedRoute!.waypoints[1].longitude,
        );
      }
    }

    _state = _state.copyWith(
      latitude: _simLatitude,
      longitude: _simLongitude,
      heading: _simHeading,
      distanceTraveledKm: 0.0,
      driftEstimatePercent: 0.2,
    );
    _tripStatusController.add(_tripStatus);
    _controller.add(_state);
  }

  @override
  void cancelDestination() {
    _currentPlannedRoute = null;
    _tripStatus = TripStatus.idle;
    _tripStatusController.add(_tripStatus);
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dLam = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLam) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLam);
    final bRad = math.atan2(y, x);
    return (bRad * 180 / math.pi + 360) % 360;
  }

  void _onTick(Timer timer) {
    _tickCount++;

    // When trip is not active, vehicle is idling at origin (0 km distance, no track history)
    if (_tripStatus != TripStatus.active) {
      _state = _state.copyWith(
        latitude: _simLatitude,
        longitude: _simLongitude,
        heading: _simHeading,
        distanceTraveledKm: 0.0,
        driftEstimatePercent: 0.2,
        timestamp: DateTime.now(),
      );
      _controller.add(_state);
      return;
    }

    _ticksInCurrentMode++;

    // 1. Check auto-toggle mode every ~25-30s if not manually forced
    if (_ticksInCurrentMode >= _ticksPerModeCycle) {
      _ticksInCurrentMode = 0;
      final newMode = _state.currentMode == NavMode.gnssAided
          ? NavMode.deadReckoning
          : NavMode.gnssAided;
      _state = _state.copyWith(
        currentMode: newMode,
        timeInCurrentMode: 0,
      );
    } else if (_tickCount % 10 == 0) {
      // Every 1 second
      _state = _state.copyWith(
        timeInCurrentMode: _state.timeInCurrentMode + 1,
      );
      if (_state.currentMode == NavMode.deadReckoning) {
        _deadReckoningSeconds++;
      } else {
        _gnssAidedSeconds++;
      }
    }

    // 2. Realistic road-following vehicle advancement
    // Speed variations around ~41.4 km/h (~11.5 m/s)
    _simSpeedMs = 11.5 + 2.0 * math.sin(_tickCount / 50.0);
    const dtSeconds = 0.1;
    double stepDistanceMeters = _simSpeedMs * dtSeconds; // ~1.15m per 100ms tick

    // Get active list of waypoints to follow:
    // If a planned route exists, follow it. Otherwise, follow the default Bengaluru road circuit.
    final List<LatLng> activePath = (_currentPlannedRoute != null && _currentPlannedRoute!.waypoints.isNotEmpty)
        ? _currentPlannedRoute!.waypoints
        : RouteCalculationService.calculateRoute(
            origin: const LatLng(12.97162, 77.594461),
            destination: const LatLng(12.975312, 77.607443),
            destinationName: 'Central Circuit',
          ).waypoints;

    if (activePath.length >= 2) {
      if (_currentWaypointIndex < 1) _currentWaypointIndex = 1;

      while (stepDistanceMeters > 0 && _currentWaypointIndex < activePath.length) {
        final targetPt = activePath[_currentWaypointIndex];
        final currentPos = LatLng(_simLatitude, _simLongitude);
        final distToTarget = const Distance().as(LengthUnit.Meter, currentPos, targetPt);

        if (distToTarget <= stepDistanceMeters) {
          _simLatitude = targetPt.latitude;
          _simLongitude = targetPt.longitude;
          stepDistanceMeters -= distToTarget;

          if (_currentWaypointIndex < activePath.length - 1) {
            _currentWaypointIndex++;
            _simHeading = _calculateBearing(
              _simLatitude,
              _simLongitude,
              activePath[_currentWaypointIndex].latitude,
              activePath[_currentWaypointIndex].longitude,
            );
          } else {
            // Reached destination endpoint
            if (_currentPlannedRoute == null) {
              _currentWaypointIndex = 0;
            } else {
              stepDistanceMeters = 0;
              break;
            }
          }
        } else {
          // Advance along current road segment towards targetPt
          final ratio = (stepDistanceMeters / distToTarget).clamp(0.0, 1.0);
          _simLatitude += ratio * (targetPt.latitude - _simLatitude);
          _simLongitude += ratio * (targetPt.longitude - _simLongitude);
          _simHeading = _calculateBearing(
            _simLatitude,
            _simLongitude,
            targetPt.latitude,
            targetPt.longitude,
          );
          stepDistanceMeters = 0;
        }
      }
    }

    final rad = _simHeading * math.pi / 180.0;
    final eastVel = _simSpeedMs * math.sin(rad);
    final northVel = _simSpeedMs * math.cos(rad);

    final stepKm = (_simSpeedMs * dtSeconds) / 1000.0;
    final newDistanceKm = _state.distanceTraveledKm + stepKm;

    // 3. Dynamic Uncertainty Ellipse logic
    // During DEAD_RECKONING: grows steadily as sensor drift accumulates
    // During GNSS_AIDED: collapses quickly back to tight bound (~3.5m)
    double majorAxis;
    double minorAxis;
    double drift;

    if (_state.currentMode == NavMode.deadReckoning) {
      final drSec = _state.timeInCurrentMode;
      majorAxis = (4.0 + (drSec * 1.1)).clamp(4.0, 38.0);
      minorAxis = (2.5 + (drSec * 0.65)).clamp(2.5, 22.0);
      drift = (0.3 + (drSec * 0.12)).clamp(0.2, 5.8);
    } else {
      majorAxis = 3.5 + 0.5 * math.sin(_tickCount / 10.0);
      minorAxis = 2.2 + 0.3 * math.cos(_tickCount / 10.0);
      drift = 0.2;
    }

    if (drift > _maxDriftSeen) {
      _maxDriftSeen = drift;
    }

    final newEllipse = UncertaintyEllipse(
      semiMajorAxis: majorAxis,
      semiMinorAxis: minorAxis,
      orientation: _simHeading,
    );

    // 4. Update state snapshot
    _state = _state.copyWith(
      latitude: _simLatitude,
      longitude: _simLongitude,
      altitude: 920.0 + 5.0 * math.sin(_tickCount / 100.0),
      eastVelocity: eastVel,
      northVelocity: northVel,
      heading: _simHeading,
      uncertaintyEllipse: newEllipse,
      distanceTraveledKm: newDistanceKm,
      driftEstimatePercent: drift,
      timestamp: DateTime.now(),
    );

    // 5. Append to route history at 1Hz (every 10 ticks)
    if (_tickCount % 10 == 0) {
      _routeHistory.add(RoutePoint(
        point: LatLng(_simLatitude, _simLongitude),
        mode: _state.currentMode,
        timestamp: DateTime.now(),
      ));
      if (_routeHistory.length > 1000) {
        _routeHistory.removeAt(0);
      }
    }

    // 6. Emit 10Hz update
    _controller.add(_state);
  }

  @override
  void triggerSimulatedCrash() {
    _sosTimer?.cancel();
    _state = _state.copyWith(
      crashDetected: true,
      crashConfidence: 0.94,
      impactMagnitude: 4.8,
      sosActive: true,
      sosCountdownSeconds: 30,
    );
    _controller.add(_state);

    // 1Hz countdown
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_state.sosCountdownSeconds > 1) {
        _state = _state.copyWith(
          sosCountdownSeconds: _state.sosCountdownSeconds - 1,
        );
        _controller.add(_state);
      } else {
        // Countdown expired
        timer.cancel();
        _state = _state.copyWith(
          sosCountdownSeconds: 0,
          sosActive: false,
          crashDetected: false,
        );
        _controller.add(_state);
      }
    });
  }

  @override
  void cancelSos() {
    _sosTimer?.cancel();
    _state = _state.copyWith(
      crashDetected: false,
      sosActive: false,
      sosCountdownSeconds: 30,
    );
    _controller.add(_state);
  }

  @override
  void toggleMode() {
    final nextMode = _state.currentMode == NavMode.gnssAided
        ? NavMode.deadReckoning
        : NavMode.gnssAided;
    _ticksInCurrentMode = 0;
    _state = _state.copyWith(
      currentMode: nextMode,
      timeInCurrentMode: 0,
    );
    _controller.add(_state);
  }

  @override
  void startCalibration() {
    _calibrationTimer?.cancel();
    _calibrationProgressSeconds = 0;
    _state = _state.copyWith(
      alignmentStatus: AlignmentStatus.calibrating,
    );
    _controller.add(_state);

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calibrationProgressSeconds++;
      if (_calibrationProgressSeconds >= 10) {
        timer.cancel();
        _state = _state.copyWith(
          alignmentStatus: AlignmentStatus.calibrated,
        );
        _controller.add(_state);
      }
    });
  }

  @override
  void resetCalibration() {
    _calibrationTimer?.cancel();
    _state = _state.copyWith(
      alignmentStatus: AlignmentStatus.calibrating,
    );
    _controller.add(_state);
  }

  @override
  void resetTrip() {
    _routeHistory.clear();
    _tripStartTime = DateTime.now();
    _gnssAidedSeconds = 0;
    _deadReckoningSeconds = 0;
    _maxDriftSeen = 0.2;
    _currentWaypointIndex = 0;
    _currentPlannedRoute = null;
    _tripStatus = TripStatus.idle;
    _state = _state.copyWith(
      distanceTraveledKm: 0.0,
      driftEstimatePercent: 0.2,
    );
    _tripStatusController.add(_tripStatus);
    _controller.add(_state);
  }

  @override
  TripSummary endTrip() {
    final totalDuration = DateTime.now().difference(_tripStartTime);
    bool reached = false;
    if (_currentPlannedRoute != null) {
      final distToDest = const Distance().as(
        LengthUnit.Meter,
        LatLng(_simLatitude, _simLongitude),
        _currentPlannedRoute!.destination,
      );
      reached = distToDest < 150.0;
    }

    final summary = TripSummary(
      totalDistanceKm: _state.distanceTraveledKm,
      totalDuration: totalDuration.inSeconds > 0 ? totalDuration : const Duration(seconds: 1),
      gnssAidedDuration: Duration(seconds: _gnssAidedSeconds),
      deadReckoningDuration: Duration(seconds: _deadReckoningSeconds),
      maxDriftPercent: _maxDriftSeen,
      route: List.from(_routeHistory),
      destinationName: _currentPlannedRoute?.destinationName ?? 'Selected Destination',
      destination: _currentPlannedRoute?.destination,
      destinationReached: reached,
      plannedRoute: _currentPlannedRoute?.waypoints ?? [],
    );

    _tripStatus = TripStatus.completed;
    _tripStatusController.add(_tripStatus);
    return summary;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sosTimer?.cancel();
    _calibrationTimer?.cancel();
    _controller.close();
    _tripStatusController.close();
  }
}
