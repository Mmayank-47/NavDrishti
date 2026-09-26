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
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;

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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xF2312048),
                      const Color(0xF8203B6F),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.96),
                      const Color(0xFFEFE8FC).withValues(alpha: 0.94),
                    ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDeadReckoning
                    ? AppColors.orchidPink.withValues(alpha: 0.70)
                    : (isDark
                        ? AppColors.periwinkle.withValues(alpha: 0.55)
                        : AppColors.mediumIndigo.withValues(alpha: 0.40)),
                width: 1.4,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.60 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
              BoxShadow(
                color: (isDeadReckoning ? AppColors.orchidPink : AppColors.periwinkle)
                    .withValues(alpha: isDark ? 0.25 : 0.12),
                blurRadius: 16,
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // 1. Thin Handle Bar with Glow
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
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
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: primaryTextColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDeadReckoning ? violetColor : cyanColor)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isDeadReckoning ? violetColor : cyanColor)
                            .withValues(alpha: 0.35),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      settings.formatDistance(state.distanceTraveledKm),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDeadReckoning ? violetColor : cyanColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // 3. Subsystem Mode & Health Status Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            (isDeadReckoning ? violetColor : cyanColor)
                                .withValues(alpha: 0.16),
                            const Color(0xFF0F172A).withValues(alpha: 0.70),
                          ]
                        : [
                            (isDeadReckoning ? violetColor : cyanColor)
                                .withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.90),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDeadReckoning
                        ? violetColor.withValues(alpha: isDark ? 0.65 : 0.5)
                        : cyanColor.withValues(alpha: isDark ? 0.55 : 0.45),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDeadReckoning ? violetColor : cyanColor)
                          .withValues(alpha: isDark ? 0.22 : 0.10),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDeadReckoning ? violetColor : cyanColor,
                            boxShadow: [
                              BoxShadow(
                                color: isDeadReckoning ? violetColor : cyanColor,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDeadReckoning ? 'INS ACTIVE' : 'GNSS + INS FUSED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: isDeadReckoning ? violetColor : cyanColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      isDeadReckoning ? '84% HEALTH' : '98% HEALTH',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
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
                          color: isDark
                              ? cyanColor.withValues(alpha: 0.45)
                              : cyanColor.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        backgroundColor: isDark
                            ? cyanColor.withValues(alpha: 0.08)
                            : cyanColor.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Calibrate',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
                          color: isDark
                              ? AppColors.darkBorderHighlight
                              : primaryTextColor.withValues(alpha: 0.2),
                          width: 1.2,
                        ),
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : primaryTextColor.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
                        elevation: 4,
                        shadowColor: (isDark ? AppColors.darkRed : AppColors.lightRed)
                            .withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'End Trip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
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
    final effectiveAccent = accentColor ?? (isDark ? AppColors.darkCyan : AppColors.lightCyan);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF131D38).withValues(alpha: 0.75),
                  const Color(0xFF090E1F).withValues(alpha: 0.65),
                ]
              : [
                  Colors.white.withValues(alpha: 0.90),
                  const Color(0xFFF1F5F9).withValues(alpha: 0.80),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? effectiveAccent.withValues(alpha: 0.30)
              : effectiveAccent.withValues(alpha: 0.22),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: effectiveAccent.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isDark ? secondaryTextColor : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
