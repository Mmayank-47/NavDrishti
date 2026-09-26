import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nav_shield/screens/destination_entry_screen.dart';
import 'package:nav_shield/screens/main_navigation_screen.dart';
import 'package:nav_shield/screens/permissions_onboarding_screen.dart';
import 'package:nav_shield/screens/settings_screen.dart';
import 'package:nav_shield/screens/sos_alert_overlay.dart';
import 'package:nav_shield/screens/splash_screen.dart';
import 'package:nav_shield/screens/system_health_screen.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/nav_shield_data_service.dart';
import 'package:nav_shield/services/saved_places_service.dart';
import 'package:nav_shield/services/settings_service.dart';
import 'package:nav_shield/theme/app_theme.dart';
import 'package:nav_shield/widgets/debug_menu.dart';
import 'package:nav_shield/widgets/trip_bottom_sheet.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:nav_shield/screens/sensor_diagnostics_screen.dart';
import 'package:nav_shield/models/trip_data.dart';
import 'package:nav_shield/screens/trip_summary_screen.dart';
import 'package:nav_shield/widgets/compact_floating_overlay_window.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const artifactDir = r'C:\Users\Lenovo\.gemini\antigravity-ide\brain\30c82165-ca4c-4555-9642-a41e25062664';

  setUpAll(() async {
    Directory(artifactDir).createSync(recursive: true);
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );

    // 1. Load Material Icons font
    final iconFontFile = File(r'C:\Users\Lenovo\develop\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');
    if (iconFontFile.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(Future.value(iconFontFile.readAsBytesSync().buffer.asByteData()));
      await iconLoader.load();
    }

    // 2. Load system Segoe UI as Roboto and sans-serif
    final fontFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (fontFile.existsSync()) {
      final bytes = fontFile.readAsBytesSync().buffer.asByteData();
      for (final name in ['Roboto', 'sans-serif', 'Segoe UI', '.SF Pro Text']) {
        final loader = FontLoader(name);
        loader.addFont(Future.value(bytes));
        await loader.load();
      }
    }

    // 3. Load system Consolas as monospace
    final monoFontFile = File(r'C:\Windows\Fonts\consola.ttf');
    if (monoFontFile.existsSync()) {
      final bytes = monoFontFile.readAsBytesSync().buffer.asByteData();
      for (final name in ['monospace', 'Consolas', 'Courier New']) {
        final loader = FontLoader(name);
        loader.addFont(Future.value(bytes));
        await loader.load();
      }
    }
  });

  Future<void> captureScreen({
    required WidgetTester tester,
    required Widget widget,
    required String filename,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
    tester.view.devicePixelRatio = 2.0;

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: widget,
      ),
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File('$artifactDir\\$filename');
        file.writeAsBytesSync(byteData.buffer.asUint8List());
      }
    });

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Widget wrapWithProviders({
    required Widget child,
    NavShieldDataService? service,
    SettingsService? settings,
    SavedPlacesService? savedPlaces,
    bool isDark = true,
  }) {
    final curSettings = settings ?? SettingsService();
    if (!isDark) {
      curSettings.setThemePreference(AppThemePreference.light);
    } else {
      curSettings.setThemePreference(AppThemePreference.dark);
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: curSettings),
        Provider<NavShieldDataService>.value(
          value: service ?? MockNavShieldDataService(autoStart: false),
        ),
        ChangeNotifierProvider<SavedPlacesService>.value(
          value: savedPlaces ?? SavedPlacesService(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: child,
      ),
    );
  }

  testWidgets('Generate all redesigned screen screenshots', (tester) async {
    // 1. Splash Screen
    await captureScreen(
      tester: tester,
      widget: wrapWithProviders(
        child: const SplashScreen(autoDismiss: false),
      ),
      filename: 'splash_screen.png',
    );

    // 2. Destination Entry / Home Screen (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const DestinationEntryScreen(),
        ),
        filename: isDark ? 'home_dark.png' : 'home_light.png',
      );
      service.dispose();
    }

    // 3. Route Preview Screen (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const DestinationEntryScreen(),
        ),
        filename: isDark ? 'route_preview_dark.png' : 'route_preview_light.png',
      );
      if (isDark) {
        await captureScreen(
          tester: tester,
          widget: wrapWithProviders(
            service: service,
            isDark: isDark,
            child: const DestinationEntryScreen(),
          ),
          filename: 'route_preview_drive_bike.png',
        );
      }
      service.dispose();
    }

    // 4. Main Navigation - FUSED GNSS+INS Mode (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const MainNavigationScreen(),
        ),
        filename: isDark ? 'nav_fused_dark.png' : 'nav_fused_light.png',
      );
      service.dispose();
    }

    // 5. Main Navigation - DEAD-RECKONING Mode (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();
      service.toggleMode(); // Toggle to Dead Reckoning

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const MainNavigationScreen(),
        ),
        filename: isDark ? 'nav_dr_dark.png' : 'nav_dr_light.png',
      );
      service.dispose();
    }

    // 6. System Health Dashboard (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const Scaffold(
            body: SystemHealthScreen(showBackButton: false),
          ),
        ),
        filename: isDark ? 'system_health_dark.png' : 'system_health_light.png',
        size: const Size(390, 844),
      );
      service.dispose();
    }

    // 7. Settings Screen (Dark & Light) - Main Tab
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: const Scaffold(
            body: SettingsScreen(
              showBackButton: false,
            ),
          ),
        ),
        filename: isDark ? 'settings_dark.png' : 'settings_light.png',
      );
      service.dispose();
    }

    // 7b. Settings Screen Scrolled to Preferences & Tools (Confirm Recalibrate Sensors is gone)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            service: service,
            isDark: isDark,
            child: const Scaffold(
              body: SettingsScreen(
                showBackButton: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\${isDark ? "settings_preferences_tools_dark.png" : "settings_preferences_tools_light.png"}');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      service.dispose();
    }

    // 8. Debug Menu (Dark)
    {
      final service = MockNavShieldDataService(autoStart: false);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: true,
          child: Scaffold(
            backgroundColor: AppColors.darkBackground,
            body: SafeArea(
              child: DebugMenu(
                dataService: service,
              ),
            ),
          ),
        ),
        filename: 'debug_menu_dark.png',
      );
      service.dispose();
    }

    // 9. Relocated Telemetry Swipe-Up TripBottomSheet (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: isDark,
          child: Scaffold(
            backgroundColor: isDark ? Colors.black54 : const Color(0x66000000),
            body: TripBottomSheet(
              state: service.currentState,
              settings: settings,
              initialChildSize: 0.85,
              minChildSize: 0.30,
              maxChildSize: 0.85,
              onEndTrip: () {},
              onCalibrate: () {},
              onSettings: () {},
            ),
          ),
        ),
        filename: isDark ? 'trip_sheet_dark.png' : 'trip_sheet_light.png',
      );
      service.dispose();
    }

    // ═══════════════════════════════════════════════════════════════════
    // NEW CONSOLIDATED FEATURES (1 TO 8)
    // ═══════════════════════════════════════════════════════════════════

    // FEATURE: GNSS Outlier Rejection Visual Feedback
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();
      service.triggerSimulatedOutlierRejection();

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: const MainNavigationScreen(),
        ),
        filename: 'gnss_outlier_rejection_badge.png',
      );
      service.dispose();
    }

    // FEATURE: GNSS Recovery — Transient Reacquiring / Annealing State
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();
      service.toggleMode(); // to Dead Reckoning
      service.toggleMode(); // to Reacquiring annealing window

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: const MainNavigationScreen(),
        ),
        filename: 'gnss_reacquiring_state.png',
      );
      service.dispose();
    }


    // FEATURE 3: Emergency Contact Setup + SOS Action Confirmation ("Notifying...")
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      await settings.setEmergencyContact(
        name: 'Sarah Miller',
        phone: '+91 98765 43210',
        relation: 'Spouse',
      );
      service.triggerSimulatedCrash();
      // Set countdown to 0 to enter notifying confirmation state
      service.setSosCountdown(0);

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: SosAlertOverlay(
            state: service.currentState,
            dataService: service,
          ),
        ),
        filename: 'sos_notifying_state.png',
      );
      service.dispose();
    }

    // SOS Alert Overlay - Active Countdown State (Dark & Light Mode)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      await settings.setEmergencyContact(
        name: 'Sarah Miller',
        phone: '+91 98765 43210',
        relation: 'Spouse',
      );
      service.triggerSimulatedCrash();
      service.setSosCountdown(26);

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: isDark,
          child: SosAlertOverlay(
            state: service.currentState,
            dataService: service,
          ),
        ),
        filename: isDark ? 'sos_alert_dark.png' : 'sos_alert_light.png',
      );
      service.dispose();
    }

    // FEATURE 4: Destination Search — Real Search Results List Dropdown
    {
      final service = MockNavShieldDataService(autoStart: false);
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            service: service,
            isDark: true,
            child: const DestinationEntryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter "Indira" into the search bar
      final searchInput = find.byType(TextField).first;
      await tester.enterText(searchInput, 'Indira');
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\destination_search_results.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      service.dispose();
    }

    // FEATURE 5: Rerouting UI State (Loading/Pulsing Instruction Card)
    {
      final service = MockNavShieldDataService(autoStart: false);
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            service: service,
            isDark: true,
            child: const MainNavigationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger rerouting state via MainNavigationScreenState
      final navState = tester.state<MainNavigationScreenState>(find.byType(MainNavigationScreen));
      navState.simulateRouteDeviation();
      // Pump frame during the 2-second rerouting state
      await tester.pump(const Duration(milliseconds: 300));

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\rerouting_state.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      // Let the rerouting timer finish cleanly
      await tester.pump(const Duration(seconds: 3));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      service.dispose();
    }

    // FEATURE 6: Saved Places (Home/Work/etc.) — Make Actually Editable (Edit Sheet)
    {
      final service = MockNavShieldDataService(autoStart: false);
      final savedPlaces = SavedPlacesService();

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            service: service,
            savedPlaces: savedPlaces,
            isDark: true,
            child: const DestinationEntryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Long press the Work chip to open the edit bottom sheet
      final workChip = find.text('Work');
      await tester.longPress(workChip);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\saved_places_edit.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      service.dispose();
    }

    // FEATURE 7: Permissions Onboarding Screen
    {
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          isDark: true,
          child: const PermissionsOnboardingScreen(),
        ),
        filename: 'permissions_onboarding.png',
      );
    }

    // FEATURE 8: Background/Lock-Screen Trip Status Indicator (Persistent Notification Preview)
    {
      // Render the dedicated system notification preview banner
      final notificationWidget = Scaffold(
        backgroundColor: const Color(0xFF0F141C),
        body: Center(
          child: Container(
            width: 350,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2332),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2C394E), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.darkAmber.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.electric_bolt_rounded,
                        color: AppColors.darkAmber,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'NAV-SHIELD · Live Trip Status',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.darkAmber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.darkAmber.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'DEAD RECKONING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkAmber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '1.2 km remaining · 4 min ETA',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'To: MG Road Metro Station (via Kasturba Rd)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.sensors_rounded, size: 14, color: AppColors.darkCyan),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'INS 100Hz IMU Fusion · Re-fusing when GNSS locks',
                          style: TextStyle(fontSize: 11, color: AppColors.darkCyan),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          isDark: true,
          child: notificationWidget,
        ),
        filename: 'trip_notification_indicator.png',
      );
    }

    // REQUIREMENT 1: Settings Screen with Restored External IMU Toggle & Honesty Caption
    {
      final settings = SettingsService();
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            settings: settings,
            isDark: true,
            child: const SettingsScreen(showBackButton: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down so SENSOR SOURCE with honesty caption is prominently visible
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -380));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\settings_external_imu.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // REQUIREMENT 2: Voice Guidance Unmuted & Muted UI on Active Navigation Screen
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      // 1. Unmuted
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: const MainNavigationScreen(),
        ),
        filename: 'voice_guidance_unmuted.png',
      );

      // 2. Muted
      await settings.setVoiceGuidanceMuted(true);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: const MainNavigationScreen(),
        ),
        filename: 'voice_guidance_muted.png',
      );

      service.dispose();
    }

    // REQUIREMENT 3: Sensor Diagnostics Screen Step 7 (Magnetometer & Compass Check Mid-Rotation)
    {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: SensorDiagnosticsScreen(
              customAccelerometerStream: accelController.stream,
              customGyroscopeStream: gyroController.stream,
              customMagnetometerStream: magController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Skip first 6 steps to reach Step 7 (Rotate Phone Flat / Compass Check)
      for (int i = 0; i < 6; i++) {
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
      }

      // Emit active sensor readings mid-rotation (~112° tracked rotation, heading 248°)
      accelController.add(AccelerometerEvent(0.12, -0.08, 9.81, DateTime.now()));
      gyroController.add(GyroscopeEvent(0.01, 0.02, -0.35, DateTime.now()));
      magController.add(MagnetometerEvent(-14.2, 30.5, -42.8, DateTime.now()));
      await tester.pump();

      // Simulate partial rotation
      magController.add(MagnetometerEvent(25.0, 12.0, -42.8, DateTime.now()));
      await tester.pump();
      magController.add(MagnetometerEvent(18.0, -26.0, -42.8, DateTime.now()));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\sensor_diagnostics_magnetometer.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();

      await accelController.close();
      await gyroController.close();
      await magController.close();
    }



    // REQUIREMENT 5: Emergency Contact Prompt Appearing Right After SOS Permission Grant
    {
      final settings = SettingsService();
      await settings.clearEmergencyContact();

      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            settings: settings,
            isDark: true,
            child: const PermissionsOnboardingScreen(isModalFromSettings: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap SOS toggle (switch 2) to trigger emergency contact prompt
      final switches = find.byType(Switch);
      if (switches.evaluate().length >= 3) {
        await tester.tap(switches.at(2));
        await tester.pumpAndSettle();
        await tester.tap(switches.at(2));
        await tester.pumpAndSettle();
      }

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\sos_emergency_contact_prompt.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // REQUIREMENT 6: Floating Mini-Nav Widget Over Real Android Home Screen & YouTube
    {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;

      // REQUIREMENT 6A: Floating Mini-Nav Overlay over Real Android Home Screen
      {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: wrapWithProviders(
              isDark: true,
              child: Scaffold(
                backgroundColor: const Color(0xFF0F172A),
                body: Stack(
                  children: [
                    // Realistic Android Home Screen Wallpaper & Launcher
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildMockStatusBar(),
                              const SizedBox(height: 36),
                              // Clock and Weather Widget
                              const Text(
                                '12:45',
                                style: TextStyle(
                                  fontSize: 68,
                                  fontWeight: FontWeight.w200,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Friday, 25 September · 28°C Sunny',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 30),
                              // Google Search Bar Widget
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: Colors.white24, width: 1),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.search_rounded, color: Colors.white70, size: 22),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Search apps, web...',
                                        style: TextStyle(color: Colors.white54, fontSize: 14),
                                      ),
                                    ),
                                    Icon(Icons.mic_rounded, color: Colors.white70, size: 20),
                                    SizedBox(width: 10),
                                    Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 20),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 36),
                              // Android Apps Grid
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Wrap(
                                  spacing: 24,
                                  runSpacing: 24,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _buildMockAppIcon(Icons.play_arrow_rounded, 'YouTube', const Color(0xFFFF0000)),
                                    _buildMockAppIcon(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366)),
                                    _buildMockAppIcon(Icons.music_note_rounded, 'Spotify', const Color(0xFF1DB954)),
                                    _buildMockAppIcon(Icons.shopping_bag_rounded, 'Play Store', const Color(0xFF00C4FF)),
                                    _buildMockAppIcon(Icons.mail_outline_rounded, 'Gmail', const Color(0xFFEA4335)),
                                    _buildMockAppIcon(Icons.photo_library_outlined, 'Photos', const Color(0xFFFBBC05)),
                                    _buildMockAppIcon(Icons.map_outlined, 'Maps', const Color(0xFF34A853)),
                                    _buildMockAppIcon(Icons.settings_outlined, 'Settings', const Color(0xFF94A3B8)),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Home Screen Dock
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildMockAppIcon(Icons.phone_rounded, 'Phone', const Color(0xFF22C55E)),
                                    _buildMockAppIcon(Icons.chat_bubble_rounded, 'Messages', const Color(0xFF3B82F6)),
                                    _buildMockAppIcon(Icons.public_rounded, 'Chrome', const Color(0xFFF59E0B)),
                                    _buildMockAppIcon(Icons.camera_alt_rounded, 'Camera', const Color(0xFFEF4444)),
                                    _buildMockAppIcon(Icons.shield_rounded, 'NAV-SHIELD', const Color(0xFF00E5FF)),
                                  ],
                                ),
                              ),
                              // Android Bottom Gesture Pill
                              Container(
                                width: 100,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white38,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Floating System Overlay Window (over real Android home screen)
                    const Positioned(
                      top: 190,
                      right: 18,
                      child: SizedBox(
                        width: 240,
                        height: 165,
                        child: CompactFloatingOverlayWindow(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary != null) {
            final image = await boundary.toImage(pixelRatio: 2.0);
            final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              final bytes = byteData.buffer.asUint8List();
              File('$artifactDir\\overlay_real_home_screen.png').writeAsBytesSync(bytes);
              File('$artifactDir\\mini_nav_floating_widget.png').writeAsBytesSync(bytes);
            }
          }
        });
      }

      // REQUIREMENT 6B: Floating Mini-Nav Overlay over Real App (YouTube Running & Usable)
      {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: wrapWithProviders(
              isDark: true,
              child: Scaffold(
                backgroundColor: const Color(0xFF0F0F0F),
                body: Stack(
                  children: [
                    // Real YouTube App Layout
                    Positioned.fill(
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMockStatusBar(),
                            // YouTube Top Bar
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'YouTube',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.cast_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Color(0xFF3B82F6),
                                    child: Text('A', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                            // Active YouTube Video Player
                            Container(
                              width: double.infinity,
                              height: 210,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E293B),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.directions_car_rounded, size: 48, color: Colors.cyanAccent.withValues(alpha: 0.8)),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Inertial Odometry & Dead Reckoning Deep Dive',
                                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Video Player Controls Overlay
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: const [
                                              Icon(Icons.pause_rounded, color: Colors.white, size: 20),
                                              SizedBox(width: 10),
                                              Text('14:28 / 42:10', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                                              Spacer(),
                                              Icon(Icons.settings_outlined, color: Colors.white, size: 18),
                                              SizedBox(width: 12),
                                              Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: 0.34,
                                              backgroundColor: Colors.white24,
                                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                                              minHeight: 3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Video Details & Channel Info
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Autonomous Vehicle Dead Reckoning in GPS-Denied Urban Canyons',
                                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Tech Talks · 240K views · 2 days ago',
                                    style: TextStyle(color: Colors.white60, fontSize: 11),
                                  ),
                                  const SizedBox(height: 10),
                                  // Action Pills (Like, Share, Download)
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _buildYouTubeActionPill(Icons.thumb_up_alt_outlined, '18K'),
                                        const SizedBox(width: 8),
                                        _buildYouTubeActionPill(Icons.share_outlined, 'Share'),
                                        const SizedBox(width: 8),
                                        _buildYouTubeActionPill(Icons.download_rounded, 'Download'),
                                        const SizedBox(width: 8),
                                        _buildYouTubeActionPill(Icons.bookmark_border_rounded, 'Save'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Channel Row
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Color(0xFF6366F1),
                                        child: Text('TT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 10),
                                      const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Tech Talks', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                          Text('1.2M subscribers', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                        ],
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Text('Subscribe', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Colors.white12, height: 1),
                            // Suggested Videos Feed Underneath
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                children: [
                                  _buildYouTubeSuggestedCard('How Kalman Filters Work: Intuition & Math', 'Robotics Hub · 480K views', '18:45'),
                                  _buildYouTubeSuggestedCard('Bangalore Underground Metro: Real Navigation Challenges', 'Urban Transit · 112K views', '24:12'),
                                ],
                              ),
                            ),
                            // YouTube Bottom Nav Bar
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F0F0F),
                                border: Border(top: BorderSide(color: Colors.white10)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildYouTubeNavIcon(Icons.home_filled, 'Home', true),
                                  _buildYouTubeNavIcon(Icons.bolt_rounded, 'Shorts', false),
                                  _buildYouTubeNavIcon(Icons.subscriptions_outlined, 'Subscriptions', false),
                                  _buildYouTubeNavIcon(Icons.video_library_outlined, 'You', false),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Floating System Overlay Window (rendered right over active YouTube app!)
                    const Positioned(
                      top: 250,
                      right: 18,
                      child: SizedBox(
                        width: 240,
                        height: 165,
                        child: CompactFloatingOverlayWindow(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary != null) {
            final image = await boundary.toImage(pixelRatio: 2.0);
            final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              final file = File('$artifactDir\\overlay_over_youtube.png');
              file.writeAsBytesSync(byteData.buffer.asUint8List());
            }
          }
        });
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // REQUIREMENT 6C: Floating Mini-Nav Overlay Triggered via Back Button Specifically
    {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            isDark: true,
            child: Scaffold(
              backgroundColor: const Color(0xFF0F172A),
              body: Stack(
                children: [
                  // 1. Android Home Screen Base
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildMockStatusBar(),
                            const SizedBox(height: 36),
                            const Text(
                              '12:45',
                              style: TextStyle(
                                fontSize: 68,
                                fontWeight: FontWeight.w200,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Friday, 25 September · 28°C Sunny',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 30),
                            // Apps Grid
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Wrap(
                                spacing: 24,
                                runSpacing: 24,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildMockAppIcon(Icons.play_arrow_rounded, 'YouTube', const Color(0xFFFF0000)),
                                  _buildMockAppIcon(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366)),
                                  _buildMockAppIcon(Icons.music_note_rounded, 'Spotify', const Color(0xFF1DB954)),
                                  _buildMockAppIcon(Icons.shopping_bag_rounded, 'Play Store', const Color(0xFF00C4FF)),
                                  _buildMockAppIcon(Icons.mail_outline_rounded, 'Gmail', const Color(0xFFEA4335)),
                                  _buildMockAppIcon(Icons.photo_library_outlined, 'Photos', const Color(0xFFFBBC05)),
                                  _buildMockAppIcon(Icons.map_outlined, 'Maps', const Color(0xFF34A853)),
                                  _buildMockAppIcon(Icons.settings_outlined, 'Settings', const Color(0xFF94A3B8)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Home Screen Dock
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildMockAppIcon(Icons.phone_rounded, 'Phone', const Color(0xFF22C55E)),
                                  _buildMockAppIcon(Icons.chat_bubble_rounded, 'Messages', const Color(0xFF3B82F6)),
                                  _buildMockAppIcon(Icons.public_rounded, 'Chrome', const Color(0xFFF59E0B)),
                                  _buildMockAppIcon(Icons.camera_alt_rounded, 'Camera', const Color(0xFFEF4444)),
                                  _buildMockAppIcon(Icons.shield_rounded, 'NAV-SHIELD', const Color(0xFF00E5FF)),
                                ],
                              ),
                            ),
                            // Android Bottom Gesture Pill
                            Container(
                              width: 100,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2. Android Back Gesture Visual Indicator
                  Positioned(
                    left: 0,
                    top: 360,
                    child: Container(
                      width: 48,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.mediumIndigo.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.periwinkle.withValues(alpha: 0.50),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),

                  // 3. Top Confirmation Banner for Back Button Intercept
                  Positioned(
                    top: 54,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xF0312048), Color(0xF0203B6F)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.periwinkle.withValues(alpha: 0.7),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: AppColors.orchidPink.withValues(alpha: 0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.mediumIndigo,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.periwinkle.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Back Button Intercepted (Trip Active)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'App backgrounded · System floating overlay launched',
                                  style: TextStyle(
                                    color: Color(0xFFDBC9F9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 4. Floating System Overlay Window Drawn on Top
                  const Positioned(
                    top: 190,
                    right: 18,
                    child: SizedBox(
                      width: 240,
                      height: 165,
                      child: CompactFloatingOverlayWindow(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\overlay_triggered_via_back_button.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // REQUIREMENT 8: Destination Arrival Summary Screen
    {
      final summary = TripSummary(
        destinationName: 'MG Road Metro',
        destination: const LatLng(12.9756, 77.6066),
        totalDistanceKm: 5.2,
        totalDuration: const Duration(minutes: 14),
        gnssAidedDuration: const Duration(minutes: 11),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 0.9,
        route: const [],
        destinationReached: true,
      );

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          isDark: true,
          child: TripSummaryScreen(
            summary: summary,
            settings: SettingsService(),
            onNewTrip: () {},
          ),
        ),
        filename: 'destination_arrival_summary.png',
      );
    }

    // REQUIREMENT: TRIP SUMMARY EXIT CONTROLS VERIFICATION SEQUENCE
    // 1. Exit Options Overview on Trip Summary Screen
    {
      final summary = TripSummary(
        destinationName: 'MG Road Metro',
        destination: const LatLng(12.9756, 77.6066),
        totalDistanceKm: 5.2,
        totalDuration: const Duration(minutes: 14),
        gnssAidedDuration: const Duration(minutes: 11),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 0.9,
        route: const [],
        destinationReached: true,
      );

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          isDark: true,
          child: TripSummaryScreen(
            summary: summary,
            settings: SettingsService(),
          ),
        ),
        filename: 'trip_summary_exit_options.png',
      );
    }

    // 2. Tapping Close "X" Button -> Navigates to Navigate/Home (DestinationEntryScreen)
    {
      final summary = TripSummary(
        destinationName: 'MG Road Metro',
        destination: const LatLng(12.9756, 77.6066),
        totalDistanceKm: 5.2,
        totalDuration: const Duration(minutes: 14),
        gnssAidedDuration: const Duration(minutes: 11),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 0.9,
        route: const [],
        destinationReached: true,
      );

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            isDark: true,
            child: TripSummaryScreen(
              summary: summary,
              settings: SettingsService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('trip_summary_close_button')));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            File('$artifactDir\\trip_summary_close_x_tapped_navigate_home.png')
                .writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // 3. Tapping "Start New Trip" Button -> Navigates to Navigate/Home (DestinationEntryScreen)
    {
      final summary = TripSummary(
        destinationName: 'MG Road Metro',
        destination: const LatLng(12.9756, 77.6066),
        totalDistanceKm: 5.2,
        totalDuration: const Duration(minutes: 14),
        gnssAidedDuration: const Duration(minutes: 11),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 0.9,
        route: const [],
        destinationReached: true,
      );

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            isDark: true,
            child: TripSummaryScreen(
              summary: summary,
              settings: SettingsService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('start_new_trip_button')),
        200.0,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start_new_trip_button')));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            File('$artifactDir\\trip_summary_start_new_trip_tapped_navigate_home.png')
                .writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // 4. Pressing Device Back Button -> Navigates to Navigate/Home (DestinationEntryScreen)
    {
      final summary = TripSummary(
        destinationName: 'MG Road Metro',
        destination: const LatLng(12.9756, 77.6066),
        totalDistanceKm: 5.2,
        totalDuration: const Duration(minutes: 14),
        gnssAidedDuration: const Duration(minutes: 11),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 0.9,
        route: const [],
        destinationReached: true,
      );

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            isDark: true,
            child: TripSummaryScreen(
              summary: summary,
              settings: SettingsService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            File('$artifactDir\\trip_summary_back_pressed_navigate_home.png')
                .writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // REQUIREMENT 9: Live Overlay Progression Sequence (Step 1: t=0s, Step 2: t=10s, Step 3: t=25s)
    {
      const bengaluruRoute = [
        [12.97162, 77.594461],
        [12.97202, 77.594247],
        [12.97246, 77.594226],
        [12.97344, 77.595041],
        [12.97425, 77.596001],
        [12.97514, 77.597125],
        [12.97670, 77.599499],
        [12.97623, 77.603634],
        [12.97531, 77.607443],
      ];

      // Step 1: Initial state approaching MG Road turn (GNSS Aided)
      await captureScreen(
        tester: tester,
        size: const Size(340, 230),
        widget: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: CompactFloatingOverlayWindow(
                initialData: {
                  'instruction': 'Turn right on MG Road',
                  'distance': '240 m',
                  'eta': '4 min',
                  'mode': 'GNSS_AIDED',
                  'speed': '42 km/h',
                  'heading': 12.0,
                  'currentLat': 12.97162,
                  'currentLng': 77.594461,
                  'progress': 0.15,
                  'turnType': 'turn_right',
                  'routePoints': bengaluruRoute,
                },
              ),
            ),
          ),
        ),
        filename: 'overlay_progression_step1.png',
      );

      // Step 2: Vehicle moved 130m closer to turn (t = 10s)
      await captureScreen(
        tester: tester,
        size: const Size(340, 230),
        widget: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: CompactFloatingOverlayWindow(
                initialData: {
                  'instruction': 'Turn right in 110 m',
                  'distance': '110 m',
                  'eta': '4 min',
                  'mode': 'GNSS_AIDED',
                  'speed': '40 km/h',
                  'heading': 24.5,
                  'currentLat': 12.9729,
                  'currentLng': 77.5948,
                  'progress': 0.32,
                  'turnType': 'turn_right',
                  'routePoints': bengaluruRoute,
                },
              ),
            ),
          ),
        ),
        filename: 'overlay_progression_step2.png',
      );

      // Step 3: Turn completed, entered Dead Reckoning tunnel/canyon mode (t = 25s)
      await captureScreen(
        tester: tester,
        size: const Size(340, 230),
        widget: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: CompactFloatingOverlayWindow(
                initialData: {
                  'instruction': 'Continue on Residency Road',
                  'distance': '480 m',
                  'eta': '3 min',
                  'mode': 'DEAD_RECKONING',
                  'speed': '38 km/h',
                  'heading': 72.0,
                  'currentLat': 12.9749,
                  'currentLng': 77.5972,
                  'progress': 0.58,
                  'turnType': 'straight',
                  'routePoints': bengaluruRoute,
                },
              ),
            ),
          ),
        ),
        filename: 'overlay_progression_step3.png',
      );
    }

    // REQUIREMENT 10: Persistent Google Maps-style Navigation Notification + Floating Overlay
    {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              backgroundColor: const Color(0xFF0F172A),
              body: Stack(
                children: [
                  // 1. Android Home Screen Base
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildMockStatusBar(),
                            const SizedBox(height: 12),

                            // 2. Google Maps-style Persistent Navigation Notification Card
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xF2182236),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.periwinkle.withValues(alpha: 0.65),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: AppColors.periwinkle.withValues(alpha: 0.35),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // App Header & Ongoing Status
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.mediumIndigo,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'NAV-SHIELD · Navigation',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Ongoing',
                                          style: TextStyle(color: Colors.white60, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Turn Direction & Instruction
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.mediumIndigo,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.periwinkle.withValues(alpha: 0.5),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(Icons.turn_right_rounded, color: Colors.white, size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'In 240 m, Turn right',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Onto MG Road · To: Central Circuit',
                                              style: TextStyle(
                                                color: Color(0xFFDBC9F9),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // Route Progress Bar (matching Google Maps navigation notification)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: 0.35,
                                      minHeight: 6,
                                      backgroundColor: Colors.white12,
                                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.periwinkle),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Distance & ETA Footer
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        '1.2 km remaining · 4 min ETA',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.orchidPink.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.orchidPink.withValues(alpha: 0.5), width: 0.8),
                                        ),
                                        child: const Text(
                                          '🛰️ GNSS Aided',
                                          style: TextStyle(
                                            color: AppColors.orchidPink,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Home Apps Grid underneath
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Wrap(
                                spacing: 24,
                                runSpacing: 24,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildMockAppIcon(Icons.play_arrow_rounded, 'YouTube', const Color(0xFFFF0000)),
                                  _buildMockAppIcon(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366)),
                                  _buildMockAppIcon(Icons.music_note_rounded, 'Spotify', const Color(0xFF1DB954)),
                                  _buildMockAppIcon(Icons.shopping_bag_rounded, 'Play Store', const Color(0xFF00C4FF)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. Floating Overlay Bubble Window Coexisting Simultaneously on Screen
                  Positioned(
                    top: 360,
                    left: 20,
                    right: 20,
                    child: Center(
                      child: SizedBox(
                        width: 330,
                        height: 220,
                        child: CompactFloatingOverlayWindow(
                          initialData: {
                            'instruction': 'Turn right on MG Road',
                            'distance': '240 m',
                            'eta': '4 min',
                            'mode': 'GNSS_AIDED',
                            'speed': '42 km/h',
                            'heading': 12.0,
                            'currentLat': 12.97162,
                            'currentLng': 77.594461,
                            'progress': 0.35,
                            'turnType': 'turn_right',
                            'routePoints': const [
                              [12.97162, 77.594461],
                              [12.97246, 77.594226],
                              [12.97344, 77.595041],
                              [12.97425, 77.596001],
                            ],
                          },
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
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\persistent_notification_and_overlay.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // Requirement 11: Notification Shade Pulled Down while App in Foreground — NO Overlay Appears
    {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF0A0E1A),
            body: RepaintBoundary(
              key: boundaryKey,
              child: Stack(
                children: [
                  // Full active NAV-SHIELD navigation HUD running in foreground
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0F172A), Color(0xFF0A0E1A)],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Background map vector mock
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _MockNavMapBackgroundPainter(),
                            ),
                          ),
                          // Bottom HUD Sheet
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 160,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: const BoxDecoration(
                                color: Color(0xF0131D31),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            '4 min',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            '1.2 km · 12:49 PM',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8E68A9).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFBC7EBF)),
                                        ),
                                        child: const Text(
                                          'GNSS AIDED',
                                          style: TextStyle(
                                            color: Color(0xFFDBC9F9),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Top Android Notification Shade Pulled Down (App in Inactive State)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 480,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xF2090F1D),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1.5,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.8),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '12:45',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Row(
                                    children: const [
                                      Icon(Icons.wifi, color: Colors.white, size: 16),
                                      SizedBox(width: 8),
                                      Icon(Icons.signal_cellular_4_bar, color: Colors.white, size: 16),
                                      SizedBox(width: 8),
                                      Icon(Icons.battery_5_bar, color: Colors.white, size: 16),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Quick Settings Tiles
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildMockQuickTile(Icons.wifi, 'Wi-Fi', true),
                                  _buildMockQuickTile(Icons.bluetooth, 'Bluetooth', true),
                                  _buildMockQuickTile(Icons.do_not_disturb_on, 'DND', false),
                                  _buildMockQuickTile(Icons.flashlight_on, 'Flashlight', false),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Notification Shade Content Card (Transient system UI)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF384F95),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.message_rounded, color: Colors.white, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            'Messages · now',
                                            style: TextStyle(color: Colors.white70, fontSize: 11),
                                          ),
                                          Text(
                                            'Alex: On my way to MG Road',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),

                              // Drag handle and foreground status pill
                              Center(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF10B981), width: 1),
                                      ),
                                      child: const Text(
                                        '✓ App in Foreground (Inactive) — Floating Overlay Suppressed',
                                        style: TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 44,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.white30,
                                        borderRadius: BorderRadius.circular(2),
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

                  // Notice: NO CompactFloatingOverlayWindow is rendered here!
                  // It confirms the floating overlay is completely suppressed during transient shade pull!
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\notification_shade_pulled_no_overlay.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // Requirement 12: Noticeably Enlarged Floating Overlay Window while Backgrounded
    {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF131722),
            body: RepaintBoundary(
              key: boundaryKey,
              child: Stack(
                children: [
                  // Android desktop background with wallpaper and apps
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1E2638), Color(0xFF0F131D)],
                        ),
                      ),
                    ),
                  ),

                  // Status Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '12:45',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(Icons.wifi, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Icon(Icons.signal_cellular_alt, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Icon(Icons.battery_full, color: Colors.white, size: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Home screen app grid
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMockAppIcon(Icons.play_arrow_rounded, 'YouTube', const Color(0xFFFF0033)),
                        _buildMockAppIcon(Icons.chat_bubble_rounded, 'WhatsApp', const Color(0xFF25D366)),
                        _buildMockAppIcon(Icons.music_note_rounded, 'Spotify', const Color(0xFF1DB954)),
                        _buildMockAppIcon(Icons.settings_rounded, 'Settings', const Color(0xFFA6BAEE)),
                      ],
                    ),
                  ),

                  // Noticeably Enlarged Floating Overlay (320x210) floating over the OS
                  Positioned(
                    top: 260,
                    left: 20,
                    right: 20,
                    child: Center(
                      child: SizedBox(
                        width: 330,
                        height: 220,
                        child: CompactFloatingOverlayWindow(
                          initialData: {
                            'instruction': 'Turn right on MG Road',
                            'distance': '240 m',
                            'eta': '4 min',
                            'mode': 'GNSS_AIDED',
                            'speed': '42 km/h',
                            'heading': 12.0,
                            'currentLat': 12.97162,
                            'currentLng': 77.594461,
                            'progress': 0.35,
                            'turnType': 'turn_right',
                            'routePoints': const [
                              [12.97162, 77.594461],
                              [12.97246, 77.594226],
                              [12.97344, 77.595041],
                              [12.97425, 77.596001],
                            ],
                          },
                        ),
                      ),
                    ),
                  ),

                  // Bottom Android navigation pill bar
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 130,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white54,
                          borderRadius: BorderRadius.circular(3),
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
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\enlarged_floating_overlay_backgrounded.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // Requirement 13: Expand Button Tapped — Returning to Full NAV-SHIELD App
    {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF0A0E1A),
            body: RepaintBoundary(
              key: boundaryKey,
              child: Stack(
                children: [
                  // Full active NAV-SHIELD navigation screen restored
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0F172A), Color(0xFF0A0E1A)],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _MockNavMapBackgroundPainter(),
                            ),
                          ),
                          // Top Turn Guidance HUD Banner
                          Positioned(
                            top: 48,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xF2131D31),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFBC7EBF).withValues(alpha: 0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFBC7EBF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.turn_right_rounded, color: Colors.white, size: 26),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text(
                                          '240 m',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          'Turn right on MG Road',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Standalone compass and SOS buttons
                          Positioned(
                            bottom: 180,
                            left: 16,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xE6131D31),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.explore_rounded, color: Color(0xFFA6BAEE), size: 26),
                            ),
                          ),
                          Positioned(
                            bottom: 180,
                            right: 16,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2E63).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFF2E63), width: 1.5),
                              ),
                              child: const Icon(Icons.sos_rounded, color: Color(0xFFFF2E63), size: 26),
                            ),
                          ),
                          // Bottom HUD Sheet
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 155,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: const BoxDecoration(
                                color: Color(0xF0131D31),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            '4 min',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            '1.2 km · 12:49 PM',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8E68A9).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFBC7EBF)),
                                        ),
                                        child: const Text(
                                          'GNSS AIDED',
                                          style: TextStyle(
                                            color: Color(0xFFDBC9F9),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  // Sleek toast confirming return to app and overlay dismissed
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF203B6F).withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFA6BAEE), width: 1.0),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.check_circle_rounded, color: Color(0xFFA6BAEE), size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          '⚡ Returned to NAV-SHIELD · Overlay Dismissed',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\expand_button_tapped_return_to_app.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

