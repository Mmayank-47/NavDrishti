import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/nav_shield_data_service.dart';
import '../services/settings_service.dart';
import '../services/trip_notification_service.dart';
import '../services/overlay_navigation_service.dart';
import '../services/turn_guidance_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_menu.dart';
import '../widgets/mapbox_nav_map.dart';
import '../widgets/nav_map.dart';
import '../widgets/nav_toast.dart';
import '../widgets/sos_button.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_bottom_sheet.dart';
import 'calibration_screen.dart';
import 'settings_screen.dart';
import 'sos_alert_overlay.dart';
import 'trip_summary_screen.dart';

/// Screen: MAIN NAVIGATION HUD (Active Navigation)
///
/// Principles:
/// - Map is dominant background element
/// - Fused (GNSS+INS) state:
///   * Turn-by-turn instruction card at top ("Turn right in 240 m / MG Road")
///   * Small ETA/distance/time info card
///   * Slim bottom bar: Speed · Distance · Time + isolated red End Navigation button
/// - Degraded (Dead-Reckoning) state:
///   * Top badge switches to "GNSS SIGNAL LOST / INS Dead Reckoning Active" in violet with warning triangle
///   * "Last known GNSS position" marker/label on map at loss point
///   * Glowing violet confidence halo
///   * Visible amber warning strip: "Using IMU-based INS for continued navigation. Accuracy may decrease over time."
/// - Right-side vertical control stack (layers, compass with rotating needle, speaker, 3D, zoom +/-)
/// - Swipe-up TripBottomSheet with detailed telemetry and 5-item color model legend
/// - Circular red SOS button with glowing treatment
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  final GlobalKey<MapboxNavMapState> _navMapKey = GlobalKey<MapboxNavMapState>();
  double _mapBearing = 0.0;
  LatLng? _lastKnownGnssPosition;
  NavMode? _previousMode;

  // Mini Nav Widget / PiP & Lifecycle State
  bool _overlayPermissionGranted = true;
  bool _hasAutoEnded = false;
  bool _isAppBackgrounded = false;
  StreamSubscription<NavShieldState>? _stateSubscription;
  DateTime? _lastBackgroundPush;
  TurnGuidance _turnGuidance = TurnGuidance.initial();
  Timer? _backgroundDebounceTimer;

  // GNSS Outlier Rejection & Recovery State
  bool _showOutlierBadge = false;
  Timer? _outlierTimer;
  bool _wasReacquiring = false;

  void _triggerOutlierBadge() {
    _outlierTimer?.cancel();
    setState(() {
      _showOutlierBadge = true;
    });
    _outlierTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _showOutlierBadge = false;
        });
      }
    });
  }

  // Rerouting state (Item 5)
  bool _isRerouting = false;
  String _currentInstruction = 'Turn right in 240 m';
  String _currentStreet = 'MG Road · toward destination';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOverlayPermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stateSubscription == null) {
      final dataService = context.read<NavShieldDataService>();
      _stateSubscription = dataService.stateStream.listen(_onNavStateTick);
    }
  }

  void _onNavStateTick(NavShieldState state) {
    if (!mounted) return;
    final dataService = context.read<NavShieldDataService>();
    final planned = dataService.currentPlannedRoute;

    final guidance = TurnGuidanceService.calculate(
      currentPos: LatLng(state.latitude, state.longitude),
      currentHeading: state.heading,
      distanceTraveledKm: state.distanceTraveledKm,
      plannedRoute: planned,
    );

    _turnGuidance = guidance;
    _currentInstruction = guidance.instruction;
    _currentStreet = guidance.streetName;

    // Check auto-arrival at destination
    final destPoint = (planned != null && planned.waypoints.isNotEmpty) ? planned.waypoints.last : null;
    final distToDestMeters = destPoint != null
        ? const Distance().as(LengthUnit.Meter, LatLng(state.latitude, state.longitude), destPoint)
        : double.infinity;

    final isArrived = !_hasAutoEnded &&
        (guidance.remainingKm <= 0.05 ||
            distToDestMeters <= 50.0 ||
            guidance.progressRatio >= 0.985 ||
            (guidance.turnType == 'destination' && guidance.distanceToTurnMeters <= 40.0) ||
            (planned != null &&
                planned.totalDistanceKm > 0.05 &&
                state.distanceTraveledKm >= planned.totalDistanceKm));

    if (isArrived) {
      _hasAutoEnded = true;
      OverlayNavigationService.instance.closeOverlay();
      TripNotificationService.instance.cancelTripNotification();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _endNavigation(
            context,
            dataService,
            context.read<SettingsService>(),
            destinationReached: true,
          );
        }
      });
      return;
    }

    final now = DateTime.now();
    if (_isAppBackgrounded || OverlayNavigationService.instance.isOverlayShowing) {
      if (_lastBackgroundPush == null ||
          now.difference(_lastBackgroundPush!).inMilliseconds >= 750) {
        _lastBackgroundPush = now;
        _pushBackgroundUpdates(state, planned, guidance);
      }
    }
  }

  void _pushBackgroundUpdates(
    NavShieldState state,
    PlannedRoute? planned,
    TurnGuidance guidance,
  ) {
    List<List<double>>? waypoints;
    if (planned != null && planned.waypoints.isNotEmpty) {
      waypoints = planned.waypoints.map((pt) => [pt.latitude, pt.longitude]).toList();
    }

    // 1. Update floating overlay window if showing
    if (OverlayNavigationService.instance.isOverlayShowing) {
      OverlayNavigationService.instance.updateOverlay(
        instruction: guidance.instruction,
        distance: guidance.distanceToTurnText,
        eta: '${guidance.remainingMins} min',
        mode: state.currentMode.name,
        speed: '${state.speedKmh.toStringAsFixed(0)} km/h',
        heading: state.heading,
        currentLat: state.latitude,
        currentLng: state.longitude,
        progress: guidance.progressRatio,
        turnType: guidance.turnType,
        routePoints: waypoints,
      );
    }

    // 2. Update persistent notification if app is backgrounded
    if (_isAppBackgrounded) {
      TripNotificationService.instance.updateTripStatus(
        mode: state.currentMode,
        remainingKm: guidance.remainingKm,
        remainingMins: guidance.remainingMins,
        destinationName: planned?.destinationName ?? 'Destination',
        instruction: guidance.instruction,
        turnType: guidance.turnType,
        distanceToTurn: guidance.distanceToTurnText,
        progressRatio: guidance.progressRatio,
      );
    }
  }

  Future<void> _checkOverlayPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _overlayPermissionGranted = prefs.getBool('perm_overlay_granted') ?? true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cancel any pending background trigger if lifecycle changes
    _backgroundDebounceTimer?.cancel();
    _backgroundDebounceTimer = null;

    if (state == AppLifecycleState.paused) {
      // Debounce (350ms) to ensure the app has genuinely left the foreground
      // (and is not just a momentary blip, dialog, or transient focus shift)
      _backgroundDebounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        final currentState = WidgetsBinding.instance.lifecycleState;
        if (currentState == AppLifecycleState.paused ||
            currentState == AppLifecycleState.hidden) {
          _showOverlayAndNotification();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _isAppBackgrounded = false;
      OverlayNavigationService.instance.closeOverlay();
      TripNotificationService.instance.cancelTripNotification();
    }
    // Note: AppLifecycleState.inactive (notification shade, permission prompt, system dialog)
    // is intentionally ignored so the overlay NEVER flashes while the user interacts with system UI.
  }

  void _showOverlayAndNotification() {
    _isAppBackgrounded = true;
    try {
      final dataService = context.read<NavShieldDataService>();
      final state = dataService.currentState;
      final planned = dataService.currentPlannedRoute;
      final guidance = TurnGuidanceService.calculate(
        currentPos: LatLng(state.latitude, state.longitude),
        currentHeading: state.heading,
        distanceTraveledKm: state.distanceTraveledKm,
        plannedRoute: planned,
      );

      List<List<double>>? waypoints;
      if (planned != null && planned.waypoints.isNotEmpty) {
        waypoints = planned.waypoints.map((pt) => [pt.latitude, pt.longitude]).toList();
      }

      if (_overlayPermissionGranted) {
        OverlayNavigationService.instance.showOverlay(
          instruction: guidance.instruction,
          distance: guidance.distanceToTurnText,
          eta: '${guidance.remainingMins} min',
          mode: state.currentMode.name,
          speed: '${state.speedKmh.toStringAsFixed(0)} km/h',
          heading: state.heading,
          currentLat: state.latitude,
          currentLng: state.longitude,
          progress: guidance.progressRatio,
          turnType: guidance.turnType,
          routePoints: waypoints,
        );
      }

      TripNotificationService.instance.updateTripStatus(
        mode: state.currentMode,
        remainingKm: guidance.remainingKm,
        remainingMins: guidance.remainingMins,
        destinationName: planned?.destinationName ?? 'Destination',
        instruction: guidance.instruction,
        turnType: guidance.turnType,
        distanceToTurn: guidance.distanceToTurnText,
        progressRatio: guidance.progressRatio,
      );
    } catch (e) {
      debugPrint('[MainNavigation] Error triggering background surfaces: $e');
    }
  }

  void _handleBackTrigger() {
    _showOverlayAndNotification();
    OverlayNavigationService.instance.sendToBackground();
  }

  void _toggleMinimize() {
    _handleBackTrigger();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Floating navigation overlay active over other apps'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundDebounceTimer?.cancel();
    _stateSubscription?.cancel();
    _outlierTimer?.cancel();
    OverlayNavigationService.instance.closeOverlay();
    TripNotificationService.instance.cancelTripNotification();
    super.dispose();
  }

  void simulateRouteDeviation() {
    setState(() {
      _isRerouting = true;
    });
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) {
        setState(() {
          _isRerouting = false;
          _currentInstruction = 'Recalculated · Continue straight 450 m';
          _currentStreet = 'Residency Road (Fastest Alternative)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Route recalculated: Deviation corrected'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataService = context.watch<NavShieldDataService>();
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;
    final violetColor = isDark ? AppColors.darkViolet : AppColors.lightViolet;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Slim bottom bar is ~72px (64px container + 8px margin) + bottomInset.
    // Setting bottom to bottomInset + 110.0 provides an extra ~15px of clean breathing
    // room above the top edge across all phone screen sizes and safe area insets.
    final floatingControlsBottom = bottomInset + 110.0;

    return StreamBuilder<NavShieldState>(
      stream: dataService.stateStream,
      initialData: dataService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? dataService.currentState;
        final planned = dataService.currentPlannedRoute;
        final isDeadReckoning = state.currentMode == NavMode.deadReckoning;

        // Record point of GNSS loss
        if (_previousMode == NavMode.gnssAided && isDeadReckoning) {
          _lastKnownGnssPosition = LatLng(state.latitude, state.longitude);
        } else if (!isDeadReckoning) {
          _lastKnownGnssPosition = null;
        }
        _previousMode = state.currentMode;

        double remainingKm = 1.0;
        int remainingMins = 3;
        if (planned != null) {
          remainingKm = (planned.totalDistanceKm - state.distanceTraveledKm)
              .clamp(0.0, planned.totalDistanceKm);
          remainingMins = (remainingKm / (32.0 / 60.0)).ceil();

          // Auto-detect arrival at destination (transitions automatically like pressing End)
          if (remainingKm <= 0.02 && !_hasAutoEnded) {
            _hasAutoEnded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _endNavigation(context, dataService, settings, destinationReached: true);
              }
            });
          }
        }

        // Only keep notification active while backgrounded
        if (_isAppBackgrounded) {
          TripNotificationService.instance.updateTripStatus(
            mode: state.currentMode,
            remainingKm: remainingKm,
            remainingMins: remainingMins,
            destinationName: planned?.destinationName ?? 'Destination',
            instruction: _turnGuidance.instruction,
            turnType: _turnGuidance.turnType,
            distanceToTurn: _turnGuidance.distanceToTurnText,
            progressRatio: _turnGuidance.progressRatio,
          );
        }

        // Auto-trigger outlier badge if state indicates rejected outlier
        if (state.gnssOutlierRejected && !_showOutlierBadge) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _triggerOutlierBadge();
          });
        }

        // Detect transition from reacquiring annealing window back to GNSS_AIDED
        if (_wasReacquiring && !state.isReacquiring && state.currentMode == NavMode.gnssAided) {
          _wasReacquiring = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  duration: Duration(seconds: 3),
                  content: NavToast(type: NavToastType.gnssRecovered),
                ),
              );
            }
          });
        } else if (state.isReacquiring) {
          _wasReacquiring = true;
        }

        // Overlay SOS / Crash alert when crash detected or SOS active
        if (state.crashDetected || state.sosActive) {
          return SosAlertOverlay(
            state: state,
            dataService: dataService,
          );
        }

        if (OverlayNavigationService.instance.isOverlayShowing) {
          OverlayNavigationService.instance.updateOverlay(
            instruction: _turnGuidance.instruction,
            distance: _turnGuidance.distanceToTurnText,
            eta: '${_turnGuidance.remainingMins} min',
            mode: state.currentMode.name,
            speed: '${state.speedKmh.toStringAsFixed(0)} km/h',
            heading: state.heading,
            currentLat: state.latitude,
            currentLng: state.longitude,
            progress: _turnGuidance.progressRatio,
            turnType: _turnGuidance.turnType,
            routePoints: planned?.waypoints.map((pt) => [pt.latitude, pt.longitude]).toList(),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBackTrigger();
          },
          child: Scaffold(
            body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Full-screen NavMap with Road Polylines & Interpolated Halo
              Positioned.fill(
                child: NavMap(
                  mapKey: _navMapKey,
                  state: state,
                  isDark: isDark,
                  plannedRoute: planned,
                  routeHistory: dataService.routeHistory,
                  onMapBearingChanged: (bearing) {
                    setState(() {
                      _mapBearing = bearing;
                    });
                  },
                ),
              ),

              // 2. Last Known GNSS Position Pin (When in Dead Reckoning)
              if (isDeadReckoning && _lastKnownGnssPosition != null)
                Positioned(
                  top: 130,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.darkSurface : AppColors.lightSurface)
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cyanColor.withValues(alpha: 0.6), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pin_drop_rounded, size: 14, color: cyanColor),
                        const SizedBox(width: 6),
                        Text(
                          'Last known GNSS position',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cyanColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Top HUD: Turn-by-Turn Card & Status Pill / Outage Badge
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [


                        // Turn-by-Turn Instruction Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      const Color(0xFF131D38).withValues(alpha: 0.88),
                                      const Color(0xFF080D1D).withValues(alpha: 0.80),
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.94),
                                      const Color(0xFFF1F5F9).withValues(alpha: 0.88),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDeadReckoning
                                  ? violetColor.withValues(alpha: 0.70)
                                  : (isDark
                                      ? cyanColor.withValues(alpha: 0.50)
                                      : cyanColor.withValues(alpha: 0.35)),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                              BoxShadow(
                                color: (isDeadReckoning ? violetColor : cyanColor)
                                    .withValues(alpha: isDark ? 0.25 : 0.12),
                                blurRadius: 14,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      (isDeadReckoning ? violetColor : cyanColor)
                                          .withValues(alpha: 0.30),
                                      (isDeadReckoning ? violetColor : cyanColor)
                                          .withValues(alpha: 0.10),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: (isDeadReckoning ? violetColor : cyanColor)
                                        .withValues(alpha: 0.40),
                                    width: 1.0,
                                  ),
                                ),
                                child: _isRerouting
                                    ? Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor: AlwaysStoppedAnimation<Color>(cyanColor),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.turn_right_rounded,
                                        size: 22,
                                        color: isDeadReckoning ? violetColor : cyanColor,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isRerouting ? 'Rerouting...' : _currentInstruction,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                        color: _isRerouting ? cyanColor : primaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _isRerouting
                                          ? 'Finding optimal path around deviation...'
                                          : _currentStreet,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Voice Guidance Mute/Unmute Control (Item 2)
                              GestureDetector(
                                key: const ValueKey('voice_guidance_mute_toggle'),
                                onTap: () async {
                                  await settings.toggleVoiceGuidance();
                                  final isMuted = settings.voiceGuidanceMuted;
                                  // [TTS INTEGRATION HOOK]:
                                  // When text-to-speech audio is wired up (e.g. via flutter_tts),
                                  // invoke voice synthesis maneuvers if !settings.voiceGuidanceMuted:
                                  // if (!settings.voiceGuidanceMuted) {
                                  //   flutterTts.speak(_currentInstruction);
                                  // } else {
                                  //   flutterTts.stop();
                                  // }
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isMuted
                                            ? '🔇 Voice guidance muted'
                                            : '🔊 Voice guidance unmuted',
                                      ),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (isDark
                                            ? AppColors.darkSurfaceSubtle
                                            : cyanColor.withValues(alpha: 0.08))
                                        .withValues(alpha: 0.85),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : cyanColor.withValues(alpha: 0.25),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: settings.voiceGuidanceMuted
                                        ? Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Icon(
                                                Icons.volume_up_rounded,
                                                size: 16,
                                                color: isDark ? secondaryTextColor : cyanColor,
                                              ),
                                              // Distinct diagonal slash across speaker glyph
                                              Transform.rotate(
                                                angle: -0.785398, // -45 degrees
                                                child: Container(
                                                  width: 1.8,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: isDark ? secondaryTextColor : cyanColor,
                                                    borderRadius: BorderRadius.circular(1),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Icon(
                                            Icons.volume_up_rounded,
                                            size: 16,
                                            color: isDark ? secondaryTextColor : cyanColor,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Minimize to Compact Floating Nav (PiP Style)
                              GestureDetector(
                                key: const ValueKey('toggle_mini_nav_pip_button'),
                                onTap: _toggleMinimize,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (isDark
                                            ? AppColors.darkSurfaceSubtle
                                            : cyanColor.withValues(alpha: 0.08))
                                        .withValues(alpha: 0.8),
                                  ),
                                  child: Icon(
                                    Icons.picture_in_picture_alt_rounded,
                                    size: 16,
                                    color: isDark ? secondaryTextColor : cyanColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => DebugMenu.show(
                                  context,
                                  dataService,
                                  onSimulateRouteDeviation: simulateRouteDeviation,
                                  onSimulateOutlierRejection: () {
                                    dataService.triggerSimulatedOutlierRejection();
                                    _triggerOutlierBadge();
                                  },
                                  onSimulateGnssOutage: () {
                                    if (dataService.currentState.currentMode == NavMode.gnssAided) {
                                      dataService.toggleMode();
                                    }
                                  },
                                  onSimulateGnssRecovered: () {
                                    if (dataService.currentState.currentMode == NavMode.deadReckoning) {
                                      dataService.toggleMode();
                                    }
                                  },
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (isDark
                                            ? AppColors.darkSurfaceSubtle
                                            : cyanColor.withValues(alpha: 0.08))
                                        .withValues(alpha: 0.8),
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    size: 16,
                                    color: isDark ? secondaryTextColor : cyanColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Status Pill (GNSS Aided Fix Precision or Reacquiring Annealing State)
                        if (!isDeadReckoning || state.isReacquiring) ...[
                          const SizedBox(height: 6),
                          StatusPill(
                            mode: state.currentMode,
                            timeInCurrentMode: state.timeInCurrentMode,
                            uncertaintyMeters: state.uncertaintyEllipse.semiMajorAxis,
                            isReacquiring: state.isReacquiring,
                            onOpenDebug: () => DebugMenu.show(
                              context,
                              dataService,
                              onSimulateRouteDeviation: simulateRouteDeviation,
                              onSimulateOutlierRejection: () {
                                dataService.triggerSimulatedOutlierRejection();
                                _triggerOutlierBadge();
                              },
                              onSimulateGnssOutage: () {
                                if (dataService.currentState.currentMode == NavMode.gnssAided) {
                                  dataService.toggleMode();
                                }
                              },
                              onSimulateGnssRecovered: () {
                                if (dataService.currentState.currentMode == NavMode.deadReckoning) {
                                  dataService.toggleMode();
                                }
                              },
                            ),
                          ),
                        ],

                        // Outlier Rejection transient feedback badge (~1.8s auto-dismiss)
                        if (_showOutlierBadge || state.gnssOutlierRejected) ...[
                          const SizedBox(height: 6),
                          AnimatedOpacity(
                            opacity: (_showOutlierBadge || state.gnssOutlierRejected) ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: (isDark ? const Color(0xFF1E293B) : Colors.white)
                                    .withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: (isDark ? AppColors.darkAmber : AppColors.lightAmber)
                                      .withValues(alpha: 0.7),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isDark ? AppColors.darkAmber : AppColors.lightAmber)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.filter_alt_rounded,
                                    size: 14,
                                    color: isDark ? AppColors.darkAmber : AppColors.lightAmber,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'GNSS outlier filtered · Multipath spike rejected',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Standalone Circular Compass / North-Reset Button (Left, symmetric with SOS button)
              Positioned(
                left: 18,
                bottom: floatingControlsBottom,
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Center(
                    child: Tooltip(
                      message: 'Reset Heading to North',
                      child: Material(
                        key: const ValueKey('compass_button'),
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            _navMapKey.currentState?.resetNorth();
                          },
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? [
                                        const Color(0xFF131D38).withValues(alpha: 0.90),
                                        const Color(0xFF080D1D).withValues(alpha: 0.82),
                                      ]
                                    : [
                                        Colors.white.withValues(alpha: 0.95),
                                        const Color(0xFFF1F5F9).withValues(alpha: 0.88),
                                      ],
                              ),
                              border: Border.all(
                                color: _mapBearing.abs() > 1.0
                                    ? cyanColor.withValues(alpha: 0.8)
                                    : (isDark ? cyanColor.withValues(alpha: 0.40) : cyanColor.withValues(alpha: 0.30)),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: cyanColor.withValues(alpha: _mapBearing.abs() > 1.0 ? 0.30 : 0.12),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Transform.rotate(
                              angle: -_mapBearing * math.pi / 180.0,
                              child: Icon(
                                Icons.navigation_rounded,
                                size: 24,
                                color: _mapBearing.abs() > 1.0
                                    ? cyanColor
                                    : (isDark ? Colors.white.withValues(alpha: 0.9) : cyanColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 5. Bottom Right Floating Circular SOS Button (Above Slim Bottom HUD)
              Positioned(
                right: 18,
                bottom: floatingControlsBottom,
                child: SosButton(
                  onTrigger: () {
                    dataService.triggerSimulatedCrash();
                  },
                ),
              ),

              // 6. Slim Single-Row Bottom Navigation Bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xFF131D38).withValues(alpha: 0.92),
                                const Color(0xFF080D1D).withValues(alpha: 0.86),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.96),
                                const Color(0xFFF1F5F9).withValues(alpha: 0.90),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? (isDeadReckoning
                                ? violetColor.withValues(alpha: 0.55)
                                : cyanColor.withValues(alpha: 0.40))
                            : (isDeadReckoning
                                ? violetColor.withValues(alpha: 0.40)
                                : cyanColor.withValues(alpha: 0.30)),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: (isDeadReckoning ? violetColor : cyanColor)
                              .withValues(alpha: isDark ? 0.18 : 0.08),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Subtle drag handle affordance (tap or swipe up for full telemetry sheet)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openTripBottomSheet(context, state, settings, dataService),
                          onVerticalDragEnd: (details) {
                            if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
                              _openTripBottomSheet(context, state, settings, dataService);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.only(bottom: 6, top: 2),
                            width: double.infinity,
                            alignment: Alignment.center,
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),

                        // Single-row navigation bar: [Speed · Dist · ETA] + [End Navigation]
                        Row(
                          children: [
                            // Glanceable Metrics area - Tapping or dragging opens TripBottomSheet
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _openTripBottomSheet(context, state, settings, dataService),
                                onVerticalDragEnd: (details) {
                                  if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
                                    _openTripBottomSheet(context, state, settings, dataService);
                                  }
                                },
                                child: Row(
                                  children: [
                                    // 1. Current Vehicle Speed
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'SPEED',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              settings.formatSpeed(state.speedKmh),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.2,
                                                color: primaryTextColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Container(
                                      width: 1,
                                      height: 20,
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      color: borderColor,
                                    ),

                                    // 2. Distance Remaining
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'DIST',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              settings.formatDistance(remainingKm),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.2,
                                                color: primaryTextColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Container(
                                      width: 1,
                                      height: 20,
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      color: borderColor,
                                    ),

                                    // 3. Approx. Time Remaining
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'ETA',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '$remainingMins min',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.2,
                                                color: cyanColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // 4. Isolated Red "End Navigation" Button
                            ElevatedButton.icon(
                              key: const ValueKey('end_navigation_button'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? AppColors.darkRed : AppColors.lightRed,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shadowColor: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.stop_circle_outlined, size: 15),
                              label: const Text(
                                'End',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              onPressed: () => _endNavigation(context, dataService, settings),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    );
  }

  void _openTripBottomSheet(
    BuildContext context,
    NavShieldState state,
    SettingsService settings,
    NavShieldDataService dataService,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TripBottomSheet(
        state: state,
        settings: settings,
        onEndTrip: () {
          Navigator.of(ctx).pop();
          _endNavigation(context, dataService, settings);
        },
        onCalibrate: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CalibrationScreen(dataService: dataService),
            ),
          );
        },
        onSettings: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SettingsScreen(showBackButton: true),
            ),
          );
        },
      ),
    );
  }

  void _endNavigation(
    BuildContext context,
    NavShieldDataService dataService,
    SettingsService settings, {
    bool destinationReached = false,
  }) {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _isAppBackgrounded = false;
    TripNotificationService.instance.cancelTripNotification();
    OverlayNavigationService.instance.closeOverlay();
    final summary = dataService.endTrip();
    final finalSummary = destinationReached
        ? summary.copyWith(destinationReached: true)
        : summary;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (ctx) => TripSummaryScreen(
          summary: finalSummary,
          settings: settings,
          onNewTrip: () {
            dataService.resetTrip();
          },
        ),
      ),
    );
  }
}

