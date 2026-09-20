import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Vehicle navigation marker rotated to current heading.
///
/// Supports 3 styles:
/// 1. `arrow`: Flat crisp directional navigation chevron.
/// 2. `car`: Isometric/angled 3D automobile with windshield, roof, wheels, and mode accents.
/// 3. `bike`: Matching isometric/angled 3D motorcycle with handlebars, tank, seat, and wheels.
class VehicleMarker extends StatelessWidget {
  final double heading; // degrees (0 = North, 90 = East)
  final double mapBearing; // camera/map rotation offset in degrees (0 = North-up)
  final bool isDeadReckoning;
  final bool isDark;
  final VehicleIconStyle iconStyle;
  final Color? customAccentColor;

  const VehicleMarker({
    super.key,
    required this.heading,
    this.mapBearing = 0.0,
    required this.isDeadReckoning,
    required this.isDark,
    this.iconStyle = VehicleIconStyle.arrow,
    this.customAccentColor,
  });

  @override
  Widget build(BuildContext context) {
    final defaultAccent = isDeadReckoning
        ? (isDark ? AppColors.darkAmber : AppColors.lightAmber)
        : (isDark ? AppColors.darkBlue : AppColors.lightBlue);
    final accentColor = customAccentColor ?? defaultAccent;

    Widget painterWidget;
    switch (iconStyle) {
      case VehicleIconStyle.car:
        painterWidget = CustomPaint(
          size: const Size(42, 42),
          painter: _VehicleCarPainter(accentColor: accentColor, isDark: isDark),
        );
        break;
      case VehicleIconStyle.bike:
        painterWidget = CustomPaint(
          size: const Size(42, 42),
          painter: _VehicleBikePainter(accentColor: accentColor, isDark: isDark),
        );
        break;
      case VehicleIconStyle.arrow:
        painterWidget = CustomPaint(
          size: const Size(40, 40),
          painter: _VehicleArrowPainter(accentColor: accentColor, isDark: isDark),
        );
        break;
    }

    final relativeHeading = heading - mapBearing;
    return Transform.rotate(
      angle: relativeHeading * math.pi / 180.0,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Center(child: painterWidget),
      ),
    );
  }
}

/// 1. Flat Crisp Navigation Arrow Pointer
class _VehicleArrowPainter extends CustomPainter {
  final Color accentColor;
  final bool isDark;

  const _VehicleArrowPainter({
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Outer boundary for tile contrast
    final baseBgPaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, w / 2 - 2, baseBgPaint);

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, w / 2 - 2, borderPaint);

    // Directional chevron pointing North
    final arrowPath = Path()
      ..moveTo(w / 2, 6.0)
      ..lineTo(w - 9.0, h - 8.0)
      ..lineTo(w / 2, h - 13.0)
      ..lineTo(9.0, h - 8.0)
      ..close();

    final arrowFill = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowFill);

    // Center locator dot
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, h / 2 + 1), 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _VehicleArrowPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor || oldDelegate.isDark != isDark;
  }
}

/// 2. Stylized Isometric 3D Car
class _VehicleCarPainter extends CustomPainter {
  final Color accentColor;
  final bool isDark;

  const _VehicleCarPainter({
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 1. Soft drop shadow under the chassis
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h / 2 + 3), width: 22, height: 32),
      shadowPaint,
    );

    // 2. Wheels / Tires (4 isometric tires)
    final tirePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final tireRim = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Front-left & Front-right tires
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10.5, 9, 3, 7), const Radius.circular(1.5)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10.5, 9, 3, 7), const Radius.circular(1.5)), tireRim);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 7.5, 9, 3, 7), const Radius.circular(1.5)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 7.5, 9, 3, 7), const Radius.circular(1.5)), tireRim);

    // Rear-left & Rear-right tires
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10.5, 26, 3, 7), const Radius.circular(1.5)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10.5, 26, 3, 7), const Radius.circular(1.5)), tireRim);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 7.5, 26, 3, 7), const Radius.circular(1.5)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 7.5, 26, 3, 7), const Radius.circular(1.5)), tireRim);

    // 3. Lower Chassis / Underbody
    final chassisColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final bodyPaint = Paint()
      ..color = chassisColor
      ..style = PaintingStyle.fill;
    final bodyBorder = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final bodyPath = Path()
      ..moveTo(cx - 7.5, 7) // front-left nose
      ..quadraticBezierTo(cx, 5.5, cx + 7.5, 7) // front bumper
      ..lineTo(cx + 8.5, 33) // right side
      ..quadraticBezierTo(cx, 35, cx - 8.5, 33) // rear bumper
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, bodyBorder);

    // 4. Mode-colored Headlights & Beams
    final headlightPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 5.5, 7.5), 1.8, headlightPaint);
    canvas.drawCircle(Offset(cx + 5.5, 7.5), 1.8, headlightPaint);

    // Subtle forward headlight glow cones
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [accentColor.withValues(alpha: 0.4), accentColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(cx - 9, 0, 18, 8));
    final beamPath = Path()
      ..moveTo(cx - 7, 7)
      ..lineTo(cx - 9, 0)
      ..lineTo(cx + 9, 0)
      ..lineTo(cx + 7, 7)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // 5. Hood Accent Stripe
    final hoodStripe = Paint()
      ..color = accentColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx, 8), Offset(cx, 14), hoodStripe);

    // 6. Angled Windshield (Glass reflection)
    final windshieldPath = Path()
      ..moveTo(cx - 6.5, 14)
      ..lineTo(cx + 6.5, 14)
      ..lineTo(cx + 5.5, 20)
      ..lineTo(cx - 5.5, 20)
      ..close();
    final glassPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: isDark ? 0.45 : 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawPath(windshieldPath, glassPaint);

    // 7. Roof with 3D Depth Highlight
    final roofColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final roofPaint = Paint()
      ..color = roofColor
      ..style = PaintingStyle.fill;
    final roofPath = Path()
      ..moveTo(cx - 5.5, 20)
      ..lineTo(cx + 5.5, 20)
      ..lineTo(cx + 6.0, 27)
      ..lineTo(cx - 6.0, 27)
      ..close();
    canvas.drawPath(roofPath, roofPaint);

    // 8. Rear Windshield & Taillights
    final rearGlassPath = Path()
      ..moveTo(cx - 5.8, 27)
      ..lineTo(cx + 5.8, 27)
      ..lineTo(cx + 6.8, 31)
      ..lineTo(cx - 6.8, 31)
      ..close();
    final rearGlassPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: isDark ? 0.3 : 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(rearGlassPath, rearGlassPaint);

    // Rear taillights (mode-accented)
    final tailPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(cx - 7.5, 33, 3, 1.2), tailPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 4.5, 33, 3, 1.2), tailPaint);
  }

  @override
  bool shouldRepaint(covariant _VehicleCarPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor || oldDelegate.isDark != isDark;
  }
}

