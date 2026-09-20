import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/nav_shield_data_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mapbox_nav_map.dart';
import 'calibration_screen.dart';
import 'main_navigation_screen.dart';
import 'settings_screen.dart';
import 'system_health_screen.dart';

enum TravelMode {
  drive('Drive', Icons.directions_car_rounded, 32.0),
  bike('Bike', Icons.two_wheeler_rounded, 24.0),
  walk('Walk', Icons.directions_walk_rounded, 5.0);

  final String label;
  final IconData icon;
  final double avgSpeedKmh;
  const TravelMode(this.label, this.icon, this.avgSpeedKmh);
}

/// Screen: HOME / DESTINATION ENTRY & ROUTE PREVIEW
///
/// Features:
/// - Branded Header: small shield logo + "NAV-SHIELD / Resilient Navigation" + settings gear
/// - Search Bar: "Where are you going?" with mic icon
/// - Quick-access shortcut cards (Home / College / Work / More)
/// - Recent Destinations list with "See all"
/// - "Tap on the map to set a destination" floating hint card
/// - Bottom navigation bar with three tabs: (Navigate / System / Settings)
/// - Route Preview: back arrow, Drive/Bike/Walk tabs with ETAs, route summary, and Start Navigation button
class DestinationEntryScreen extends StatefulWidget {
  const DestinationEntryScreen({super.key});

  @override
  State<DestinationEntryScreen> createState() => _DestinationEntryScreenState();
}