Widget _buildMockQuickTile(IconData icon, String label, bool active) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF384F95) : Colors.white12,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? const Color(0xFFA6BAEE) : Colors.white24,
            width: 1,
          ),
        ),
        child: Icon(icon, color: active ? Colors.white : Colors.white60, size: 22),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _MockNavMapBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final roadCasing = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 24.0
      ..style = PaintingStyle.stroke;
    final roadPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 14.0
      ..style = PaintingStyle.stroke;

    final path = ui.Path()
      ..moveTo(size.width * 0.5, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.45)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.35, size.width * 0.85, size.height * 0.35);

    canvas.drawPath(path, roadCasing);
    canvas.drawPath(path, roadPaint);

    // Vehicle marker
    final vehicleCenter = Offset(size.width * 0.5, size.height * 0.55);
    final haloPaint = Paint()
      ..color = const Color(0xFFA6BAEE).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(vehicleCenter, 28, haloPaint);

    final markerPaint = Paint()..color = const Color(0xFF384F95);
    canvas.drawCircle(vehicleCenter, 14, markerPaint);
    final corePaint = Paint()..color = Colors.white;
    canvas.drawCircle(vehicleCenter, 6, corePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _buildMockAppIcon(IconData icon, String label, Color color) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 26),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
    ],
  );
}

Widget _buildMockStatusBar() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '12:45',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.signal_cellular_4_bar_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Icon(Icons.wifi_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Icon(Icons.battery_5_bar_rounded, size: 14, color: Colors.white),
          ],
        ),
      ],
    ),
  );
}

Widget _buildYouTubeActionPill(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 15),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

Widget _buildYouTubeSuggestedCard(String title, String channel, String duration) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 110,
            height: 64,
            color: const Color(0xFF1E293B),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.play_circle_fill_rounded, color: Colors.white38, size: 28),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(duration, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(channel, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildYouTubeNavIcon(IconData icon, String label, bool isSelected) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.white60),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 9, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
    ],
  );
}

