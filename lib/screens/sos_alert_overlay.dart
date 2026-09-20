import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../services/nav_shield_data_service.dart';
import '../theme/app_theme.dart';

/// Screen 2: SOS / CRASH ALERT OVERLAY
///
/// Principles:
/// - Full-screen red/orange high-priority alert
/// - Large centered text: "Possible impact detected"
/// - Large countdown ring (30s down to 0)
/// - Oversized, unmistakable "I'M OK — CANCEL" button, easily tapable under stress
/// - Last-known position & heading readout for emergency dispatch
/// - Auto-returns on cancel or expiry
class SosAlertOverlay extends StatelessWidget {
  final NavShieldState state;
  final NavShieldDataService dataService;

  const SosAlertOverlay({
    super.key,
    required this.state,
    required this.dataService,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alertRed = isDark ? AppColors.darkRed : AppColors.lightRed;
    final countdown = state.sosCountdownSeconds;
    final progress = (countdown / 30.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: alertRed,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Top Emergency Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'EMERGENCY IMPACT PROTOCOL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Center: Large Text and Countdown Ring
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Possible impact detected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.impactMagnitude > 0
                        ? 'Impact magnitude: ${state.impactMagnitude.toStringAsFixed(1)}g · Confidence ${(state.crashConfidence * 100).toInt()}%'
                        : 'Manual SOS signal initiated',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Large Countdown Ring (30 -> 0)
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 170,
                          height: 170,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.white.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$countdown',
                              style: const TextStyle(
                                fontSize: 62,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            const Text(
                              'SECONDS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Dispatch details
                  Text(
                    'Last-known: ${state.latitude.toStringAsFixed(4)}° N, ${state.longitude.toStringAsFixed(4)}° E\nHeading: ${state.heading.toStringAsFixed(0)}° · Altitude: ${state.altitude.toStringAsFixed(0)}m',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.white.withValues(alpha: 0.90),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Emergency dispatch will be contacted automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),

              // 3. Bottom: Unmistakable "I'M OK — CANCEL" Button
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () {
                    dataService.cancelSos();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: alertRed,
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    "I'M OK — CANCEL",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: alertRed,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
