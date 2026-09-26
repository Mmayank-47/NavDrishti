import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'config/mapbox_config.dart';
import 'screens/splash_screen.dart';
import 'services/hybrid_nav_shield_service.dart';
import 'services/nav_shield_data_service.dart';
import 'services/route_calculation_service.dart';
import 'services/saved_places_service.dart';
import 'services/settings_service.dart';
import 'services/overlay_navigation_service.dart';
import 'services/trip_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/compact_floating_overlay_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize road network for realistic navigation
  RouteCalculationService.init();
  RouteCalculationService.loadRoadNetwork();

  // Load user preferences
  final settingsService = SettingsService();
  await settingsService.loadSettings();

  // Load editable saved places
  final savedPlacesService = SavedPlacesService();
  await savedPlacesService.load();

  // Initialize Mapbox Access Token if valid
  if (mapboxAccessToken.isNotEmpty &&
      mapboxAccessToken.startsWith('pk.') &&
      !mapboxAccessToken.contains('DemoToken') &&
      mapboxAccessToken.length > 35) {
    try {
      MapboxOptions.setAccessToken(mapboxAccessToken);
    } catch (e) {
      debugPrint('[Main] Mapbox init error: $e');
    }
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Initialize Hybrid Data Service (Seamless Mock / Python WebSocket backend)
  final dataService = HybridNavShieldDataService(settings: settingsService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(
          value: settingsService,
        ),
        ChangeNotifierProvider<SavedPlacesService>.value(
          value: savedPlacesService,
        ),
        Provider<NavShieldDataService>.value(
          value: dataService,
        ),
      ],
      child: const NavShieldApp(),
    ),
  );
}

class NavShieldApp extends StatefulWidget {
  const NavShieldApp({super.key});

  @override
  State<NavShieldApp> createState() => _NavShieldAppState();
}

class _NavShieldAppState extends State<NavShieldApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onDetach: () {
        OverlayNavigationService.instance.closeOverlay();
        TripNotificationService.instance.cancelTripNotification();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return MaterialApp(
      title: 'NAV-SHIELD',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeInOut,
      home: const SplashScreen(),
    );
  }
}

/// Dedicated entry point for the Android SYSTEM_ALERT_WINDOW floating overlay
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CompactFloatingOverlayWindow(),
    ),
  );
}
