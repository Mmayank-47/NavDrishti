import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../theme/app_theme.dart';

/// Minimal top status pill (not a heavy bar).
///
/// Principles:
/// - When GNSS_AIDED: Just a small solid dot in the blue accent color (no unnecessary text)
/// - When DEAD_RECKONING: Mode label + live counting timer ("Dead Reckoning · 14s") in amber
/// - Long-press or tap opens debug actions sheet
class StatusPill extends StatelessWidget {
  final NavMode mode;
  final int timeInCurrentMode;
  final double? uncertaintyMeters;
  final VoidCallback onOpenDebug;

  const StatusPill({
    super.key,
    required this.mode,
    required this.timeInCurrentMode,
    this.uncertaintyMeters,
    required this.onOpenDebug,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDeadReckoning = mode == NavMode.deadReckoning;

    final accentColor = isDeadReckoning
        ? (isDark ? AppColors.darkAmber : AppColors.lightAmber)
        : (isDark ? AppColors.darkBlue : AppColors.lightBlue);

    final bgColor = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.92)
        : accentColor.withValues(alpha: 0.08);

    final borderColor = isDark
        ? (isDeadReckoning ? accentColor.withValues(alpha: 0.5) : AppColors.darkBorder)
        : accentColor.withValues(alpha: 0.35);

    final accuracyText = uncertaintyMeters != null ? '±${uncertaintyMeters!.toStringAsFixed(1)}m' : null;

    return Align(
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onLongPress: onOpenDebug,
        onTap: onOpenDebug,
        child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: isDeadReckoning
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                  : (accuracyText != null
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                      : const EdgeInsets.all(8)),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: borderColor,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isDeadReckoning
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Dead Reckoning · ${timeInCurrentMode}s${accuracyText != null ? ' ($accuracyText)' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                          ),
                        ),
                        if (accuracyText != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            accuracyText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        );
  }
}
