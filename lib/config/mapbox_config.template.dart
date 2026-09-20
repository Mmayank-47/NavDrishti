/// Configuration template for Mapbox Maps SDK.
///
/// To use your own Mapbox account:
/// 1. Copy this file to `lib/config/mapbox_config.dart`.
/// 2. Replace the placeholder below with your Mapbox Public Access Token (pk.xxx).
/// 3. `lib/config/mapbox_config.dart` is excluded from git via `.gitignore` to protect your token.
///
/// Alternatively, you can supply your token at build/run time via:
/// `flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here`
library;

const String defaultMapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue: 'pk.placeholder_token_enter_your_token_in_mapbox_config_dart',
);
