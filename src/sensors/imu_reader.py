"""
src/sensors/imu_reader.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Layer 1: Raw Sensor Input
Handles 10 Hz IMU (accelerometer, gyroscope, optional magnetometer)
and 1 Hz GNSS data streams, data replay, and synthetic drive generation.
─────────────────────────────────────────────────────────────────────────────
"""

from dataclasses import dataclass
from typing import Optional, Dict, Generator, Tuple
import numpy as np

STANDARD_GRAVITY = 9.80665


@dataclass
class SensorReading:
    """Standardized multi-sensor reading packet."""
    timestamp: float
    accel_raw: np.ndarray        # [ax, ay, az] in m/s^2 (includes gravity)
    gyro_raw: np.ndarray         # [gx, gy, gz] in rad/s
    mag_raw: Optional[np.ndarray] = None  # [mx, my, mz] in uT (optional)
    gnss: Optional[Dict[str, float]] = None # {'lat': ..., 'lon': ..., 'speed': ..., 'heading': ...}


class IMUReader:
    """
    Streaming and batch reader for IMU sensors.
    Supports in-memory arrays, file playback (.npz, .csv), and replay generators.
    """

    def __init__(self, sampling_rate_hz: float = 10.0):
        self.fs = float(sampling_rate_hz)
        self.dt = 1.0 / self.fs

    def stream_from_arrays(
        self,
        accel_data: np.ndarray,
        gyro_data: np.ndarray,
        mag_data: Optional[np.ndarray] = None,
        gnss_data: Optional[list] = None,
        start_time: float = 0.0
    ) -> Generator[SensorReading, None, None]:
        """Yield sensor packets sample-by-sample."""
        N = len(accel_data)
        for i in range(N):
            t = start_time + i * self.dt
            mag = mag_data[i] if mag_data is not None and i < len(mag_data) else None
            gnss = gnss_data[i] if gnss_data is not None and i < len(gnss_data) else None

            yield SensorReading(
                timestamp=t,
                accel_raw=np.asarray(accel_data[i], dtype=np.float64),
                gyro_raw=np.asarray(gyro_data[i], dtype=np.float64),
                mag_raw=np.asarray(mag, dtype=np.float64) if mag is not None else None,
                gnss=gnss
            )

    def load_npz(self, filepath: str) -> Dict[str, np.ndarray]:
        """Load recorded IMU dataset from an .npz archive."""
        data = np.load(filepath)
        return {k: data[k] for k in data.files}


