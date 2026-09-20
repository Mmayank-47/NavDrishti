import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet collapsed to a thin handle by default.
/// Swiping up reveals glanceable trip stats and navigation controls.
class TripBottomSheet extends StatelessWidget {
  final NavShieldState state;
  final SettingsService settings;
  final VoidCallback onEndTrip;
  final VoidCallback onCalibrate;
  final VoidCallback onSettings;

  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<double>? snapSizes;

  const TripBottomSheet({
    super.key,
    required this.state,
    required this.settings,
    required this.onEndTrip,
    required this.onCalibrate,
    required this.onSettings,
    this.initialChildSize = 0.60,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.85,
    this.snapSizes = const [0.35, 0.60, 0.85],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final isDeadReckoning = state.currentMode == NavMode.deadReckoning;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightCyan;
    final violetColor = isDark ? AppColors.darkViolet : AppColors.lightViolet;
    final amberColor = isDark ? AppColors.darkAmber : AppColors.lightAmber;

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      snap: snapSizes != null,
      snapSizes: snapSizes,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: borderColor, width: 1.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // 1. Thin Handle Bar
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF323B47) : const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. Collapsed glanceable summary line
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trip & Sensor Telemetry',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primaryTextColor,
                    ),
                  ),
                  Text(
                    settings.formatDistance(state.distanceTraveledKm),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // 3. Subsystem Mode & Health Status Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceSubtle.withValues(alpha: 0.8)
                      : (isDeadReckoning
                          ? violetColor.withValues(alpha: 0.08)
                          : cyanColor.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDeadReckoning
                        ? violetColor.withValues(alpha: isDark ? 0.5 : 0.4)
                        : cyanColor.withValues(alpha: isDark ? 0.4 : 0.35),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDeadReckoning ? violetColor : cyanColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDeadReckoning ? 'INS ACTIVE' : 'GNSS + INS FUSED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: isDeadReckoning ? violetColor : cyanColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      isDeadReckoning ? '84% HEALTH' : '98% HEALTH',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: isDeadReckoning
                            ? amberColor
                            : (isDark ? AppColors.darkGreen : AppColors.lightGreen),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. Glanceable Stats Grid (Accuracy, Speed, Distance, Drift, Altitude, Satellites)
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'ACCURACY',
                      value: '±${state.uncertaintyEllipse.semiMajorAxis.toStringAsFixed(1)} m',
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'SPEED',
                      value: settings.formatSpeed(state.speedKmh),
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'DISTANCE',
                      value: settings.formatDistance(state.distanceTraveledKm),
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'DRIFT ESTIMATE',
                      value: '${state.driftEstimatePercent.toStringAsFixed(1)}%',
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'ALTITUDE',
                      value: '${state.altitude.toStringAsFixed(0)} m',
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'SATELLITES',
                      value: isDeadReckoning ? 'Lost' : '14 Locked',
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      isDark: isDark,
                      accentColor: isDeadReckoning ? violetColor : cyanColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 5. Quick Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCalibrate,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: isDark ? borderColor : cyanColor.withValues(alpha: 0.35),
                        ),
                        backgroundColor: isDark ? Colors.transparent : cyanColor.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Calibrate',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? primaryTextColor : cyanColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSettings,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: isDark ? borderColor : primaryTextColor.withValues(alpha: 0.2),
                        ),
                        backgroundColor: isDark ? Colors.transparent : primaryTextColor.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      key: const ValueKey('sheet_end_trip_button'),
                      onPressed: onEndTrip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppColors.darkRed : AppColors.lightRed,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'End Trip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final bool isDark;
  final Color? accentColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.isDark,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceSubtle
            : (accentColor != null
                ? accentColor!.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : (accentColor != null
                  ? accentColor!.withValues(alpha: 0.22)
                  : const Color(0xFFCBD5E1)),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark ? secondaryTextColor : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
