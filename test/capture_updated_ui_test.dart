import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:nav_shield/screens/sensor_diagnostics_screen.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/nav_shield_data_service.dart';
import 'package:nav_shield/services/saved_places_service.dart';
import 'package:nav_shield/services/settings_service.dart';
import 'package:nav_shield/theme/app_theme.dart';
import 'package:nav_shield/widgets/debug_menu.dart';
import 'package:nav_shield/widgets/trip_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const artifactDir = r'C:\Users\Lenovo\.gemini\antigravity-ide\brain\3c083612-fa56-4261-ab7f-232e704ecf2f';

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

  testWidgets('Capture Updated Debug Menu and Trip Bottom Sheet', (tester) async {
    // 1. Debug Menu (Dark & Light)
    for (final isDark in [true, false]) {
      final service = MockNavShieldDataService(autoStart: false);
      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          service: service,
          isDark: isDark,
          child: Scaffold(
            backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
            body: SafeArea(
              child: DebugMenu(
                dataService: service,
              ),
            ),
          ),
        ),
        filename: isDark ? 'updated_debug_menu_dark.png' : 'updated_debug_menu_light.png',
      );
      service.dispose();
    }

    // 2. Trip Bottom Sheet (Dark & Light)
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
        filename: isDark ? 'updated_trip_sheet_dark.png' : 'updated_trip_sheet_light.png',
      );
      service.dispose();
    }
  });

  testWidgets('Capture Updated Sensor Diagnostics Screen', (tester) async {
    // 1. Active Step - Tilt Phone Right (Dark & Light)
    for (final isDark in [true, false]) {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      await captureScreen(
        tester: tester,
        widget: wrapWithProviders(
          isDark: isDark,
          child: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
            customMagnetometerStream: magController.stream,
          ),
        ),
        filename: isDark ? 'updated_sensor_diagnostics_dark.png' : 'updated_sensor_diagnostics_light.png',
      );

      await accelController.close();
      await gyroController.close();
      await magController.close();
    }

    // 2. Summary Results Card (Dark & Light)
    for (final isDark in [true, false]) {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: wrapWithProviders(
            isDark: isDark,
            child: SensorDiagnosticsScreen(
              customAccelerometerStream: accelController.stream,
              customGyroscopeStream: gyroController.stream,
              customMagnetometerStream: magController.stream,
            ),
          ),
        ),
      );
      await tester.pump();

      // Pass first 5 checks and skip last 2 to show a realistic mixed / completed summary
      for (int i = 0; i < 7; i++) {
        final skipBtn = find.text('Skip');
        if (skipBtn.evaluate().isNotEmpty) {
          await tester.tap(skipBtn);
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File('$artifactDir\\${isDark ? "updated_sensor_diagnostics_summary_dark.png" : "updated_sensor_diagnostics_summary_light.png"}');
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
  });
}

