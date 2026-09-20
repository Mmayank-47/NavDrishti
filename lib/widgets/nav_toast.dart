import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NavToastType {
  gnssRecovered,
  lowConfidence,
  arrived,
}

/// Reusable pill-style toast/banner component for brief status transitions.
///
/// Principles:
/// - "GNSS RECOVERED / Re-fusing with INS" (green)
/// - "LOW CONFIDENCE / Accuracy degrading" (amber)
/// - "ARRIVED / Destination reached" (blue)
/// - Glassmorphic dark navy pill with glowing status dot and soft border
class NavToast extends StatelessWidget {
  final NavToastType type;
  final String? customTitle;
  final String? customSubtitle;
  final VoidCallback? onDismiss;

  const NavToast({
    super.key,
    required this.type,
    this.customTitle,
    this.customSubtitle,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color accentColor;
    IconData icon;
    String title;
    String subtitle;

    switch (type) {
      case NavToastType.gnssRecovered:
        accentColor = isDark ? AppColors.darkGreen : AppColors.lightGreen;
        icon = Icons.satellite_alt_rounded;
        title = 'GNSS RECOVERED';
        subtitle = 'Re-fusing with INS';
        break;
      case NavToastType.lowConfidence:
        accentColor = isDark ? AppColors.darkAmber : AppColors.lightAmber;
        icon = Icons.warning_amber_rounded;
        title = 'LOW CONFIDENCE';
        subtitle = 'Accuracy degrading';
        break;
      case NavToastType.arrived:
        accentColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;
        icon = Icons.check_circle_outline_rounded;
        title = 'ARRIVED';
        subtitle = 'Destination reached';
        break;
    }

    final displayTitle = customTitle ?? title;
    final displaySubtitle = customSubtitle ?? subtitle;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.darkSurface : AppColors.lightSurface)
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.35 : 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.2),
            ),
            child: Icon(icon, color: accentColor, size: 14),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayTitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: accentColor,
                ),
              ),
              Text(
                displaySubtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                ),
              ),
            ],
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
