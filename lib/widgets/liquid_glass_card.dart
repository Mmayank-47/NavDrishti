import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable Liquid Glassmorphic card container.
///
/// Features:
/// - Real backdrop blur filter for frosted glass depth separation
/// - Semi-transparent layered surface with subtle reflection gradient
/// - Glowing outer border and soft ambient elevation shadows
/// - Subtle light reflection and highlight on card edges
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? glowColor;
  final double blurSigma;
  final double glowRadius;
  final double glowAlpha;
  final VoidCallback? onTap;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.borderColor,
    this.glowColor,
    this.blurSigma = 12.0,
    this.glowRadius = 14.0,
    this.glowAlpha = 0.25,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultGlow = isDark ? AppColors.periwinkle : AppColors.orchidPink;
    final effectiveGlow = glowColor ?? defaultGlow;

    final border = borderColor ??
        (isDark
            ? const Color(0xFF8E68A9).withValues(alpha: 0.50)
            : const Color(0xFFBC7EBF).withValues(alpha: 0.35));

    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF312048).withValues(alpha: 0.86), // deep plum
                  const Color(0xFF203B6F).withValues(alpha: 0.74), // deep navy
                ]
              : [
                  Colors.white.withValues(alpha: 0.94),
                  const Color(0xFFDBC9F9).withValues(alpha: 0.32), // palest lavender
                ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: effectiveGlow.withValues(alpha: glowAlpha),
            blurRadius: glowRadius,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (blurSigma > 0) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

