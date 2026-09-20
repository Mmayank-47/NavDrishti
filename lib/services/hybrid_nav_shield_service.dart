import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import 'mock_nav_shield_data_service.dart';
import 'nav_shield_data_service.dart';
import 'real_nav_shield_service.dart';
import 'settings_service.dart';

/// Unified Data Service that delegates to either [MockNavShieldDataService]
/// or [RealNavShieldDataService] based on [SettingsService.useRealBackend].
///
/// Ensures 100% polymorphic drop-in behavior without restarting the application.
class HybridNavShieldDataService implements NavShieldDataService {
  final SettingsService settings;

  late MockNavShieldDataService _mockService;
  RealNavShieldDataService? _realService;

  final StreamController<NavShieldState> _controller =
      StreamController<NavShieldState>.broadcast();
  final StreamController<TripStatus> _tripStatusController =
      StreamController<TripStatus>.broadcast();

  StreamSubscription? _mockStateSub;
  StreamSubscription? _mockTripSub;
  StreamSubscription? _realStateSub;
  StreamSubscription? _realTripSub;

  HybridNavShieldDataService({required this.settings}) {
    _mockService = MockNavShieldDataService(autoStart: true);
    _initListeners();
    settings.addListener(_onSettingsChanged);
  }

  void _initListeners() {
    _mockStateSub?.cancel();
    _mockTripSub?.cancel();
    _mockStateSub = _mockService.stateStream.listen((state) {
      if (!settings.useRealBackend) {
        _controller.add(state);
      }
    });
    _mockTripSub = _mockService.tripStatusStream.listen((status) {
      if (!settings.useRealBackend) {
        _tripStatusController.add(status);
      }
    });

    if (settings.useRealBackend) {
      _ensureRealService();
    }
  }

  void _ensureRealService() {
    if (_realService == null ||
        _realService!.host != settings.backendHost ||
        _realService!.port != settings.backendPort) {
      _realStateSub?.cancel();
      _realTripSub?.cancel();
      _realService?.dispose();

      _realService = RealNavShieldDataService(
        host: settings.backendHost,
        port: settings.backendPort,
        autoConnect: true,
      );

      _realStateSub = _realService!.stateStream.listen((state) {
        if (settings.useRealBackend) {
          _controller.add(state);
        }
      });
      _realTripSub = _realService!.tripStatusStream.listen((status) {
        if (settings.useRealBackend) {
          _tripStatusController.add(status);
        }
      });
    }
  }

  void _onSettingsChanged() {
    if (settings.useRealBackend) {
      _ensureRealService();
      _controller.add(_realService!.currentState);
      _tripStatusController.add(_realService!.tripStatus);
    } else {
      _controller.add(_mockService.currentState);
      _tripStatusController.add(_mockService.tripStatus);
    }
  }

  NavShieldDataService get _activeService =>
      settings.useRealBackend && _realService != null
          ? _realService!
          : _mockService;

  bool get isRealBackendConnected =>
      settings.useRealBackend && (_realService?.isConnected ?? false);

  @override
  Stream<NavShieldState> get stateStream => _controller.stream;

  @override
  NavShieldState get currentState => _activeService.currentState;

  @override
  List<RoutePoint> get routeHistory => _activeService.routeHistory;

  @override
  TripStatus get tripStatus => _activeService.tripStatus;

  @override
  Stream<TripStatus> get tripStatusStream => _tripStatusController.stream;

  @override
  PlannedRoute? get currentPlannedRoute => _activeService.currentPlannedRoute;

  @override
  void setDestination(LatLng destination, String name) {
    _activeService.setDestination(destination, name);
  }

  @override
  void startTrip() {
    _activeService.startTrip();
  }

  @override
  void cancelDestination() {
    _activeService.cancelDestination();
  }

  @override
  void triggerSimulatedCrash() {
    _activeService.triggerSimulatedCrash();
  }

  @override
  void cancelSos() {
    _activeService.cancelSos();
  }

  @override
  void toggleMode() {
    _activeService.toggleMode();
  }

  @override
  void startCalibration() {
    _activeService.startCalibration();
  }

  @override
  void resetCalibration() {
    _activeService.resetCalibration();
  }

  @override
  void resetTrip() {
    _activeService.resetTrip();
  }

  @override
  TripSummary endTrip() {
    return _activeService.endTrip();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _mockStateSub?.cancel();
    _mockTripSub?.cancel();
    _realStateSub?.cancel();
    _realTripSub?.cancel();
    _mockService.dispose();
    _realService?.dispose();
    _controller.close();
    _tripStatusController.close();
  }
}
