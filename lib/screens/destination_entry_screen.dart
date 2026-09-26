import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/nav_shield_data_service.dart';
import '../services/search_location_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/mapbox_nav_map.dart';
import 'main_navigation_screen.dart';
import 'settings_screen.dart';
import 'system_health_screen.dart';

enum TravelMode {
  drive('Drive', Icons.directions_car_rounded, 32.0),
  bike('Bike', Icons.two_wheeler_rounded, 24.0);

  final String label;
  final IconData icon;
  final double avgSpeedKmh;
  const TravelMode(this.label, this.icon, this.avgSpeedKmh);
}

/// Screen: HOME / DESTINATION ENTRY & ROUTE PREVIEW
///
/// Features:
/// - Branded Header: small shield logo + "NAV-SHIELD / Resilient Navigation" + settings gear
/// - Search Bar: "Where are you going?" with live typed search results list
/// - Quick-access shortcut cards (Home / College / Work / More) - Editable & Persisted
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
  List<SearchLocation> _searchResults = [];

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
      'colorLight': Color(0xFF384F95),
      'colorDark': Color(0xFFA6BAEE),
    },
    {
      'title': 'College',
      'icon': Icons.school_rounded,
      'name': 'UVCE College Campus',
      'point': const LatLng(12.9734, 77.5855),
      'colorLight': Color(0xFF8E68A9),
      'colorDark': Color(0xFFBC7EBF),
    },
    {
      'title': 'Work',
      'icon': Icons.work_rounded,
      'name': 'MG Road Metro Station',
      'point': const LatLng(12.9756, 77.6066),
      'colorLight': Color(0xFF203B6F),
      'colorDark': Color(0xFFDBC9F9),
    },
    {
      'title': 'More',
      'icon': Icons.more_horiz_rounded,
      'name': 'Kanteerava Stadium',
      'point': const LatLng(12.9698, 77.5926),
      'colorLight': Color(0xFFBC7EBF),
      'colorDark': Color(0xFFC792EA),
    },
  ];

  StreamSubscription<TripStatus>? _tripStatusSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      final results = SearchLocationService.search(query);
      setState(() {
        _searchResults = results;
      });
    } else {
      if (_searchResults.isNotEmpty) {
        setState(() {
          _searchResults = [];
        });
      }
    }
  }

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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _selectDestination(NavShieldDataService dataService, LatLng point, String name) {
    dataService.setDestination(point, name);
    setState(() {
      _searchController.text = name;
      _searchResults.clear();
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
          body: GalaxyBackground(
            child: IndexedStack(
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
              const SettingsScreen(),
            ],
          ),
        ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xF2312048),
                        const Color(0xF8203B6F),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.96),
                        const Color(0xFFEFE8FC).withValues(alpha: 0.92),
                      ],
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF8E68A9).withValues(alpha: 0.45)
                      : const Color(0xFFBC7EBF).withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
                BoxShadow(
                  color: cyanColor.withValues(alpha: isDark ? 0.12 : 0.05),
                  blurRadius: 14,
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: _currentTabIndex,
              backgroundColor: Colors.transparent,
              indicatorColor: cyanColor.withValues(alpha: 0.22),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xF0312048),
                            const Color(0xF0203B6F),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.95),
                            const Color(0xFFEFE8FC).withValues(alpha: 0.90),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark ? const Color(0xFFBC7EBF).withValues(alpha: 0.50) : const Color(0xFFBC7EBF).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: (isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95)).withValues(alpha: 0.15),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95)).withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.touch_app_rounded,
                        size: 15,
                        color: isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where to? (Tap map or select below)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tap on the map to set a destination',
                            style: TextStyle(
                              fontSize: 10.5,
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF312048).withValues(alpha: 0.92),
                      const Color(0xFF203B6F).withValues(alpha: 0.86),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      const Color(0xFFEFE8FC).withValues(alpha: 0.90),
                    ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? const Color(0xFFBC7EBF).withValues(alpha: 0.45) : const Color(0xFFBC7EBF).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: cyanColor.withValues(alpha: isDark ? 0.15 : 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          cyanColor.withValues(alpha: 0.35),
                          cyanColor.withValues(alpha: 0.12),
                        ],
                      ),
                      border: Border.all(
                        color: cyanColor.withValues(alpha: 0.50),
                        width: 1.0,
                      ),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      size: 19,
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
                          fontWeight: FontWeight.w600,
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xF2312048),
                  const Color(0xF2203B6F),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95),
                  const Color(0xFFEFE8FC).withValues(alpha: 0.90),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFFBC7EBF).withValues(alpha: 0.45) : const Color(0xFFBC7EBF).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: (isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95)).withValues(alpha: isDark ? 0.12 : 0.05),
            blurRadius: 10,
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
              fontWeight: FontWeight.w900,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF21D1532) // Refined cosmic galaxy dark surface
            : const Color(0xFAF8F5FD), // Soft frosted lilac-white in light mode
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color(0xFFBC7EBF).withValues(alpha: 0.40)
                : const Color(0xFFBC7EBF).withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtle pull handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF8E68A9).withValues(alpha: 0.50)
                    : const Color(0xFFBC7EBF).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search Bar ("Where are you going?" with mic icon)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF281F3F) // Deep plum/navy container fill
                  : const Color(0xFFF3EDFA), // Clean pastel lavender container fill
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF8E68A9).withValues(alpha: 0.40)
                    : const Color(0xFFBC7EBF).withValues(alpha: 0.30),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95),
                  size: 20,
                ),
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
                        color: isDark
                            ? const Color(0xFFDBC9F9).withValues(alpha: 0.75)
                            : const Color(0xFF8E68A9),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        final matches = SearchLocationService.search(val.trim());
                        if (matches.isNotEmpty) {
                          _selectDestination(dataService, matches.first.point, matches.first.name);
                        } else {
                          _selectDestination(dataService, const LatLng(12.9756, 77.6066), val.trim());
                        }
                      }
                    },
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults.clear();
                      });
                    },
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.mic_none_rounded,
                      color: isDark ? const Color(0xFFA6BAEE) : const Color(0xFF8E68A9),
                      size: 20,
                    ),
                    onPressed: () {
                      _selectDestination(dataService, const LatLng(12.9756, 77.6066), 'MG Road Metro');
                    },
                  ),
              ],
            ),
          ),

          // Dropdown Search Results List (if search query entered)
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF281F3F) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF8E68A9).withValues(alpha: 0.40) : borderColor,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: borderColor.withValues(alpha: 0.4)),
                  itemBuilder: (ctx, i) {
                    final loc = _searchResults[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95)).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(loc.icon, size: 16, color: isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95)),
                      ),
                      title: Text(
                        loc.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        loc.subtitle,
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        _selectDestination(dataService, loc.point, loc.name);
                        setState(() {
                          _searchResults.clear();
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Quick-Access Shortcut Cards (Home / College / Work / More)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _shortcutLocations.map((sc) {
              final scColor = isDark
                  ? (sc['colorDark'] as Color)
                  : (sc['colorLight'] as Color);

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
                          ? scColor.withValues(alpha: 0.14)
                          : scColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? scColor.withValues(alpha: 0.40)
                            : scColor.withValues(alpha: 0.28),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scColor.withValues(alpha: isDark ? 0.22 : 0.16),
                          ),
                          child: Icon(sc['icon'] as IconData, size: 17, color: scColor),
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
                  color: isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95),
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

              final itemColor = isDark ? const Color(0xFFA6BAEE) : const Color(0xFF384F95);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Material(
                  color: isDark
                      ? const Color(0x38203B6F)
                      : const Color(0xFFF3EDFA).withValues(alpha: 0.8),
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
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: itemColor.withValues(alpha: isDark ? 0.18 : 0.14),
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
                                    color: isDark
                                        ? const Color(0xFFDBC9F9).withValues(alpha: 0.75)
                                        : secondaryTextColor,
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
    // Sync with settings vehicle marker style as single source of truth
    final isBike = settings.vehicleIconStyle == VehicleIconStyle.bike;
    final activeMode = isBike ? TravelMode.bike : TravelMode.drive;

    // Calculate ETAs for each travel mode (Drive / Bike only)
    final driveMins = (planned.totalDistanceKm / (TravelMode.drive.avgSpeedKmh / 60.0)).ceil();
    final bikeMins = (planned.totalDistanceKm / (TravelMode.bike.avgSpeedKmh / 60.0)).ceil();
    final selectedMins = activeMode == TravelMode.bike ? bikeMins : driveMins;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xF20B132B),
                      const Color(0xFA030712),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      const Color(0xF2F1F5F9),
                    ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.darkLuminousBorder : const Color(0x80CBD5E1),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.60 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
              if (isDark)
                BoxShadow(
                  color: AppColors.darkCyan.withValues(alpha: 0.08),
                  blurRadius: 30,
                  offset: const Offset(0, -2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Mode-of-Travel Tabs (Drive / Bike with live ETAs)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            AppColors.darkSurfaceSubtle.withValues(alpha: 0.85),
                            AppColors.darkSurfaceElevated.withValues(alpha: 0.70),
                          ]
                        : [
                            const Color(0xFFF1F5F9),
                            const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    _buildModeTab(TravelMode.drive, '$driveMins m', isDark, cyanColor, settings),
                    _buildModeTab(TravelMode.bike, '$bikeMins m', isDark, cyanColor, settings),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Route Summary Card (Liquid Glass with glowing Emerald accent)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            AppColors.darkGreen.withValues(alpha: 0.12),
                            AppColors.darkSurfaceElevated.withValues(alpha: 0.70),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.95),
                            AppColors.lightGreen.withValues(alpha: 0.08),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: isDark ? 0.50 : 0.40),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: isDark ? 0.15 : 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
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
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppColors.darkGreen : AppColors.lightGreen,
                                shadows: [
                                  if (isDark)
                                    Shadow(
                                      color: AppColors.darkGreen.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                    ),
                                ],
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
                        color: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.6),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? AppColors.darkGreen : AppColors.lightGreen).withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
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

              // Full-Width Start Navigation Button (Glowing Cyan Gradient)
              Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.cyanGlowGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.darkCyan.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xFF030712),
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    _startNavigation(context, dataService);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation_rounded, size: 20, color: Color(0xFF030712)),
                      SizedBox(width: 8),
                      Text(
                        'Start Navigation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: Color(0xFF030712),
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
    );
  }

  Widget _buildModeTab(TravelMode mode, String eta, bool isDark, Color cyanColor, SettingsService settings) {
    final isBike = settings.vehicleIconStyle == VehicleIconStyle.bike;
    final isSelected = mode == TravelMode.bike ? isBike : !isBike;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (mode == TravelMode.bike) {
            settings.setVehicleIconStyle(VehicleIconStyle.bike);
          } else {
            settings.setVehicleIconStyle(VehicleIconStyle.car);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: isDark
                        ? [
                            cyanColor.withValues(alpha: 0.30),
                            cyanColor.withValues(alpha: 0.15),
                          ]
                        : [
                            Colors.white,
                            cyanColor.withValues(alpha: 0.15),
                          ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: cyanColor.withValues(alpha: 0.7), width: 1.0)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cyanColor.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
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
