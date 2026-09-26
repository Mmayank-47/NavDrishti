import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../theme/app_theme.dart';
import 'nav_map.dart';

/// Compact Floating Navigation Widget (Google Maps PiP Style)
///
/// Designed to persist above the UI when the trip is active and minimized.
/// Displays:
/// 1. A small cropped map tile centered on current vehicle position with route polyline
/// 2. Turn direction arrow icon
/// 3. Turn instruction text (e.g. "Turn right")
/// 4. Distance to turn (e.g. "240 m")
/// 5. Live ETA (e.g. "4 min")
/// 6. Tap to bring full app back to foreground
/// 7. Draggable / repositionable on screen
class CompactFloatingNavWidget extends StatefulWidget {
  final NavShieldState state;
  final PlannedRoute? plannedRoute;
  final String instruction;
  final String distanceToTurn;
  final String eta;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final Offset? initialPosition;
  final bool isDark;

  const CompactFloatingNavWidget({
    super.key,
    required this.state,
    this.plannedRoute,
    this.instruction = 'Turn right',
    this.distanceToTurn = '240 m',
    this.eta = '4 min',
    required this.onTap,
    this.onDismiss,
    this.initialPosition,
    this.isDark = true,
  });

  @override
  State<CompactFloatingNavWidget> createState() =>
      _CompactFloatingNavWidgetState();
}

class _CompactFloatingNavWidgetState extends State<CompactFloatingNavWidget> {
  late Offset _position;
  final double _widgetWidth = 210.0;
  final double _widgetHeight = 160.0;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition ?? const Offset(20, 100);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isDeadReckoning = widget.state.currentMode == NavMode.deadReckoning;
    final accentColor = isDeadReckoning
        ? (widget.isDark ? AppColors.darkViolet : AppColors.lightViolet)
        : (widget.isDark ? AppColors.darkCyan : AppColors.lightBlue);

    // Keep position clamped within screen bounds
    final clampedX = _position.dx.clamp(10.0, (screenSize.width - _widgetWidth - 10.0).clamp(10.0, 1000.0));
    final clampedY = _position.dy.clamp(40.0, (screenSize.height - _widgetHeight - 40.0).clamp(40.0, 2000.0));

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        key: const ValueKey('compact_floating_nav_draggable'),
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onTap: widget.onTap,
        child: Material(
          elevation: 12,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: _widgetWidth,
            height: _widgetHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.8),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Stack(
              children: [
                // 1. Cropped Mini Map Tile
                Positioned.fill(
                  child: IgnorePointer(
                    child: NavMap(
                      state: widget.state,
                      isDark: widget.isDark,
                      plannedRoute: widget.plannedRoute,
                    ),
                  ),
                ),

                // 2. Subtle dark gradient overlay for text readability
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.70),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Top Banner: Next Turn Direction + Distance + Mode Pill
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      // Turn Arrow Badge
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.turn_right_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Turn Distance & Instruction
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.distanceToTurn,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              widget.instruction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Mode indicator badge (GNSS vs DR)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDeadReckoning
                              ? Colors.purple.withValues(alpha: 0.3)
                              : Colors.cyan.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isDeadReckoning ? 'DR' : 'GNSS',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Bottom Banner: Live ETA & Expand Hint
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ETA Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.eta,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Return to App Hint Icon
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // 5. Subtle drag handle top center
                Positioned(
                  top: 3,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
