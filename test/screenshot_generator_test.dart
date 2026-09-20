import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nav_shield/screens/destination_entry_screen.dart';
import 'package:nav_shield/screens/main_navigation_screen.dart';
import 'package:nav_shield/screens/settings_screen.dart';
import 'package:nav_shield/screens/splash_screen.dart';
import 'package:nav_shield/screens/system_health_screen.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/nav_shield_data_service.dart';
import 'package:nav_shield/services/settings_service.dart';
import 'package:nav_shield/theme/app_theme.dart';
import 'package:nav_shield/widgets/debug_menu.dart';
import 'package:nav_shield/widgets/mapbox_nav_map.dart';
import 'package:nav_shield/widgets/trip_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const artifactDir = r'C:\Users\Lenovo\.gemini\antigravity-ide\brain\4cc3d768-7652-48ee-8618-a479653cb29f';

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

  testWidgets('Generate all redesigned screen screenshots', (tester) async {
    // 1. Splash Screen
    await captureScreen(
      tester: tester,
      widget: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const SplashScreen(autoDismiss: false),
      ),
      filename: 'splash_screen.png',
    );

    // 2. Destination Entry / Home Screen (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const DestinationEntryScreen(),
          ),
        ),
        filename: isDark ? 'home_dark.png' : 'home_light.png',
      );
      service.dispose();
    }

    // 3. Route Preview Screen (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const DestinationEntryScreen(),
          ),
        ),
        filename: isDark ? 'route_preview_dark.png' : 'route_preview_light.png',
      );
      service.dispose();
    }

    // 4. Main Navigation - FUSED GNSS+INS Mode (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const MainNavigationScreen(),
          ),
        ),
        filename: isDark ? 'nav_fused_dark.png' : 'nav_fused_light.png',
      );
      service.dispose();
    }

    // 5. Main Navigation - DEAD-RECKONING (GNSS Denied) Mode (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();
      service.toggleMode(); // Toggle to Dead Reckoning

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const MainNavigationScreen(),
          ),
        ),
        filename: isDark ? 'nav_dr_dark.png' : 'nav_dr_light.png',
      );
      service.dispose();
    }

    // 6. System Health Dashboard (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const Scaffold(
              body: SystemHealthScreen(showBackButton: false),
            ),
          ),
        ),
        filename: isDark ? 'system_health_dark.png' : 'system_health_light.png',
      );
      service.dispose();
    }

    // 7. Settings Screen (Dark & Light) - Main Tab (no back button)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
              body: SettingsScreen(
                showBackButton: false,
                onRecalibrate: () {},
              ),
            ),
          ),
        ),
        filename: isDark ? 'settings_dark.png' : 'settings_light.png',
      );
      service.dispose();
    }

    // 8. Debug Menu (Dark)
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: Scaffold(
              backgroundColor: AppColors.darkBackground,
              body: SafeArea(
                child: DebugMenu(
                  dataService: service,
                ),
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
      if (!isDark) settings.setThemePreference(AppThemePreference.light);

      await captureScreen(
        tester: tester,
        widget: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            Provider<NavShieldDataService>.value(value: service),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
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
        ),
        filename: isDark ? 'trip_sheet_dark.png' : 'trip_sheet_light.png',
      );
      service.dispose();
    }

    // 10. Main Navigation with Rotated Map (Dark)
    {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      const size = Size(390, 844);
      tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsService>.value(value: settings),
              Provider<NavShieldDataService>.value(value: service),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              home: const MainNavigationScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rotate the map to 45 degrees
      final mapState = tester.state<MapboxNavMapState>(find.byType(MapboxNavMap));
      mapState.setBearing(45.0);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\map_rotation_dark.png');
            file.writeAsBytesSync(byteData.buffer.asUint8List());
          }
        }
      });

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      service.dispose();
    }
  });
}
