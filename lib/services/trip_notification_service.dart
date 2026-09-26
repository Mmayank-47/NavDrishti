import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/nav_shield_state.dart';

/// Service managing persistent background / lock-screen trip notifications.
///
/// Principles:
/// - Low-priority ongoing notification shown during active navigation
/// - Reflects live trip status: current mode (GNSS-Aided vs Dead Reckoning),
///   remaining distance, and ETA
/// - Safe error handling across platforms (Android, iOS, Web, Windows/tests)
class TripNotificationService {
  TripNotificationService._();
  static final TripNotificationService instance = TripNotificationService._();

  FlutterLocalNotificationsPlugin? _notificationsPlugin;
  FlutterLocalNotificationsPlugin? get _notifications {
    if (_unavailable) return null;
    if (_notificationsPlugin != null) return _notificationsPlugin;
    try {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();
    } catch (e) {
      _unavailable = true;
      debugPrint('[TripNotificationService] Plugin unavailable: $e');
    }
    return _notificationsPlugin;
  }

  bool _isInitialized = false;
  bool _unavailable = false;

  // Track status for UI, notifications preview, or testing
  String? lastTitle;
  String? lastBody;
  String? lastInstruction;
  String? lastTurnType;
  String? lastDistanceToTurn;
  double? lastProgressRatio;
  int? lastProgressPercent;
  DateTime? lastUpdateTime;
  bool isShowing = false;

  static const int _notificationId = 1001;
  static const String _channelId = 'nav_shield_trip_channel';
  static const String _channelName = 'NAV-SHIELD Active Trip Status';
  static const String _channelDesc =
      'Shows live turn-by-turn navigation updates, remaining distance, ETA, and route progress.';

  Future<void> initialize() async {
    if (_isInitialized || _unavailable) return;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxSettings =
          LinuxInitializationSettings(defaultActionName: 'Open NavDrishti');
      const windowsSettings = WindowsInitializationSettings(
        appName: 'NAV-SHIELD',
        appUserModelId: 'com.navshield.app',
        guid: 'c52ea11a-1a86-4f76-9cf1-248df9911e3b',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      );

      final plugin = _notifications;
      if (plugin == null) {
        _unavailable = true;
        return;
      }

      await plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('[TripNotificationService] Notification tapped: ${response.payload}');
        },
      );

      _isInitialized = true;
      debugPrint('[TripNotificationService] Initialized successfully');
    } catch (e) {
      _unavailable = true;
      debugPrint('[TripNotificationService] Init error (non-fatal, mocked or running in test): $e');
    }
  }

  /// Request notification permission on Android 13+ and iOS
  Future<bool> requestPermissions() async {
    if (_unavailable) return true;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _notifications?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidImpl?.requestNotificationsPermission();
        return granted ?? true;
      }
      return true;
    } catch (e) {
      debugPrint('[TripNotificationService] Permission request failed: $e');
      return true;
    }
  }

  /// Displays or updates the persistent live Google Maps-style trip status notification
  Future<void> updateTripStatus({
    required NavMode mode,
    required double remainingKm,
    required int remainingMins,
    required String destinationName,
    String? instruction,
    String? turnType,
    String? distanceToTurn,
    double? progressRatio,
  }) async {
    final isDeadReckoning = mode == NavMode.deadReckoning;
    final remainingText = remainingKm < 1.0
        ? '${(remainingKm * 1000).toStringAsFixed(0)} m'
        : '${remainingKm.toStringAsFixed(1)} km';

    final effectiveInstruction = instruction ??
        (isDeadReckoning
            ? 'INS Dead Reckoning Active'
            : 'Continue on current route');

    // Turn icon unicode symbol for notification title
    String turnSymbol = '⬆️';
    if (turnType != null) {
      if (turnType.contains('right')) {
        turnSymbol = '↪️';
      } else if (turnType.contains('left')) {
        turnSymbol = '↩️';
      } else if (turnType.contains('u_turn')) {
        turnSymbol = '🔄';
      } else if (turnType.contains('destination')) {
        turnSymbol = '🏁';
      }
    }

    final String notificationTitle = distanceToTurn != null
        ? '$turnSymbol $distanceToTurn · $effectiveInstruction'
        : '$turnSymbol $effectiveInstruction';

    final String modeLabel = isDeadReckoning ? 'INS DR Active' : 'GNSS Aided';
    final String subText = '$remainingText · $remainingMins min ETA';
    final String body = 'To: $destinationName · $modeLabel';

    final progressInt = ((progressRatio ?? 0.0) * 100).round().clamp(0, 100);

    lastTitle = notificationTitle;
    lastBody = body;
    lastInstruction = effectiveInstruction;
    lastTurnType = turnType;
    lastDistanceToTurn = distanceToTurn;
    lastProgressRatio = progressRatio;
    lastProgressPercent = progressInt;
    lastUpdateTime = DateTime.now();
    isShowing = true;

    if (_unavailable) return;

    if (!_isInitialized) {
      await initialize();
    }
    if (_unavailable) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        showProgress: true,
        maxProgress: 100,
        progress: progressInt,
        indeterminate: false,
        category: AndroidNotificationCategory.navigation,
        icon: '@mipmap/ic_launcher',
        subText: subText,
        styleInformation: BigTextStyleInformation(
          '$effectiveInstruction\n$remainingText remaining · $remainingMins min ETA\nTo: $destinationName · Mode: $modeLabel',
          contentTitle: notificationTitle,
          summaryText: subText,
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      const linuxDetails = LinuxNotificationDetails();
      const windowsDetails = WindowsNotificationDetails();

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        linux: linuxDetails,
        windows: windowsDetails,
      );

      await _notifications?.show(
        id: _notificationId,
        title: notificationTitle,
        body: '$remainingText remaining · $remainingMins min ETA to $destinationName',
        notificationDetails: details,
        payload: 'active_trip',
      );
    } catch (e) {
      debugPrint('[TripNotificationService] Failed to show notification: $e');
    }
  }

  /// Dismisses and clears the active trip notification
  Future<void> cancelTripNotification() async {
    isShowing = false;
    if (_unavailable) return;

    try {
      await _notifications?.cancel(id: _notificationId);
      debugPrint('[TripNotificationService] Trip notification cancelled');
    } catch (e) {
      debugPrint('[TripNotificationService] Cancel error: $e');
    }
  }
}
