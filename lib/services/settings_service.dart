import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  static AppThemePreference fromString(String? val) {
    if (val == 'light') return AppThemePreference.light;
    if (val == 'dark') return AppThemePreference.dark;
    return AppThemePreference.system;
  }
}

enum ImuSource {
  phoneSensors('Phone Sensors (In-app)'),
  externalImu('External Edge IMU (NAV-SHIELD)');

  final String label;
  const ImuSource(this.label);

  static ImuSource fromString(String? val) {
    if (val == 'external') return ImuSource.externalImu;
    return ImuSource.phoneSensors;
  }
}

enum VehicleIconStyle {
  arrow('Arrow (Directional)'),
  car('3D Car (Automobile)'),
  bike('3D Bike (Two-Wheeler)');

  final String label;
  const VehicleIconStyle(this.label);

  static VehicleIconStyle fromString(String? val) {
    if (val == 'car') return VehicleIconStyle.car;
    if (val == 'bike') return VehicleIconStyle.bike;
    return VehicleIconStyle.arrow;
  }
}

class HaloColorOption {
  final String name;
  final Color color;
  const HaloColorOption(this.name, this.color);
}

/// Curated palette strictly excluding red and red-adjacent hues
/// to preserve "red means SOS/crash only".
const List<HaloColorOption> kAllowedHaloColors = [
  HaloColorOption('Default Blue', Color(0xFF2563EB)),
  HaloColorOption('Cyan', Color(0xFF06B6D4)),
  HaloColorOption('Teal', Color(0xFF0D9488)),
  HaloColorOption('Emerald', Color(0xFF059669)),
  HaloColorOption('Lime', Color(0xFF65A30D)),
  HaloColorOption('Gold', Color(0xFFCA8A04)),
  HaloColorOption('Amber', Color(0xFFD97706)),
  HaloColorOption('Purple', Color(0xFF9333EA)),
  HaloColorOption('Violet', Color(0xFF7C3AED)),
  HaloColorOption('Indigo', Color(0xFF4F46E5)),
];

class SettingsService extends ChangeNotifier {
  static const String _keyThemeMode = 'nav_shield_theme_mode';
  static const String _keyImuSource = 'nav_shield_imu_source';
  static const String _keyMetricUnits = 'nav_shield_metric_units';
  static const String _keyVehicleIcon = 'nav_shield_vehicle_icon';
  static const String _keyGnssHaloColor = 'nav_shield_gnss_halo_color';
  static const String _keyDrHaloColor = 'nav_shield_dr_halo_color';
  static const String _keyBackendHost = 'nav_shield_backend_host';
  static const String _keyBackendPort = 'nav_shield_backend_port';
  static const String _keyUseRealBackend = 'nav_shield_use_real_backend';
  static const String _keyEmergencyContactName = 'nav_shield_emergency_contact_name';
  static const String _keyEmergencyContactPhone = 'nav_shield_emergency_contact_phone';
  static const String _keyEmergencyContactRelation = 'nav_shield_emergency_contact_relation';
  static const String _keyVoiceGuidanceMuted = 'nav_shield_voice_guidance_muted';

  AppThemePreference _themePreference = AppThemePreference.system;
  ImuSource _imuSource = ImuSource.phoneSensors;
  bool _useMetricUnits = true;
  VehicleIconStyle _vehicleIconStyle = VehicleIconStyle.arrow;
  Color? _customGnssColor;
  Color? _customDrColor;
  String _backendHost = '10.0.2.2';
  int _backendPort = 8765;
  bool _useRealBackend = false;

  // Emergency Contact (persisted locally)
  String _emergencyContactName = '';
  String _emergencyContactPhone = '';
  String _emergencyContactRelation = '';

  // Voice Guidance (Mute/Unmute state)
  bool _voiceGuidanceMuted = false;

  AppThemePreference get themePreference => _themePreference;
  ImuSource get imuSource => _imuSource;
  bool get useMetricUnits => _useMetricUnits;
  VehicleIconStyle get vehicleIconStyle => _vehicleIconStyle;
  Color? get customGnssColor => _customGnssColor;
  Color? get customDrColor => _customDrColor;
  String get backendHost => _backendHost;
  int get backendPort => _backendPort;
  bool get useRealBackend => _useRealBackend;

  String get emergencyContactName => _emergencyContactName;
  String get emergencyContactPhone => _emergencyContactPhone;
  String get emergencyContactRelation => _emergencyContactRelation;
  bool get hasEmergencyContact =>
      _emergencyContactName.trim().isNotEmpty && _emergencyContactPhone.trim().isNotEmpty;

  bool get voiceGuidanceMuted => _voiceGuidanceMuted;

