import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/nav_shield_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/liquid_glass_card.dart';
import 'calibration_screen.dart';
import 'sensor_diagnostics_screen.dart';

/// Screen: SYSTEM HEALTH / SENSOR ACTIONS
///
/// Principles:
/// - Clean, focused page containing Sensor Actions:
///   1. Recalibrate Sensors (10-second forward vehicle alignment)
///   2. Run Guided Sensor Diagnostics (Hardware sensor health & telemetry test)
/// - Subsystem status cards (GNSS, IMU, INS, EKF) removed per user requirements.
/// - Polished galaxy glassmorphism styling consistent with NavShield design system.
class SystemHealthScreen extends StatelessWidget {
  final bool showBackButton;
  final VoidCallback? onRecalibrate;

  const SystemHealthScreen({
    super.key,
    this.showBackButton = false,
    this.onRecalibrate,
  });

  @override
  Widget build(BuildContext context) {
    final dataService = context.read<NavShieldDataService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;
    final violetColor = isDark ? AppColors.darkViolet : AppColors.lightViolet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: primaryTextColor),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          'System Health',
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
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            children: [
              // 1. Overview Header Card
              LiquidGlassCard(
                glowColor: cyanColor,
                borderColor: cyanColor.withValues(alpha: isDark ? 0.35 : 0.25),
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cyanColor.withValues(alpha: isDark ? 0.18 : 0.12),
                        border: Border.all(
                          color: cyanColor.withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cyanColor.withValues(alpha: isDark ? 0.35 : 0.15),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.sensors_rounded,
                        color: cyanColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sensor Management',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Calibrate 6-DoF inertial sensors and verify real-time hardware telemetry.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Sensor Actions Section Header
              Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.build_circle_outlined,
                      size: 15,
                      color: cyanColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'SENSOR ACTIONS',
                      style: TextStyle(
                        color: cyanColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Sensor Actions Card (Recalibrate & Guided Diagnostics)
              LiquidGlassCard(
                glowColor: cyanColor,
                borderColor: borderColor,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cyanColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cyanColor.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 20,
                          color: cyanColor,
                        ),
                      ),
                      title: Text(
                        'Recalibrate Sensors',
                        style: TextStyle(
                          color: primaryTextColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Perform 10-second forward vehicle alignment',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: secondaryTextColor,
                      ),
                      onTap: () {
                        if (onRecalibrate != null) {
                          onRecalibrate!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CalibrationScreen(dataService: dataService),
                            ),
                          );
                        }
                      },
                    ),
                    Divider(color: borderColor, height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: violetColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: violetColor.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Icon(
                          Icons.speed_rounded,
                          size: 20,
                          color: violetColor,
                        ),
                      ),
                      title: Text(
                        'Run Guided Sensor Diagnostics',
                        style: TextStyle(
                          color: primaryTextColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Hardware sensor health & 3-axis telemetry test',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: secondaryTextColor,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SensorDiagnosticsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 4. Guided Tips & Information Card
              LiquidGlassCard(
                glowColor: violetColor,
                borderColor: borderColor,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: violetColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SENSOR BEST PRACTICES',
                          style: TextStyle(
                            color: violetColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: violetColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Mount your phone firmly in the vehicle dock before starting calibration.',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: violetColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Run diagnostics if dead-reckoning drift increases during GNSS outages.',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
