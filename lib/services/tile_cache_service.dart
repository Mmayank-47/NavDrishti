/// Scaffold for offline tile caching in NAV-SHIELD.
///
/// Pre-structured for bundling or storing OpenStreetMap tiles locally (e.g. SQLite / MBTiles)
/// so dead-reckoning navigation functions seamlessly without cellular reception.
abstract class TileCacheService {
  /// Checks whether tile (z, x, y) is cached locally
  Future<bool> hasCachedTile(int z, int x, int y);

  /// Retrieves local file path or byte buffer for tile
  Future<String?> getCachedTilePath(int z, int x, int y);

  /// Downloads and caches a region bounding box for offline use
  Future<void> prefetchRegion({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
  });
}

/// Default implementation fallback that uses standard OSM network tile provider
class DefaultTileCacheService implements TileCacheService {
  @override
  Future<bool> hasCachedTile(int z, int x, int y) async => false;

  @override
  Future<String?> getCachedTilePath(int z, int x, int y) async => null;

  @override
  Future<void> prefetchRegion({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
  }) async {
    // TODO: Scaffold for caching tiles to path_provider app storage
  }
}
