import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/liquid_glass_card.dart';

/// Enum representing the individual guided sensor diagnostic checks.
enum DiagnosticStep {
  tiltLeft,
  tiltRight,
  tiltForward,
  tiltBackward,
  rotateYaw,
  shakeMotion,
  rotatePhoneFlat,
  summary,
}

/// Metadata describing each diagnostic step.
class StepConfig {
  final DiagnosticStep step;
  final String title;
  final String subtitle;
  final String instruction;
  final String targetAxisLabel;
  final String expectedCriteria;
  final IconData icon;

  const StepConfig({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.instruction,
    required this.targetAxisLabel,
    required this.expectedCriteria,
    required this.icon,
  });
}

/// Screen: SENSOR DIAGNOSTICS & HEALTH-CHECK
///
/// Principles:
/// - 100% LOCAL: Directly accesses device physical sensors via sensors_plus.
/// - Never touches the Python backend, WebSocket, or mock stream.
/// - Step-by-step guided flow: Left tilt, Right tilt, Pitch down, Pitch up,
///   Yaw rotation, Dynamic tap/shake, and Rotate Phone Flat (Compass check).
/// - Live numeric readouts (2 decimal places) for Accelerometer, Gyroscope, and Magnetometer.
/// - Animated visual threshold bar showing real-time deviation into pass zone.
/// - Auto-advance on pass, with manual Next and Retry on timeout.
/// - Comprehensive health summary report covering all 7 checks.
class SensorDiagnosticsScreen extends StatefulWidget {
  final Stream<AccelerometerEvent>? customAccelerometerStream;
  final Stream<GyroscopeEvent>? customGyroscopeStream;
  final Stream<MagnetometerEvent>? customMagnetometerStream;

  const SensorDiagnosticsScreen({
    super.key,
    this.customAccelerometerStream,
    this.customGyroscopeStream,
    this.customMagnetometerStream,
  });

  @override
  State<SensorDiagnosticsScreen> createState() => _SensorDiagnosticsScreenState();
}

