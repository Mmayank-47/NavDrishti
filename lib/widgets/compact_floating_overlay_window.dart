import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../theme/app_theme.dart';

/// Overlay Window Entry Widget (System-wide floating card drawn on top of other apps)
/// Runs inside the Android SYSTEM_ALERT_WINDOW rendered by flutter_overlay_window.
class CompactFloatingOverlayWindow extends StatefulWidget {
  final Map<String, dynamic>? initialData;

  const CompactFloatingOverlayWindow({super.key, this.initialData});

  @override
  State<CompactFloatingOverlayWindow> createState() =>
      _CompactFloatingOverlayWindowState();
}

class _CompactFloatingOverlayWindowState
    extends State<CompactFloatingOverlayWindow> {
  String _instruction = 'Turn right on MG Road';
  String _distance = '240 m';
  String _eta = '4 min';
  String _mode = 'GNSS_AIDED';
  String _speed = '36 km/h';
  double _heading = 12.67;
  double _currentLat = 12.97162;
  double _currentLng = 77.594461;
  double _progress = 0.15;
  String _turnType = 'turn_right';
  List<List<double>> _routePoints = [];

  StreamSubscription? _overlaySub;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _applyData(widget.initialData!);
    }

    // Listen for live trip telemetry streamed from the main app
    try {
      _overlaySub = FlutterOverlayWindow.overlayListener.listen((data) {
        if (data == null) return;
        try {
          Map<String, dynamic> map;
          if (data is String) {
            map = jsonDecode(data) as Map<String, dynamic>;
          } else if (data is Map) {
            map = Map<String, dynamic>.from(data);
          } else {
            return;
          }

          if (mounted) {
            setState(() {
              _applyData(map);
            });
          }
        } catch (e) {
          debugPrint('[Overlay] Data parse error: $e');
        }
      }, onError: (err) {
        debugPrint('[Overlay] Listener stream error: $err');
      });
    } catch (e) {
      debugPrint('[Overlay] Listener registration: $e');
    }
  }

  void _applyData(Map<String, dynamic> map) {
    _instruction = map['instruction'] as String? ?? _instruction;
    _distance = map['distance'] as String? ?? _distance;
    _eta = map['eta'] as String? ?? _eta;
    _mode = map['mode'] as String? ?? _mode;
    _speed = map['speed'] as String? ?? _speed;
    _heading = (map['heading'] as num?)?.toDouble() ?? _heading;
    _currentLat = (map['currentLat'] as num?)?.toDouble() ?? _currentLat;
    _currentLng = (map['currentLng'] as num?)?.toDouble() ?? _currentLng;
    _progress = (map['progress'] as num?)?.toDouble() ?? _progress;
    _turnType = map['turnType'] as String? ?? _turnType;
    if (map['routePoints'] != null) {
      final raw = map['routePoints'] as List<dynamic>;
      _routePoints = raw
          .map((p) => [
                ((p as List)[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ])
          .toList();
    }
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    _overlaySub = null;
    super.dispose();
  }

  Future<void> _bringAppToForeground() async {
    // 1. Invoke Android platform intent to bring NAV-SHIELD back to foreground
    const platform = MethodChannel('com.navshield.nav_shield/overlay_control');
    try {
      await platform.invokeMethod('bringToForeground');
    } catch (e) {
      debugPrint('[Overlay] Error bringing app to foreground via channel: $e');
    }

    // 2. Also send IPC message via flutter_overlay_window
    try {
      await FlutterOverlayWindow.shareData(
        jsonEncode({'action': 'bringToForeground'}),
      );
    } catch (_) {}

    // 3. Close the overlay window
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  IconData _getTurnIcon(String type) {
    switch (type) {
      case 'turn_right':
        return Icons.turn_right_rounded;
      case 'slight_right':
        return Icons.turn_slight_right_rounded;
      case 'turn_left':
        return Icons.turn_left_rounded;
      case 'slight_left':
        return Icons.turn_slight_left_rounded;
      case 'u_turn':
        return Icons.u_turn_left_rounded;
      case 'destination':
        return Icons.place_rounded;
      default:
        return Icons.straight_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDR = _mode.toUpperCase().contains('DEAD') ||
        _mode.toUpperCase().contains('DR');
    final accentColor = isDR ? AppColors.orchidPink : AppColors.periwinkle;
    final turnIcon = _getTurnIcon(_turnType);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: _bringAppToForeground,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 320,
            height: 210,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xF5312048), // deep plum
                  Color(0xF5203B6F), // deep navy
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.85),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.40),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  // Live dynamic mini-map tile updating with current coordinates and route
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LiveMiniMapPainter(
                        currentLat: _currentLat,
                        currentLng: _currentLng,
                        heading: _heading,
                        routePoints: _routePoints,
                        accentColor: accentColor,
                        isDR: isDR,
                        turnType: _turnType,
                        progress: _progress,
                      ),
                    ),
                  ),

                  // Top instruction banner
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE6131D31),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.40),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.55),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              turnIcon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _distance,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _instruction,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Dedicated Expand Button with explicit tap handler
                          GestureDetector(
                            onTap: _bringAppToForeground,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                              child: const Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom telemetry strip (ETA pill & Speed/Mode badge)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ETA Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xE610192A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded, color: Colors.white70, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                _eta,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Speed & Mode Badge
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accentColor,
                                width: 1.1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Text(
                              isDR ? 'INS DR · $_speed' : 'GNSS · $_speed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 11.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a live, dynamic mini-map tile centered on current vehicle position
/// in heading-up orientation with live route path, vehicle chevron, and turn beacon.
class _LiveMiniMapPainter extends CustomPainter {
  final double currentLat;
  final double currentLng;
  final double heading;
  final List<List<double>> routePoints;
  final Color accentColor;
  final bool isDR;
  final String turnType;
  final double progress;

  _LiveMiniMapPainter({
    required this.currentLat,
    required this.currentLng,
    required this.heading,
    required this.routePoints,
    required this.accentColor,
    required this.isDR,
    required this.turnType,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Cosmic dark map base
    final bgPaint = Paint()..color = const Color(0xFF0D1527);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Faint street grid / block network
    final gridPaint = Paint()
      ..color = const Color(0xFF162238)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const gridSpacing = 32.0;
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final center = Offset(size.width * 0.5, size.height * 0.58);
    final radHeading = -heading * math.pi / 180.0;
    const double metersPerDegLat = 111139.0;
    final double metersPerDegLng =
        111139.0 * math.cos(currentLat * math.pi / 180.0);
    const double scale = 0.52; // 1 meter = 0.52 screen pixels

    Offset toScreen(double lat, double lng) {
      final dyMeters = (lat - currentLat) * metersPerDegLat;
      final dxMeters = (lng - currentLng) * metersPerDegLng;
      final rx = dxMeters * math.cos(radHeading) - dyMeters * math.sin(radHeading);
      final ry = dxMeters * math.sin(radHeading) + dyMeters * math.cos(radHeading);
      return Offset(center.dx + rx * scale, center.dy - ry * scale);
    }

    // 3. Render Route Polyline
    if (routePoints.length >= 2) {
      final casingPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final routeGlowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final routePaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      bool first = true;
      for (final pt in routePoints) {
        final screenPos = toScreen(pt[0], pt[1]);
        if (first) {
          path.moveTo(screenPos.dx, screenPos.dy);
          first = false;
        } else {
          path.lineTo(screenPos.dx, screenPos.dy);
        }
      }

      canvas.drawPath(path, casingPaint);
      canvas.drawPath(path, routeGlowPaint);
      canvas.drawPath(path, routePaint);
    } else {
      // Fallback stylized live road curve dynamically rotating with heading
      final casingPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final routePaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(center.dx, size.height + 20);
      path.lineTo(center.dx, center.dy);

      final turnRight = turnType.contains('right');
      final targetX = turnRight ? size.width + 20 : -20.0;
      path.quadraticBezierTo(
        center.dx,
        center.dy - 40,
        targetX,
        center.dy - 40,
      );

      canvas.drawPath(path, casingPaint);
      canvas.drawPath(path, routePaint);
    }

    // 4. Vehicle Navigation Marker (at center, pointing forward/up)
    // Uncertainty halo
    final haloRadius = isDR ? 28.0 : 15.0;
    final haloPaint = Paint()
      ..color = accentColor.withValues(alpha: isDR ? 0.28 : 0.20)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, haloRadius, haloPaint);

    final haloBorderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, haloRadius, haloBorderPaint);

    // Vehicle directional chevron pointing upward
    final chevronPath = Path();
    chevronPath.moveTo(center.dx, center.dy - 14); // tip
    chevronPath.lineTo(center.dx + 9.5, center.dy + 9.5); // right wing
    chevronPath.lineTo(center.dx, center.dy + 4.5); // inner notch
    chevronPath.lineTo(center.dx - 9.5, center.dy + 9.5); // left wing
    chevronPath.close();

    final chevronPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(chevronPath, chevronPaint);

    final chevronBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(chevronPath, chevronBorderPaint);

    // Center vehicle dot
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 2.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _LiveMiniMapPainter oldDelegate) {
    return oldDelegate.currentLat != currentLat ||
        oldDelegate.currentLng != currentLng ||
        oldDelegate.heading != heading ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.turnType != turnType ||
        oldDelegate.progress != progress ||
        oldDelegate.routePoints.length != routePoints.length;
  }
}
