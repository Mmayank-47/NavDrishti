import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Service managing the system-wide floating navigation overlay.
/// When NAV-SHIELD is backgrounded or minimized during an active trip,
/// this service opens a native Android SYSTEM_ALERT_WINDOW floating over
/// whatever app the user is using (YouTube, WhatsApp, Android Home, etc.).
class OverlayNavigationService {
  OverlayNavigationService._();
  static final OverlayNavigationService instance = OverlayNavigationService._();

  bool _isOverlayShowing = false;
  bool get isOverlayShowing => _isOverlayShowing;

  /// Check whether the SYSTEM_ALERT_WINDOW permission has been granted
  Future<bool> isPermissionGranted() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('[OverlayService] Permission check error: $e');
      return false;
    }
  }

  /// Request SYSTEM_ALERT_WINDOW permission from Android system settings
  Future<bool?> requestPermission() async {
    try {
      return await FlutterOverlayWindow.requestPermission();
    } catch (e) {
      debugPrint('[OverlayService] Request permission error: $e');
      return false;
    }
  }

  Map<String, dynamic>? lastPayload;

  /// Show the floating overlay window
  Future<bool> showOverlay({
    required String instruction,
    required String distance,
    required String eta,
    required String mode,
    required String speed,
    double? heading,
    double? currentLat,
    double? currentLng,
    double? progress,
    String? turnType,
    List<List<double>>? routePoints,
  }) async {
    try {
      final hasPermission = await isPermissionGranted();
      if (!hasPermission) {
        debugPrint('[OverlayService] Overlay permission not granted; falling back to notification.');
        return false;
      }

      final isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) {
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          overlayTitle: 'NAV-SHIELD Navigation',
          overlayContent: '$instruction · $distance ($eta)',
          flag: OverlayFlag.defaultFlag,
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.auto,
          height: 540,
          width: 760,
        );
      }

      _isOverlayShowing = true;
      try {
        await _controlChannel.invokeMethod('hookOverlayEngine');
      } catch (_) {}
      await updateOverlay(
        instruction: instruction,
        distance: distance,
        eta: eta,
        mode: mode,
        speed: speed,
        heading: heading,
        currentLat: currentLat,
        currentLng: currentLng,
        progress: progress,
        turnType: turnType,
        routePoints: routePoints,
      );
      return true;
    } catch (e) {
      debugPrint('[OverlayService] Error showing overlay: $e');
      _isOverlayShowing = false;
      return false;
    }
  }

  /// Send live telemetry and map coordinates to the floating overlay isolate
  Future<void> updateOverlay({
    required String instruction,
    required String distance,
    required String eta,
    required String mode,
    required String speed,
    double? heading,
    double? currentLat,
    double? currentLng,
    double? progress,
    String? turnType,
    List<List<double>>? routePoints,
  }) async {
    try {
      final data = <String, dynamic>{
        'instruction': instruction,
        'distance': distance,
        'eta': eta,
        'mode': mode,
        'speed': speed,
        'heading': ?heading,
        'currentLat': ?currentLat,
        'currentLng': ?currentLng,
        'progress': ?progress,
        'turnType': ?turnType,
        'routePoints': ?routePoints,
      };
      lastPayload = data;
      final payload = jsonEncode(data);
      await FlutterOverlayWindow.shareData(payload);
    } catch (e) {
      debugPrint('[OverlayService] Error sharing overlay data: $e');
    }
  }

  static const MethodChannel _controlChannel =
      MethodChannel('com.navshield.nav_shield/overlay_control');

  /// Move NAV-SHIELD task to Android background (like pressing Home)
  Future<void> sendToBackground() async {
    try {
      await _controlChannel.invokeMethod('sendToBackground');
    } catch (e) {
      debugPrint('[OverlayService] Error sending to background: $e');
    }
  }

  /// Bring NAV-SHIELD task back to the Android foreground
  Future<void> bringToForeground() async {
    try {
      await _controlChannel.invokeMethod('bringToForeground');
    } catch (e) {
      debugPrint('[OverlayService] Error bringing to foreground: $e');
    }
  }

  /// Close and dismiss the floating overlay window
  Future<void> closeOverlay() async {
    try {
      _isOverlayShowing = false;
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (e) {
      debugPrint('[OverlayService] Error closing overlay: $e');
    }
  }
}
