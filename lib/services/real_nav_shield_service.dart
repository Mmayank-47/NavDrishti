import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import 'nav_shield_data_service.dart';
import 'route_calculation_service.dart';

/// Real WebSocket client connecting to the NAV-SHIELD Python engine (NavDrishti).
///
/// Binds to `ws://host:port` (default ws://10.0.2.2:8765 on Android Emulator,
/// ws://127.0.0.1:8765 on desktop/host, or local Wi-Fi IP on physical devices).
///
/// Features:
/// - Connects to Python 10Hz unified navigation state stream
/// - Automatic exponential backoff reconnection (1s, 2s, 4s, up to 10s)
/// - Deserializes exact NavShieldState JSON payloads
/// - Bidirectional control actions (trigger_crash, cancel_sos, toggle_mode, reset_trip)
/// - Trip lifecycle tracking & breadcrumb history accumulation
class RealNavShieldDataService implements NavShieldDataService {
  final String host;
  final int port;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;

  final StreamController<NavShieldState> _controller =
      StreamController<NavShieldState>.broadcast();
  final StreamController<TripStatus> _tripStatusController =
      StreamController<TripStatus>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  NavShieldState _state = NavShieldState.initial();
  final List<RoutePoint> _routeHistory = [];
  TripStatus _tripStatus = TripStatus.idle;
  PlannedRoute? _currentPlannedRoute;

  // Trip summary accumulation
  DateTime _tripStartTime = DateTime.now();
  int _gnssAidedSeconds = 0;
  int _deadReckoningSeconds = 0;
  double _maxDriftSeen = 0.2;
  double _lastModeTimestamp = 0.0;

  RealNavShieldDataService({
    this.host = '10.0.2.2',
    this.port = 8765,
    bool autoConnect = true,
  }) {
    if (autoConnect) {
      connect();
    }
  }

  String get wsUrl => 'ws://$host:$port';
  bool get isConnected => _isConnected;
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Connect or reconnect to the WebSocket server
  Future<void> connect() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    final uri = Uri.parse(wsUrl);
    debugPrint('[NavShield WS] Connecting to $uri ...');

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionController.add(true);
      debugPrint('[NavShield WS] Connected successfully to $uri');

      _subscription?.cancel();
      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: (err) {
          debugPrint('[NavShield WS] Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[NavShield WS] Stream closed');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[NavShield WS] Connection failed: $e');
      _handleDisconnect();
    }
  }

  void _onMessageReceived(dynamic message) {
    if (_disposed) return;
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final state = NavShieldState.fromJson(json);
      _state = state;
      _controller.add(state);

      // Track trip accumulation if trip is active
      if (_tripStatus == TripStatus.active) {
        final pos = LatLng(state.latitude, state.longitude);
        if (_routeHistory.isEmpty ||
            _routeHistory.last.point.latitude != pos.latitude ||
            _routeHistory.last.point.longitude != pos.longitude) {
          _routeHistory.add(RoutePoint(
            point: pos,
            mode: state.currentMode,
            timestamp: DateTime.now(),
          ));
        }

        if (state.driftEstimatePercent > _maxDriftSeen) {
          _maxDriftSeen = state.driftEstimatePercent;
        }

        // Mode time tracking
        final nowSecs = DateTime.now().millisecondsSinceEpoch / 1000.0;
        if (_lastModeTimestamp > 0) {
          final dt = (nowSecs - _lastModeTimestamp).clamp(0.0, 1.0).toInt();
          if (state.currentMode == NavMode.gnssAided) {
            _gnssAidedSeconds += dt;
          } else {
            _deadReckoningSeconds += dt;
          }
        }
        _lastModeTimestamp = nowSecs;
      }
    } catch (e) {
      debugPrint('[NavShield WS] JSON parse error: $e');
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    final wasConnected = _isConnected;
    _isConnected = false;
    if (wasConnected) {
      _connectionController.add(false);
    }
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    // Exponential backoff reconnect: 1s, 2s, 4s, max 10s
    _reconnectAttempts++;
    final backoffSeconds = math.min(10, math.pow(2, _reconnectAttempts - 1).toInt());
    debugPrint('[NavShield WS] Reconnecting in $backoffSeconds seconds (attempt $_reconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (!_disposed && !_isConnected) {
        connect();
      }
    });
  }

  void _sendAction(String action, [Map<String, dynamic>? extra]) {
    if (_channel != null && _isConnected) {
      try {
        final payload = {'action': action, ...?extra};
        _channel!.sink.add(jsonEncode(payload));
        debugPrint('[NavShield WS] Sent action: $action');
      } catch (e) {
        debugPrint('[NavShield WS] Failed to send action $action: $e');
      }
    } else {
      debugPrint('[NavShield WS] Cannot send action $action: Not connected');
    }
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
      origin: LatLng(_state.latitude, _state.longitude),
      destination: destination,
      destinationName: name,
    );
    _tripStatus = TripStatus.destinationSet;
    _tripStatusController.add(_tripStatus);

    RouteCalculationService.calculateRoadRoute(
      origin: LatLng(_state.latitude, _state.longitude),
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
    _lastModeTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _tripStatusController.add(_tripStatus);
    _sendAction('reset_trip');
  }

  @override
  void cancelDestination() {
    _currentPlannedRoute = null;
    _tripStatus = TripStatus.idle;
    _tripStatusController.add(_tripStatus);
  }

  @override
  void triggerSimulatedCrash() {
    _sendAction('trigger_crash');
  }

  @override
  void cancelSos() {
    _sendAction('cancel_sos');
  }

  @override
  void toggleMode() {
    _sendAction('toggle_mode');
  }

  @override
  void startCalibration() {
    // Send calibration start command if backend supports
  }

  @override
  void resetCalibration() {
    // Reset calibration command if backend supports
  }

  @override
  void resetTrip() {
    _routeHistory.clear();
    _gnssAidedSeconds = 0;
    _deadReckoningSeconds = 0;
    _maxDriftSeen = 0.2;
    _sendAction('reset_trip');
  }

  @override
  TripSummary endTrip() {
    final now = DateTime.now();
    final duration = now.difference(_tripStartTime);
    final distance = _state.distanceTraveledKm;

    final summary = TripSummary(
      totalDistanceKm: distance,
      totalDuration: duration,
      gnssAidedDuration: Duration(seconds: _gnssAidedSeconds),
      deadReckoningDuration: Duration(seconds: _deadReckoningSeconds),
      maxDriftPercent: _maxDriftSeen,
      route: List.from(_routeHistory),
      destinationName: _currentPlannedRoute?.destinationName ?? 'Custom Destination',
      destination: _currentPlannedRoute?.destination,
      destinationReached: false,
      plannedRoute: _currentPlannedRoute?.waypoints ?? [],
    );

    _tripStatus = TripStatus.completed;
    _tripStatusController.add(_tripStatus);
    return summary;
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.close();
    _tripStatusController.close();
    _connectionController.close();
  }
}
