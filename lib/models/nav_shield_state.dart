import 'dart:math' as math;

/// Navigation mode emitted by NAV-SHIELD backend
enum NavMode {
  gnssAided('GNSS_AIDED'),
  deadReckoning('DEAD_RECKONING');

  final String value;
  const NavMode(this.value);

  static NavMode fromString(String val) {
    if (val == 'DEAD_RECKONING') return NavMode.deadReckoning;
    return NavMode.gnssAided;
  }
}

/// Sensor alignment status for mounting calibration
enum AlignmentStatus {
  calibrating('CALIBRATING'),
  calibrated('CALIBRATED');

  final String value;
  const AlignmentStatus(this.value);

  static AlignmentStatus fromString(String val) {
    if (val == 'CALIBRATING') return AlignmentStatus.calibrating;
    return AlignmentStatus.calibrated;
  }
}

/// 1-sigma uncertainty ellipse representing covariance in position estimation
class UncertaintyEllipse {
  final double semiMajorAxis; // meters
  final double semiMinorAxis; // meters
  final double orientation;   // degrees clockwise from north

  const UncertaintyEllipse({
    required this.semiMajorAxis,
    required this.semiMinorAxis,
    required this.orientation,
  });

  factory UncertaintyEllipse.fromJson(Map<String, dynamic> json) {
    return UncertaintyEllipse(
      semiMajorAxis: (json['semi_major_axis'] as num?)?.toDouble() ?? 5.0,
      semiMinorAxis: (json['semi_minor_axis'] as num?)?.toDouble() ?? 3.0,
      orientation: (json['orientation'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'semi_major_axis': semiMajorAxis,
    'semi_minor_axis': semiMinorAxis,
    'orientation': orientation,
  };

  UncertaintyEllipse copyWith({
    double? semiMajorAxis,
    double? semiMinorAxis,
    double? orientation,
  }) {
    return UncertaintyEllipse(
      semiMajorAxis: semiMajorAxis ?? this.semiMajorAxis,
      semiMinorAxis: semiMinorAxis ?? this.semiMinorAxis,
      orientation: orientation ?? this.orientation,
    );
  }

  /// Linear interpolation for smooth rendering between 10Hz updates
  static UncertaintyEllipse lerp(UncertaintyEllipse a, UncertaintyEllipse b, double t) {
    return UncertaintyEllipse(
      semiMajorAxis: a.semiMajorAxis + (b.semiMajorAxis - a.semiMajorAxis) * t,
      semiMinorAxis: a.semiMinorAxis + (b.semiMinorAxis - a.semiMinorAxis) * t,
      orientation: a.orientation + (b.orientation - a.orientation) * t,
    );
  }
}

/// 10Hz State emitted by NAV-SHIELD Python Engine
class NavShieldState {
  final double latitude;
  final double longitude;
  final double altitude; // meters
  final double eastVelocity; // m/s
  final double northVelocity; // m/s
  final double heading; // degrees (0 = North, 90 = East)
  final UncertaintyEllipse uncertaintyEllipse;
  final NavMode currentMode;
  final int timeInCurrentMode; // seconds
  final bool crashDetected;
  final double crashConfidence; // 0.0 - 1.0
  final double impactMagnitude; // g
  final bool sosActive;
  final int sosCountdownSeconds; // 30 down to 0
  final AlignmentStatus alignmentStatus;
  final double distanceTraveledKm;
  final double driftEstimatePercent;
  final DateTime timestamp;

  const NavShieldState({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.eastVelocity,
    required this.northVelocity,
    required this.heading,
    required this.uncertaintyEllipse,
    required this.currentMode,
    required this.timeInCurrentMode,
    required this.crashDetected,
    required this.crashConfidence,
    required this.impactMagnitude,
    required this.sosActive,
    required this.sosCountdownSeconds,
    required this.alignmentStatus,
    required this.distanceTraveledKm,
    required this.driftEstimatePercent,
    required this.timestamp,
  });

  /// Computed speed in km/h
  double get speedKmh {
    final speedMs = math.sqrt(eastVelocity * eastVelocity + northVelocity * northVelocity);
    return speedMs * 3.6;
  }

  /// Computed speed in mph
  double get speedMph => speedKmh * 0.621371;

  factory NavShieldState.initial() {
    return NavShieldState(
      latitude: 12.971598,
      longitude: 77.594566,
      altitude: 920.0,
      eastVelocity: 0.0,
      northVelocity: 0.0,
      heading: 0.0,
      uncertaintyEllipse: const UncertaintyEllipse(
        semiMajorAxis: 3.5,
        semiMinorAxis: 2.2,
        orientation: 0.0,
      ),
      currentMode: NavMode.gnssAided,
      timeInCurrentMode: 0,
      crashDetected: false,
      crashConfidence: 0.0,
      impactMagnitude: 0.0,
      sosActive: false,
      sosCountdownSeconds: 30,
      alignmentStatus: AlignmentStatus.calibrated,
      distanceTraveledKm: 0.0,
      driftEstimatePercent: 0.2,
      timestamp: DateTime.now(),
    );
  }

  factory NavShieldState.fromJson(Map<String, dynamic> json) {
    return NavShieldState(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      eastVelocity: (json['east_velocity'] as num?)?.toDouble() ?? 0.0,
      northVelocity: (json['north_velocity'] as num?)?.toDouble() ?? 0.0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      uncertaintyEllipse: json['uncertainty_ellipse'] != null
          ? UncertaintyEllipse.fromJson(json['uncertainty_ellipse'] as Map<String, dynamic>)
          : const UncertaintyEllipse(semiMajorAxis: 4.0, semiMinorAxis: 2.5, orientation: 0.0),
      currentMode: NavMode.fromString(json['current_mode'] as String? ?? 'GNSS_AIDED'),
      timeInCurrentMode: (json['time_in_current_mode'] as num?)?.toInt() ?? 0,
      crashDetected: json['crash_detected'] as bool? ?? false,
      crashConfidence: (json['crash_confidence'] as num?)?.toDouble() ?? 0.0,
      impactMagnitude: (json['impact_magnitude'] as num?)?.toDouble() ?? 0.0,
      sosActive: json['sos_active'] as bool? ?? false,
      sosCountdownSeconds: (json['sos_countdown_seconds'] as num?)?.toInt() ?? 30,
      alignmentStatus: AlignmentStatus.fromString(json['alignment_status'] as String? ?? 'CALIBRATED'),
      distanceTraveledKm: (json['distance_traveled_km'] as num?)?.toDouble() ?? 0.0,
      driftEstimatePercent: (json['drift_estimate_percent'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'east_velocity': eastVelocity,
    'north_velocity': northVelocity,
    'heading': heading,
    'uncertainty_ellipse': uncertaintyEllipse.toJson(),
    'current_mode': currentMode.value,
    'time_in_current_mode': timeInCurrentMode,
    'crash_detected': crashDetected,
    'crash_confidence': crashConfidence,
    'impact_magnitude': impactMagnitude,
    'sos_active': sosActive,
    'sos_countdown_seconds': sosCountdownSeconds,
    'alignment_status': alignmentStatus.value,
    'distance_traveled_km': distanceTraveledKm,
    'drift_estimate_percent': driftEstimatePercent,
    'timestamp': timestamp.toIso8601String(),
  };

  NavShieldState copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? eastVelocity,
    double? northVelocity,
    double? heading,
    UncertaintyEllipse? uncertaintyEllipse,
    NavMode? currentMode,
    int? timeInCurrentMode,
    bool? crashDetected,
    double? crashConfidence,
    double? impactMagnitude,
    bool? sosActive,
    int? sosCountdownSeconds,
    AlignmentStatus? alignmentStatus,
    double? distanceTraveledKm,
    double? driftEstimatePercent,
    DateTime? timestamp,
  }) {
    return NavShieldState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      eastVelocity: eastVelocity ?? this.eastVelocity,
      northVelocity: northVelocity ?? this.northVelocity,
      heading: heading ?? this.heading,
      uncertaintyEllipse: uncertaintyEllipse ?? this.uncertaintyEllipse,
      currentMode: currentMode ?? this.currentMode,
      timeInCurrentMode: timeInCurrentMode ?? this.timeInCurrentMode,
      crashDetected: crashDetected ?? this.crashDetected,
      crashConfidence: crashConfidence ?? this.crashConfidence,
      impactMagnitude: impactMagnitude ?? this.impactMagnitude,
      sosActive: sosActive ?? this.sosActive,
      sosCountdownSeconds: sosCountdownSeconds ?? this.sosCountdownSeconds,
      alignmentStatus: alignmentStatus ?? this.alignmentStatus,
      distanceTraveledKm: distanceTraveledKm ?? this.distanceTraveledKm,
      driftEstimatePercent: driftEstimatePercent ?? this.driftEstimatePercent,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
