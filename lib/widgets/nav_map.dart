import 'package:flutter/material.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import 'mapbox_nav_map.dart';

/// Full-screen navigation map with Mapbox Vector Maps integration
/// and 60fps vehicle heading interpolation.
class NavMap extends StatelessWidget {
  final NavShieldState state;
  final bool isDark;
  final PlannedRoute? plannedRoute;
  final List<RoutePoint> routeHistory;
  final ValueChanged<double>? onMapBearingChanged;
  final GlobalKey<MapboxNavMapState>? mapKey;

  const NavMap({
    super.key,
    required this.state,
    required this.isDark,
    this.plannedRoute,
    this.routeHistory = const [],
    this.onMapBearingChanged,
    this.mapKey,
  });

  @override
  Widget build(BuildContext context) {
    return MapboxNavMap(
      key: mapKey,
      state: state,
      isDark: isDark,
      plannedRoute: plannedRoute,
      routeHistory: routeHistory,
      onMapBearingChanged: onMapBearingChanged,
    );
  }
}
