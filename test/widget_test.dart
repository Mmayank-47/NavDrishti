import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nav_shield/models/nav_shield_state.dart';
import 'package:nav_shield/models/trip_data.dart';
import 'package:nav_shield/screens/trip_summary_screen.dart';
import 'package:nav_shield/services/saved_places_service.dart';
import 'package:nav_shield/services/settings_service.dart';
import 'package:nav_shield/theme/app_theme.dart';
import 'package:nav_shield/widgets/sos_button.dart';
import 'package:nav_shield/widgets/status_pill.dart';
import 'package:nav_shield/widgets/vehicle_marker.dart';
import 'package:nav_shield/screens/calibration_screen.dart';
import 'package:nav_shield/screens/destination_entry_screen.dart';
import 'package:nav_shield/screens/main_navigation_screen.dart';
import 'package:nav_shield/screens/settings_screen.dart';
import 'package:nav_shield/screens/sos_alert_overlay.dart';
import 'package:nav_shield/screens/splash_screen.dart';
import 'package:nav_shield/screens/system_health_screen.dart';
import 'package:nav_shield/screens/permissions_onboarding_screen.dart';
import 'package:nav_shield/services/mock_nav_shield_data_service.dart';
import 'package:nav_shield/services/nav_shield_data_service.dart';
import 'package:nav_shield/services/turn_guidance_service.dart';
import 'package:nav_shield/services/trip_notification_service.dart';
import 'package:nav_shield/services/overlay_navigation_service.dart';
import 'package:nav_shield/services/route_calculation_service.dart';
import 'package:nav_shield/widgets/compact_floating_nav_widget.dart';
import 'package:nav_shield/widgets/compact_floating_overlay_window.dart';
import 'package:nav_shield/widgets/nav_toast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget buildTestWrapper({
  required Widget child,
  NavShieldDataService? service,
  SettingsService? settings,
  SavedPlacesService? savedPlaces,
  ThemeData? theme,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
          value: settings ?? SettingsService()),
      Provider<NavShieldDataService>.value(
          value: service ?? MockNavShieldDataService(autoStart: false)),
      ChangeNotifierProvider<SavedPlacesService>.value(
          value: savedPlaces ?? SavedPlacesService()),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StatusPill Widget Tests', () {
    testWidgets('Renders minimal dot with optional accuracy in GNSS_AIDED mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: StatusPill(
              mode: NavMode.gnssAided,
              timeInCurrentMode: 0,
              uncertaintyMeters: 2.5,
              onOpenDebug: () {},
            ),
          ),
        ),
      );

      // Should show ±2.5m and NOT show "Dead Reckoning" text
      expect(find.text('±2.5m'), findsOneWidget);
      expect(find.textContaining('Dead Reckoning'), findsNothing);
      expect(find.byType(StatusPill), findsOneWidget);
    });

    testWidgets('Renders amber badge with live elapsed timer and accuracy in DEAD_RECKONING mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: StatusPill(
              mode: NavMode.deadReckoning,
              timeInCurrentMode: 14,
              uncertaintyMeters: 8.2,
              onOpenDebug: () {},
            ),
          ),
        ),
      );

      expect(find.text('Dead Reckoning · 14s (±8.2m)'), findsOneWidget);
    });
  });

  group('VehicleMarker Widget Tests', () {
    testWidgets('Renders all three styles (arrow, car, bike) without error', (tester) async {
      for (final style in VehicleIconStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: VehicleMarker(
                  heading: 45.0,
                  isDeadReckoning: false,
                  isDark: true,
                  iconStyle: style,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(VehicleMarker), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('VehicleMarker rotation uses (heading - mapBearing)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarker(
                heading: 90.0,
                mapBearing: 30.0,
                isDeadReckoning: false,
                isDark: true,
              ),
            ),
          ),
        ),
      );

      final transformFinder = find.byType(Transform);
      expect(transformFinder, findsWidgets);
      final transformWidget = tester.widget<Transform>(transformFinder.first);
      // Expected angle in radians: (90 - 30) * pi / 180 = 60 * pi / 180 (cos ~0.5, sin ~0.866)
      expect(transformWidget.transform.storage[0], closeTo(0.5, 0.02));
      expect(transformWidget.transform.storage[1], closeTo(0.866, 0.02));
    });
  });

  group('MainNavigationScreen Slim Bar & Compass Tests', () {
    testWidgets('Slim bottom bar renders Speed, Dist, ETA, End button, and compass reset', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await tester.pumpWidget(
        buildTestWrapper(
          settings: settings,
          service: service,
          child: const MainNavigationScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('DIST'), findsOneWidget);
      expect(find.text('ETA'), findsOneWidget);
      expect(find.byKey(const ValueKey('end_navigation_button')), findsOneWidget);
      expect(find.byTooltip('Reset Heading to North'), findsOneWidget);
    });
  });

  group('SosButton Hold-to-Trigger Tests', () {
    testWidgets('Brief tap does NOT trigger SOS', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SosButton(
                onTrigger: () {
                  triggered = true;
                },
              ),
            ),
          ),
        ),
      );

      // Tap and release immediately (100ms)
      final gesture = await tester.startGesture(tester.getCenter(find.byType(SosButton)));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(triggered, isFalse);
    });

    testWidgets('Holding for full 1000ms triggers SOS', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SosButton(
                onTrigger: () {
                  triggered = true;
                },
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SosButton)));
      await tester.pump();
      // Hold for 1100ms to exceed 1000ms requirement
      await tester.pump(const Duration(milliseconds: 1100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(triggered, isTrue);
    });
  });

  group('DestinationEntryScreen Widget Tests', () {
    testWidgets('Renders search bar, destination chips, and selects destination', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const DestinationEntryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search bar and default destination chips
      expect(find.text('NAV-SHIELD'), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);

      // Tap destination chip
      final chipFinder = find.text('Work');
      expect(chipFinder, findsOneWidget);
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(service.tripStatus, equals(TripStatus.destinationSet));
      expect(service.currentPlannedRoute?.destinationName, equals('MG Road Metro Station'));
      expect(find.text('Start Navigation'), findsOneWidget);

      // Tap Start Navigation
      await tester.tap(find.text('Start Navigation'));
      await tester.pumpAndSettle();

      expect(service.tripStatus, equals(TripStatus.active));
      service.dispose();
    });
  });

  group('TripSummaryScreen Tests', () {
    testWidgets('Renders destination badge, split bar, and distance stats properly', (tester) async {
      final summary = TripSummary(
        totalDistanceKm: 15.2,
        totalDuration: const Duration(minutes: 10),
        gnssAidedDuration: const Duration(minutes: 7),
        deadReckoningDuration: const Duration(minutes: 3),
        maxDriftPercent: 2.4,
        route: const [],
        destinationName: 'MG Road Metro',
        destinationReached: true,
      );

      final settings = SettingsService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: TripSummaryScreen(
            summary: summary,
            settings: settings,
            onNewTrip: () {},
          ),
        ),
      );

      expect(find.text('Trip Summary'), findsOneWidget);
      expect(find.text('MG Road Metro'), findsOneWidget);
      expect(find.text('REACHED'), findsOneWidget);
      expect(find.text('15.2 km'), findsOneWidget);
      expect(find.text('10m 0s'), findsOneWidget);
      expect(find.text('2.4%'), findsOneWidget);
      expect(find.textContaining('GNSS Aided: 70%'), findsOneWidget);
      expect(find.textContaining('Dead Reckoning: 30%'), findsOneWidget);
    });

    testWidgets('Device back button on TripSummaryScreen triggers onNewTrip and navigates to DestinationEntryScreen', (tester) async {
      bool onNewTripCalled = false;
      final summary = TripSummary(
        totalDistanceKm: 5.0,
        totalDuration: const Duration(minutes: 5),
        gnssAidedDuration: const Duration(minutes: 5),
        deadReckoningDuration: Duration.zero,
        maxDriftPercent: 1.0,
        route: const [],
        destinationName: 'MG Road Metro',
        destinationReached: true,
      );

      await tester.pumpWidget(
        buildTestWrapper(
          child: TripSummaryScreen(
            summary: summary,
            settings: SettingsService(),
            onNewTrip: () => onNewTripCalled = true,
          ),
        ),
      );

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(onNewTripCalled, isTrue);
      expect(find.byType(DestinationEntryScreen), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);
    });

    testWidgets('Close X button on TripSummaryScreen navigates to DestinationEntryScreen', (tester) async {
      bool onNewTripCalled = false;
      final summary = TripSummary(
        totalDistanceKm: 5.0,
        totalDuration: const Duration(minutes: 5),
        gnssAidedDuration: const Duration(minutes: 5),
        deadReckoningDuration: Duration.zero,
        maxDriftPercent: 1.0,
        route: const [],
        destinationName: 'MG Road Metro',
        destinationReached: true,
      );

      await tester.pumpWidget(
        buildTestWrapper(
          child: TripSummaryScreen(
            summary: summary,
            settings: SettingsService(),
            onNewTrip: () => onNewTripCalled = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('trip_summary_close_button')));
      await tester.pumpAndSettle();

      expect(onNewTripCalled, isTrue);
      expect(find.byType(DestinationEntryScreen), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);
    });

    testWidgets('Start New Trip button on TripSummaryScreen navigates to DestinationEntryScreen', (tester) async {
      bool onNewTripCalled = false;
      final summary = TripSummary(
        totalDistanceKm: 5.0,
        totalDuration: const Duration(minutes: 5),
        gnssAidedDuration: const Duration(minutes: 5),
        deadReckoningDuration: Duration.zero,
        maxDriftPercent: 1.0,
        route: const [],
        destinationName: 'MG Road Metro',
        destinationReached: true,
      );

      await tester.pumpWidget(
        buildTestWrapper(
          child: TripSummaryScreen(
            summary: summary,
            settings: SettingsService(),
            onNewTrip: () => onNewTripCalled = true,
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('start_new_trip_button')),
        200.0,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start_new_trip_button')));
      await tester.pumpAndSettle();

      expect(onNewTripCalled, isTrue);
      expect(find.byType(DestinationEntryScreen), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);
    });
  });

  group('SosAlertOverlay Tests', () {
    testWidgets('Renders emergency impact detected and cancel button cancels SOS', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      service.triggerSimulatedCrash();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          child: SosAlertOverlay(
            state: service.currentState,
            dataService: service,
          ),
        ),
      );

      expect(find.text('Possible impact detected'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text("I'M OK — CANCEL"), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text("I'M OK — CANCEL"));
      await tester.pump();

      expect(service.currentState.crashDetected, isFalse);
      expect(service.currentState.sosActive, isFalse);
      service.dispose();
    });
  });

  group('CalibrationScreen Tests', () {
    testWidgets('Renders instruction and recalibrate flow', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: CalibrationScreen(dataService: service),
        ),
      );

      expect(find.text('Sensor Alignment'), findsOneWidget);
      expect(find.text('Sensors Calibrated'), findsOneWidget);
      expect(find.text('Return to Navigation'), findsOneWidget);

      service.dispose();
    });
  });

  group('SettingsScreen Tests', () {
    testWidgets('Renders appearance, vehicle icon styles, confidence halo options, and units', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = SettingsService();

      await tester.pumpWidget(
        buildTestWrapper(
          settings: settings,
          child: const SettingsScreen(),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('Follow System'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Light Mode'), findsOneWidget);

      // Vehicle Icon Style section
      expect(find.text('VEHICLE ICON STYLE'), findsOneWidget);
      expect(find.text('Arrow (Directional)'), findsOneWidget);
      expect(find.text('3D Car (Automobile)'), findsOneWidget);
      expect(find.text('3D Bike (Two-Wheeler)'), findsOneWidget);

      // Confidence Halo section contains ONLY the two color pickers
      expect(find.text('CONFIDENCE HALO'), findsOneWidget);
      expect(find.text('Dynamic Confidence Opacity'), findsNothing);
      expect(find.text('GNSS Aided Color'), findsOneWidget);
      expect(find.text('Dead Reckoning Color'), findsOneWidget);
      expect(find.textContaining('Red is strictly reserved for SOS'), findsOneWidget);

      expect(find.text('Phone Sensors'), findsOneWidget);
      expect(find.text('External IMU'), findsOneWidget);
      expect(find.text('Metric Units'), findsOneWidget);

      // Verify Recalibrate Sensors is NOT anywhere in Settings
      expect(find.text('Recalibrate Sensors'), findsNothing);
      expect(find.text('Perform 10-second forward vehicle alignment'), findsNothing);
    });
  });

  group('Responsive Layout & Theme Checks', () {
    testWidgets('Main screen renders without overflow on small screen (360x640) and large screen (412x915)', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      for (final size in [const Size(360, 640), const Size(412, 915)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
          await tester.pumpWidget(
            buildTestWrapper(
              service: service,
              settings: settings,
              theme: theme,
              child: const Scaffold(
                body: MainNavigationScreen(),
              ),
            ),
          );

          await tester.pump();
          // Verify no exceptions or overflow occurred
          expect(tester.takeException(), isNull);
        }
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        service.dispose();
      });
    });
  });

  group('Map Pan & Recenter Tests', () {
    testWidgets('Map can be panned, shows Recenter button, and tapping recenter restores follow', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially, auto-follow is active, recenter button is NOT shown
      expect(find.byKey(const ValueKey('recenter_button')), findsNothing);

      // Simulate dragging/panning the map with a single pointer
      await tester.drag(find.byType(MainNavigationScreen), const Offset(0, -100));
      await tester.pumpAndSettle();

      // Recenter button should now appear
      expect(find.byKey(const ValueKey('recenter_button')), findsOneWidget);

      // Tap the recenter button
      await tester.tap(find.byKey(const ValueKey('recenter_button')));
      await tester.pumpAndSettle();

      // Verify auto-follow stays disengaged across time/ticks until tapped
      await tester.drag(find.byType(MainNavigationScreen), const Offset(50, 50));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recenter_button')), findsOneWidget);

      // Advance time by 5 seconds - must NOT auto-re-engage
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('recenter_button')), findsOneWidget);

      // Tap recenter to restore
      await tester.tap(find.byKey(const ValueKey('recenter_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recenter_button')), findsNothing);

      service.dispose();
    });

    testWidgets('Pan and Recenter works in DEAD_RECKONING mode and both Light and Dark themes', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();
      service.toggleMode(); // Toggles to NavMode.deadReckoning

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          buildTestWrapper(
            service: service,
            settings: settings,
            theme: theme,
            child: const Scaffold(
              body: MainNavigationScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('recenter_button')), findsNothing);

        await tester.drag(find.byType(MainNavigationScreen), const Offset(-80, 60));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('recenter_button')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('recenter_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('recenter_button')), findsNothing);
      }

      service.dispose();
    });
  });

  group('SplashScreen Tests', () {
    testWidgets('Renders NAV-SHIELD title, tagline, and brand elements', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(autoDismiss: false),
        ),
      );

      expect(find.text('NAV-SHIELD'), findsOneWidget);
      expect(find.text('Resilient Navigation Beyond GPS'), findsOneWidget);
      expect(find.text('Navigate · Stay on Track · Anywhere'), findsOneWidget);
    });
  });

  group('SystemHealthScreen Tests', () {
    testWidgets('Renders simplified Sensor Actions and confirms subsystem cards removed', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = MockNavShieldDataService(autoStart: false);

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          child: const SystemHealthScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Check subsystem cards are NOT present (removed per requirement)
      expect(find.text('GNSS Subsystem'), findsNothing);
      expect(find.text('IMU Subsystem'), findsNothing);
      expect(find.text('INS Subsystem'), findsNothing);
      expect(find.text('EKF Fusion Engine'), findsNothing);
      expect(find.text('ALL SYSTEMS NOMINAL'), findsNothing);

      // Check Sensor Actions section
      expect(find.text('SENSOR ACTIONS'), findsOneWidget);
      expect(find.text('Recalibrate Sensors'), findsOneWidget);
      expect(find.text('Run Guided Sensor Diagnostics'), findsOneWidget);
      expect(find.text('Sensor Management'), findsOneWidget);

      service.dispose();
    });

    testWidgets('Tapping Recalibrate Sensors triggers callback or navigates', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool recalibrateCalled = false;
      final service = MockNavShieldDataService(autoStart: false);

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          child: SystemHealthScreen(
            onRecalibrate: () => recalibrateCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recalibrate Sensors'));
      await tester.pumpAndSettle();

      expect(recalibrateCalled, isTrue);
      service.dispose();
    });
  });

  group('NavToast Tests', () {
    testWidgets('Renders each toast type correctly in dark and light mode', (tester) async {
      for (final type in NavToastType.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: NavToast(type: type),
              ),
            ),
          ),
        );

        expect(find.byType(NavToast), findsOneWidget);
      }
      // Specifically verify gnssRecovered texts
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: NavToast(type: NavToastType.gnssRecovered),
            ),
          ),
        ),
      );
      expect(find.text('GNSS RECOVERED'), findsOneWidget);
      expect(find.text('Re-fusing with INS'), findsOneWidget);
    });
  });

  group('DestinationEntryScreen Redesign Tests', () {
    testWidgets('Renders search bar, shortcuts, recent destinations, and bottom tabs', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const DestinationEntryScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify search bar and shortcuts
      expect(find.text('Where are you going?'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('College'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      // Verify bottom navigation tabs
      expect(find.text('Navigate'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Select shortcut destination -> route preview appears
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Start Navigation'), findsOneWidget);
      expect(find.textContaining('Drive'), findsOneWidget);
      expect(find.textContaining('Bike'), findsOneWidget);
      expect(find.textContaining('Walk'), findsNothing);

      // Tap 'Bike' tab -> sets vehicle marker style to Bike
      await tester.tap(find.textContaining('Bike'));
      await tester.pumpAndSettle();
      expect(settings.vehicleIconStyle, VehicleIconStyle.bike);

      // Tap 'Drive' tab -> sets vehicle marker style to Car
      await tester.tap(find.textContaining('Drive'));
      await tester.pumpAndSettle();
      expect(settings.vehicleIconStyle, VehicleIconStyle.car);

      service.dispose();
    });
  });

  group('Active Navigation HUD Clean Layout Tests', () {
    testWidgets('DR mode does NOT render GNSS-lost banner or warning strip', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();
      service.toggleMode(); // Toggle to Dead Reckoning

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that the GNSS lost banner and warning strip are completely removed
      expect(find.textContaining('GNSS SIGNAL LOST'), findsNothing);
      expect(find.textContaining('INS Dead Reckoning Active'), findsNothing);
      expect(find.textContaining('Using IMU-based INS'), findsNothing);
      expect(find.textContaining('Accuracy may decrease over time'), findsNothing);

      // Verify slim navigation bar still present
      expect(find.byKey(const ValueKey('end_navigation_button')), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('DIST'), findsOneWidget);
      expect(find.text('ETA'), findsOneWidget);

      service.dispose();
    });

    testWidgets('Right-side vertical control stack is completely removed', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all elements of the old right control stack are gone (layers, zoom, 3D)
      expect(find.byIcon(Icons.layers_outlined), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
      expect(find.text('3D'), findsNothing);
      // Voice guidance is restored near turn-by-turn card
      expect(find.byKey(const ValueKey('voice_guidance_mute_toggle')), findsOneWidget);

      service.dispose();
    });

    testWidgets('Standalone compass button on left and SOS button on right are symmetric and functional', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Standalone compass button exists on the left
      expect(find.byKey(const ValueKey('compass_button')), findsOneWidget);

      // SOS button exists on the right
      expect(find.byType(SosButton), findsOneWidget);

      // Tap compass button to verify it resets north without error
      await tester.tap(find.byKey(const ValueKey('compass_button')));
      await tester.pumpAndSettle();

      service.dispose();
    });

    testWidgets('Compass and SOS buttons maintain visible breathing room above bottom bar across screen sizes', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      for (final size in [const Size(390, 844), const Size(360, 640), const Size(412, 915)]) {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;

        for (final isDr in [false, true]) {
          if (isDr && service.currentState.currentMode != NavMode.deadReckoning) {
            service.toggleMode();
          } else if (!isDr && service.currentState.currentMode == NavMode.deadReckoning) {
            service.toggleMode();
          }

          for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
            await tester.pumpWidget(
              buildTestWrapper(
                service: service,
                settings: settings,
                theme: theme,
                child: const Scaffold(
                  body: MainNavigationScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final compassBox = tester.getRect(find.byKey(const ValueKey('compass_button')));
            final sosBox = tester.getRect(find.byType(SosButton));
            final endBtnBox = tester.getRect(find.byKey(const ValueKey('end_navigation_button')));

            // Both buttons are at the exact same vertical center
            expect((compassBox.center.dy - sosBox.center.dy).abs(), lessThan(1.0));

            // Gap between bottom of buttons and top of bottom bar elements is at least 25px
            final compassGap = endBtnBox.top - compassBox.bottom;
            final sosGap = endBtnBox.top - sosBox.bottom;
            expect(compassGap, greaterThan(20.0));
            expect(sosGap, greaterThan(15.0));

            // Compass is on the left, SOS on the right
            expect(compassBox.center.dx, lessThan(size.width / 2));
            expect(sosBox.center.dx, greaterThan(size.width / 2));
          }
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }

      service.dispose();
    });
  });

  group('Voice Guidance & Trip Recovery Tests', () {
    testWidgets('Voice guidance mute toggle button updates icon and persists setting', (tester) async {
      final service = MockNavShieldDataService(autoStart: false);
      final settings = SettingsService();

      expect(settings.voiceGuidanceMuted, isFalse);

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pump();

      // Find voice guidance button
      final voiceBtn = find.byKey(const ValueKey('voice_guidance_mute_toggle'));
      expect(voiceBtn, findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      // Toggle 1: Tap to mute
      await tester.tap(voiceBtn);
      await tester.pump();

      expect(settings.voiceGuidanceMuted, isTrue);
      // Muted state has diagonal slash (Transform.rotate)
      expect(find.byType(Transform), findsWidgets);

      // Toggle 2: Tap to unmute
      await tester.tap(voiceBtn);
      await tester.pump();

      expect(settings.voiceGuidanceMuted, isFalse);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

      // Toggle 3: Tap to mute again
      await tester.tap(voiceBtn);
      await tester.pump();

      expect(settings.voiceGuidanceMuted, isTrue);

      // Toggle 4: Tap to unmute again
      await tester.tap(voiceBtn);
      await tester.pump();

      expect(settings.voiceGuidanceMuted, isFalse);

    });
  });

  group('Mini Nav Widget, SOS Onboarding & Trip Resume Tests', () {
    testWidgets('CompactFloatingNavWidget renders turn info, is draggable, and handles tap', (tester) async {
      bool tapped = false;
      final state = NavShieldState.initial();

      final settings = SettingsService();
      final service = MockNavShieldDataService(autoStart: false);

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: Scaffold(
            body: Stack(
              children: [
                CompactFloatingNavWidget(
                  state: state,
                  instruction: 'Turn right on MG Road',
                  distanceToTurn: '240 m',
                  eta: '4 min',
                  onTap: () {
                    tapped = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('240 m'), findsOneWidget);
      expect(find.text('Turn right on MG Road'), findsOneWidget);
      expect(find.text('4 min'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);

      // Tap on widget triggers onTap
      await tester.tap(find.byKey(const ValueKey('compact_floating_nav_draggable')));
      await tester.pump();
      expect(tapped, isTrue);

      // Drag widget
      await tester.drag(find.byKey(const ValueKey('compact_floating_nav_draggable')), const Offset(50, 50));
      await tester.pump();

      service.dispose();
    });

    testWidgets('PermissionsOnboardingScreen displays 4 permission tiles and triggers emergency contact prompt on SOS toggle', (tester) async {
      final settings = SettingsService();
      await settings.clearEmergencyContact();
      expect(settings.hasEmergencyContact, isFalse);

      await tester.pumpWidget(
        buildTestWrapper(
          settings: settings,
          child: const PermissionsOnboardingScreen(isModalFromSettings: true),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 4 permission tiles
      expect(find.text('Location & Satellite Fix'), findsOneWidget);
      expect(find.text('Motion & Inertial Sensors'), findsOneWidget);
      expect(find.text('Lock-Screen & SOS Alerts'), findsOneWidget);
      expect(find.text('Floating Mini-Nav (PiP / Overlay)'), findsOneWidget);

      // Find switch for SOS Alerts and toggle
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(4));

      // Toggle off and on for SOS Alerts (index 2)
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();

      // Should show Emergency Contact Setup modal because hasEmergencyContact is false
      expect(find.text('Emergency Contact Setup'), findsOneWidget);
      expect(find.byKey(const ValueKey('sos_contact_name_field')), findsOneWidget);
      expect(find.byKey(const ValueKey('sos_contact_phone_field')), findsOneWidget);

      // Fill in and save contact
      await tester.enterText(find.byKey(const ValueKey('sos_contact_name_field')), 'Rohan Verma');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('sos_contact_phone_field')), '+91 99887 76655');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sos_contact_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(settings.hasEmergencyContact, isTrue);
      expect(settings.emergencyContactName, 'Rohan Verma');
    });

    testWidgets('MainNavigationScreen minimize button activates floating overlay without fake home screen placeholder', (tester) async {
      final settings = SettingsService();
      final service = MockNavShieldDataService(autoStart: false);
      service.setDestination(const LatLng(12.9756, 77.6066), 'MG Road Metro');
      service.startTrip();

      await tester.pumpWidget(
        buildTestWrapper(
          service: service,
          settings: settings,
          child: const Scaffold(
            body: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pump();

      // Find minimize button
      final minimizeBtn = find.byKey(const ValueKey('toggle_mini_nav_pip_button'));
      expect(minimizeBtn, findsOneWidget);

      // Tap minimize
      await tester.tap(minimizeBtn);
      await tester.pumpAndSettle();

      // MUST NOT render fake in-app "Home Screen" placeholder
      expect(find.text('Home Screen'), findsNothing);
      // SnackBar confirmation is displayed
      expect(find.text('Floating navigation overlay active over other apps'), findsOneWidget);
      // Full navigation HUD remains rendered and ready
      expect(find.byKey(const ValueKey('end_navigation_button')), findsOneWidget);

      service.dispose();
    });

    testWidgets('CompactFloatingOverlayWindow renders navigation telemetry correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CompactFloatingOverlayWindow(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Turn right on MG Road'), findsOneWidget);
      expect(find.text('240 m'), findsOneWidget);
      expect(find.text('4 min'), findsOneWidget);
      expect(find.byIcon(Icons.turn_right_rounded), findsOneWidget);
      expect(find.textContaining('GNSS'), findsWidgets);
    });

    testWidgets('CompactFloatingOverlayWindow dynamically updates with live coordinates and INS DR mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CompactFloatingOverlayWindow(
                initialData: {
                  'instruction': 'Continue on Residency Road',
                  'distance': '480 m',
                  'eta': '2 min',
                  'mode': 'DEAD_RECKONING',
                  'speed': '38 km/h',
                  'heading': 45.0,
                  'currentLat': 12.9735,
                  'currentLng': 77.5982,
                  'progress': 0.65,
                  'turnType': 'straight',
                  'routePoints': [
                    [12.9716, 77.5944],
                    [12.9735, 77.5982],
                    [12.9753, 77.6074],
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Continue on Residency Road'), findsOneWidget);
      expect(find.text('480 m'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(find.textContaining('INS DR'), findsWidgets);
      expect(find.byIcon(Icons.straight_rounded), findsOneWidget);
    });

    test('TurnGuidanceService calculates road maneuvers and progress correctly', () {
      final route = RouteCalculationService.calculateRoute(
        origin: const LatLng(12.97162, 77.594461),
        destination: const LatLng(12.975312, 77.607443),
        destinationName: 'Central Circuit',
      );

      final guidance = TurnGuidanceService.calculate(
        currentPos: const LatLng(12.97162, 77.594461),
        currentHeading: 12.0,
        distanceTraveledKm: 0.2,
        plannedRoute: route,
      );

      expect(guidance.instruction, isNotEmpty);
      expect(guidance.distanceToTurnText, isNotEmpty);
      expect(guidance.remainingKm, greaterThan(0.0));
      expect(guidance.progressRatio, inInclusiveRange(0.0, 1.0));
    });

    test('TripNotificationService formats Google Maps-style ongoing notification correctly', () async {
      final notifService = TripNotificationService.instance;

      await notifService.updateTripStatus(
        mode: NavMode.gnssAided,
        remainingKm: 1.4,
        remainingMins: 4,
        destinationName: 'Central Circuit',
        instruction: 'Turn right on MG Road',
        turnType: 'turn_right',
        distanceToTurn: '240 m',
        progressRatio: 0.35,
      );

      expect(notifService.isShowing, isTrue);
      expect(notifService.lastTitle, contains('240 m'));
      expect(notifService.lastTitle, contains('Turn right on MG Road'));
      expect(notifService.lastInstruction, equals('Turn right on MG Road'));
      expect(notifService.lastTurnType, equals('turn_right'));
      expect(notifService.lastProgressPercent, equals(35));
      expect(notifService.lastBody, contains('Central Circuit'));

      // Dismissal on cancel
      await notifService.cancelTripNotification();
      expect(notifService.isShowing, isFalse);
    });

    test('OverlayNavigationService records and serializes live telemetry payload', () async {
      final overlayService = OverlayNavigationService.instance;

      await overlayService.updateOverlay(
        instruction: 'Turn left on Brigade Road',
        distance: '180 m',
        eta: '3 min',
        mode: 'GNSS_AIDED',
        speed: '41 km/h',
        heading: 88.5,
        currentLat: 12.973,
        currentLng: 77.598,
        progress: 0.42,
        turnType: 'turn_left',
        routePoints: [
          [12.9716, 77.5944],
          [12.9730, 77.5980],
        ],
      );

      expect(overlayService.lastPayload, isNotNull);
      expect(overlayService.lastPayload!['instruction'], equals('Turn left on Brigade Road'));
      expect(overlayService.lastPayload!['distance'], equals('180 m'));
      expect(overlayService.lastPayload!['heading'], equals(88.5));
      expect(overlayService.lastPayload!['turnType'], equals('turn_left'));
      expect(overlayService.lastPayload!['progress'], equals(0.42));
    });

    testWidgets('CompactFloatingOverlayWindow has enlarged dimensions (320x210) and interactive expand button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CompactFloatingOverlayWindow(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify enlarged container size (320 width x 210 height)
      final containerFinder = find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxWidth == 320.0,
      );
      expect(containerFinder, findsOneWidget);

      // Verify dedicated expand button
      final expandIconFinder = find.byIcon(Icons.open_in_full_rounded);
      expect(expandIconFinder, findsOneWidget);

      // Verify tapping the expand button executes tap gesture smoothly
      await tester.tap(expandIconFinder);
      await tester.pump();
    });
  });
}
