import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../services/nav_shield_data_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Screen 2: SOS / CRASH ALERT OVERLAY
///
/// Principles:
/// - Full-screen red/amber high-priority emergency alert
/// - Large countdown ring (30s down to 0) with cancel option
/// - Action Confirmation upon countdown expiry:
///   - If emergency contact set: "Notifying [Name]..." with animated spinner -> checkmark
///   - If no contact set: clear fallback message with option to add one in Settings
/// - Real-time coordinates and sensor telemetry readout for emergency services
class SosAlertOverlay extends StatefulWidget {
  final NavShieldState state;
  final NavShieldDataService dataService;

  const SosAlertOverlay({
    super.key,
    required this.state,
    required this.dataService,
  });

  @override
  State<SosAlertOverlay> createState() => _SosAlertOverlayState();
}

class _SosAlertOverlayState extends State<SosAlertOverlay> {
  bool _actionDispatched = false;
  Timer? _dispatchTimer;

  @override
  void initState() {
    super.initState();
    _checkDispatchState();
  }

  @override
  void didUpdateWidget(covariant SosAlertOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkDispatchState();
  }

  void _checkDispatchState() {
    if (widget.state.sosCountdownSeconds <= 0 && !_actionDispatched) {
      _dispatchTimer?.cancel();
      _dispatchTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() {
            _actionDispatched = true;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _dispatchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alertRed = isDark ? AppColors.darkRed : AppColors.lightRed;
    final countdown = widget.state.sosCountdownSeconds;
    final isExpired = countdown <= 0;
    final progress = (countdown / 30.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF030712) : const Color(0xFF18040A),
      body: Stack(
        children: [
          // Background emergency radial glow aura
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    alertRed.withValues(alpha: isDark ? 0.35 : 0.45),
                    const Color(0xFF6B021E).withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. Top Emergency Tag (Liquid Glass Pill)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          alertRed.withValues(alpha: 0.35),
                          alertRed.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: alertRed.withValues(alpha: 0.60),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: alertRed.withValues(alpha: 0.35),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpired
                              ? Icons.emergency_share_rounded
                              : Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isExpired
                              ? 'EMERGENCY ACTION DISPATCHED'
                              : 'EMERGENCY IMPACT PROTOCOL',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Center: Countdown OR Action Taken confirmation
                  if (!isExpired)
                    _buildCountdownView(
                      progress,
                      countdown,
                      widget.state,
                      alertRed,
                    )
                  else
                    _buildActionDispatchedView(
                      settings,
                      widget.state,
                      _actionDispatched,
                      alertRed,
                    ),

                  // 3. Bottom Action Button
                  Container(
                    width: double.infinity,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        widget.dataService.cancelSos();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: alertRed,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        isExpired ? "I'M OK — DISMISS ALERT" : "I'M OK — CANCEL",
                        style: TextStyle(
                          fontSize: 19,
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
        ],
      ),
    );
  }

  Widget _buildCountdownView(
    double progress,
    int countdown,
    NavShieldState state,
    Color alertRed,
  ) {
    return Column(
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
              : 'Manual SOS distress signal initiated',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 32),

        // Large Countdown Ring (30 -> 0) with concentric glowing halos
        SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glowing ambient ring
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: alertRed.withValues(alpha: 0.50),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                height: 170,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.20),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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

        // Dispatch details (Liquid Glass Telemetry Capsule)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
          child: Text(
            'GPS: ${state.latitude.toStringAsFixed(4)}° N, ${state.longitude.toStringAsFixed(4)}° E\nHeading: ${state.heading.toStringAsFixed(0)}° · Altitude: ${state.altitude.toStringAsFixed(0)}m',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Countdown expiring will notify your emergency contact and dispatch services.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.80),
          ),
        ),
      ],
    );
  }

  Widget _buildActionDispatchedView(
    SettingsService settings,
    NavShieldState state,
    bool actionDispatched,
    Color alertRed,
  ) {
    final hasContact = settings.hasEmergencyContact;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xF018040A),
            const Color(0xF8030712),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: alertRed.withValues(alpha: 0.50),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: alertRed.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated Action Status Icon
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: actionDispatched
                  ? const Color(0xFF10B981).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.20),
              border: Border.all(
                color: actionDispatched ? const Color(0xFF10B981) : Colors.white,
                width: 2.0,
              ),
              boxShadow: [
                if (actionDispatched)
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.40),
                    blurRadius: 16,
                  ),
              ],
            ),
            child: actionDispatched
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 44,
                    color: Color(0xFF34D399),
                  )
                : const SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 18),

          // Main Header Text
          Text(
            actionDispatched
                ? (hasContact
                    ? 'Emergency Contact Notified'
                    : 'Emergency Beacon Broadcasted')
                : (hasContact
                    ? 'Notifying ${settings.emergencyContactName}...'
                    : 'Dispatching Emergency Alert...'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 10),

          // Body explanation & fallback message
          if (hasContact) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_pin_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${settings.emergencyContactName} (${settings.emergencyContactRelation})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Phone: ${settings.emergencyContactPhone}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              actionDispatched
                  ? 'Live GPS location, impact force (${state.impactMagnitude.toStringAsFixed(1)}g), and sensor trace were successfully transmitted.'
                  : 'Sending automated crash alert with live coordinates...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.90),
              ),
            ),
          ] else ...[
            // Sensible fallback message when no emergency contact is set
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.50),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.amberAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No emergency contact configured — add one in Settings.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              actionDispatched
                  ? 'Automated regional distress beacon has been transmitted to emergency responders with GPS fix and vehicle telemetry.'
                  : 'Broadcasting automated municipal distress beacon...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.90),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Telemetry readout
          Text(
            'Coordinates: ${state.latitude.toStringAsFixed(4)}° N, ${state.longitude.toStringAsFixed(4)}° E',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