/// 3. Stylized Isometric 3D Motorcycle / Bike
/// Matching the exact camera angle (~35° pitch) and multi-layered depth treatment of 3D Car.
class _VehicleBikePainter extends CustomPainter {
  final Color accentColor;
  final bool isDark;

  const _VehicleBikePainter({
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 1. Drop shadow under motorcycle
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h / 2 + 2), width: 14, height: 32),
      shadowPaint,
    );

    // 2. Foreshortened Front Tire
    final tirePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final tireRim = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 1.8, 5, 3.6, 9), const Radius.circular(1.8)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 1.8, 5, 3.6, 9), const Radius.circular(1.8)), tireRim);

    // 3. Front Headlight & Forward Glow Beam
    final headlightPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, 8.5), 2.2, headlightPaint);

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [accentColor.withValues(alpha: 0.4), accentColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(cx - 6, 0, 12, 8));
    final beamPath = Path()
      ..moveTo(cx - 2, 8)
      ..lineTo(cx - 6, 0)
      ..lineTo(cx + 6, 0)
      ..lineTo(cx + 2, 8)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // 4. Handlebars (Angled bar across with dark grips)
    final handlebarPaint = Paint()
      ..color = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 8.5, 12.5), Offset(cx + 8.5, 12.5), handlebarPaint);

    // Handlebar grips
    final gripPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 8.5, 12.5), 1.5, gripPaint);
    canvas.drawCircle(Offset(cx + 8.5, 12.5), 1.5, gripPaint);

    // 5. Fairing / Windscreen
    final windscreenPath = Path()
      ..moveTo(cx - 3, 10)
      ..lineTo(cx + 3, 10)
      ..lineTo(cx + 2, 14)
      ..lineTo(cx - 2, 14)
      ..close();
    final windscreenPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: isDark ? 0.5 : 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(windscreenPath, windscreenPaint);

    // 6. Fuel Tank & Bodywork with 3D Depth
    final tankColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final tankPaint = Paint()
      ..color = tankColor
      ..style = PaintingStyle.fill;
    final tankBorder = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final tankPath = Path()
      ..moveTo(cx - 2.5, 14)
      ..quadraticBezierTo(cx - 5.5, 18, cx - 4.5, 23) // left tank bulge
      ..lineTo(cx + 4.5, 23)
      ..quadraticBezierTo(cx + 5.5, 18, cx + 2.5, 14) // right tank bulge
      ..close();
    canvas.drawPath(tankPath, tankPaint);
    canvas.drawPath(tankPath, tankBorder);

    // Central mode-accent racing stripe on tank
    final stripePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(cx - 1.0, 14.5, 2.0, 8.0), stripePaint);

    // 7. Motorcycle Saddle / Seat
    final saddlePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final saddlePath = Path()
      ..moveTo(cx - 3.8, 23)
      ..lineTo(cx + 3.8, 23)
      ..lineTo(cx + 3.2, 29)
      ..lineTo(cx - 3.2, 29)
      ..close();
    canvas.drawPath(saddlePath, saddlePaint);

    // Seat contour highlight
    final seatHighlight = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx - 2.5, 26), Offset(cx + 2.5, 26), seatHighlight);

    // 8. Rear Wheel & Exhaust
    // Thick rear tire
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 2.0, 29, 4.0, 8), const Radius.circular(2.0)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 2.0, 29, 4.0, 8), const Radius.circular(2.0)), tireRim);

    // Exhaust pipe (right side)
    final exhaustPaint = Paint()
      ..color = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 4.2, 23), Offset(cx + 4.8, 32), exhaustPaint);

    // Rear Taillight (mode-accented)
    final tailPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(cx - 2.2, 33, 4.4, 1.4), tailPaint);
  }

  @override
  bool shouldRepaint(covariant _VehicleBikePainter oldDelegate) {
    return oldDelegate.accentColor != accentColor || oldDelegate.isDark != isDark;
  }
}
