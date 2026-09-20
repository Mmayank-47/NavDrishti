import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../services/nav_shield_data_service.dart';
import '../theme/app_theme.dart';
import 'sensor_diagnostics_screen.dart';

/// Screen: SYSTEM HEALTH DASHBOARD
///
/// Principles:
/// - "System Health" header
/// - Overall green "All systems nominal" banner (or amber/violet when degraded)
/// - Detailed status rows for GNSS, IMU, INS, and Fusion
/// - Wired to live NavShieldState stream
/// - Clean dark navy glassmorphic cards with glowing status indicators
class SystemHealthScreen extends StatelessWidget {
  final bool showBackButton;

  const SystemHealthScreen({
    super.key,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final dataService = context.watch<NavShieldDataService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return StreamBuilder<NavShieldState>(
      stream: dataService.stateStream,
      initialData: dataService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? dataService.currentState;
        final isDeadReckoning = state.currentMode == NavMode.deadReckoning;
        final isCalibrated = state.alignmentStatus == AlignmentStatus.calibrated;
        final isNominal = !isDeadReckoning && isCalibrated && !state.crashDetected;

        final bannerColor = isNominal
            ? (isDark ? AppColors.darkGreen : AppColors.lightGreen)
            : (isDark ? AppColors.darkAmber : AppColors.lightAmber);

        return Scaffold(
          backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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
            actions: [
              IconButton(
                icon: Icon(Icons.healing_rounded, color: isDark ? AppColors.darkCyan : AppColors.lightBlue),
                tooltip: 'Hardware Diagnostics',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SensorDiagnosticsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              children: [
                // 1. Overall Systems Status Banner
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: bannerColor.withValues(alpha: isDark ? 0.15 : 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: bannerColor.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: bannerColor.withValues(alpha: isDark ? 0.20 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: bannerColor.withValues(alpha: 0.25),
                        ),
                        child: Icon(
                          isNominal ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          color: bannerColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isNominal ? 'ALL SYSTEMS NOMINAL' : 'DEGRADED DEAD-RECKONING ACTIVE',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: bannerColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isNominal
                                  ? 'GNSS & 6-DoF INS tightly coupled. Localization optimal.'
                                  : 'Satellite lock lost. Operating on inertial navigation.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 2. GNSS Subsystem Card
                _SubsystemCard(
                  title: 'GNSS Subsystem',
                  statusPillText: isDeadReckoning ? 'DENIED' : 'LOCKED',
                  statusPillColor: isDeadReckoning
                      ? (isDark ? AppColors.darkViolet : AppColors.lightViolet)
                      : (isDark ? AppColors.darkBlue : AppColors.lightBlue),
                  icon: Icons.satellite_alt_rounded,
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  metrics: [
                    _MetricItem('Accuracy', '±${state.uncertaintyEllipse.semiMajorAxis.toStringAsFixed(1)} m'),
                    _MetricItem('Satellites', isDeadReckoning ? '0 Locked' : '14 Locked (GPS/Galileo)'),
                    _MetricItem('HDOP', isDeadReckoning ? 'N/A' : '0.85 (Optimal)'),
                    _MetricItem('Signal State', isDeadReckoning ? 'Multipath / Outage' : '3D High-Precision Fix'),
                  ],
                ),

                const SizedBox(height: 14),

                // 3. IMU Subsystem Card
                _SubsystemCard(
                  title: 'IMU Subsystem',
                  statusPillText: 'ONLINE',
                  statusPillColor: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                  icon: Icons.screen_rotation_rounded,
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  metrics: [
                    _MetricItem('Sampling Rate', '100 Hz (Real-time)'),
                    _MetricItem('Alignment', state.alignmentStatus.value),
                    _MetricItem('Axes Active', '3-Axis Accel + 3-Axis Gyro'),
                    _MetricItem('Calibration', isCalibrated ? 'Calibrated' : 'Calibrating...'),
                  ],
                ),

                const SizedBox(height: 14),

                // 4. INS Dead-Reckoning Subsystem Card (with live sparkline icon)
                _SubsystemCard(
                  title: 'INS Subsystem',
                  statusPillText: isDeadReckoning ? 'ACTIVE' : 'STANDBY',
                  statusPillColor: isDeadReckoning
                      ? (isDark ? AppColors.darkViolet : AppColors.lightViolet)
                      : (isDark ? AppColors.darkGreen : AppColors.lightGreen),
                  icon: Icons.timeline_rounded,
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  hasSparkline: true,
                  metrics: [
                    _MetricItem('Drift Estimate', '${state.driftEstimatePercent.toStringAsFixed(1)}%'),
                    _MetricItem('Confidence', isDeadReckoning ? '84% (Estimated)' : '98% (High)'),
                    _MetricItem('Propagation', 'Zero-Velocity Update (ZUPT)'),
                    _MetricItem('Duration in Mode', '${state.timeInCurrentMode} s'),
                  ],
                ),

                const SizedBox(height: 14),

                // 5. Fusion Engine Subsystem Card
                _SubsystemCard(
                  title: 'EKF Fusion Engine',
                  statusPillText: state.currentMode.value,
                  statusPillColor: isDeadReckoning
                      ? (isDark ? AppColors.darkViolet : AppColors.lightViolet)
                      : (isDark ? AppColors.darkCyan : AppColors.lightCyan),
                  icon: Icons.hub_rounded,
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  metrics: [
                    _MetricItem('System Health', isDeadReckoning ? '88% Operational' : '99% Optimal'),
                    _MetricItem('Filter Mode', isDeadReckoning ? 'Inertial Dead Reckoning' : 'Tightly-Coupled GNSS/INS'),
                    _MetricItem('Covariance', 'Stable (1-Sigma Bound)'),
                    _MetricItem('Speed', '${state.speedKmh.toStringAsFixed(1)} km/h'),
                  ],
                ),

                const SizedBox(height: 20),

                // 6. Diagnostics Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppColors.darkSurfaceSubtle : AppColors.lightBlue.withValues(alpha: 0.08),
                    foregroundColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBlue.withValues(alpha: 0.30),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: const Text(
                    'Run Guided Sensor Diagnostics',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SensorDiagnosticsScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  _MetricItem(this.label, this.value);
}

class _SubsystemCard extends StatelessWidget {
  final String title;
  final String statusPillText;
  final Color statusPillColor;
  final IconData icon;
  final bool isDark;
  final Color surfaceColor;
  final Color borderColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final bool hasSparkline;
  final List<_MetricItem> metrics;

  const _SubsystemCard({
    required this.title,
    required this.statusPillText,
    required this.statusPillColor,
    required this.icon,
    required this.isDark,
    required this.surfaceColor,
    required this.borderColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    this.hasSparkline = false,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? surfaceColor.withValues(alpha: 0.90)
            : statusPillColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? borderColor : statusPillColor.withValues(alpha: 0.28),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : statusPillColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusPillColor.withValues(alpha: 0.15),
                ),
                child: Icon(icon, size: 18, color: statusPillColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
              ),
              if (hasSparkline) ...[
                // Small live sparkline indicator
                SizedBox(
                  width: 36,
                  height: 16,
                  child: CustomPaint(
                    painter: _SparklinePainter(color: statusPillColor),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusPillColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusPillColor.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusPillColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusPillText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: statusPillColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: isDark ? borderColor : statusPillColor.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: 12),

          // Metrics Grid (2x2)
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: metrics.map((m) {
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 76) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..lineTo(size.width * 0.25, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.8)
      ..lineTo(size.width * 0.75, size.height * 0.3)
      ..lineTo(size.width, size.height * 0.4);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => false;
}
