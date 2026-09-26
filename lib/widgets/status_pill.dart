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
  final bool isReacquiring;
  final VoidCallback onOpenDebug;

  const StatusPill({
    super.key,
    required this.mode,
    required this.timeInCurrentMode,
    this.uncertaintyMeters,
    this.isReacquiring = false,
    required this.onOpenDebug,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDeadReckoning = mode == NavMode.deadReckoning;

    Color accentColor;
    if (isReacquiring) {
      accentColor = const Color(0xFF10B981); // Emerald / Transitioning Green
    } else if (isDeadReckoning) {
      accentColor = isDark ? AppColors.darkViolet : AppColors.lightViolet;
    } else {
      accentColor = isDark ? AppColors.darkCyan : AppColors.lightCyan;
    }

    final borderColor = isReacquiring
        ? const Color(0xFF10B981).withValues(alpha: 0.75)
        : (isDark
            ? (isDeadReckoning
                ? accentColor.withValues(alpha: 0.70)
                : accentColor.withValues(alpha: 0.50))
            : accentColor.withValues(alpha: 0.40));

    final accuracyText = uncertaintyMeters != null ? '±${uncertaintyMeters!.toStringAsFixed(1)}m' : null;

    return Align(
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onLongPress: onOpenDebug,
        onTap: onOpenDebug,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: (isDeadReckoning || isReacquiring)
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
              : (accuracyText != null
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : const EdgeInsets.all(8)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF131D38).withValues(alpha: 0.88),
                      const Color(0xFF090E1F).withValues(alpha: 0.80),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.94),
                      const Color(0xFFF1F5F9).withValues(alpha: 0.88),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: isDark ? 0.35 : 0.22),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
          ),
          child: isReacquiring
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF10B981),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'REACQUIRING · Annealing GNSS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                )
              : isDeadReckoning
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Dead Reckoning · ${timeInCurrentMode}s${accuracyText != null ? ' ($accuracyText)' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                            ),
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
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ],
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
