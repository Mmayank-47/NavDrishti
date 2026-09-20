import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';

/// Abstract contract for NAV-SHIELD engine data providers.
///
/// Swapping MockNavShieldDataService with the real Python backend engine
/// requires ONLY providing an implementation of this interface and injecting it,
/// without touching any UI widgets or view models.
abstract class NavShieldDataService {
  /// Stream emitting state updates at 10Hz (100ms interval)
  Stream<NavShieldState> get stateStream;

  /// Current latest snapshot of navigation state
  NavShieldState get currentState;

  /// Historical breadcrumb points for the current trip
  List<RoutePoint> get routeHistory;

  /// Current trip lifecycle status
  TripStatus get tripStatus;

  /// Stream emitting changes to trip lifecycle status
  Stream<TripStatus> get tripStatusStream;

  /// Currently planned route if a destination has been set
  PlannedRoute? get currentPlannedRoute;

  /// Set destination and generate planned route
  void setDestination(LatLng destination, String name);

  /// Start active navigation along the planned route
  void startTrip();

  /// Clear the current destination and return to idle state
  void cancelDestination();

  /// Trigger a simulated impact/crash event for demonstration
  void triggerSimulatedCrash();

  /// Dismiss and cancel active SOS countdown
  void cancelSos();

  /// Manually toggle between GNSS_AIDED and DEAD_RECKONING modes
  void toggleMode();

  /// Trigger sensor alignment/calibration routine
  void startCalibration();

  /// Reset calibration status
  void resetCalibration();

  /// Reset trip distance and historical route
  void resetTrip();

  /// End current trip and generate summary
  TripSummary endTrip();

  /// Clean up timers and streams
  void dispose();
}
