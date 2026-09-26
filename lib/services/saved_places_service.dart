import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model representing an editable quick-access shortcut chip
class SavedPlace {
  final String id;
  final String title;
  final String name;
  final String address;
  final LatLng point;
  final bool isConfigured;
  final IconData icon;
  final Color colorLight;
  final Color colorDark;

  const SavedPlace({
    required this.id,
    required this.title,
    required this.name,
    required this.address,
    required this.point,
    required this.isConfigured,
    required this.icon,
    required this.colorLight,
    required this.colorDark,
  });

  SavedPlace copyWith({
    String? title,
    String? name,
    String? address,
    LatLng? point,
    bool? isConfigured,
    IconData? icon,
    Color? colorLight,
    Color? colorDark,
  }) {
    return SavedPlace(
      id: id,
      title: title ?? this.title,
      name: name ?? this.name,
      address: address ?? this.address,
      point: point ?? this.point,
      isConfigured: isConfigured ?? this.isConfigured,
      icon: icon ?? this.icon,
      colorLight: colorLight ?? this.colorLight,
      colorDark: colorDark ?? this.colorDark,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'name': name,
        'address': address,
        'lat': point.latitude,
        'lng': point.longitude,
        'is_configured': isConfigured,
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json, SavedPlace template) {
    return template.copyWith(
      title: json['title'] as String?,
      name: json['name'] as String?,
      address: json['address'] as String?,
      point: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      isConfigured: json['is_configured'] as bool? ?? true,
    );
  }
}

/// Service managing persistent editable Saved Places chips (Home, College, Work, More)
class SavedPlacesService extends ChangeNotifier {
  static const String _prefKey = 'nav_shield_saved_places_v1';

  static final List<SavedPlace> _defaultPlaces = [
    const SavedPlace(
      id: 'home',
      title: 'Home',
      name: 'Home (Lavelle Rd)',
      address: 'Lavelle Rd, Shanthala Nagar, Bengaluru',
      point: LatLng(12.971598, 77.594566),
      isConfigured: true,
      icon: Icons.home_rounded,
      colorLight: Color(0xFF384F95),
      colorDark: Color(0xFFA6BAEE),
    ),
    const SavedPlace(
      id: 'college',
      title: 'College',
      name: 'UVCE College Campus',
      address: 'K.R. Circle, Dr Ambedkar Veedhi, Bengaluru',
      point: LatLng(12.9734, 77.5855),
      isConfigured: true,
      icon: Icons.school_rounded,
      colorLight: Color(0xFF8E68A9),
      colorDark: Color(0xFFBC7EBF),
    ),
    const SavedPlace(
      id: 'work',
      title: 'Work',
      name: 'MG Road Metro Station',
      address: 'MG Road, Ashok Nagar, Bengaluru',
      point: LatLng(12.9756, 77.6066),
      isConfigured: true,
      icon: Icons.work_rounded,
      colorLight: Color(0xFF203B6F),
      colorDark: Color(0xFFDBC9F9),
    ),
    const SavedPlace(
      id: 'more',
      title: 'More',
      name: 'Kanteerava Stadium',
      address: 'Kasturba Rd, Sampangi Rama Nagar, Bengaluru',
      point: LatLng(12.9698, 77.5926),
      isConfigured: true,
      icon: Icons.bookmark_rounded,
      colorLight: Color(0xFF312048),
      colorDark: Color(0xFFC792EA),
    ),
  ];

  List<SavedPlace> _places = List.of(_defaultPlaces);

  List<SavedPlace> get places => List.unmodifiable(_places);

  SavedPlace? getPlaceById(String id) {
    try {
      return _places.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loaded = <SavedPlace>[];
        for (final item in decoded) {
          final map = item as Map<String, dynamic>;
          final id = map['id'] as String?;
          final template = _defaultPlaces.firstWhere(
            (p) => p.id == id,
            orElse: () => _defaultPlaces.first,
          );
          loaded.add(SavedPlace.fromJson(map, template));
        }
        if (loaded.isNotEmpty) {
          _places = loaded;
        }
      }
    } catch (e) {
      debugPrint('[SavedPlacesService] Failed to load places: $e');
    }
    notifyListeners();
  }

  Future<void> updatePlace(
    String id, {
    required String name,
    required String address,
    required LatLng point,
    String? title,
  }) async {
    final idx = _places.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _places[idx] = _places[idx].copyWith(
        name: name,
        address: address,
        point: point,
        title: title,
        isConfigured: true,
      );
      notifyListeners();
      await _persist();
    }
  }

  Future<void> clearPlace(String id) async {
    final idx = _places.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final def = _defaultPlaces[idx];
      _places[idx] = def.copyWith(
        name: 'Tap to set ${def.title}',
        address: 'No location selected',
        isConfigured: false,
      );
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_places.map((p) => p.toJson()).toList());
      await prefs.setString(_prefKey, raw);
    } catch (e) {
      debugPrint('[SavedPlacesService] Failed to persist places: $e');
    }
  }
}
