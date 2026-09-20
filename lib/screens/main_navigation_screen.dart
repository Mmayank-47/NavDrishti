import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../services/nav_shield_data_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_menu.dart';
import '../widgets/mapbox_nav_map.dart';
import '../widgets/nav_map.dart';
import '../widgets/sos_button.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_bottom_sheet.dart';
import 'calibration_screen.dart';
import 'destination_entry_screen.dart';
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
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<MapboxNavMapState> _navMapKey = GlobalKey<MapboxNavMapState>();
  double _mapBearing = 0.0;
  LatLng? _lastKnownGnssPosition;
  NavMode? _previousMode;

  @override
  Widget build(BuildContext context) {
    final dataService = context.watch<NavShieldDataService>();
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
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
        }

        // Overlay SOS / Crash alert when crash detected or SOS active
        if (state.crashDetected || state.sosActive) {
          return SosAlertOverlay(
            state: state,
            dataService: dataService,
          );
        }

        return Scaffold(
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: surfaceColor.withValues(alpha: isDark ? 0.92 : 0.96),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDeadReckoning
                                  ? violetColor.withValues(alpha: 0.6)
                                  : (isDark ? borderColor : cyanColor.withValues(alpha: 0.25)),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                              if (isDeadReckoning)
                                BoxShadow(
                                  color: violetColor.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (isDeadReckoning ? violetColor : cyanColor)
                                      .withValues(alpha: 0.18),
                                ),
                                child: Icon(
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
                                      'Turn right in 240 m',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'MG Road · toward destination',
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
                              GestureDetector(
                                onTap: () => DebugMenu.show(context, dataService),
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

                        // Status Pill (GNSS Aided Fix Precision) — Hidden during Dead Reckoning
                        if (!isDeadReckoning) ...[
                          const SizedBox(height: 6),
                          StatusPill(
                            mode: state.currentMode,
                            timeInCurrentMode: state.timeInCurrentMode,
                            uncertaintyMeters: state.uncertaintyEllipse.semiMajorAxis,
                            onOpenDebug: () => DebugMenu.show(context, dataService),
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
                        color: surfaceColor.withValues(alpha: isDark ? 0.92 : 0.96),
                        shape: CircleBorder(
                          side: BorderSide(
                            color: _mapBearing.abs() > 1.0
                                ? cyanColor.withValues(alpha: 0.7)
                                : (isDark ? borderColor : cyanColor.withValues(alpha: 0.35)),
                            width: 1.2,
                          ),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            _navMapKey.currentState?.resetNorth();
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            child: Transform.rotate(
                              angle: -_mapBearing * math.pi / 180.0,
                              child: Icon(
                                Icons.navigation_rounded,
                                size: 24,
                                color: _mapBearing.abs() > 1.0
                                    ? cyanColor
                                    : (isDark ? secondaryTextColor : cyanColor),
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
                      color: surfaceColor.withValues(alpha: isDark ? 0.94 : 0.98),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? borderColor
                            : (isDeadReckoning
                                ? violetColor.withValues(alpha: 0.35)
                                : cyanColor.withValues(alpha: 0.25)),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
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

  void _endNavigation(BuildContext context, NavShieldDataService dataService, SettingsService settings) {
    final summary = dataService.endTrip();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => TripSummaryScreen(
          summary: summary,
          settings: settings,
          onNewTrip: () {
            dataService.resetTrip();
            Navigator.of(ctx).pop();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const DestinationEntryScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}

