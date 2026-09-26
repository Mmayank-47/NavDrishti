import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../services/nav_shield_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import 'sensor_diagnostics_screen.dart';

/// Screen 3: CALIBRATION SCREEN
///
/// Principles:
/// - "Mount your phone, then drive straight for 10 seconds"
/// - Clean progress indicator while alignment_status == "CALIBRATING"
/// - Clear success state once "CALIBRATED", with way to recalibrate later
class CalibrationScreen extends StatefulWidget {
  final NavShieldDataService dataService;

  const CalibrationScreen({
    super.key,
    required this.dataService,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final blueColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;

    return StreamBuilder<NavShieldState>(
      stream: widget.dataService.stateStream,
      initialData: widget.dataService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.dataService.currentState;
        final isCalibrating = state.alignmentStatus == AlignmentStatus.calibrating;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: primaryTextColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Sensor Alignment',
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: GalaxyBackground(
            child: SafeArea(
              child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(height: 10),

                  // Center Instruction & Graphic
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Phone Mount Graphic with concentric glow
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    (isCalibrating ? blueColor : const Color(0xFF10B981)).withValues(alpha: 0.22),
                                    AppColors.darkSurfaceElevated.withValues(alpha: 0.70),
                                  ]
                                : [
                                    Colors.white,
                                    (isCalibrating ? blueColor : const Color(0xFF10B981)).withValues(alpha: 0.12),
                                  ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (isCalibrating ? blueColor : const Color(0xFF10B981)).withValues(alpha: isDark ? 0.60 : 0.40),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isCalibrating ? blueColor : const Color(0xFF10B981)).withValues(alpha: isDark ? 0.35 : 0.15),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Icon(
                          isCalibrating ? Icons.navigation_rounded : Icons.check_circle_rounded,
                          size: 54,
                          color: isCalibrating ? blueColor : const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(height: 28),

                      Text(
                        isCalibrating ? 'Aligning Sensors' : 'Sensors Calibrated',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: primaryTextColor,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          isCalibrating
                              ? 'Mount your phone firmly in the vehicle dock, then drive straight for 10 seconds.'
                              : 'IMU orientation aligned with vehicle forward axis. Dead reckoning is active and calibrated.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Progress Indicator during calibration
                      if (isCalibrating) ...[
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(blueColor),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Detecting vehicle forward vector...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: secondaryTextColor,
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.5 : 0.4),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.10),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, color: Color(0xFF10B981), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'READY FOR NAVIGATION',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Bottom Action Buttons
                  Column(
                    children: [
                      if (!isCalibrating) ...[
                        Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppColors.cyanGlowGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: blueColor.withValues(alpha: 0.40),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
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
                              'Return to Navigation',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                                color: Color(0xFF030712),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () {
                              widget.dataService.startCalibration();
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isDark ? blueColor.withValues(alpha: 0.45) : blueColor.withValues(alpha: 0.35),
                              ),
                              backgroundColor: isDark ? AppColors.darkSurfaceSubtle.withValues(alpha: 0.6) : blueColor.withValues(alpha: 0.04),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Recalibrate Alignment',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? primaryTextColor : blueColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SensorDiagnosticsScreen(),
                                ),
                              );
                            },
                            icon: Icon(Icons.sensors_rounded, size: 18, color: blueColor),
                            label: Text(
                              'Run Hardware Sensor Diagnostics',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: blueColor,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: secondaryTextColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ),
        );
      },
    );
  }
}
