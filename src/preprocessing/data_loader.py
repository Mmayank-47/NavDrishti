"""
src/preprocessing/data_loader.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Robust IO-VNBD dataset loader, session synchronization, and feature extraction.
─────────────────────────────────────────────────────────────────────────────
"""

import os
import yaml
from pathlib import Path
import numpy as np
import pandas as pd

from src.preprocessing.frame_transform import geodetic_to_enu, STANDARD_GRAVITY
from src.preprocessing.imu_preprocessor import IMUPreprocessor


class IOVNBDLoader:
    """
    Unified loader for the primary IO-VNBD (Inertial and Odometry Vehicle
    Navigation Benchmark Dataset).
    
    Pairs Smartphone (S-*.csv) and Vehicle (V-*.csv) synchronized records,
    resolves character encodings, strips whitespace from headers,
    computes local ENU trajectories, and partitions data by driver.
    """

    # Pre-defined split per Section 9 and dataset audit
    SPLIT_CONFIG = {
        'train': ['M (Driver B)', 'Vf (Driver E)', 'Vta (Driver E)', 'Vtb (Driver E)', 'Vw (Driver E)'],
        'val':   ['Y (Driver D)'],
        'test':  ['S (Driver A)'],
    }

    def __init__(self, data_root=None, config_path="configs/paths.yaml"):
        if data_root is None:
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    cfg = yaml.safe_load(f)
                data_root = cfg['datasets']['io_vnbd']['synchronised']
            else:
                data_root = "data/IO-VNBD/Synchronised V abd S datasets/Categorised IOVNB Dataset"

        self.root = Path(data_root)
        if not self.root.exists():
            # Try searching up relative to repo
            alt = Path(os.getcwd()) / data_root
            if alt.exists():
                self.root = alt
            else:
                raise FileNotFoundError(f"IO-VNBD root directory not found at: {self.root}")

        self.sessions = self._discover_sessions()

    def _discover_sessions(self):
        """Find all paired S-*.csv and V-*.csv sessions across driver subfolders."""
        sessions = {}
        for s_file in self.root.rglob("S-*.csv"):
            stem = s_file.stem[2:]  # Remove 'S-' prefix
            v_file = s_file.parent / f"V-{stem}.csv"
            
            # The top-level folder under self.root is the driver directory (e.g. 'Y (Driver D)')
            rel_parts = s_file.relative_to(self.root).parts
            driver = rel_parts[0] if len(rel_parts) > 0 else s_file.parent.name

            # Determine split
            split = 'train'
            for sp, drvs in self.SPLIT_CONFIG.items():
                if any(d in driver for d in drvs):
                    split = sp
                    break

            sessions[stem] = {
                'stem': stem,
                'driver': driver,
                'session_dir': s_file.parent.name,
                'split': split,
                'smartphone_file': s_file,
                'vehicle_file': v_file if v_file.exists() else None
            }
        return sessions

    def get_session_names(self, split=None):
        """Return list of session stems, optionally filtered by split ('train', 'val', 'test')."""
        if split is None:
            return sorted(list(self.sessions.keys()))
        return sorted([k for k, v in self.sessions.items() if v['split'] == split])

    def load_raw_csv(self, file_path):
        """Load CSV with automatic fallback from UTF-8 to Latin-1 encoding."""
        try:
            df = pd.read_csv(file_path, low_memory=False)
        except UnicodeDecodeError:
            df = pd.read_csv(file_path, low_memory=False, encoding='latin1')
        df.columns = [c.strip() for c in df.columns]
        return df

    def load_session(self, session_stem, preprocess_imu=True):
        """
        Load a complete synchronized session by stem (e.g. 'M', 'S1', 'Vfa01').
        
        Returns a rich dictionary containing:
          - imu: accel, gyro, gravity, mag, orientation (Euler)
          - gnss: lat, lon, alt, speed_mps, accuracy_m, heading_deg
          - vehicle: speed_mps, lon_accel, lat_accel, wheel_speeds, engine_rpm
          - enu_coords: (e, n, u) metric coordinates relative to first GNSS fix
          - timestamps: time_s
          - zupt_mask: stationary detector flags
        """
        if session_stem not in self.sessions:
            raise KeyError(f"Session '{session_stem}' not found. Available: {self.get_session_names()[:10]}...")

        meta = self.sessions[session_stem]
        df_s = self.load_raw_csv(meta['smartphone_file'])
        df_v = self.load_raw_csv(meta['vehicle_file']) if meta['vehicle_file'] else None

        # Harmonize length
        min_len = len(df_s)
        if df_v is not None:
            min_len = min(min_len, len(df_v))
        df_s = df_s.iloc[:min_len].copy()
        if df_v is not None:
            df_v = df_v.iloc[:min_len].copy()

        # ── Extract Smartphone IMU channels ──
        # Accel [m/s^2]
        acc_x = df_s.get('ACCELEROMETER X (m/s²)', df_s.get('ACCELEROMETER X (m/s\xb2)', df_s.iloc[:, 9]))
        acc_y = df_s.get('ACCELEROMETER Y (m/s²)', df_s.get('ACCELEROMETER Y (m/s\xb2)', df_s.iloc[:, 10]))
        acc_z = df_s.get('ACCELEROMETER Z (m/s²)', df_s.get('ACCELEROMETER Z (m/s\xb2)', df_s.iloc[:, 11]))
        accel_raw = np.column_stack([acc_x, acc_y, acc_z]).astype(np.float64)

        # Gyro [rad/s] (Yaw, Pitch, Roll in data)
        gyr_yaw   = df_s.get('GYROSCOPE Yaw (rad/s)', df_s.iloc[:, 15])
        gyr_pitch = df_s.get('GYROSCOPE Pitch (rad/s)', df_s.iloc[:, 16])
        gyr_roll  = df_s.get('GYROSCOPE Roll (rad/s)', df_s.iloc[:, 17])
        gyro_raw  = np.column_stack([gyr_roll, gyr_pitch, gyr_yaw]).astype(np.float64)

        # Gravity [m/s^2]
        grav_x = df_s.get('GRAVITY X (m/s²)', df_s.get('GRAVITY X (m/s\xb2)', df_s.iloc[:, 12]))
        grav_y = df_s.get('GRAVITY Y (m/s²)', df_s.get('GRAVITY Y (m/s\xb2)', df_s.iloc[:, 13]))
        grav_z = df_s.get('GRAVITY Z (m/s²)', df_s.get('GRAVITY Z (m/s\xb2)', df_s.iloc[:, 14]))
        gravity_raw = np.column_stack([grav_x, grav_y, grav_z]).astype(np.float64)

        # Magnetometer [μT]
        mag_x = df_s.get('MAGNETIC FIELD X (μT)', df_s.get('MAGNETIC FIELD X (\u03bcT)', df_s.iloc[:, 18]))
        mag_y = df_s.get('MAGNETIC FIELD Y (μT)', df_s.get('MAGNETIC FIELD Y (\u03bcT)', df_s.iloc[:, 19]))
        mag_z = df_s.get('MAGNETIC FIELD Z (μT)', df_s.get('MAGNETIC FIELD Z (\u03bcT)', df_s.iloc[:, 20]))
        mag_raw = np.column_stack([mag_x, mag_y, mag_z]).astype(np.float64)

        # Phone Orientation angles [deg]
        ori_yaw   = df_s.get('ORIENTATION (Yaw) (°)', df_s.iloc[:, 21])
        ori_pitch = df_s.get('ORIENTATION (Pitch) (°)', df_s.iloc[:, 22])
        ori_roll  = df_s.get('ORIENTATION (Roll ) (°)', df_s.iloc[:, 23])
        ori_euler_deg = np.column_stack([ori_roll, ori_pitch, ori_yaw]).astype(np.float64)

        # Timestamps (convert ms to seconds)
        t_ms = pd.to_numeric(df_s.iloc[:, 7], errors='coerce').fillna(0).values
        time_s = (t_ms - t_ms[0]) / 1000.0

        # GNSS fields from phone
        lat = pd.to_numeric(df_s.iloc[:, 0], errors='coerce').values
        lon = pd.to_numeric(df_s.iloc[:, 1], errors='coerce').values
        alt = pd.to_numeric(df_s.iloc[:, 2], errors='coerce').values
        gps_speed_mps = pd.to_numeric(df_s.iloc[:, 3], errors='coerce').values / 3.6  # km/h -> m/s
        gps_acc_m = pd.to_numeric(df_s.iloc[:, 4], errors='coerce').values
        gps_heading = pd.to_numeric(df_s.iloc[:, 5], errors='coerce').values

        # Local ENU projection relative to first valid coordinate
        valid_idx = np.where(~np.isnan(lat) & ~np.isnan(lon) & (lat != 0))[0]
        if len(valid_idx) > 0:
            i0 = valid_idx[0]
            lat0, lon0, alt0 = lat[i0], lon[i0], alt[i0] if not np.isnan(alt[i0]) else 0.0
            enu_coords = geodetic_to_enu(lat, lon, np.nan_to_num(alt, nan=alt0), lat0, lon0, alt0)
        else:
            lat0, lon0, alt0 = 0.0, 0.0, 0.0
            enu_coords = np.zeros((min_len, 3))

        # ── Extract Vehicle CAN-bus reference ──
        veh_speed_mps = None
        veh_lon_accel = None
        veh_lat_accel = None
        if df_v is not None:
            # Vehicle speed (Column 'Indicated Vehicle Speed (km/hr)' or col 11)
            veh_spd_col = [c for c in df_v.columns if 'vehicle speed' in c.lower()]
            if veh_spd_col:
                veh_speed_mps = pd.to_numeric(df_v[veh_spd_col[0]], errors='coerce').values / 3.6
            else:
                veh_speed_mps = pd.to_numeric(df_v.iloc[:, 11], errors='coerce').values / 3.6

            lon_acc_col = [c for c in df_v.columns if 'longitudinal' in c.lower()]
            if lon_acc_col:
                veh_lon_accel = pd.to_numeric(df_v[lon_acc_col[0]], errors='coerce').values * STANDARD_GRAVITY

            lat_acc_col = [c for c in df_v.columns if 'lateral' in c.lower()]
            if lat_acc_col:
                veh_lat_accel = pd.to_numeric(df_v[lat_acc_col[0]], errors='coerce').values * STANDARD_GRAVITY

        # Preprocess IMU (filtering, vibration suppression, ZUPT)
        preproc_data = None
        if preprocess_imu:
            preprocessor = IMUPreprocessor(sampling_rate_hz=10.0)
            preproc_data = preprocessor.process(accel_raw, gyro_raw, gravity_raw=gravity_raw)

        return {
            'stem': session_stem,
            'driver': meta['driver'],
            'split': meta['split'],
            'length': min_len,
            'time_s': time_s,
            'accel_raw': accel_raw,
            'gyro_raw': gyro_raw,
            'gravity_raw': gravity_raw,
            'mag_raw': mag_raw,
            'euler_deg': ori_euler_deg,
            'accel_linear': preproc_data['accel_linear'] if preproc_data else (accel_raw - gravity_raw),
            'accel_filtered': preproc_data['accel_filtered'] if preproc_data else accel_raw,
            'gyro_filtered': preproc_data['gyro_filtered'] if preproc_data else gyro_raw,
            'zupt_mask': preproc_data['zupt_mask'] if preproc_data else np.zeros(min_len, dtype=bool),
            'gps': {
                'lat': lat,
                'lon': lon,
                'alt': alt,
                'speed_mps': gps_speed_mps,
                'accuracy_m': gps_acc_m,
                'heading_deg': gps_heading,
                'lat0': lat0,
                'lon0': lon0,
                'alt0': alt0,
            },
            'enu_coords': enu_coords,
            'vehicle': {
                'speed_mps': veh_speed_mps,
                'lon_accel_mps2': veh_lon_accel,
                'lat_accel_mps2': veh_lat_accel,
            }
        }