class SyntheticDriveGenerator:
    """
    Generates synthetic vehicle drives adhering to IO-VNBD sensor noise
    and real-world dynamics (stops, cruising, turns, mount angles).
    """

    def __init__(self, sampling_rate_hz: float = 10.0, seed: int = 42):
        self.fs = float(sampling_rate_hz)
        self.dt = 1.0 / self.fs
        self.rng = np.random.RandomState(seed)

    def generate_drive(
        self,
        duration_s: float = 600.0,
        mount_pitch_deg: float = 0.0,
        mount_roll_deg: float = 0.0,
        mount_yaw_deg: float = 0.0,
        accel_noise_std: float = 0.05,
        gyro_noise_std: float = 0.002,
        gyro_bias: Optional[np.ndarray] = None,
        initial_speed: float = 0.0
    ) -> Dict[str, np.ndarray]:
        """
        Generate a complete ground truth and apparent IMU trajectory.

        Vehicle coordinate frame:
          X: Forward, Y: Right (lateral), Z: Down (NED) or Up (ENU)
        """
        N = int(duration_s * self.fs)
        t = np.arange(N) * self.dt

        # Mount rotation R_p2v (phone to vehicle)
        # Using ZYX convention: R_p2v = Rz(yaw) @ Ry(pitch) @ Rx(roll)
        cr, sr = np.cos(np.radians(mount_roll_deg)), np.sin(np.radians(mount_roll_deg))
        cp, sp = np.cos(np.radians(mount_pitch_deg)), np.sin(np.radians(mount_pitch_deg))
        cy, sy = np.cos(np.radians(mount_yaw_deg)), np.sin(np.radians(mount_yaw_deg))

        R_p2v = np.array([
            [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
            [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
            [-sp,     cp * sr,                cp * cr]
        ])

        # Create smooth vehicle motion profile
        # Phase 1 (0 to 30s): Stationary parked
        # Phase 2 (30 to 60s): Smooth acceleration to 15 m/s (~54 km/h)
        # Phase 3 (60 to 450s): Steady highway cruising with minor bumps
        # Phase 4 (450 to 510s): Smooth cornering maneuver
        # Phase 5 (510 to 570s): Deceleration to stop
        # Phase 6 (570 to 600s): Stationary stop
        v_true = np.zeros(N)
        omega_z_true = np.zeros(N)

        for i in range(N):
            ti = t[i]
            if ti < 30.0:
                v_true[i] = 0.0
                omega_z_true[i] = 0.0
            elif ti < 60.0:
                v_true[i] = 15.0 * 0.5 * (1.0 - np.cos(np.pi * (ti - 30.0) / 30.0))
                omega_z_true[i] = 0.0
            elif ti < 450.0:
                v_true[i] = 15.0 + 0.3 * np.sin(2.0 * np.pi * 0.02 * ti)
                omega_z_true[i] = 0.001 * np.sin(2.0 * np.pi * 0.01 * ti)
            elif ti < 510.0:
                # 60s cornering (turn 90 degrees total: omega_z = (pi/2) / 60)
                v_true[i] = 12.0
                omega_z_true[i] = (np.pi / 2.0) / 60.0
            elif ti < 570.0:
                v_true[i] = 12.0 * 0.5 * (1.0 + np.cos(np.pi * (ti - 510.0) / 60.0))
                omega_z_true[i] = 0.0
            else:
                v_true[i] = 0.0
                omega_z_true[i] = 0.0

        # Kinematic acceleration in vehicle frame:
        # Long accel: dv/dt
        # Lat accel: v * omega_z (centripetal)
        a_fwd = np.gradient(v_true, self.dt)
        a_lat = v_true * omega_z_true
        a_vert = np.zeros(N)

        # Vehicle specific force (with vertical gravity reaction in ENU: [0, 0, g])
        accel_veh_spec = np.column_stack([a_fwd, a_lat, a_vert + STANDARD_GRAVITY])
        gyro_veh = np.column_stack([np.zeros(N), np.zeros(N), omega_z_true])

        # Project into phone frame: v_phone = R_p2v.T @ v_veh
        accel_phone_clean = (R_p2v.T @ np.column_stack([a_fwd, a_lat, a_vert]).T).T
        accel_phone_raw = (R_p2v.T @ accel_veh_spec.T).T
        gyro_phone = (R_p2v.T @ gyro_veh.T).T

        # Add realistic sensor noise & bias
        accel_noise = self.rng.normal(0.0, accel_noise_std, size=(N, 3))
        gyro_noise = self.rng.normal(0.0, gyro_noise_std, size=(N, 3))
        bias_g = gyro_bias if gyro_bias is not None else np.array([0.001, -0.002, 0.0015])

        accel_phone_meas = accel_phone_raw + accel_noise
        gyro_phone_meas = gyro_phone + gyro_noise + bias_g

        # Ground truth positions
        heading_true = np.cumsum(omega_z_true * self.dt)
        pos_x = np.cumsum(v_true * np.cos(heading_true) * self.dt)
        pos_y = np.cumsum(v_true * np.sin(heading_true) * self.dt)

        return {
            'time': t,
            'accel_raw': accel_phone_meas,
            'gyro_raw': gyro_phone_meas,
            'accel_true_veh': np.column_stack([a_fwd, a_lat, a_vert]),
            'accel_true_phone': accel_phone_clean,
            'velocity_true': v_true,
            'heading_true': heading_true,
            'pos_true': np.column_stack([pos_x, pos_y]),
            'R_p2v_true': R_p2v
        }
