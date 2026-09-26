import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/nav_shield_data_service.dart';
import '../services/overlay_navigation_service.dart';
import '../services/settings_service.dart';
import '../services/trip_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/liquid_glass_card.dart';
import '../widgets/mapbox_nav_map.dart';
import 'destination_entry_screen.dart';

/// Screen 4: TRIP SUMMARY SCREEN
///
/// Principles:
/// - Distance, duration, max drift estimate
/// - GNSS-denied vs GNSS-aided time as a simple horizontal split bar (not a pie chart)
/// - Route map with path colored by mode (solid blue = GNSS-aided, dashed/amber = dead-reckoning)
/// - Parked vehicle floor level & note confirmation for Find My Car
class TripSummaryScreen extends StatefulWidget {
  final TripSummary summary;
  final SettingsService settings;
  final VoidCallback? onNewTrip;

  const TripSummaryScreen({
    super.key,
    required this.summary,
    required this.settings,
    this.onNewTrip,
  });

  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen> {
  bool _isNavigatingHome = false;

  void _handleStartNewTrip() {
    if (_isNavigatingHome) return;
    _isNavigatingHome = true;

    // 1. Reset data service if available in context
    try {
      final dataService = context.read<NavShieldDataService>();
      dataService.resetTrip();
    } catch (_) {}

    // 2. Clear any lingering background notifications or overlay
    try {
      TripNotificationService.instance.cancelTripNotification();
      OverlayNavigationService.instance.closeOverlay();
    } catch (_) {}

    // 3. Invoke caller's callback if provided
    try {
      widget.onNewTrip?.call();
    } catch (_) {}

    // 4. Safely navigate to DestinationEntryScreen (Navigate / Home), clearing the entire stack
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const DestinationEntryScreen(),
        ),
        (route) => false,
      );
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final settings = widget.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceSubtle = isDark ? AppColors.darkSurfaceSubtle : AppColors.lightSurfaceSubtle;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;
    final amberColor = isDark ? AppColors.darkAmber : AppColors.lightAmber;

    final gnssPercent = (summary.gnssAidedRatio * 100).toInt();
    final drPercent = 100 - gnssPercent;

    // Segment route points into continuous polylines by mode
    final polylines = <Polyline>[];
    if (summary.route.isNotEmpty) {
      List<LatLng> currentSegment = [];
      NavMode? currentMode;

      for (final pt in summary.route) {
        if (currentMode == null) {
          currentMode = pt.mode;
          currentSegment.add(pt.point);
        } else if (currentMode == pt.mode) {
          currentSegment.add(pt.point);
        } else {
          // Finish previous segment
          if (currentSegment.length > 1) {
            polylines.add(Polyline(
              points: List.from(currentSegment),
              strokeWidth: 4.0,
              color: currentMode == NavMode.gnssAided ? cyanColor : amberColor,
            ));
          }
          currentMode = pt.mode;
          currentSegment = [currentSegment.last, pt.point];
        }
      }
      if (currentSegment.length > 1) {
        polylines.add(Polyline(
          points: currentSegment,
          strokeWidth: 4.0,
          color: currentMode == NavMode.gnssAided ? cyanColor : amberColor,
        ));
      }
    }

