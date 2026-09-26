import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/nav_shield_data_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/nav_toast.dart';

/// Unobtrusive debug sheet for testing and demoing NAV-SHIELD features.
///
/// Restyled with clean dark pill-button cards matching the reference mockup.
class DebugMenu extends StatelessWidget {
  final NavShieldDataService dataService;
  final VoidCallback? onSimulateRouteDeviation;
  final VoidCallback? onSimulateOutlierRejection;
  final VoidCallback? onSimulateGnssOutage;
  final VoidCallback? onSimulateGnssRecovered;

  const DebugMenu({
    super.key,
    required this.dataService,
    this.onSimulateRouteDeviation,
    this.onSimulateOutlierRejection,
    this.onSimulateGnssOutage,
    this.onSimulateGnssRecovered,
  });

  static void show(
    BuildContext context,
    NavShieldDataService service, {
    VoidCallback? onSimulateRouteDeviation,
    VoidCallback? onSimulateOutlierRejection,
    VoidCallback? onSimulateGnssOutage,
    VoidCallback? onSimulateGnssRecovered,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DebugMenu(
        dataService: service,
        onSimulateRouteDeviation: onSimulateRouteDeviation,
        onSimulateOutlierRejection: onSimulateOutlierRejection,
        onSimulateGnssOutage: onSimulateGnssOutage,
        onSimulateGnssRecovered: onSimulateGnssRecovered,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightCyan;
    final redColor = isDark ? AppColors.darkRed : AppColors.lightRed;
    final violetColor = isDark ? AppColors.darkViolet : AppColors.lightViolet;
    final amberColor = isDark ? AppColors.darkAmber : AppColors.lightAmber;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xF20B132B),
                      const Color(0xFA030712),
                    ]
                  : [
                      Colors.white,
                      const Color(0xF2F1F5F9),
                    ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.darkLuminousBorder : const Color(0x80CBD5E1),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.60 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: cyanColor, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Demo & Debug Controls',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: primaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: secondaryTextColor,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'Simulate real-world resilience scenarios and edge conditions.',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              const SizedBox(height: 18),

              // Action Buttons in Clean Dark Pill-Card Style
              _DebugActionButton(
                icon: Icons.warning_rounded,
                iconColor: redColor,
                title: 'Simulate Crash / High-G Impact',
                subtitle: 'Triggers crash alert & 30s emergency SOS countdown',
                isDark: isDark,
                borderColor: redColor.withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  dataService.triggerSimulatedCrash();
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.swap_horiz_rounded,
                iconColor: violetColor,
                title: 'Toggle GNSS / Dead Reckoning',
                subtitle: 'Switches between fused satellite lock & inertial propagation',
                isDark: isDark,
                borderColor: violetColor.withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  dataService.toggleMode();
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.alt_route_rounded,
                iconColor: cyanColor,
                title: 'Simulate Route Deviation',
                subtitle: 'Triggers active "Rerouting..." UI recalculation state',
                isDark: isDark,
                borderColor: cyanColor.withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  if (onSimulateRouteDeviation != null) {
                    onSimulateRouteDeviation!();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Simulated Route Deviation triggered')),
                    );
                  }
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.filter_alt_rounded,
                iconColor: amberColor,
                title: 'Simulate GNSS Outlier Rejection',
                subtitle: 'Triggers Huber M-estimator / χ² multipath rejection cue',
                isDark: isDark,
                borderColor: amberColor.withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  if (onSimulateOutlierRejection != null) {
                    onSimulateOutlierRejection!();
                  } else {
                    dataService.triggerSimulatedOutlierRejection();
                  }
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.satellite_alt_rounded,
                iconColor: amberColor,
                title: 'Simulate GNSS Outage / Degrading',
                subtitle: 'Showcases amber "LOW CONFIDENCE" transition toast',
                isDark: isDark,
                borderColor: amberColor.withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  if (onSimulateGnssOutage != null) {
                    onSimulateGnssOutage!();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        duration: Duration(seconds: 3),
                        content: NavToast(type: NavToastType.lowConfidence),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.check_circle_rounded,
                iconColor: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                title: 'Simulate GNSS Recovered',
                subtitle: 'Transitions through REACQUIRING annealing to GNSS-Aided',
                isDark: isDark,
                borderColor: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.35),
                onTap: () {
                  Navigator.of(context).pop();
                  if (onSimulateGnssRecovered != null) {
                    onSimulateGnssRecovered!();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        duration: Duration(seconds: 3),
                        content: NavToast(type: NavToastType.gnssRecovered),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 10),

              _DebugActionButton(
                icon: Icons.restart_alt_rounded,
                iconColor: secondaryTextColor,
                title: 'Reset Trip Statistics',
                subtitle: 'Clears distance, drift and restarts breadcrumb track',
                isDark: isDark,
                onTap: () {
                  Navigator.of(context).pop();
                  dataService.resetTrip();
                },
              ),

              const SizedBox(height: 14),
              Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              const SizedBox(height: 10),

              // Live WebSocket Backend Toggle
              Consumer<SettingsService>(
                builder: (context, settings, _) {
                  return Material(
                    color: (isDark ? AppColors.darkSurfaceSubtle : AppColors.lightSurfaceSubtle)
                        .withValues(alpha: 0.8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.sensors_rounded,
                          color: settings.useRealBackend ? const Color(0xFF10B981) : secondaryTextColor,
                        ),
                        title: Text(
                          'Live Python WebSocket Backend',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        subtitle: Text(
                          settings.useRealBackend
                              ? 'Connecting to ws://${settings.backendHost}:${settings.backendPort}'
                              : 'Using realistic simulated 10Hz Bangalore telemetry',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                        value: settings.useRealBackend,
                        onChanged: (val) {
                          settings.setUseRealBackend(val);
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }
}

class _DebugActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final Color? borderColor;
  final VoidCallback onTap;

  const _DebugActionButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = borderColor ?? (isDark ? iconColor.withValues(alpha: 0.35) : AppColors.lightBorder);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      AppColors.darkSurfaceElevated.withValues(alpha: 0.80),
                      AppColors.darkSurfaceSubtle.withValues(alpha: 0.65),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      AppColors.lightSurfaceElevated.withValues(alpha: 0.85),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: effectiveBorder, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              if (isDark)
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.08),
                  blurRadius: 10,
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: isDark ? 0.20 : 0.15),
                  border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