  ThemeMode get themeMode {
    switch (_themePreference) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
      case AppThemePreference.system:
        return ThemeMode.system;
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _themePreference = AppThemePreference.fromString(prefs.getString(_keyThemeMode));
    _imuSource = ImuSource.fromString(prefs.getString(_keyImuSource));
    _useMetricUnits = prefs.getBool(_keyMetricUnits) ?? true;
    _vehicleIconStyle = VehicleIconStyle.fromString(prefs.getString(_keyVehicleIcon));
    _backendHost = prefs.getString(_keyBackendHost) ?? '10.0.2.2';
    _backendPort = prefs.getInt(_keyBackendPort) ?? 8765;
    _useRealBackend = prefs.getBool(_keyUseRealBackend) ?? false;

    _emergencyContactName =
        prefs.getString(_keyEmergencyContactName) ?? '';
    _emergencyContactPhone =
        prefs.getString(_keyEmergencyContactPhone) ?? '';
    _emergencyContactRelation =
        prefs.getString(_keyEmergencyContactRelation) ?? '';

    _voiceGuidanceMuted = prefs.getBool(_keyVoiceGuidanceMuted) ?? false;

    final gnssColorVal = prefs.getInt(_keyGnssHaloColor);
    if (gnssColorVal != null) {
      _customGnssColor = Color(gnssColorVal);
    }
    final drColorVal = prefs.getInt(_keyDrHaloColor);
    if (drColorVal != null) {
      _customDrColor = Color(drColorVal);
    }

    notifyListeners();
  }

  Future<void> setEmergencyContact({
    required String name,
    required String phone,
    String relation = 'Emergency Contact',
  }) async {
    _emergencyContactName = name.trim();
    _emergencyContactPhone = phone.trim();
    _emergencyContactRelation = relation.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmergencyContactName, _emergencyContactName);
    await prefs.setString(_keyEmergencyContactPhone, _emergencyContactPhone);
    await prefs.setString(_keyEmergencyContactRelation, _emergencyContactRelation);
  }

  Future<void> clearEmergencyContact() async {
    _emergencyContactName = '';
    _emergencyContactPhone = '';
    _emergencyContactRelation = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmergencyContactName);
    await prefs.remove(_keyEmergencyContactPhone);
    await prefs.remove(_keyEmergencyContactRelation);
  }

  Future<void> setVoiceGuidanceMuted(bool muted) async {
    _voiceGuidanceMuted = muted;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoiceGuidanceMuted, muted);
  }

  Future<void> toggleVoiceGuidance() async {
    await setVoiceGuidanceMuted(!_voiceGuidanceMuted);
  }

  Future<void> setThemePreference(AppThemePreference pref) async {
    _themePreference = pref;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, pref.name);
  }

  Future<void> setImuSource(ImuSource source) async {
    _imuSource = source;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyImuSource, source == ImuSource.externalImu ? 'external' : 'phone');
  }

  Future<void> setMetricUnits(bool metric) async {
    _useMetricUnits = metric;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMetricUnits, metric);
  }

  Future<void> setVehicleIconStyle(VehicleIconStyle style) async {
    _vehicleIconStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVehicleIcon, style.name);
  }

  Future<void> setBackendHost(String host) async {
    _backendHost = host.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendHost, _backendHost);
  }

  Future<void> setBackendPort(int port) async {
    _backendPort = port;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBackendPort, port);
  }

  Future<void> setUseRealBackend(bool useReal) async {
    _useRealBackend = useReal;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseRealBackend, useReal);
  }

  Future<void> setCustomGnssColor(Color? color) async {
    _customGnssColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_keyGnssHaloColor);
    } else {
      await prefs.setInt(_keyGnssHaloColor, color.toARGB32());
    }
  }

  Future<void> setCustomDrColor(Color? color) async {
    _customDrColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_keyDrHaloColor);
    } else {
      await prefs.setInt(_keyDrHaloColor, color.toARGB32());
    }
  }

  Future<void> resetHaloColors() async {
    _customGnssColor = null;
    _customDrColor = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGnssHaloColor);
    await prefs.remove(_keyDrHaloColor);
  }

  String formatDistance(double km) {
    if (_useMetricUnits) {
      return '${km.toStringAsFixed(1)} km';
    } else {
      final mi = km * 0.621371;
      return '${mi.toStringAsFixed(1)} mi';
    }
  }

  String formatSpeed(double kmh) {
    if (_useMetricUnits) {
      return '${kmh.toStringAsFixed(0)} km/h';
    } else {
      final mph = kmh * 0.621371;
      return '${mph.toStringAsFixed(0)} mph';
    }
  }
}