class _SensorDiagnosticsScreenState extends State<SensorDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  // Sensor Subscriptions
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;

  // Real-time raw telemetry
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 0.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;
  double _magX = 0.0;
  double _magY = 0.0;
  double _magZ = 0.0;
  double _compassHeading = 0.0;
  double _lastHeading = -1.0;
  double _accumulatedHeadingDelta = 0.0;
  bool _hasReceivedSensorData = false;
  bool _magnetometerAvailable = true;

  // Step state
  int _currentStepIndex = 0;
  bool _stepPassed = false;
  bool _stepTimedOut = false;
  Timer? _countdownTimer;
  int _secondsRemaining = 12;
  static const int _stepTimeoutSeconds = 12;

  // Results map
  final Map<DiagnosticStep, bool> _stepResults = {
    DiagnosticStep.tiltLeft: false,
    DiagnosticStep.tiltRight: false,
    DiagnosticStep.tiltForward: false,
    DiagnosticStep.tiltBackward: false,
    DiagnosticStep.rotateYaw: false,
    DiagnosticStep.shakeMotion: false,
    DiagnosticStep.rotatePhoneFlat: false,
  };

  static const List<StepConfig> _steps = [
    StepConfig(
      step: DiagnosticStep.tiltRight,
      title: 'Tilt Phone RIGHT',
      subtitle: 'Roll Axis — Negative X Acceleration',
      instruction: 'Tilt the phone to the right (right edge down)',
      targetAxisLabel: 'Accel X',
      expectedCriteria: 'X ≤ -2.2 m/s²',
      icon: Icons.phone_android_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.tiltLeft,
      title: 'Tilt Phone LEFT',
      subtitle: 'Roll Axis — Positive X Acceleration',
      instruction: 'Tilt the phone to the left (left edge down)',
      targetAxisLabel: 'Accel X',
      expectedCriteria: 'X ≥ +2.2 m/s²',
      icon: Icons.phone_android_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.tiltForward,
      title: 'Tilt Phone FORWARD',
      subtitle: 'Pitch Axis — Nose Down',
      instruction: 'Tip the top edge of the phone downwards (away from you)',
      targetAxisLabel: 'Accel Y',
      expectedCriteria: 'Y ≤ -2.2 m/s²',
      icon: Icons.arrow_downward_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.tiltBackward,
      title: 'Tilt Phone BACKWARD',
      subtitle: 'Pitch Axis — Nose Up',
      instruction: 'Tilt the top edge of the phone upwards (towards you)',
      targetAxisLabel: 'Accel Y',
      expectedCriteria: 'Y ≥ +2.2 m/s²',
      icon: Icons.arrow_upward_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.rotateYaw,
      title: 'Rotate Phone (Yaw)',
      subtitle: 'Z-Axis Angular Rate — Gyroscope',
      instruction: 'Twist or rotate the phone left or right',
      targetAxisLabel: 'Gyro Z',
      expectedCriteria: '|Z| ≥ 0.45 rad/s',
      icon: Icons.rotate_right_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.shakeMotion,
      title: 'Shake or Tap Phone',
      subtitle: 'Dynamic Impulse — Accelerometer Response',
      instruction: 'Gently shake or tap the phone to verify dynamic sensitivity',
      targetAxisLabel: 'Total G',
      expectedCriteria: '|a| > 12.8 or < 6.8 m/s²',
      icon: Icons.vibration_rounded,
    ),
    StepConfig(
      step: DiagnosticStep.rotatePhoneFlat,
      title: 'Rotate Phone Flat (Compass Check)',
      subtitle: 'Z-Axis Magnetometer & Heading',
      instruction: 'Hold the phone flat and slowly rotate it in a full circle',
      targetAxisLabel: 'Heading Delta',
      expectedCriteria: 'Δθ ≥ 180° rotation',
      icon: Icons.explore_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startSensorStreams();
    _startStepCountdown();
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _magSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startSensorStreams() {
    final accelStream = widget.customAccelerometerStream ?? accelerometerEventStream();
    final gyroStream = widget.customGyroscopeStream ?? gyroscopeEventStream();
    final magStream = widget.customMagnetometerStream ?? magnetometerEventStream();

    _accelSubscription = accelStream.listen((AccelerometerEvent event) {
      if (!mounted) return;
      setState(() {
        _accelX = event.x;
        _accelY = event.y;
        _accelZ = event.z;
        _hasReceivedSensorData = true;
      });
      _evaluateCurrentStep();
    });

    _gyroSubscription = gyroStream.listen((GyroscopeEvent event) {
      if (!mounted) return;
      setState(() {
        _gyroX = event.x;
        _gyroY = event.y;
        _gyroZ = event.z;
        _hasReceivedSensorData = true;
      });
      _evaluateCurrentStep();
    });

    try {
      _magSubscription = magStream.listen(
        (MagnetometerEvent event) {
          if (!mounted) return;
          setState(() {
            _magX = event.x;
            _magY = event.y;
            _magZ = event.z;
            _hasReceivedSensorData = true;

            // atan2(y, x) compass heading in 0..360°
            final rad = math.atan2(event.y, event.x);
            final deg = ((rad * 180.0 / math.pi) + 360.0) % 360.0;
            _compassHeading = deg;

            if (_currentStepIndex < _steps.length &&
                _steps[_currentStepIndex].step == DiagnosticStep.rotatePhoneFlat) {
              if (_lastHeading >= 0) {
                double diff = (deg - _lastHeading).abs();
                if (diff > 180.0) diff = 360.0 - diff;
                _accumulatedHeadingDelta += diff;
              }
              _lastHeading = deg;
            }
          });
          _evaluateCurrentStep();
        },
        onError: (err) {
          if (!mounted) return;
          setState(() {
            _magnetometerAvailable = false;
          });
        },
      );
    } catch (_) {
      _magnetometerAvailable = false;
    }
  }

  void _startStepCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = _stepTimeoutSeconds;
      _stepPassed = false;
      _stepTimedOut = false;
      _lastHeading = -1.0;
      _accumulatedHeadingDelta = 0.0;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        if (!_stepPassed) {
          setState(() {
            _secondsRemaining = 0;
            _stepTimedOut = true;
          });
        }
      }
    });
  }

  void _evaluateCurrentStep() {
    if (_currentStepIndex >= _steps.length || _stepPassed || _stepTimedOut) {
      return;
    }

    final currentConfig = _steps[_currentStepIndex];
    bool passed = false;

    switch (currentConfig.step) {
      case DiagnosticStep.tiltRight:
        passed = _accelX <= -2.2;
        break;
      case DiagnosticStep.tiltLeft:
        passed = _accelX >= 2.2;
        break;
      case DiagnosticStep.tiltForward:
        passed = _accelY <= -2.2;
        break;
      case DiagnosticStep.tiltBackward:
        passed = _accelY >= 2.2;
        break;
      case DiagnosticStep.rotateYaw:
        passed = _gyroZ.abs() >= 0.45;
        break;
      case DiagnosticStep.shakeMotion:
        final mag = math.sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
        passed = mag > 12.8 || mag < 6.8;
        break;
      case DiagnosticStep.rotatePhoneFlat:
        passed = _accumulatedHeadingDelta >= 180.0;
        break;
      case DiagnosticStep.summary:
        break;
    }

    if (passed && !_stepPassed) {
      _onStepSuccess(currentConfig.step);
    }
  }

  void _onStepSuccess(DiagnosticStep step) {
    _countdownTimer?.cancel();
    setState(() {
      _stepPassed = true;
      _stepTimedOut = false;
      _stepResults[step] = true;
    });

    // Auto-advance after 800ms so user clearly sees the success state
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _advanceToNextStep();
    });
  }

  void _advanceToNextStep() {
    _countdownTimer?.cancel();
    if (_currentStepIndex < _steps.length) {
      setState(() {
        _currentStepIndex++;
      });
      if (_currentStepIndex < _steps.length) {
        _startStepCountdown();
      }
    }
  }

  void _retryCurrentStep() {
    _startStepCountdown();
  }

  void _skipCurrentStep() {
    if (_currentStepIndex < _steps.length) {
      _stepResults[_steps[_currentStepIndex].step] = false;
      _advanceToNextStep();
    }
  }

  void _restartAll() {
    setState(() {
      _currentStepIndex = 0;
      _stepResults.updateAll((key, value) => false);
    });
    _startStepCountdown();
  }

  /// Compute current metric progress fraction [-1.0, 1.0] for the visual bar
  double _computeStepProgressFraction(DiagnosticStep step) {
    switch (step) {
      case DiagnosticStep.tiltRight:
        return (_accelX / -3.5).clamp(-1.0, 1.0);
      case DiagnosticStep.tiltLeft:
        return (_accelX / 3.5).clamp(-1.0, 1.0);
      case DiagnosticStep.tiltForward:
        return (_accelY / -3.5).clamp(-1.0, 1.0);
      case DiagnosticStep.tiltBackward:
        return (_accelY / 3.5).clamp(-1.0, 1.0);
      case DiagnosticStep.rotateYaw:
        return (_gyroZ.abs() / 0.8).clamp(0.0, 1.0);
      case DiagnosticStep.shakeMotion:
        final mag = math.sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
        final dev = (mag - 9.81).abs();
        return (dev / 4.0).clamp(0.0, 1.0);
      case DiagnosticStep.rotatePhoneFlat:
        return (_accumulatedHeadingDelta / 180.0).clamp(0.0, 1.0);
      case DiagnosticStep.summary:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final blueColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;
    const greenColor = Color(0xFF10B981);
    const redColor = Color(0xFFEF4444);
    const amberColor = Color(0xFFF59E0B);

    final isSummary = _currentStepIndex >= _steps.length;

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
          'Sensor Diagnostics',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (!isSummary)
            TextButton(
              onPressed: _skipCurrentStep,
              child: Text(
                'Skip',
                style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: GalaxyBackground(
        child: SafeArea(
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Explicit Local-Only Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: blueColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.sensors_rounded, size: 18, color: blueColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Reading live from this device's sensors (Local-Only)",
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Direct hardware telemetry · Completely independent of Python backend",
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (!isSummary) ...[
                // 2. Step Progress Indicators
                _buildStepProgressBar(blueColor, greenColor, borderColor, secondaryTextColor),

                const SizedBox(height: 18),

                // 3. Active Step Card
                _buildActiveStepCard(
                  step: _steps[_currentStepIndex],
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  blueColor: blueColor,
                  greenColor: greenColor,
                  amberColor: amberColor,
                  redColor: redColor,
                ),
              ] else ...[
                // Summary Screen
                _buildSummaryCard(
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  borderColor: borderColor,
                  primaryTextColor: primaryTextColor,
                  secondaryTextColor: secondaryTextColor,
                  blueColor: blueColor,
                  greenColor: greenColor,
                  amberColor: amberColor,
                  redColor: redColor,
                ),
              ],

              const SizedBox(height: 18),

              // 4. Live Raw Hardware Telemetry Stream Card
              _buildRawTelemetryCard(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                blueColor: blueColor,
              ),

              const SizedBox(height: 16),

              // Bottom note for emulator users
              if (!_hasReceivedSensorData)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    "Note: In Android Emulator, open Extended Controls (•••) -> Virtual Sensors to tilt device or tap Skip.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Builds the 6-step progress indicator at top.
  Widget _buildStepProgressBar(
    Color activeColor,
    Color passedColor,
    Color borderColor,
    Color textColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STEP ${_currentStepIndex + 1} OF ${_steps.length}',
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: _secondsRemaining <= 4 ? const Color(0xFFEF4444) : textColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_secondsRemaining}s',
                  style: TextStyle(
                    color: _secondsRemaining <= 4 ? const Color(0xFFEF4444) : textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_steps.length, (index) {
            final step = _steps[index].step;
            final isPassed = _stepResults[step] == true;
            final isCurrent = index == _currentStepIndex;

            Color barColor;
            if (isPassed) {
              barColor = passedColor;
            } else if (isCurrent) {
              barColor = activeColor;
            } else {
              barColor = borderColor;
            }

            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index == _steps.length - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Builds the central interactive card for the active guided step.
  Widget _buildActiveStepCard({
    required StepConfig step,
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required Color blueColor,
    required Color greenColor,
    required Color amberColor,
    required Color redColor,
  }) {
    final progressFraction = _computeStepProgressFraction(step.step);
    final isClose = progressFraction.abs() >= 0.8;
    final stepGlow = _stepPassed
        ? greenColor
        : _stepTimedOut
            ? amberColor
            : (isDark ? blueColor : const Color(0xFF0891B2));

    return LiquidGlassCard(
      borderRadius: 16,
      glowColor: stepGlow,
      glowRadius: _stepPassed || _stepTimedOut ? 20 : 12,
      glowAlpha: isDark ? 0.35 : 0.18,
      padding: const EdgeInsets.all(20.0),
      child: Column(
          children: [
            // Status Icon Circle
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _stepPassed
                    ? greenColor.withValues(alpha: 0.15)
                    : _stepTimedOut
                        ? amberColor.withValues(alpha: 0.15)
                        : blueColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _stepPassed
                      ? greenColor
                      : _stepTimedOut
                          ? amberColor
                          : blueColor.withValues(alpha: 0.3),
                  width: 2.0,
                ),
              ),
              child: Icon(
                _stepPassed
                    ? Icons.check_circle_rounded
                    : _stepTimedOut
                        ? Icons.help_outline_rounded
                        : step.icon,
                size: 36,
                color: _stepPassed
                    ? greenColor
                    : _stepTimedOut
                        ? amberColor
                        : blueColor,
              ),
            ),

            const SizedBox(height: 16),

            // Step Title
            Text(
              step.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: secondaryTextColor,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 14),

            // Target Criteria Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : blueColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? borderColor : blueColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TARGET: ',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      step.expectedCriteria,
                      style: TextStyle(
                        color: blueColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            if (step.step == DiagnosticStep.rotatePhoneFlat && !_magnetometerAvailable) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: amberColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: amberColor.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sensors_off_rounded, color: amberColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Magnetometer not available on this device',
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No hardware compass sensor was detected or stream failed. You can skip this step.',
                      style: TextStyle(color: secondaryTextColor, fontSize: 11.5),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _skipCurrentStep,
                      icon: const Icon(Icons.skip_next_rounded, size: 16),
                      label: const Text('Skip Magnetometer Check'),
                      style: FilledButton.styleFrom(
                        backgroundColor: amberColor,
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (step.step == DiagnosticStep.rotatePhoneFlat) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : blueColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? borderColor : blueColor.withValues(alpha: 0.25)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.rotate(
                          angle: (_compassHeading * math.pi / 180.0),
                          child: Icon(Icons.navigation_rounded, color: blueColor, size: 20),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'HEADING: ${_compassHeading.toStringAsFixed(0)}°',
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: blueColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_accumulatedHeadingDelta.toStringAsFixed(0)}° / 180°',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: blueColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Instruction prompt
            Text(
              step.instruction,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: primaryTextColor,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 18),

            // Visual Threshold Meter Bar
            _buildThresholdGauge(
              label: step.targetAxisLabel,
              currentProgress: progressFraction,
              isPassed: _stepPassed,
              activeColor: blueColor,
              passedColor: greenColor,
              trackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              textColor: primaryTextColor,
            ),

            const SizedBox(height: 20),

            // Action / Status State
            if (_stepPassed) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 18, color: greenColor),
                  const SizedBox(width: 8),
                  Text(
                    'Motion Confirmed! Advancing...',
                    style: TextStyle(
                      color: greenColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ] else if (_stepTimedOut) ...[
              Column(
                children: [
                  Text(
                    "Didn't detect that — try again",
                    style: TextStyle(
                      color: amberColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _retryCurrentStep,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _skipCurrentStep,
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Next Step'),
                          style: FilledButton.styleFrom(
                            backgroundColor: blueColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              // Ongoing Active Detection
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _onStepSuccess(step.step),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isClose ? greenColor : borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Manual Pass / Next',
                        style: TextStyle(
                          color: isClose ? greenColor : secondaryTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
    );
  }

  /// Visual threshold gauge displaying how close the user is to the required motion.
  Widget _buildThresholdGauge({
    required String label,
    required double currentProgress,
    required bool isPassed,
    required Color activeColor,
    required Color passedColor,
    required Color trackColor,
    required Color textColor,
  }) {
    final absProgress = currentProgress.abs().clamp(0.0, 1.0);
    final fillColor = isPassed ? passedColor : (absProgress >= 0.85 ? passedColor : activeColor);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Motion Deflection',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
            ),
            Text(
              isPassed ? '100% PASSED' : '${(absProgress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fillColor,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 10,
          width: double.infinity,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(5),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: isPassed ? 1.0 : absProgress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Live Numeric Telemetry Card showing real hardware values directly.
  Widget _buildRawTelemetryCard({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required Color blueColor,
  }) {
    return LiquidGlassCard(
      borderRadius: 16,
      glowColor: isDark ? const Color(0xFF06B6D4) : const Color(0xFF0891B2),
      glowRadius: 14,
      glowAlpha: isDark ? 0.25 : 0.12,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'LIVE HARDWARE READOUT',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '100Hz Local Stream',
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Accelerometer Live Values
            Text(
              'ACCELEROMETER (m/s²)',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildAxisValueBox('X', _accelX, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Y', _accelY, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Z', _accelZ, isDark, borderColor, primaryTextColor),
              ],
            ),

            const SizedBox(height: 14),

            // Gyroscope Live Values
            Text(
              'GYROSCOPE (rad/s)',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildAxisValueBox('X', _gyroX, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Y', _gyroY, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Z', _gyroZ, isDark, borderColor, primaryTextColor),
              ],
            ),

            const SizedBox(height: 14),

            // Magnetometer Live Values & Heading (Item 3)
            Text(
              'MAGNETOMETER (µT) & COMPASS',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildAxisValueBox('X', _magX, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Y', _magY, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                _buildAxisValueBox('Z', _magZ, isDark, borderColor, primaryTextColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFF0891B2).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? borderColor : const Color(0xFF0891B2).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'HEADING',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF0891B2),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_compassHeading.toStringAsFixed(0)}°',
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildAxisValueBox(
    String axis,
    double value,
    bool isDark,
    Color borderColor,
    Color textColor,
  ) {
    final isNegative = value < 0;
    final formatted = '${isNegative ? "" : "+"}${value.toStringAsFixed(2)}';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFF0891B2).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? borderColor : const Color(0xFF0891B2).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: [
            Text(
              axis,
              style: TextStyle(
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF0891B2),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatted,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Final Summary Card displaying results of all 6 checks.
  Widget _buildSummaryCard({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required Color blueColor,
    required Color greenColor,
    required Color amberColor,
    required Color redColor,
  }) {
    final passedCount = _stepResults.values.where((v) => v).length;
    final allPassed = passedCount == _steps.length;

    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: allPassed ? greenColor : amberColor,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Overall Status Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (allPassed ? greenColor : amberColor).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                allPassed ? Icons.verified_rounded : Icons.warning_amber_rounded,
                size: 36,
                color: allPassed ? greenColor : amberColor,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              allPassed
                  ? 'All Sensors Responding Correctly'
                  : 'Diagnostics Completed ($passedCount/${_steps.length} Passed)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              allPassed
                  ? 'Physical accelerometer, gyroscope, and magnetometer operational across all spatial axes.'
                  : 'One or more motion thresholds were skipped or timed out. See breakdown below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: secondaryTextColor),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Step results breakdown list
            ..._steps.map((step) {
              final passed = _stepResults[step.step] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(
                      passed ? Icons.check_circle : Icons.cancel_outlined,
                      size: 18,
                      color: passed ? greenColor : redColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(
                          color: primaryTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      passed ? 'PASSED' : 'NOT DETECTED',
                      style: TextStyle(
                        color: passed ? greenColor : redColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restartAll,
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: const Text('Restart Test'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Done'),
                    style: FilledButton.styleFrom(
                      backgroundColor: blueColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