    final initialCenter = summary.route.isNotEmpty
        ? summary.route.first.point
        : const LatLng(12.971598, 77.594566);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleStartNewTrip();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('trip_summary_close_button'),
          icon: Icon(Icons.close, color: primaryTextColor),
          onPressed: _handleStartNewTrip,
        ),
        title: Text(
          'Trip Summary',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: GalaxyBackground(
        child: SafeArea(
          child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          children: [
            // 1. Destination & Completion Status Card (Liquid Glass)
            LiquidGlassCard(
              glowColor: summary.destinationReached ? (isDark ? AppColors.darkGreen : AppColors.lightGreen) : amberColor,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cyanColor.withValues(alpha: isDark ? 0.20 : 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: cyanColor.withValues(alpha: 0.35), width: 0.8),
                    ),
                    child: Icon(Icons.flag_rounded, color: cyanColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.destinationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary.destinationReached
                              ? 'Destination reached successfully'
                              : 'Navigation concluded before destination',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (summary.destinationReached
                              ? (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                              : amberColor)
                          .withValues(alpha: isDark ? 0.22 : 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (summary.destinationReached
                                ? (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                                : amberColor)
                            .withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (summary.destinationReached
                                  ? (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                                  : amberColor)
                              .withValues(alpha: isDark ? 0.30 : 0.10),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      summary.destinationReached ? 'REACHED' : 'ENDED EARLY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: summary.destinationReached
                            ? (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                            : amberColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Primary Glanceable Stats
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'DISTANCE',
                    value: settings.formatDistance(summary.totalDistanceKm),
                    primaryColor: primaryTextColor,
                    secondaryColor: secondaryTextColor,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'DURATION',
                    value: _formatDuration(summary.totalDuration),
                    primaryColor: primaryTextColor,
                    secondaryColor: secondaryTextColor,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'MAX DRIFT',
                    value: '${summary.maxDriftPercent.toStringAsFixed(1)}%',
                    primaryColor: primaryTextColor,
                    secondaryColor: secondaryTextColor,
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. Horizontal Split Bar (GNSS-Denied vs GNSS-Aided)
            Text(
              'GNSS COVERAGE ANALYSIS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 10),

            // Proportional split bar with subtle glow
            Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: surfaceSubtle,
                boxShadow: [
                  BoxShadow(
                    color: cyanColor.withValues(alpha: isDark ? 0.20 : 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // GNSS-aided segment
                  if (gnssPercent > 0)
                    Expanded(
                      flex: gnssPercent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cyanColor, cyanColor.withValues(alpha: 0.85)],
                          ),
                        ),
                      ),
                    ),
                  // Dead-reckoning segment
                  if (drPercent > 0)
                    Expanded(
                      flex: drPercent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [amberColor, amberColor.withValues(alpha: 0.85)],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Split Bar Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: cyanColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: cyanColor.withValues(alpha: 0.6), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'GNSS Aided: $gnssPercent% (${_formatDuration(summary.gnssAidedDuration)})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: amberColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: amberColor.withValues(alpha: 0.6), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dead Reckoning: $drPercent% (${_formatDuration(summary.deadReckoningDuration)})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 28),

            // 4. Route Reconstruction Map Preview with Planned vs Actual Comparison
            Text(
              'ROUTE RECONSTRUCTION (PLANNED VS ACTUAL)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.darkLuminousBorder : borderColor,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: MapboxNavMap(
                state: NavShieldState.initial(),
                isDark: isDark,
                plannedRoute: summary.plannedRoute.isNotEmpty
                    ? PlannedRoute(
                        destination: summary.destination ??
                            (summary.route.isNotEmpty
                                ? summary.route.last.point
                                : const LatLng(12.971598, 77.594566)),
                        destinationName: summary.destinationName,
                        waypoints: summary.plannedRoute,
                        totalDistanceKm: summary.totalDistanceKm,
                        estimatedDuration: summary.totalDuration,
                      )
                    : null,
                routeHistory: summary.route,
                isStaticPreview: true,
                staticCenter: initialCenter,
                initialZoom: 15.0,
              ),
            ),
            const SizedBox(height: 10),

            // Map Legend
            Wrap(
              spacing: 14,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: isDark ? Colors.white38 : Colors.black38),
                    const SizedBox(width: 4),
                    Text('Planned Route', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: cyanColor),
                    const SizedBox(width: 4),
                    Text('GNSS Traveled', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: amberColor),
                    const SizedBox(width: 4),
                    Text('DR Deviation', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 6. Return / New Trip Action Button (Glowing Cyan Gradient)
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: AppColors.cyanGlowGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkCyan.withValues(alpha: 0.40),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                key: const ValueKey('start_new_trip_button'),
                onPressed: _handleStartNewTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: const Color(0xFF030712),
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Start New Trip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Color(0xFF030712),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      ),
    ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.darkSurfaceElevated.withValues(alpha: 0.85),
                  AppColors.darkSurfaceSubtle.withValues(alpha: 0.70),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95),
                  AppColors.lightSurfaceElevated.withValues(alpha: 0.85),
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkLuminousBorder : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
