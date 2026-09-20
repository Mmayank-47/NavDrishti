import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// CustomPainter rendering the confidence halo around the vehicle.
///
/// Principles:
/// - Restyled to match the reference mockup: a clean glowing ring directly
///   around the vehicle icon with concentric fade rings (radar/sonar pulse look).
/// - Instantaneous discrete color swap on mode change:
///   GNSS_AIDED (Cyan/Blue) <-> DEAD_RECKONING (Violet/Amber).
/// - Preserves fixed radius behavior (~26px by default) and custom color personalization.
/// - Flat constant opacities at all times — no time ramping.
class ConfidenceHaloPainter extends CustomPainter {
  /// Toggle to maintain fixed-size halo regardless of uncertainty ellipse expansion.
  final bool useFixedHaloRadius;

  final double semiMajorPixels;
  final double semiMinorPixels;
  final double orientationDegrees;
  final bool isDeadReckoning;
  final bool isDark;
  final Color? customGnssColor;
  final Color? customDrColor;

  const ConfidenceHaloPainter({
    this.useFixedHaloRadius = true,
    required this.semiMajorPixels,
    required this.semiMinorPixels,
    required this.orientationDegrees,
    required this.isDeadReckoning,
    required this.isDark,
    this.customGnssColor,
    this.customDrColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Cyan for Fused/GNSS lock in dark mode, Violet for Dead Reckoning
    final defaultAccentColor = isDeadReckoning
        ? (isDark ? AppColors.darkViolet : AppColors.lightViolet)
        : (isDark ? AppColors.darkCyan : AppColors.lightBlue);

    final accentColor = isDeadReckoning
        ? (customDrColor ?? defaultAccentColor)
        : (customGnssColor ?? defaultAccentColor);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Rotate to ellipse orientation (clockwise from north)
    canvas.rotate(orientationDegrees * math.pi / 180.0);

    // Radii: fixed size (~26px) or dynamic uncertainty
    final double effectiveMajor;
    final double effectiveMinor;
    if (useFixedHaloRadius) {
      effectiveMajor = 26.0;
      effectiveMinor = 26.0;
    } else {
      effectiveMajor = semiMajorPixels;
      effectiveMinor = semiMinorPixels;
    }

    // 1. Soft central translucent fill
    final fillPaint = Paint()
      ..color = accentColor.withValues(alpha: isDeadReckoning ? 0.22 : 0.18)
      ..style = PaintingStyle.fill;

    final primaryRect = Rect.fromCenter(
      center: Offset.zero,
      width: effectiveMinor * 2,
      height: effectiveMajor * 2,
    );
    canvas.drawOval(primaryRect, fillPaint);

    // 2. Primary clean glowing boundary ring
    final primaryStroke = Paint()
      ..color = accentColor.withValues(alpha: isDeadReckoning ? 0.90 : 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(primaryRect, primaryStroke);

    // 3. Concentric radar/sonar pulse fade ring 1 (scale: 1.35x)
    final ring1Rect = Rect.fromCenter(
      center: Offset.zero,
      width: effectiveMinor * 2 * 1.35,
      height: effectiveMajor * 2 * 1.35,
    );
    final ring1Stroke = Paint()
      ..color = accentColor.withValues(alpha: isDeadReckoning ? 0.48 : 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawOval(ring1Rect, ring1Stroke);

    // 4. Concentric radar/sonar pulse fade ring 2 (scale: 1.7x)
    final ring2Rect = Rect.fromCenter(
      center: Offset.zero,
      width: effectiveMinor * 2 * 1.7,
      height: effectiveMajor * 2 * 1.7,
    );
    final ring2Stroke = Paint()
      ..color = accentColor.withValues(alpha: isDeadReckoning ? 0.25 : 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawOval(ring2Rect, ring2Stroke);

    // 5. Outer subtle pulse ring 3 (scale: 2.05x)
    final ring3Rect = Rect.fromCenter(
      center: Offset.zero,
      width: effectiveMinor * 2 * 2.05,
      height: effectiveMajor * 2 * 2.05,
    );
    final ring3Stroke = Paint()
      ..color = accentColor.withValues(alpha: isDeadReckoning ? 0.12 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawOval(ring3Rect, ring3Stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConfidenceHaloPainter oldDelegate) {
    return oldDelegate.useFixedHaloRadius != useFixedHaloRadius ||
        oldDelegate.semiMajorPixels != semiMajorPixels ||
        oldDelegate.semiMinorPixels != semiMinorPixels ||
        oldDelegate.orientationDegrees != orientationDegrees ||
        oldDelegate.isDeadReckoning != isDeadReckoning ||
        oldDelegate.isDark != isDark ||
        oldDelegate.customGnssColor != customGnssColor ||
        oldDelegate.customDrColor != customDrColor;
  }
}