class _DestinationEntryScreenState extends State<DestinationEntryScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _currentTabIndex = 0;
  TravelMode _selectedTravelMode = TravelMode.drive;

  // Preset destinations around Bangalore center
  static final List<Map<String, dynamic>> _presetDestinations = [
    {
      'name': 'MG Road Metro',
      'point': const LatLng(12.9756, 77.6066),
      'subtitle': 'via Kasturba Rd · 1.0 km',
    },
    {
      'name': 'Kanteerava Stadium',
      'point': const LatLng(12.9698, 77.5926),
      'subtitle': 'via Kasturba Rd · 1.8 km',
    },
    {
      'name': 'Indiranagar 100ft Rd',
      'point': const LatLng(12.9784, 77.6408),
      'subtitle': 'via Old Airport Rd · 4.2 km',
    },
    {
      'name': 'Lalbagh Botanical',
      'point': const LatLng(12.9507, 77.5848),
      'subtitle': 'via Hosur Main Rd · 3.6 km',
    },
  ];

  static final List<Map<String, dynamic>> _shortcutLocations = [
    {
      'title': 'Home',
      'icon': Icons.home_rounded,
      'name': 'Home (Lavelle Rd)',
      'point': const LatLng(12.971598, 77.594566),
      'colorLight': AppColors.lightBlue,
      'colorDark': AppColors.darkBlue,
    },
    {
      'title': 'College',
      'icon': Icons.school_rounded,
      'name': 'UVCE College Campus',
      'point': const LatLng(12.9734, 77.5855),
      'colorLight': AppColors.lightViolet,
      'colorDark': AppColors.darkViolet,
    },
    {
      'title': 'Work',
      'icon': Icons.work_rounded,
      'name': 'MG Road Metro',
      'point': const LatLng(12.9756, 77.6066),
      'colorLight': AppColors.lightGreen,
      'colorDark': AppColors.darkGreen,
    },
    {
      'title': 'More',
      'icon': Icons.more_horiz_rounded,
      'name': 'Kanteerava Stadium',
      'point': const LatLng(12.9698, 77.5926),
      'colorLight': AppColors.lightAmber,
      'colorDark': AppColors.darkAmber,
    },
  ];

  StreamSubscription<TripStatus>? _tripStatusSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripStatusSub?.cancel();
    final dataService = context.read<NavShieldDataService>();
    _tripStatusSub = dataService.tripStatusStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tripStatusSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _selectDestination(NavShieldDataService dataService, LatLng point, String name) {
    dataService.setDestination(point, name);
    setState(() {
      _searchController.text = name;
    });
  }

  void _onMapTap(NavShieldDataService dataService, LatLng tappedPoint) {
    final name = 'Pinned Location (${tappedPoint.latitude.toStringAsFixed(4)}°, ${tappedPoint.longitude.toStringAsFixed(4)}°)';
    _selectDestination(dataService, tappedPoint, name);
  }

  void _startNavigation(BuildContext context, NavShieldDataService dataService) {
    if (dataService.currentPlannedRoute == null) {
      final defaultDest = _presetDestinations.first;
      dataService.setDestination(defaultDest['point'] as LatLng, defaultDest['name'] as String);
    }
    dataService.startTrip();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const MainNavigationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataService = context.watch<NavShieldDataService>();
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;

    return StreamBuilder<NavShieldState>(
      stream: dataService.stateStream,
      initialData: dataService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? dataService.currentState;
        final planned = dataService.currentPlannedRoute;

        return Scaffold(
          body: IndexedStack(
            index: _currentTabIndex,
            children: [
              // Tab 0: Main Navigation / Route Planning
              _buildNavigateTab(
                context,
                dataService,
                settings,
                state,
                planned,
                isDark,
                surfaceColor,
                primaryTextColor,
                secondaryTextColor,
                borderColor,
                cyanColor,
              ),

              // Tab 1: System Health Dashboard
              const SystemHealthScreen(showBackButton: false),

              // Tab 2: Settings Screen
              SettingsScreen(
                onRecalibrate: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CalibrationScreen(dataService: dataService),
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: isDark ? 0.95 : 0.98),
              border: Border(top: BorderSide(color: borderColor, width: 1.0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: _currentTabIndex,
              backgroundColor: Colors.transparent,
              indicatorColor: cyanColor.withValues(alpha: 0.18),
              elevation: 0,
              onDestinationSelected: (idx) {
                setState(() {
                  _currentTabIndex = idx;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined, color: secondaryTextColor),
                  selectedIcon: Icon(Icons.explore_rounded, color: cyanColor),
                  label: 'Navigate',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shield_outlined, color: secondaryTextColor),
                  selectedIcon: Icon(Icons.shield_rounded, color: cyanColor),
                  label: 'System',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, color: secondaryTextColor),
                  selectedIcon: Icon(Icons.settings_rounded, color: cyanColor),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigateTab(
    BuildContext context,
    NavShieldDataService dataService,
    SettingsService settings,
    NavShieldState state,
    PlannedRoute? planned,
    bool isDark,
    Color surfaceColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
    Color cyanColor,
  ) {
    final isRoutePreview = planned != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Interactive Map Preview
        Positioned.fill(
          child: MapboxNavMap(
            state: state,
            isDark: isDark,
            plannedRoute: planned,
            onTap: (point) {
              _onMapTap(dataService, point);
            },
            initialZoom: 15.2,
          ),
        ),

        // 2. Floating Map Hint Card (When no route selected)
        if (!isRoutePreview)
          Positioned(
            top: 136,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.darkSurface : AppColors.lightSurface)
                      .withValues(alpha: isDark ? 0.88 : 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : cyanColor.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 15,
                      color: cyanColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where to? (Tap map or select below)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tap on the map to set a destination',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 3. Top Header Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: isRoutePreview
                  ? _buildRoutePreviewHeader(
                      context,
                      dataService,
                      isDark,
                      surfaceColor,
                      primaryTextColor,
                      secondaryTextColor,
                      borderColor,
                    )
                  : _buildHomeHeader(
                      context,
                      isDark,
                      surfaceColor,
                      primaryTextColor,
                      secondaryTextColor,
                      borderColor,
                      cyanColor,
                    ),
            ),
          ),
        ),

        // 4. Bottom Cards: Either Destination Entry List OR Route Preview Panel
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: isRoutePreview
              ? _buildRoutePreviewCard(
                  context,
                  dataService,
                  settings,
                  planned,
                  isDark,
                  surfaceColor,
                  primaryTextColor,
                  secondaryTextColor,
                  borderColor,
                  cyanColor,
                )
              : _buildDestinationSheet(
                  context,
                  dataService,
                  isDark,
                  surfaceColor,
                  primaryTextColor,
                  secondaryTextColor,
                  borderColor,
                  cyanColor,
                ),
        ),
      ],
    );
  }

  Widget _buildHomeHeader(
    BuildContext context,
    bool isDark,
    Color surfaceColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
    Color cyanColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Brand Title & Settings Gear
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: isDark ? 0.90 : 0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? borderColor : cyanColor.withValues(alpha: 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cyanColor.withValues(alpha: 0.18),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      size: 18,
                      color: cyanColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NAV-SHIELD',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: primaryTextColor,
                        ),
                      ),
                      Text(
                        'Resilient Navigation',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, color: secondaryTextColor, size: 20),
                onPressed: () {
                  setState(() {
                    _currentTabIndex = 2; // Switch to settings tab
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoutePreviewHeader(
    BuildContext context,
    NavShieldDataService dataService,
    bool isDark,
    Color surfaceColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: isDark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: primaryTextColor),
            onPressed: () {
              dataService.resetTrip();
            },
          ),
          const SizedBox(width: 6),
          Text(
            'Route Preview',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationSheet(
    BuildContext context,
    NavShieldDataService dataService,
    bool isDark,
    Color surfaceColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
    Color cyanColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: isDark ? 0.94 : 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar ("Where are you going?" with mic icon)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurfaceSubtle : AppColors.lightSurfaceSubtle)
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: cyanColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Where are you going?',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: secondaryTextColor,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _selectDestination(dataService, const LatLng(12.9756, 77.6066), val.trim());
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.mic_none_rounded, color: secondaryTextColor, size: 20),
                  onPressed: () {
                    _selectDestination(dataService, const LatLng(12.9756, 77.6066), 'MG Road Metro');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Quick-Access Shortcut Cards (Home / College / Work / More)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _shortcutLocations.map((sc) {
              final scColor = isDark
                  ? (sc['colorDark'] as Color? ?? cyanColor)
                  : (sc['colorLight'] as Color? ?? cyanColor);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    _selectDestination(
                      dataService,
                      sc['point'] as LatLng,
                      sc['name'] as String,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceSubtle.withValues(alpha: 0.7)
                          : scColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : scColor.withValues(alpha: 0.28),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scColor.withValues(alpha: isDark ? 0.15 : 0.18),
                          ),
                          child: Icon(sc['icon'] as IconData, size: 16, color: scColor),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sc['title'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // "Recent Destinations" Header + "See all"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Destinations',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: primaryTextColor,
                ),
              ),
              Text(
                'See all',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cyanColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Recent Destinations List
          Column(
            children: _presetDestinations.map((dest) {
              final name = dest['name'] as String;
              final point = dest['point'] as LatLng;
              final subtitle = dest['subtitle'] as String;

              final itemColor = isDark ? cyanColor : AppColors.lightBlue;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Material(
                  color: isDark
                      ? AppColors.darkSurfaceSubtle.withValues(alpha: 0.6)
                      : const Color(0xFFF1F5F9).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _selectDestination(dataService, point, name);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: itemColor.withValues(alpha: isDark ? 0.15 : 0.14),
                            ),
                            child: Icon(Icons.history_rounded, size: 16, color: itemColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: primaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: secondaryTextColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePreviewCard(
    BuildContext context,
    NavShieldDataService dataService,
    SettingsService settings,
    PlannedRoute planned,
    bool isDark,
    Color surfaceColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
    Color cyanColor,
  ) {
    // Calculate ETAs for each travel mode
    final driveMins = (planned.totalDistanceKm / (TravelMode.drive.avgSpeedKmh / 60.0)).ceil();
    final bikeMins = (planned.totalDistanceKm / (TravelMode.bike.avgSpeedKmh / 60.0)).ceil();
    final walkMins = (planned.totalDistanceKm / (TravelMode.walk.avgSpeedKmh / 60.0)).ceil();

    int selectedMins;
    switch (_selectedTravelMode) {
      case TravelMode.drive:
        selectedMins = driveMins;
        break;
      case TravelMode.bike:
        selectedMins = bikeMins;
        break;
      case TravelMode.walk:
        selectedMins = walkMins;
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: isDark ? 0.95 : 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode-of-Travel Tabs (Drive / Bike / Walk with live ETAs)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurfaceSubtle : AppColors.lightSurfaceSubtle)
                  .withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                _buildModeTab(TravelMode.drive, '$driveMins m', isDark, cyanColor),
                _buildModeTab(TravelMode.bike, '$bikeMins m', isDark, cyanColor),
                _buildModeTab(TravelMode.walk, '$walkMins m', isDark, cyanColor),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Route Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceSubtle.withValues(alpha: 0.7)
                  : (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$selectedMins min',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${settings.formatDistance(planned.totalDistanceKm)})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'via Kasturba Rd · Optimal corridor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isDark ? AppColors.darkGreen : AppColors.lightGreen)
                          .withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Best route',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Full-Width Start Navigation Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cyanColor,
                foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
                elevation: 4,
                shadowColor: cyanColor.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                _startNavigation(context, dataService);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Start Navigation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(TravelMode mode, String eta, bool isDark, Color cyanColor) {
    final isSelected = _selectedTravelMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTravelMode = mode;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyanColor.withValues(alpha: 0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: cyanColor.withValues(alpha: 0.6), width: 1.0)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                mode.icon,
                size: 16,
                color: isSelected
                    ? cyanColor
                    : (isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText),
              ),
              const SizedBox(width: 6),
              Text(
                '${mode.label} $eta',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : AppColors.lightPrimaryText)
                      : (isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
