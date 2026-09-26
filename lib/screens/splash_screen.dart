import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'destination_entry_screen.dart';
import 'permissions_onboarding_screen.dart';

/// Screen: BRANDED SPLASH / LAUNCH SCREEN
///
/// Principles:
/// - Centered glowing shield-and-arrow logo icon with radiating glow rings
/// - App name "NAV-SHIELD" in large bold text
/// - Tagline: "Resilient Navigation Beyond GPS"
/// - Subtle Earth/globe graphic in lower portion with glowing horizon arc and scattered light points
/// - Bottom caption: "Navigate · Stay on Track · Anywhere"
/// - Thin animated progress bar at the very bottom
/// - Auto-dismisses into DestinationEntryScreen once initialized
class SplashScreen extends StatefulWidget {
  final Duration displayDuration;
  final bool autoDismiss;

  const SplashScreen({
    super.key,
    this.displayDuration = const Duration(milliseconds: 2000),
    this.autoDismiss = true,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.displayDuration,
    )..forward();

    if (widget.autoDismiss) {
      _dismissTimer = Timer(widget.displayDuration, _navigateToHome);
    }
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final hasCompletedOnboarding =
        prefs.getBool('has_completed_onboarding') ?? false;

    if (!mounted) return;

    final targetScreen = hasCompletedOnboarding
        ? const DestinationEntryScreen()
        : const PermissionsOnboardingScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : const Color(0xFF070B14);
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : Colors.white;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : const Color(0xFF94A3B8);
    final accentCyan = AppColors.darkCyan;
    final accentBlue = AppColors.darkBlue;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: _navigateToHome,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Subtle Earth Horizon & City Light Points Graphic
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.42,
              child: CustomPaint(
                painter: _EarthHorizonPainter(
                  horizonColor: accentCyan.withValues(alpha: 0.35),
                  atmosphereColor: accentBlue.withValues(alpha: 0.15),
                ),
              ),
            ),

            // 2. Centered Logo & Branding
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Radiating Shield Logo
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return SizedBox(
                        width: 140,
                        height: 140,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Radiating Outer Pulse Ring 2
                            Container(
                              width: 130 + math.sin(_controller.value * math.pi * 2) * 6,
                              height: 130 + math.sin(_controller.value * math.pi * 2) * 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accentCyan.withValues(alpha: 0.18),
                                  width: 1.0,
                                ),
                              ),
                            ),
                            // Radiating Outer Pulse Ring 1
                            Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accentBlue.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentCyan.withValues(alpha: 0.20),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            // Core Glowing Badge
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accentCyan.withValues(alpha: 0.25),
                                    accentBlue.withValues(alpha: 0.40),
                                  ],
                                ),
                                border: Border.all(
                                  color: accentCyan,
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentCyan.withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(
                                      Icons.shield_rounded,
                                      size: 38,
                                      color: accentCyan,
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 2.0),
                                      child: Icon(
                                        Icons.navigation_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Brand Title
                  Text(
                    'NAV-SHIELD',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.8,
                      color: primaryTextColor,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tagline
                  Text(
                    'Resilient Navigation Beyond GPS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),

            // 3. Bottom Caption & Thin Loading Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Navigate · Stay on Track · Anywhere',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: secondaryTextColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Thin Progress Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48.0),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              height: 3,
                              child: LinearProgressIndicator(
                                value: _controller.value,
                                backgroundColor: Colors.white.withValues(alpha: 0.10),
                                valueColor: AlwaysStoppedAnimation<Color>(accentCyan),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter rendering a subtle Earth / globe horizon arc with scattered city lights
class _EarthHorizonPainter extends CustomPainter {
  final Color horizonColor;
  final Color atmosphereColor;

  _EarthHorizonPainter({
    required this.horizonColor,
    required this.atmosphereColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 2.1);
    final radius = size.height * 1.85;

    // Atmospheric Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 1.0),
        radius: 0.9,
        colors: [
          atmosphereColor,
          atmosphereColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);

    // Planet Body Fill
    final planetPaint = Paint()
      ..color = const Color(0xFF060912)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, planetPaint);

    // Glowing Horizon Line
    final horizonPaint = Paint()
      ..color = horizonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, horizonPaint);

    // Scattered City Light Points
    final random = math.Random(42);
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 40; i++) {
      final angle = -math.pi / 2 + (random.nextDouble() - 0.5) * 0.95;
      final dist = radius - (random.nextDouble() * 55 + 5);
      final dx = center.dx + dist * math.cos(angle);
      final dy = center.dy + dist * math.sin(angle);

      if (dx >= 0 && dx <= size.width && dy >= size.height * 0.35 && dy <= size.height) {
        final brightness = random.nextDouble() * 0.6 + 0.3;
        dotPaint.color = (random.nextBool() ? const Color(0xFF38BDF8) : const Color(0xFFFDE047))
            .withValues(alpha: brightness);
        canvas.drawCircle(Offset(dx, dy), random.nextDouble() * 1.6 + 0.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EarthHorizonPainter oldDelegate) => false;
}
