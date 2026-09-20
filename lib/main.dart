import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'config/mapbox_config.dart';
import 'screens/splash_screen.dart';
import 'services/hybrid_nav_shield_service.dart';
import 'services/nav_shield_data_service.dart';
import 'services/route_calculation_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize road network for realistic navigation
  RouteCalculationService.init();
  RouteCalculationService.loadRoadNetwork();

  // Load user preferences
  final settingsService = SettingsService();
  await settingsService.loadSettings();

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
        Provider<NavShieldDataService>.value(
          value: dataService,
        ),
      ],
      child: const NavShieldApp(),
    ),
  );
}

class NavShieldApp extends StatelessWidget {
  const NavShieldApp({super.key});

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
