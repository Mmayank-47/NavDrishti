import 'package:flutter/material.dart';

/// Semantic design tokens for NAV-SHIELD Galaxy / Starry Glassmorphic HUD Style.
///
/// Palette Reference (Exact Hex Values):
/// - #DBC9F9 — palest lavender (light accents, subtle highlights, light-mode base tones)
/// - #BC7EBF — orchid pink-purple (secondary accent, highlights, active states)
/// - #8E68A9 — muted purple (mid-tone accent, borders/glows)
/// - #312048 — deep plum/purple-black (dark surfaces, card backgrounds)
/// - #203B6F — deep navy blue (dark surfaces, base background tone)
/// - #384F95 — medium indigo-blue (primary accent, buttons, active elements)
/// - #A6BAEE — soft periwinkle blue (light accents, text on dark surfaces, glows)
class AppColors {
  // Exact Palette Definitions
  static const Color palestLavender = Color(0xFFDBC9F9);
  static const Color orchidPink = Color(0xFFBC7EBF);
  static const Color mutedPurple = Color(0xFF8E68A9);
  static const Color deepPlum = Color(0xFF312048);
  static const Color deepNavy = Color(0xFF203B6F);
  static const Color mediumIndigo = Color(0xFF384F95);
  static const Color periwinkle = Color(0xFFA6BAEE);

  // Dark Palette (Galaxy Deep Space)
  static const Color darkBackground = Color(0xFF203B6F);
  static const Color darkSurface = Color(0xFF312048);
  static const Color darkSurfaceSubtle = Color(0xFF261838);
  static const Color darkSurfaceElevated = Color(0xFF3C2756);
  static const Color darkCardSurface = Color(0xFF312048);
  static const Color darkPrimaryText = Color(0xFFF8FAFC);
  static const Color darkSecondaryText = Color(0xFFA6BAEE);
  static const Color darkBorder = Color(0xFF4C366B);
  static const Color darkBorderHighlight = Color(0xFF8E68A9);
  static const Color darkLuminousBorder = Color(0xFFA6BAEE);

  static const Color darkBlue = Color(0xFFA6BAEE);
  static const Color darkCyan = Color(0xFF8EACEC);
  static const Color darkViolet = Color(0xFFBC7EBF);
  static const Color darkMagenta = Color(0xFFDBC9F9);
  static const Color darkGreen = Color(0xFF34D399);
  static const Color darkAmber = Color(0xFFFBBF24);
  static const Color darkRed = Color(0xFFFF2E63);

  // Light Palette (High-Contrast Clean Glass Variant adapted to palette)
  static const Color lightBackground = Color(0xFFF8F5FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSubtle = Color(0xFFEFE8FC);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightPrimaryText = Color(0xFF203B6F);
  static const Color lightSecondaryText = Color(0xFF4C366B);
  static const Color lightBorder = Color(0xFFDBC9F9);
  static const Color lightBorderHighlight = Color(0xFFBC7EBF);

  static const Color lightBlue = Color(0xFF384F95);
  static const Color lightCyan = Color(0xFF203B6F);
  static const Color lightViolet = Color(0xFF8E68A9);
  static const Color lightMagenta = Color(0xFFBC7EBF);
  static const Color lightGreen = Color(0xFF059669);
  static const Color lightAmber = Color(0xFFD97706);
  static const Color lightRed = Color(0xFFDC2626);

  static const LinearGradient cyanGlowGradient = LinearGradient(
    colors: [Color(0xFF384F95), Color(0xFFBC7EBF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [Color(0xFF384F95), Color(0xFF8E68A9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.darkSurface,
        primary: AppColors.orchidPink,
        secondary: AppColors.periwinkle,
        tertiary: AppColors.mediumIndigo,
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
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: AppColors.darkPrimaryText,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
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
        primary: AppColors.lightCyan,
        secondary: AppColors.lightBlue,
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
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: AppColors.lightPrimaryText,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
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
  /// (Cyan for GNSS_AIDED/Fused, Violet for DEAD_RECKONING, Amber for DEGRADED, Red for SOS)
  static Color getAccentColor(
    BuildContext context, {
    required bool isDeadReckoning,
    bool isDegraded = false,
    bool isSos = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isSos) {
      return isDark ? AppColors.darkRed : AppColors.lightRed;
    }
    if (isDegraded) {
      return isDark ? AppColors.darkAmber : AppColors.lightAmber;
    }
    if (isDeadReckoning) {
      return isDark ? AppColors.darkViolet : AppColors.lightViolet;
    }
    return isDark ? AppColors.darkCyan : AppColors.lightCyan;
  }

  /// Reusable glassmorphic decoration for NAV-SHIELD cards with liquid glass aesthetic
  static BoxDecoration glassDecoration(
    BuildContext context, {
    double borderRadius = 20.0,
    Color? borderColor,
    Color? glowColor,
    double glowRadius = 14.0,
    double glowAlpha = 0.25,
    bool withGradient = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseSurface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final defaultGlow = isDark ? AppColors.periwinkle : AppColors.orchidPink;
    final effectiveGlow = glowColor ?? defaultGlow;
    final border = borderColor ??
        (isDark
            ? const Color(0xFF8E68A9).withValues(alpha: 0.45)
            : const Color(0xFFBC7EBF).withValues(alpha: 0.35));

    return BoxDecoration(
      gradient: withGradient
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF312048).withValues(alpha: 0.86),
                      const Color(0xFF203B6F).withValues(alpha: 0.74),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.94),
                      const Color(0xFFDBC9F9).withValues(alpha: 0.30),
                    ],
            )
          : null,
      color: withGradient ? null : baseSurface.withValues(alpha: isDark ? 0.78 : 0.90),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: border, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: effectiveGlow.withValues(alpha: glowAlpha),
          blurRadius: glowRadius,
          spreadRadius: 0,
        ),
      ],
    );
  }

  /// Advanced Liquid Glass decoration matching the futuristic glassmorphic aesthetic
  /// (Layered soft blur, glowing edge borders, depth drop shadows, light highlights)
  static BoxDecoration liquidGlassDecoration(
    BuildContext context, {
    double borderRadius = 22.0,
    Color? borderColor,
    Color? glowColor,
    double glowRadius = 16.0,
    double glowAlpha = 0.28,
  }) {
    return glassDecoration(
      context,
      borderRadius: borderRadius,
      borderColor: borderColor,
      glowColor: glowColor,
      glowRadius: glowRadius,
      glowAlpha: glowAlpha,
      withGradient: true,
    );
  }
}
