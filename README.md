# NAV-SHIELD Mobile Frontend (Flutter + Android)

> **Smart India Hackathon PS 26168**  
> AI/ML-based Intelligent Dead Reckoning for GNSS-Denied Urban Navigation & High-G Crash/SOS Coordination.

---

## Architecture Overview

1. **State & Telemetry Provider**: 10Hz unified stream (`NavShieldState`) with position, velocities, heading, covariance uncertainty ellipse, navigation mode (`GNSS_AIDED`, `DEAD_RECKONING`, `DEGRADED`), and crash/SOS telemetry.
2. **Hybrid Engine Layer**: Polymorphic service (`HybridNavShieldDataService`) enabling real-time toggling between:
   - **Offline Mock Generator**: Realistic simulated driving loop with periodic GNSS blackouts, uncertainty growth, and mock crashes.
   - **Real Python Backend**: Live WebSocket connection to NavDrishti Python engine (`ws://10.0.2.2:8765` on Android emulator or local IP).
3. **Map Rendering & Visuals**:
   - **Mapbox Vector Maps (`mapbox_maps_flutter`)**: Light and Dark vector map styles (`MapboxStyles.LIGHT` and `MapboxStyles.DARK`), vector polylines, and smooth camera navigation.
   - **Graceful Fallback**: If a Mapbox token is not configured or fails, renders OpenStreetMap fallback with an informational setup banner, preventing app crashes.
   - **Confidence Halo**: Constant flat opacity (30% fill / 65% stroke) with instantaneous discrete color swapping between modes.
   - **Vehicle Markers**: 60fps heading interpolation with Arrow, 3D Car, and 3D Bike isometric vector painters.

---

## 1. Mapbox Access Token Setup

To enable Mapbox vector maps:

1. Create a free account at [account.mapbox.com](https://account.mapbox.com/) and copy your **Default Public Token** (starts with `pk.`).
2. Copy the template configuration:
   ```bash
   cp lib/config/mapbox_config.template.dart lib/config/mapbox_config.dart
   ```
3. Open `lib/config/mapbox_config.dart` and paste your token:
   ```dart
   const String mapboxAccessToken = 'pk.eyJ1IjoieW91ci11c2VybmFtZSIsImEiOiJ...';
   ```
   *(Note: `lib/config/mapbox_config.dart` is gitignored to protect private API keys).*
4. Alternatively, pass via dart define during build:
   ```bash
   flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here
   ```

If no valid token is provided, NAV-SHIELD automatically displays a setup banner and renders fallback tiles without interrupting navigation.

---

## 2. Running the Python Backend (NavDrishti)

To stream real-time sensor fusion and crash detection from the Python backend:

```bash
cd /path/to/NavDrishti

# Install requirements
pip install -r requirements.txt
pip install websockets

# (Optional) Configure Mapbox Token for dynamic route re-fetching:
# PowerShell:  $env:MAPBOX_ACCESS_TOKEN="pk.your_token_here"
# Linux/macOS: export MAPBOX_ACCESS_TOKEN="pk.your_token_here"
# (By default, the server runs 100% offline using the pre-cached 7.1km Bengaluru road circuit in bengaluru_demo_route.json)

# Start the 10Hz WebSocket streaming server
python src/server/nav_shield_ws_server.py
```

The server binds to `0.0.0.0:8765` and broadcasts 10Hz `NavShieldState` packets following real Bengaluru street routes with realistic sensor noise and 30s/20s GNSS outage cycling.

---

## 3. Running the Flutter App

### On Android Emulator:
```bash
flutter run
```
- When using the Android Emulator, the app connects to the host machine's Python server via `ws://10.0.2.2:8765`.
- Switch between the Mock Generator and Live Python Engine in **Settings -> NAV-SHIELD ENGINE** or via the **Debug Menu**.

### On Physical Device:
- Ensure phone and host machine are on the same Wi-Fi network.
- In **Settings -> NAV-SHIELD ENGINE -> Server Endpoint**, set the IP to your host's local IP (e.g. `ws://192.168.1.100:8765`).

---

## 4. Test Suite

Run unit and widget tests:
```bash
flutter test
```
All 18+ tests verify model serialization, trip lifecycle, theme transitions, confidence halo properties, and UI components.
