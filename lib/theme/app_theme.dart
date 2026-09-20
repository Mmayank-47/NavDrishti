import 'package:flutter/material.dart';

/// Semantic design tokens for NAV-SHIELD Branded HUD Style.
///
/// Principles:
/// - Deep navy/black backgrounds with glassmorphic cards and soft borders.
/// - Glowing rings and icon badges.
/// - Color semantic model:
///   Blue: GNSS / high-accuracy satellite localization (~#3B82F6)
///   Cyan: Fused GNSS+INS localization (~#22D3EE)
///   Violet: INS / Dead-Reckoning (~#A855F7)
///   Green: Healthy / nominal system status (~#22C55E)
///   Amber: Degraded / low-confidence warning (~#F59E0B)
///   Red: Exclusively reserved for Emergency / SOS / Crash (~#EF4444)
class AppColors {
  // Dark Palette (Primary Reference Visuals)
  static const Color darkBackground = Color(0xFF0A0E1A);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceSubtle = Color(0xFF1E293B);
  static const Color darkPrimaryText = Color(0xFFF9FAFB);
  static const Color darkSecondaryText = Color(0xFF9CA3AF);
  static const Color darkBorder = Color(0xFF1F293D);
  static const Color darkBorderHighlight = Color(0xFF334155);

  static const Color darkBlue = Color(0xFF3B82F6);
  static const Color darkCyan = Color(0xFF22D3EE);
  static const Color darkViolet = Color(0xFFA855F7);
  static const Color darkGreen = Color(0xFF22C55E);
  static const Color darkAmber = Color(0xFFF59E0B);
  static const Color darkRed = Color(0xFFEF4444);

  // Light Palette (Equivalent High-Contrast Variant)
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSubtle = Color(0xFFF1F5F9);
  static const Color lightPrimaryText = Color(0xFF0F172A);
  static const Color lightSecondaryText = Color(0xFF64748B);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderHighlight = Color(0xFFCBD5E1);

  static const Color lightBlue = Color(0xFF2563EB);
  static const Color lightCyan = Color(0xFF0891B2);
  static const Color lightViolet = Color(0xFF9333EA);
  static const Color lightGreen = Color(0xFF16A34A);
  static const Color lightAmber = Color(0xFFD97706);
  static const Color lightRed = Color(0xFFDC2626);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.darkSurface,
        primary: AppColors.darkBlue,
        secondary: AppColors.darkCyan,
        tertiary: AppColors.darkViolet,
        error: AppColors.darkRed,
        onSurface: AppColors.darkPrimaryText,
        onPrimary: Colors.white,
        outline: AppColors.darkBorder,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.darkPrimaryText,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.darkPrimaryText,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.darkPrimaryText,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.darkPrimaryText,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.darkPrimaryText,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.darkSecondaryText,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.darkPrimaryText,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        surface: AppColors.lightSurface,
        primary: AppColors.lightBlue,
        secondary: AppColors.lightCyan,
        tertiary: AppColors.lightViolet,
        error: AppColors.lightRed,
        onSurface: AppColors.lightPrimaryText,
        onPrimary: Colors.white,
        outline: AppColors.lightBorder,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.lightPrimaryText,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.lightPrimaryText,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.lightPrimaryText,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.lightPrimaryText,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.lightPrimaryText,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.lightSecondaryText,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.lightPrimaryText,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// Helper to get current mode accent color
  /// (Blue for GNSS_AIDED, Violet/Amber for DEAD_RECKONING, Red for SOS)
  static Color getAccentColor(
    BuildContext context, {
    required bool isDeadReckoning,
    bool isSos = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isSos) {
      return isDark ? AppColors.darkRed : AppColors.lightRed;
    }
    if (isDeadReckoning) {
      return isDark ? AppColors.darkViolet : AppColors.lightViolet;
    }
    return isDark ? AppColors.darkCyan : AppColors.lightBlue;
  }

  /// Reusable glassmorphic decoration for NAV-SHIELD cards
  static BoxDecoration glassDecoration(
    BuildContext context, {
    double borderRadius = 18.0,
    Color? borderColor,
    Color? glowColor,
    double glowRadius = 8.0,
    double glowAlpha = 0.2,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = borderColor ?? (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    return BoxDecoration(
      color: surface.withValues(alpha: isDark ? 0.90 : 0.94),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: border, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        if (glowColor != null)
          BoxShadow(
            color: glowColor.withValues(alpha: glowAlpha),
            blurRadius: glowRadius,
            spreadRadius: 0,
          ),
      ],
    );
  }
}
