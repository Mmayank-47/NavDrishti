import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Circular bottom-right emergency SOS button with HUD glow styling.
///
/// Principles:
/// - Red is strictly reserved for SOS / Crash emergency alerts.
/// - Requires press-and-hold (~1000ms) with an animated radial ring to prevent accidental taps.
/// - Concentric glowing shadows matching the reference mockup.
/// - Bell / Alert icon + bold "SOS" label.
class SosButton extends StatefulWidget {
  final VoidCallback onTrigger;

  const SosButton({
    super.key,
    required this.onTrigger,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;
  bool _hasTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_hasTriggered) {
          _hasTriggered = true;
          HapticFeedback.heavyImpact();
          widget.onTrigger();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _isHolding = true;
    });
    HapticFeedback.lightImpact();
    _controller.forward(from: 0.0);
  }

  void _onPointerUp(PointerUpEvent event) {
    _cancelHold();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelHold();
  }

  void _cancelHold() {
    setState(() {
      _isHolding = false;
    });
    _hasTriggered = false;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? AppColors.darkRed : AppColors.lightRed;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final scale = 1.0 + (progress * 0.08);

          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Ambient Glow Halo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: redColor.withValues(
                            alpha: _isHolding ? 0.65 : 0.35,
                          ),
                          blurRadius: _isHolding ? 24 : 16,
                          spreadRadius: _isHolding ? 4 : 1,
                        ),
                      ],
                    ),
                  ),

                  // Hold Progress Ring
                  if (_isHolding || progress > 0)
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4.0,
                        backgroundColor: redColor.withValues(alpha: 0.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),

                  // Core Red Circular Button with Glow & Subtle Inner Gradient
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          redColor.withValues(alpha: 0.95),
                          isDark ? const Color(0xFFB91C1C) : const Color(0xFF991B1B),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                        const SizedBox(height: 1),
                        const Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
