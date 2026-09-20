import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mapbox_nav_map.dart';

/// Screen 4: TRIP SUMMARY SCREEN
///
/// Principles:
/// - Distance, duration, max drift estimate
/// - GNSS-denied vs GNSS-aided time as a simple horizontal split bar (not a pie chart)
/// - Route map with path colored by mode (solid blue = GNSS-aided, dashed/amber = dead-reckoning)
class TripSummaryScreen extends StatelessWidget {
  final TripSummary summary;
  final SettingsService settings;
  final VoidCallback onNewTrip;

  const TripSummaryScreen({
    super.key,
    required this.summary,
    required this.settings,
    required this.onNewTrip,
  });

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final surfaceSubtle = isDark ? AppColors.darkSurfaceSubtle : AppColors.lightSurfaceSubtle;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final blueColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;
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
              color: currentMode == NavMode.gnssAided ? blueColor : amberColor,
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
          color: currentMode == NavMode.gnssAided ? blueColor : amberColor,
        ));
      }
    }

    final initialCenter = summary.route.isNotEmpty
        ? summary.route.first.point
        : const LatLng(12.971598, 77.594566);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: primaryTextColor),
          onPressed: onNewTrip,
        ),
        title: Text(
          'Trip Summary',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          children: [
            // 1. Destination & Completion Status Card
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: blueColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.flag_rounded, color: blueColor, size: 20),
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
                      color: summary.destinationReached
                          ? blueColor.withValues(alpha: 0.15)
                          : amberColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: summary.destinationReached ? blueColor : amberColor,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      summary.destinationReached ? 'REACHED' : 'ENDED EARLY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: summary.destinationReached ? blueColor : amberColor,
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
                    bgColor: surfaceColor,
                    borderColor: borderColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'DURATION',
                    value: _formatDuration(summary.totalDuration),
                    primaryColor: primaryTextColor,
                    secondaryColor: secondaryTextColor,
                    bgColor: surfaceColor,
                    borderColor: borderColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'MAX DRIFT',
                    value: '${summary.maxDriftPercent.toStringAsFixed(1)}%',
                    primaryColor: primaryTextColor,
                    secondaryColor: secondaryTextColor,
                    bgColor: surfaceColor,
                    borderColor: borderColor,
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
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 10),

            // Proportional split bar
            Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: surfaceSubtle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // GNSS-aided segment
                  if (gnssPercent > 0)
                    Expanded(
                      flex: gnssPercent,
                      child: Container(
                        color: blueColor,
                      ),
                    ),
                  // Dead-reckoning segment
                  if (drPercent > 0)
                    Expanded(
                      flex: drPercent,
                      child: Container(
                        color: amberColor,
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
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: blueColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      'GNSS Aided: $gnssPercent% (${_formatDuration(summary.gnssAidedDuration)})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: amberColor, shape: BoxShape.circle)),
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
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              height: 250,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.0),
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
            const SizedBox(height: 8),

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
                    Container(width: 14, height: 3, color: blueColor),
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

            const SizedBox(height: 28),

            // 4. Return / New Trip Action Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: onNewTrip,
                style: FilledButton.styleFrom(
                  backgroundColor: blueColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Start New Trip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
  final Color bgColor;
  final Color borderColor;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.primaryColor,
    required this.secondaryColor,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
