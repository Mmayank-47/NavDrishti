import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:provider/provider.dart';
import '../config/mapbox_config.dart';
import '../models/nav_shield_state.dart';
import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'confidence_halo_painter.dart';
import 'vehicle_marker.dart';

/// Navigation Map Widget utilizing Mapbox Vector Maps (mapbox_maps_flutter)
/// with automatic Light/Dark style switching, 60fps vehicle heading interpolation,
/// fixed-radius confidence halo, and graceful fallback with setup banner if
/// a valid Mapbox Public Access Token is not configured.
class MapboxNavMap extends StatefulWidget {
  final NavShieldState state;
  final bool isDark;
  final PlannedRoute? plannedRoute;
  final List<RoutePoint> routeHistory;
  final Function(latlong.LatLng)? onTap;
  final bool isStaticPreview;
  final latlong.LatLng? staticCenter;
  final double initialZoom;
  final ValueChanged<double>? onMapBearingChanged;

  const MapboxNavMap({
    super.key,
    required this.state,
    required this.isDark,
    this.plannedRoute,
    this.routeHistory = const [],
    this.onTap,
    this.isStaticPreview = false,
    this.staticCenter,
    this.initialZoom = 17.2,
    this.onMapBearingChanged,
  });

  @override
  State<MapboxNavMap> createState() => MapboxNavMapState();
}

