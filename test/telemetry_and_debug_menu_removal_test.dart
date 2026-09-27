import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nav_shield/models/nav_shield_state.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/nav_shield_data_service.dart';
import 'package:nav_shield/services/settings_service.dart';
import 'package:nav_shield/theme/app_theme.dart';
import 'package:nav_shield/widgets/debug_menu.dart';
import 'package:nav_shield/widgets/trip_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProviders({
  required Widget child,
  required NavShieldDataService service,
  required SettingsService settings,
  bool isDark = true,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      Provider<NavShieldDataService>.value(value: service),
    ],
    child: MaterialApp(
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Trip & Sensor Telemetry Card - Removals & Layout', () {
    testWidgets('Altitude and Satellites tiles are removed in Dark Theme', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: TripBottomSheet(
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
      );
      await tester.pumpAndSettle();

      // Confirmed removed
      expect(find.text('ALTITUDE'), findsNothing);
      expect(find.text('SATELLITES'), findsNothing);
      expect(find.text('14 Locked'), findsNothing);

      // Remaining 4 tiles present
      expect(find.text('ACCURACY'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('DRIFT ESTIMATE'), findsOneWidget);

      service.dispose();
    });

    testWidgets('Altitude and Satellites tiles are removed in Light Theme', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: false,
          child: TripBottomSheet(
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
      );
      await tester.pumpAndSettle();

      // Confirmed removed
      expect(find.text('ALTITUDE'), findsNothing);
      expect(find.text('SATELLITES'), findsNothing);
      expect(find.text('14 Locked'), findsNothing);

      // Remaining 4 tiles present
      expect(find.text('ACCURACY'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('DRIFT ESTIMATE'), findsOneWidget);

      service.dispose();
    });
  });

  group('Debug Menu - Four Entries Removed & Remaining Functionality', () {
    testWidgets('Four entries are completely removed from Debug Menu in Dark Theme', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: DebugMenu(dataService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Removed 4 entries:
      expect(find.text('Simulate GNSS Outlier Rejection'), findsNothing);
      expect(find.text('Simulate GNSS Outage / Degrading'), findsNothing);
      expect(find.text('Reset Trip Statistics'), findsNothing);
      expect(find.text('Live Python WebSocket Backend'), findsNothing);
      expect(find.text('Using realistic simulated 10Hz Bangalore telemetry'), findsNothing);

      // Retained entries:
      expect(find.text('Simulate Crash / High-G Impact'), findsOneWidget);
      expect(find.text('Toggle GNSS / Dead Reckoning'), findsOneWidget);
      expect(find.text('Simulate Route Deviation'), findsOneWidget);
      expect(find.text('Simulate GNSS Recovered'), findsOneWidget);

      service.dispose();
    });

    testWidgets('Four entries are completely removed from Debug Menu in Light Theme', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: false,
          child: DebugMenu(dataService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Removed 4 entries:
      expect(find.text('Simulate GNSS Outlier Rejection'), findsNothing);
      expect(find.text('Simulate GNSS Outage / Degrading'), findsNothing);
      expect(find.text('Reset Trip Statistics'), findsNothing);
      expect(find.text('Live Python WebSocket Backend'), findsNothing);
      expect(find.text('Using realistic simulated 10Hz Bangalore telemetry'), findsNothing);

      // Retained entries:
      expect(find.text('Simulate Crash / High-G Impact'), findsOneWidget);
      expect(find.text('Toggle GNSS / Dead Reckoning'), findsOneWidget);
      expect(find.text('Simulate Route Deviation'), findsOneWidget);
      expect(find.text('Simulate GNSS Recovered'), findsOneWidget);

      service.dispose();
    });

    testWidgets('Simulate GNSS Recovered functions standalone from GNSS-aided mode', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      expect(service.currentState.currentMode, NavMode.gnssAided);

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: DebugMenu(dataService: service),
        ),
      );
      await tester.pumpAndSettle();

      final recoveredFinder = find.text('Simulate GNSS Recovered');
      expect(recoveredFinder, findsOneWidget);

      await tester.tap(recoveredFinder);
      await tester.pump();

      // Standalone trigger should toggle into outage then recover through reacquiring
      expect(service.currentState.currentMode, NavMode.deadReckoning);

      // Advance timer for recovery
      await tester.pump(const Duration(milliseconds: 700));
      expect(service.currentState.isReacquiring, isTrue);

      // Advance through reacquiring annealing duration
      await tester.pump(const Duration(milliseconds: 2600));
      expect(service.currentState.currentMode, NavMode.gnssAided);
      expect(service.currentState.isReacquiring, isFalse);

      service.dispose();
    });

    testWidgets('Simulate GNSS Recovered functions standalone when already in Dead Reckoning', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.toggleMode(); // Put into deadReckoning
      expect(service.currentState.currentMode, NavMode.deadReckoning);

      await tester.pumpWidget(
        _wrapWithProviders(
          service: service,
          settings: settings,
          isDark: true,
          child: DebugMenu(dataService: service),
        ),
      );
      await tester.pumpAndSettle();

      final recoveredFinder = find.text('Simulate GNSS Recovered');
      expect(recoveredFinder, findsOneWidget);

      await tester.tap(recoveredFinder);
      await tester.pump();

      // Should immediately enter reacquiring
      expect(service.currentState.isReacquiring, isTrue);

      // Advance through reacquiring annealing duration
      await tester.pump(const Duration(milliseconds: 2600));
      expect(service.currentState.currentMode, NavMode.gnssAided);
      expect(service.currentState.isReacquiring, isFalse);

      service.dispose();
    });
  });
}
