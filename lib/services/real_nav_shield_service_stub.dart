import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import 'nav_shield_data_service.dart';

/// ============================================================================
/// NAV-SHIELD REAL BACKEND INTEGRATION STUB
/// ============================================================================
///
/// When you are ready to connect the real Python NAV-SHIELD engine
/// (github.com/Mmayank-47/NavDrishti), implement this class and swap it in
/// `main.dart`:
///
/// ```dart
/// // In lib/main.dart:
/// // Replace:
/// Provider<NavShieldDataService>(create: (_) => MockNavShieldDataService())
/// // With:
/// Provider<NavShieldDataService>(create: (_) => RealNavShieldDataService(serverUrl: 'ws://192.168.1.100:8765'))
/// ```
///
/// The engine publishes a 10Hz JSON payload matching [NavShieldState.fromJson].
/// ============================================================================
class RealNavShieldDataService implements NavShieldDataService {
  final String serverUrl;
  final StreamController<NavShieldState> _controller = StreamController<NavShieldState>.broadcast();
  final NavShieldState _latestState = NavShieldState.initial();
  final List<RoutePoint> _routeHistory = [];

  // TODO: Add WebSocketChannel or RawSocket client:
  // WebSocketChannel? _webSocketChannel;
  // StreamSubscription? _socketSubscription;

  RealNavShieldDataService({this.serverUrl = 'ws://127.0.0.1:8765'}) {
    // connect();
  }

  /// Establish live connection with the Python NAV-SHIELD backend
  Future<void> connect() async {
    // -------------------------------------------------------------------------
    // STEP 1: Connect WebSocket / TCP to Python backend
    // Example:
    //   _webSocketChannel = WebSocketChannel.connect(Uri.parse(serverUrl));
    //
    // STEP 2: Listen to 10Hz stream and deserialize
    //   _socketSubscription = _webSocketChannel!.stream.listen((message) {
    //      final json = jsonDecode(message as String) as Map<String, dynamic>;
    //      final state = NavShieldState.fromJson(json);
    //      _latestState = state;
    //      _controller.add(state);
    //   });
    // -------------------------------------------------------------------------
  }

  @override
  Stream<NavShieldState> get stateStream => _controller.stream;

  @override
  NavShieldState get currentState => _latestState;

  @override
  List<RoutePoint> get routeHistory => List.unmodifiable(_routeHistory);

  TripStatus _tripStatus = TripStatus.idle;
  final StreamController<TripStatus> _tripStatusController = StreamController<TripStatus>.broadcast();
  PlannedRoute? _currentPlannedRoute;

  @override
  TripStatus get tripStatus => _tripStatus;

  @override
  Stream<TripStatus> get tripStatusStream => _tripStatusController.stream;

  @override
  PlannedRoute? get currentPlannedRoute => _currentPlannedRoute;

  @override
  void setDestination(LatLng destination, String name) {
    _tripStatus = TripStatus.destinationSet;
    _tripStatusController.add(_tripStatus);
  }

  @override
  void startTrip() {
    _tripStatus = TripStatus.active;
    _tripStatusController.add(_tripStatus);
  }

  @override
  void cancelDestination() {
    _currentPlannedRoute = null;
    _tripStatus = TripStatus.idle;
    _tripStatusController.add(_tripStatus);
  }

  @override
  void triggerSimulatedCrash() {
    // Send debug crash trigger packet to Python engine if supported
  }

  @override
  void cancelSos() {
    // Send SOS cancel packet to backend
  }

  @override
  void toggleMode() {
    // Send mode override packet to backend
  }

  @override
  void startCalibration() {
    // Send start alignment command to backend
  }

  @override
  void resetCalibration() {
    // Send reset calibration command to backend
  }

  @override
  void resetTrip() {
    _routeHistory.clear();
  }

  @override
  TripSummary endTrip() {
    return TripSummary(
      totalDistanceKm: _latestState.distanceTraveledKm,
      totalDuration: const Duration(minutes: 10),
      gnssAidedDuration: const Duration(minutes: 7),
      deadReckoningDuration: const Duration(minutes: 3),
      maxDriftPercent: _latestState.driftEstimatePercent,
      route: List.from(_routeHistory),
    );
  }

  @override
  void dispose() {
    // _socketSubscription?.cancel();
    // _webSocketChannel?.sink.close();
    _controller.close();
  }
}