class MapboxNavMapState extends State<MapboxNavMap>
    with SingleTickerProviderStateMixin {
  // Mapbox Controller & Annotation Managers
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  fmap.MapController? _osmMapController;

  late final AnimationController _animController;

  // Map camera rotation (bearing from true north)
  double _currentMapBearing = 0.0;
  double get currentMapBearing => _currentMapBearing;

  // Previous and Target states for smooth 100ms lerping
  double _prevLat = 12.971598;
  double _prevLon = 77.594566;
  double _prevHeading = 0.0;
  double _prevMajor = 3.5;
  double _prevMinor = 2.2;
  double _prevOrientation = 0.0;

  double _targetLat = 12.971598;
  double _targetLon = 77.594566;
  double _targetHeading = 0.0;
  double _targetMajor = 3.5;
  double _targetMinor = 2.2;
  double _targetOrientation = 0.0;

  bool _autoFollow = true;
  bool _bannerDismissed = false;
  bool _isMapReady = false;
  bool _mapboxFailed = false;

  final Set<int> _activePointers = {};
  final Map<int, Offset> _pointerStartPositions = {};
  Offset? _vehicleScreenPos;


  bool get _hasValidMapboxToken =>
      mapboxAccessToken.isNotEmpty &&
      mapboxAccessToken.startsWith('pk.') &&
      !mapboxAccessToken.contains('DemoToken') &&
      mapboxAccessToken.length > 35;

  bool get _useMapbox =>
      _hasValidMapboxToken &&
      !_mapboxFailed &&
      !io.Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (widget.staticCenter != null) {
      _prevLat = _targetLat = widget.staticCenter!.latitude;
      _prevLon = _targetLon = widget.staticCenter!.longitude;
    } else {
      _setInitialCoordinates(widget.state);
    }

    if (!_useMapbox || io.Platform.environment.containsKey('FLUTTER_TEST')) {
      _mapboxFailed = true;
      _osmMapController = fmap.MapController();
    } else {
      try {
        mapbox.MapboxOptions.setAccessToken(mapboxAccessToken);
      } catch (e) {
        _mapboxFailed = true;
        _osmMapController = fmap.MapController();
      }
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_onAnimationTick);
  }

  int _lastCameraUpdate = 0;

  void _onAnimationTick() {
    if (!mounted) return;
    if (_isMapReady && !widget.isStaticPreview) {
      final t = _animController.value;
      final currentLat = _lerpDouble(_prevLat, _targetLat, t);
      final currentLon = _lerpDouble(_prevLon, _targetLon, t);

      // ONLY force camera center when auto-follow is actively engaged
      if (_autoFollow) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastCameraUpdate >= 60) {
          _lastCameraUpdate = now;
          if (_useMapbox && _mapboxMap != null) {
            _mapboxMap?.setCamera(
              mapbox.CameraOptions(
                center: mapbox.Point(
                  coordinates: mapbox.Position(currentLon, currentLat),
                ),
              ),
            );
          } else if (_osmMapController != null) {
            try {
              _osmMapController?.move(
                latlong.LatLng(currentLat, currentLon),
                _osmMapController!.camera.zoom,
              );
            } catch (_) {}
          }
        }
      } else {
        if (_useMapbox && _mapboxMap != null) {
          _updateVehicleScreenPos(currentLat, currentLon);
        }
      }
    }
  }

  Future<void> _updateVehicleScreenPos(double lat, double lon) async {
    if (_mapboxMap == null) return;
    try {
      final screenCoord = await _mapboxMap!.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(lon, lat)),
      );
      if (mounted) {
        setState(() {
          _vehicleScreenPos = Offset(screenCoord.x, screenCoord.y);
        });
      }
    } catch (_) {}
  }

  void _disengageAutoFollow() {
    if (!_autoFollow || widget.isStaticPreview) return;
    setState(() {
      _autoFollow = false;
    });
    if (_useMapbox && _mapboxMap != null) {
      final t = _animController.value;
      final currentLat = _lerpDouble(_prevLat, _targetLat, t);
      final currentLon = _lerpDouble(_prevLon, _targetLon, t);
      _updateVehicleScreenPos(currentLat, currentLon);
    }
  }

  Future<void> _recenter() async {
    setState(() {
      _autoFollow = true;
      _vehicleScreenPos = null;
    });
    if (_useMapbox && _mapboxMap != null) {
      double currentZoom = widget.initialZoom;
      try {
        final camState = await _mapboxMap!.getCameraState();
        currentZoom = camState.zoom;
      } catch (_) {}
      _mapboxMap?.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              widget.state.longitude,
              widget.state.latitude,
            ),
          ),
          zoom: currentZoom,
        ),
      );
    } else if (_osmMapController != null) {
      try {
        final currentZoom = _osmMapController!.camera.zoom;
        _osmMapController?.move(
          latlong.LatLng(widget.state.latitude, widget.state.longitude),
          currentZoom,
        );
      } catch (_) {}
    }
  }

  void setBearing(double bearing) {
    if (_useMapbox && _mapboxMap != null) {
      _mapboxMap?.setCamera(mapbox.CameraOptions(bearing: bearing));
    } else if (_osmMapController != null) {
      _osmMapController?.rotate(bearing);
    }
    setState(() {
      _currentMapBearing = bearing;
    });
    widget.onMapBearingChanged?.call(bearing);
  }

  void resetNorth() {
    if (_useMapbox && _mapboxMap != null) {
      _mapboxMap?.flyTo(
        mapbox.CameraOptions(bearing: 0.0),
        mapbox.MapAnimationOptions(duration: 500),
      );
    } else if (_osmMapController != null) {
      _osmMapController?.rotate(0.0);
    }
    setState(() {
      _currentMapBearing = 0.0;
    });
    widget.onMapBearingChanged?.call(0.0);
  }

  void _setInitialCoordinates(NavShieldState s) {
    _prevLat = _targetLat = s.latitude;
    _prevLon = _targetLon = s.longitude;
    _prevHeading = _targetHeading = s.heading;
    _prevMajor = _targetMajor = s.uncertaintyEllipse.semiMajorAxis;
    _prevMinor = _targetMinor = s.uncertaintyEllipse.semiMinorAxis;
    _prevOrientation = _targetOrientation = s.uncertaintyEllipse.orientation;
  }

  @override
  void didUpdateWidget(covariant MapboxNavMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Theme changed: reload Mapbox style
    if (oldWidget.isDark != widget.isDark && _mapboxMap != null && _useMapbox) {
      final newStyle = widget.isDark
          ? mapbox.MapboxStyles.DARK
          : mapbox.MapboxStyles.LIGHT;
      _mapboxMap?.loadStyleURI(newStyle);
    }

    if (oldWidget.state.latitude != widget.state.latitude ||
        oldWidget.state.longitude != widget.state.longitude ||
        oldWidget.state.heading != widget.state.heading) {
      final t = _animController.value;
      _prevLat = _lerpDouble(_prevLat, _targetLat, t);
      _prevLon = _lerpDouble(_prevLon, _targetLon, t);
      _prevHeading = _lerpAngleDeg(_prevHeading, _targetHeading, t);
      _prevMajor = _lerpDouble(_prevMajor, _targetMajor, t);
      _prevMinor = _lerpDouble(_prevMinor, _targetMinor, t);
      _prevOrientation = _lerpAngleDeg(_prevOrientation, _targetOrientation, t);

      _targetLat = widget.state.latitude;
      _targetLon = widget.state.longitude;
      _targetHeading = widget.state.heading;
      _targetMajor = widget.state.uncertaintyEllipse.semiMajorAxis;
      _targetMinor = widget.state.uncertaintyEllipse.semiMinorAxis;
      _targetOrientation = widget.state.uncertaintyEllipse.orientation;

      _animController.forward(from: 0.0);
    }

    // Update polylines if route changed
    if (oldWidget.plannedRoute != widget.plannedRoute ||
        oldWidget.routeHistory.length != widget.routeHistory.length) {
      _syncMapboxPolylines();
    }
  }

  Future<void> _syncMapboxPolylines() async {
    if (_polylineManager == null || !_useMapbox) return;
    try {
      await _polylineManager?.deleteAll();

      if (!mounted) return;
      SettingsService? settings;
      try {
        settings = context.read<SettingsService>();
      } catch (_) {}
      final defaultBlue =
          widget.isDark ? AppColors.darkBlue : AppColors.lightBlue;
      final defaultAmber =
          widget.isDark ? AppColors.darkAmber : AppColors.lightAmber;
      final blueColor = settings?.customGnssColor ?? defaultBlue;
      final amberColor = settings?.customDrColor ?? defaultAmber;

      // Planned Route
      if (widget.plannedRoute != null &&
          widget.plannedRoute!.waypoints.isNotEmpty) {
        final pts = widget.plannedRoute!.waypoints
            .map((p) => mapbox.Position(p.longitude, p.latitude))
            .toList();

        await _polylineManager?.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: pts),
            lineColor: blueColor.toARGB32(),
            lineWidth: 5.0,
            lineOpacity: 0.50,
          ),
        );
      }

      // History Traveled Route
      if (widget.routeHistory.isNotEmpty) {
        List<mapbox.Position> currentSegment = [];
        NavMode? currentMode;

        for (final pt in widget.routeHistory) {
          final pos = mapbox.Position(pt.point.longitude, pt.point.latitude);
          if (currentMode == null) {
            currentMode = pt.mode;
            currentSegment.add(pos);
          } else if (currentMode == pt.mode) {
            currentSegment.add(pos);
          } else {
            if (currentSegment.length > 1) {
              await _polylineManager?.create(
                mapbox.PolylineAnnotationOptions(
                  geometry: mapbox.LineString(coordinates: currentSegment),
                  lineColor: (currentMode == NavMode.gnssAided
                          ? blueColor
                          : amberColor)
                      .toARGB32(),
                  lineWidth: 4.0,
                  lineOpacity: 0.90,
                ),
              );
            }
            currentMode = pt.mode;
            currentSegment = [currentSegment.last, pos];
          }
        }

        if (currentSegment.length > 1) {
          await _polylineManager?.create(
            mapbox.PolylineAnnotationOptions(
              geometry: mapbox.LineString(coordinates: currentSegment),
              lineColor: (currentMode == NavMode.gnssAided
                      ? blueColor
                      : amberColor)
                  .toARGB32(),
              lineWidth: 4.0,
              lineOpacity: 0.90,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[MapboxNavMap] Polyline sync error: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _osmMapController?.dispose();
    super.dispose();
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  double _lerpAngleDeg(double a, double b, double t) {
    double diff = (b - a) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return (a + diff * t) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    SettingsService? settings;
    try {
      settings = context.watch<SettingsService>();
    } catch (_) {}
    final isDeadReckoning = widget.state.currentMode == NavMode.deadReckoning;

    final defaultBlue =
        widget.isDark ? AppColors.darkBlue : AppColors.lightBlue;
    final defaultAmber =
        widget.isDark ? AppColors.darkAmber : AppColors.lightAmber;
    final blueColor = settings?.customGnssColor ?? defaultBlue;
    final amberColor = settings?.customDrColor ?? defaultAmber;

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final t = _animController.value;
            final currentLat = _lerpDouble(_prevLat, _targetLat, t);
            final currentLon = _lerpDouble(_prevLon, _targetLon, t);
            final currentHeading =
                _lerpAngleDeg(_prevHeading, _targetHeading, t);
            final currentMajor = _lerpDouble(_prevMajor, _targetMajor, t);
            final currentMinor = _lerpDouble(_prevMinor, _targetMinor, t);
            final currentOrientation =
                _lerpAngleDeg(_prevOrientation, _targetOrientation, t);

            final currentPos = latlong.LatLng(currentLat, currentLon);
            final semiMajorPixels = (currentMajor * 2.2).clamp(18.0, 140.0);
            final semiMinorPixels = (currentMinor * 2.2).clamp(12.0, 90.0);

            return Stack(
              children: [
                // 1. Base Map (Mapbox Native or OSM Fallback)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      _activePointers.add(event.pointer);
                      _pointerStartPositions[event.pointer] = event.position;
                    },
                    onPointerMove: (event) {
                      // Only detect pan when exactly ONE pointer is moving (multi-finger is pinch-zoom)
                      if (_activePointers.length == 1 &&
                          _autoFollow &&
                          !widget.isStaticPreview) {
                        final start = _pointerStartPositions[event.pointer];
                        if (start != null &&
                            (event.position - start).distance > 8.0) {
                          _disengageAutoFollow();
                        }
                      }
                    },
                    onPointerUp: (event) {
                      _activePointers.remove(event.pointer);
                      _pointerStartPositions.remove(event.pointer);
                    },
                    onPointerCancel: (event) {
                      _activePointers.remove(event.pointer);
                      _pointerStartPositions.remove(event.pointer);
                    },
                    child: _useMapbox
                        ? _buildMapboxWidget(currentLat, currentLon)
                        : _buildOsmFallback(
                            currentPos,
                            blueColor,
                            amberColor,
                            semiMajorPixels,
                            semiMinorPixels,
                            currentOrientation,
                            currentHeading,
                            isDeadReckoning,
                            settings,
                          ),
                  ),
                ),

                // 2. Vehicle Marker Overlay (When using Mapbox)
                if (_useMapbox && !widget.isStaticPreview)
                  Positioned(
                    left: _autoFollow || _vehicleScreenPos == null
                        ? (MediaQuery.of(context).size.width - 280) / 2
                        : _vehicleScreenPos!.dx - 140,
                    top: _autoFollow || _vehicleScreenPos == null
                        ? (MediaQuery.of(context).size.height - 280) / 2
                        : _vehicleScreenPos!.dy - 140,
                    width: 280,
                    height: 280,
                    child: IgnorePointer(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Confidence Halo (Fixed size, constant opacity 0.30/0.65)
                          CustomPaint(
                            size: const Size(280, 280),
                            painter: ConfidenceHaloPainter(
                              useFixedHaloRadius: true,
                              semiMajorPixels: semiMajorPixels,
                              semiMinorPixels: semiMinorPixels,
                              orientationDegrees: currentOrientation - _currentMapBearing,
                              isDeadReckoning: isDeadReckoning,
                              isDark: widget.isDark,
                              customGnssColor: settings?.customGnssColor,
                              customDrColor: settings?.customDrColor,
                            ),
                          ),
                          // Vehicle Marker (Arrow, 3D Car, 3D Bike)
                          VehicleMarker(
                            heading: currentHeading,
                            mapBearing: _currentMapBearing,
                            isDeadReckoning: isDeadReckoning,
                            isDark: widget.isDark,
                            iconStyle: settings?.vehicleIconStyle ??
                                VehicleIconStyle.arrow,
                            customAccentColor: isDeadReckoning
                                ? settings?.customDrColor
                                : settings?.customGnssColor,
                          ),
                        ],
                      ),
                    ),
                  ),

                // 3. Mapbox Setup Warning Banner if Token is Missing / Placeholder
                if (!_hasValidMapboxToken && !_bannerDismissed)
                  Positioned(
                    top: widget.isStaticPreview ? 8 : 175,
                    left: 14,
                    right: 14,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFF59E0B), width: 1.2),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black45,
                                blurRadius: 8,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.key_rounded,
                                color: Color(0xFFF59E0B), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'Mapbox Token Required for Vector Maps',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Add token (pk.xxx) to lib/config/mapbox_config.dart. (Showing OSM preview)',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() => _bannerDismissed = true),
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(Icons.close, color: Colors.white70, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        // Re-center Floating Action Button
        if (!_autoFollow && !widget.isStaticPreview)
          Positioned(
            left: 18,
            bottom: MediaQuery.paddingOf(context).bottom + 195,
            child: Material(
              key: const ValueKey('recenter_button'),
              color: widget.isDark
                  ? AppColors.darkSurface
                  : AppColors.lightSurface,
              shape: CircleBorder(
                side: BorderSide(
                  color: widget.isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                  width: 1.2,
                ),
              ),
              elevation: 4,
              shadowColor: Colors.black45,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenter,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Center(
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 22,
                      color: widget.isDark
                          ? AppColors.darkBlue
                          : AppColors.lightBlue,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapboxWidget(double currentLat, double currentLon) {
    return mapbox.MapWidget(
      key: const ValueKey('mapbox_nav_map_native'),
      // ignore: deprecated_member_use
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(currentLon, currentLat),
        ),
        zoom: widget.initialZoom,
      ),
      styleUri:
          widget.isDark ? mapbox.MapboxStyles.DARK : mapbox.MapboxStyles.LIGHT,
      onMapCreated: (mapbox.MapboxMap map) async {
        _mapboxMap = map;
        try {
          map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
          map.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
          _polylineManager =
              await map.annotations.createPolylineAnnotationManager();
          _isMapReady = true;
          _syncMapboxPolylines();
        } catch (e) {
          debugPrint('[MapboxNavMap] Annotation manager init error: $e');
        }
      },
      onMapLoadErrorListener: (err) {
        debugPrint('[MapboxNavMap] Mapbox load error: $err');
        setState(() {
          _mapboxFailed = true;
          _osmMapController ??= fmap.MapController();
        });
      },
      onCameraChangeListener: (camera) {
        if (_mapboxMap != null) {
          _mapboxMap!.getCameraState().then((camState) {
            final b = camState.bearing;
            if ((b - _currentMapBearing).abs() > 0.1) {
              if (mounted) {
                setState(() {
                  _currentMapBearing = b;
                });
              }
              widget.onMapBearingChanged?.call(_currentMapBearing);
            }
          }).catchError((_) {});
        }
        if (!_autoFollow && _mapboxMap != null) {
          final t = _animController.value;
          final currentLat = _lerpDouble(_prevLat, _targetLat, t);
          final currentLon = _lerpDouble(_prevLon, _targetLon, t);
          _updateVehicleScreenPos(currentLat, currentLon);
        }
      },
      onScrollListener: (scroll) {
        if (_activePointers.length <= 1) {
          _disengageAutoFollow();
        }
      },
    );
  }

  Widget _buildOsmFallback(
    latlong.LatLng currentPos,
    Color blueColor,
    Color amberColor,
    double semiMajorPixels,
    double semiMinorPixels,
    double currentOrientation,
    double currentHeading,
    bool isDeadReckoning,
    SettingsService? settings,
  ) {
    final polylines = <fmap.Polyline>[];

    if (widget.plannedRoute != null &&
        widget.plannedRoute!.waypoints.isNotEmpty) {
      polylines.add(
        fmap.Polyline(
          points: widget.plannedRoute!.waypoints,
          strokeWidth: 5.0,
          color: blueColor.withValues(alpha: 0.50),
        ),
      );
    }

    if (widget.routeHistory.isNotEmpty) {
      List<latlong.LatLng> currentSegment = [];
      NavMode? currentMode;

      for (final pt in widget.routeHistory) {
        if (currentMode == null) {
          currentMode = pt.mode;
          currentSegment.add(pt.point);
        } else if (currentMode == pt.mode) {
          currentSegment.add(pt.point);
        } else {
          if (currentSegment.length > 1) {
            polylines.add(
              fmap.Polyline(
                points: List.from(currentSegment),
                strokeWidth: 4.0,
                color:
                    currentMode == NavMode.gnssAided ? blueColor : amberColor,
              ),
            );
          }
          currentMode = pt.mode;
          currentSegment = [currentSegment.last, pt.point];
        }
      }
      if (currentSegment.length > 1) {
        polylines.add(
          fmap.Polyline(
            points: currentSegment,
            strokeWidth: 4.0,
            color: currentMode == NavMode.gnssAided ? blueColor : amberColor,
          ),
        );
      }
    }

    _osmMapController ??= fmap.MapController();

    return fmap.FlutterMap(
      mapController: _osmMapController,
      options: fmap.MapOptions(
        initialCenter: widget.staticCenter ?? currentPos,
        initialZoom: widget.initialZoom,
        onMapReady: () {
          _isMapReady = true;
        },
        interactionOptions: const fmap.InteractionOptions(
          flags: fmap.InteractiveFlag.all,
        ),
        onTap: (tapPosition, point) {
          widget.onTap?.call(point);
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _autoFollow && _activePointers.length <= 1) {
            _disengageAutoFollow();
          }
          if ((camera.rotation - _currentMapBearing).abs() > 0.1) {
            _currentMapBearing = camera.rotation;
            widget.onMapBearingChanged?.call(_currentMapBearing);
            if (mounted) setState(() {});
          }
        },
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.navshield.nav_shield',
          maxZoom: 19,
        ),
        if (polylines.isNotEmpty) fmap.PolylineLayer(polylines: polylines),
        fmap.MarkerLayer(
          markers: [
            if (widget.plannedRoute != null)
              fmap.Marker(
                point: widget.plannedRoute!.destination,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on,
                  size: 44,
                  color: Color(0xFFDC2626),
                ),
              ),
            if (!widget.isStaticPreview)
              fmap.Marker(
                point: currentPos,
                width: 280,
                height: 280,
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(280, 280),
                      painter: ConfidenceHaloPainter(
                        useFixedHaloRadius: true,
                        semiMajorPixels: semiMajorPixels,
                        semiMinorPixels: semiMinorPixels,
                        orientationDegrees: currentOrientation - _currentMapBearing,
                        isDeadReckoning: isDeadReckoning,
                        isDark: widget.isDark,
                        customGnssColor: settings?.customGnssColor,
                        customDrColor: settings?.customDrColor,
                      ),
                    ),
                    VehicleMarker(
                      heading: currentHeading,
                      mapBearing: _currentMapBearing,
                      isDeadReckoning: isDeadReckoning,
                      isDark: widget.isDark,
                      iconStyle: settings?.vehicleIconStyle ?? VehicleIconStyle.arrow,
                      customAccentColor: isDeadReckoning
                          ? settings?.customDrColor
                          : settings?.customGnssColor,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
