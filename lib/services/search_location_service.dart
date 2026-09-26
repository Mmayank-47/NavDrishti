import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Destination Search result item model
class SearchLocation {
  final String id;
  final String name;
  final String subtitle;
  final String category;
  final LatLng point;
  final IconData icon;
  final double? distanceKm;

  const SearchLocation({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.point,
    required this.icon,
    this.distanceKm,
  });

  SearchLocation withDistance(double km) {
    return SearchLocation(
      id: id,
      name: name,
      subtitle: subtitle,
      category: category,
      point: point,
      icon: icon,
      distanceKm: km,
    );
  }
}

/// Service providing typed destination search with a rich set of demo locations.
///
/// Designed with a decoupled architecture so substituting a live geocoding API
/// (Mapbox Geocoding, Google Places, Photon/OSM Nominatim) requires changing only
/// this service's query backend.
class SearchLocationService {
  static const Distance _distance = Distance();

  // Curated Bengaluru landmarks and common destinations
  static final List<SearchLocation> _demoDatabase = [
    const SearchLocation(
      id: 'mg_road_metro',
      name: 'MG Road Metro Station',
      subtitle: 'Kasturba Rd & MG Rd Junction · Central Bengaluru',
      category: 'Transit',
      point: LatLng(12.9756, 77.6066),
      icon: Icons.subway_rounded,
    ),
    const SearchLocation(
      id: 'kanteerava_stadium',
      name: 'Kanteerava Indoor Stadium',
      subtitle: 'Kasturba Rd, Sampangi Rama Nagar',
      category: 'Sports & Arena',
      point: LatLng(12.9698, 77.5926),
      icon: Icons.stadium_rounded,
    ),
    const SearchLocation(
      id: 'indiranagar_100ft',
      name: 'Indiranagar 100ft Road',
      subtitle: 'Defense Colony, HAL 2nd Stage',
      category: 'Commercial',
      point: LatLng(12.9784, 77.6408),
      icon: Icons.shopping_bag_rounded,
    ),
    const SearchLocation(
      id: 'lalbagh_botanical',
      name: 'Lalbagh Botanical Garden',
      subtitle: 'Mavalli, Hosur Main Rd',
      category: 'Park & Nature',
      point: LatLng(12.9507, 77.5848),
      icon: Icons.park_rounded,
    ),
    const SearchLocation(
      id: 'uvce_campus',
      name: 'UVCE College Campus',
      subtitle: 'K.R. Circle, Ambedkar Veedhi',
      category: 'Education',
      point: LatLng(12.9734, 77.5855),
      icon: Icons.school_rounded,
    ),
    const SearchLocation(
      id: 'vidhana_soudha',
      name: 'Vidhana Soudha',
      subtitle: 'Dr Ambedkar Veedhi, Sampangi Rama Nagar',
      category: 'Government Landmark',
      point: LatLng(12.9796, 77.5907),
      icon: Icons.account_balance_rounded,
    ),
    const SearchLocation(
      id: 'majestic_station',
      name: 'Kempegowda Bus Station (Majestic)',
      subtitle: 'Subhash Nagar, Tank Bund Rd',
      category: 'Transit Hub',
      point: LatLng(12.9778, 77.5724),
      icon: Icons.directions_bus_rounded,
    ),
    const SearchLocation(
      id: 'commercial_street',
      name: 'Commercial Street',
      subtitle: 'Tasker Town, Shivaji Nagar',
      category: 'Shopping & Dining',
      point: LatLng(12.9822, 77.6083),
      icon: Icons.storefront_rounded,
    ),
    const SearchLocation(
      id: 'koramangala_sony',
      name: 'Koramangala 5th Block (Sony Signal)',
      subtitle: '80 Feet Rd, 5th Block, Koramangala',
      category: 'Commercial & Tech',
      point: LatLng(12.9345, 77.6253),
      icon: Icons.business_center_rounded,
    ),
    const SearchLocation(
      id: 'brigade_road',
      name: 'Brigade Road Junction',
      subtitle: 'Shanthala Nagar, Ashok Nagar',
      category: 'Shopping District',
      point: LatLng(12.9738, 77.6074),
      icon: Icons.local_activity_rounded,
    ),
    const SearchLocation(
      id: 'ub_city',
      name: 'UB City Luxury Mall',
      subtitle: '24 Vittal Mallya Rd, KG Halli',
      category: 'Mall & Underground Parking',
      point: LatLng(12.9719, 77.5958),
      icon: Icons.local_parking_rounded,
    ),
    const SearchLocation(
      id: 'cubbon_park_metro',
      name: 'Cubbon Park Metro Station',
      subtitle: 'Kasturba Rd, Near Chinnaswamy Stadium',
      category: 'Transit',
      point: LatLng(12.9810, 77.5982),
      icon: Icons.subway_rounded,
    ),
    const SearchLocation(
      id: 'bangalore_palace',
      name: 'Bangalore Palace',
      subtitle: 'Vasanth Nagar, Armane Nagar',
      category: 'Heritage & Tourism',
      point: LatLng(12.9988, 77.5921),
      icon: Icons.fort_rounded,
    ),
  ];

  /// Performs substring search against demo database.
  /// If [query] is empty, returns all locations sorted by distance or default order.
  static List<SearchLocation> search(
    String query, {
    LatLng? userPosition,
  }) {
    final cleanQuery = query.trim().toLowerCase();

    List<SearchLocation> results;
    if (cleanQuery.isEmpty) {
      results = List.of(_demoDatabase);
    } else {
      results = _demoDatabase.where((loc) {
        final nameMatch = loc.name.toLowerCase().contains(cleanQuery);
        final subMatch = loc.subtitle.toLowerCase().contains(cleanQuery);
        final catMatch = loc.category.toLowerCase().contains(cleanQuery);
        return nameMatch || subMatch || catMatch;
      }).toList();
    }

    if (userPosition != null) {
      results = results.map((loc) {
        final distMeters = _distance(userPosition, loc.point);
        return loc.withDistance(distMeters / 1000.0);
      }).toList();

      results.sort((a, b) {
        if (a.distanceKm == null || b.distanceKm == null) return 0;
        return a.distanceKm!.compareTo(b.distanceKm!);
      });
    }

    return results;
  }

  /// Returns all available demo locations
  static List<SearchLocation> getAll() => List.unmodifiable(_demoDatabase);
}
