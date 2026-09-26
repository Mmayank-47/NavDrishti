import 'package:flutter/material.dart';

/// Cosmic starry / galaxy atmospheric background.
///
/// Features:
/// - Base gradient blending deep navy (#203B6F) and deep plum/purple-black (#312048).
/// - Diffuse, soft nebula color blooms in purple/orchid/indigo tones (#8E68A9, #BC7EBF, #384F95).
/// - Scattered celestial starfield with varying radius, opacity, and soft glow dots.
/// - In Light Mode, renders a clean, bright lavender-periwinkle base (#F8F5FF to #EFE8FC)
///   without star clutter, preserving maximum driving legibility.
class GalaxyBackground extends StatelessWidget {
  final Widget child;
  final bool showStars;

  const GalaxyBackground({
    super.key,
    required this.child,
    this.showStars = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isDark) {
      // Light Mode: clean, bright high-contrast lavender-tinted palette
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F5FF), // crisp bright lavender white
              Color(0xFFEFE8FC), // soft lavender periwinkle
            ],
          ),
        ),
        child: child,
      );
    }

    // Dark Mode: Deep cosmic galaxy with nebula blooms and starfield
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Cosmic Gradient Base (#203B6F to #312048)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF203B6F), // Deep Navy (#203B6F)
                Color(0xFF312048), // Deep Plum / Purple-black (#312048)
                Color(0xFF181026), // Deep Cosmic Void
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),

        // 2. Diffuse Nebula Blooms
        Positioned(
          top: -80,
          right: -60,
          width: 340,
          height: 340,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFBC7EBF).withValues(alpha: 0.18), // Orchid pink bloom
                  const Color(0xFF8E68A9).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -80,
          width: 380,
          height: 380,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF384F95).withValues(alpha: 0.22), // Medium indigo bloom
                  const Color(0xFF203B6F).withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: 280,
          left: 30,
          width: 250,
          height: 250,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF8E68A9).withValues(alpha: 0.14), // Muted purple bloom
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // 3. Subtle Scattered Starfield
        if (showStars)
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StarFieldPainter(),
              ),
            ),
          ),

        // 4. Foreground Content
        child,
      ],
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic pseudo-random generation using fixed coordinates so stars never flicker
    final stars = [
      // xRatio, yRatio, radius, opacity, isGlow
      [0.12, 0.08, 1.2, 0.75, true],
      [0.25, 0.15, 0.8, 0.50, false],
      [0.38, 0.06, 1.5, 0.85, true],
      [0.55, 0.12, 0.9, 0.60, false],
      [0.72, 0.05, 1.3, 0.80, true],
      [0.85, 0.18, 0.7, 0.45, false],
      [0.92, 0.10, 1.1, 0.70, false],
      [0.08, 0.24, 0.8, 0.55, false],
      [0.48, 0.22, 1.6, 0.90, true],
      [0.65, 0.28, 0.7, 0.40, false],
      [0.82, 0.32, 1.0, 0.65, false],
      [0.15, 0.38, 1.4, 0.80, true],
      [0.28, 0.42, 0.8, 0.50, false],
      [0.78, 0.45, 1.2, 0.75, false],
      [0.90, 0.40, 0.9, 0.60, false],
      [0.06, 0.55, 1.0, 0.70, false],
      [0.22, 0.58, 1.5, 0.85, true],
      [0.35, 0.65, 0.8, 0.45, false],
      [0.58, 0.52, 1.1, 0.65, false],
      [0.85, 0.60, 1.3, 0.80, true],
      [0.95, 0.68, 0.7, 0.50, false],
      [0.10, 0.72, 1.2, 0.75, false],
      [0.42, 0.75, 1.6, 0.90, true],
      [0.70, 0.78, 0.9, 0.60, false],
      [0.88, 0.82, 1.1, 0.70, false],
      [0.18, 0.88, 0.8, 0.55, false],
      [0.30, 0.92, 1.3, 0.80, true],
      [0.62, 0.90, 1.0, 0.65, false],
      [0.75, 0.95, 1.5, 0.85, true],
      [0.92, 0.92, 0.8, 0.50, false],
    ];

    final starPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    for (final s in stars) {
      final x = (s[0] as double) * size.width;
      final y = (s[1] as double) * size.height;
      final radius = s[2] as double;
      final opacity = s[3] as double;
      final isGlow = s[4] as bool;

      if (isGlow) {
        glowPaint.color = const Color(0xFFDBC9F9).withValues(alpha: opacity * 0.35);
        canvas.drawCircle(Offset(x, y), radius * 2.8, glowPaint);
      }

      starPaint.color = const Color(0xFFF8FAFC).withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
