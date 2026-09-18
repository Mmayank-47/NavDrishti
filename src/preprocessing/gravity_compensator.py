"""
src/preprocessing/gravity_compensator.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning (NavDrishti)
Dynamic 3D Gravity Compensation & Rotation Tracking Engine.

Removes gravity contamination from raw accelerometer measurements by
maintaining an accurate 3D rotation state (R_v2w) via quaternion gyro integration
fused with low-pass accelerometer-derived tilt at a 0.01 Hz cutoff frequency.
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Tuple, Union, Dict
import numpy as np

# Standard gravity (m/s^2)
STANDARD_GRAVITY = 9.80665


def _rodrigues_exp(omega_dt: np.ndarray) -> np.ndarray:
    """
    Compute unit quaternion [qw, qx, qy, qz] from rotation vector omega * dt
    using the exponential map on SO(3) / SU(2).
    """
    angle = float(np.linalg.norm(omega_dt))
    if angle < 1e-10:
        # First-order Taylor approximation
        qw = 1.0 - 0.125 * angle**2
        scale = 0.5 - (angle**2) / 48.0
        return np.array([qw, omega_dt[0] * scale, omega_dt[1] * scale, omega_dt[2] * scale], dtype=np.float64)

    half_angle = 0.5 * angle
    sin_ha = np.sin(half_angle)
    scale = sin_ha / angle
    return np.array([
        np.cos(half_angle),
        omega_dt[0] * scale,
        omega_dt[1] * scale,
        omega_dt[2] * scale
    ], dtype=np.float64)


def _quat_multiply(q1: np.ndarray, q2: np.ndarray) -> np.ndarray:
    """Hamilton product of two quaternions q1 ⊗ q2, where q = [qw, qx, qy, qz]."""
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    return np.array([
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2
    ], dtype=np.float64)


def _quat_to_rot_matrix(q: np.ndarray) -> np.ndarray:
    """Convert unit quaternion q = [qw, qx, qy, qz] to 3x3 rotation matrix R."""
    q_norm = q / np.linalg.norm(q)
    qw, qx, qy, qz = q_norm

    return np.array([
        [1.0 - 2.0 * (qy**2 + qz**2), 2.0 * (qx*qy - qw*qz),       2.0 * (qx*qz + qw*qy)],
        [2.0 * (qx*qy + qw*qz),       1.0 - 2.0 * (qx**2 + qz**2), 2.0 * (qy*qz - qw*qx)],
        [2.0 * (qx*qz - qw*qy),       2.0 * (qy*qz + qw*qx),       1.0 - 2.0 * (qx**2 + qy**2)]
    ], dtype=np.float64)


def _euler_to_quat(roll: float, pitch: float, yaw: float) -> np.ndarray:
    """Convert Euler angles (roll, pitch, yaw in radians, ZYX) to quaternion."""
    cr, sr = np.cos(roll * 0.5), np.sin(roll * 0.5)
    cp, sp = np.cos(pitch * 0.5), np.sin(pitch * 0.5)
    cy, sy = np.cos(yaw * 0.5), np.sin(yaw * 0.5)

    qw = cr * cp * cy + sr * sp * sy
    qx = sr * cp * cy - cr * sp * sy
    qy = cr * sp * cy + sr * cp * sy
    qz = cr * cp * sy - sr * sp * cy

    q = np.array([qw, qx, qy, qz], dtype=np.float64)
    return q / np.linalg.norm(q)


class GravityCompensator:
    """
    Robust 3D Gravity Compensation and Orientation Tracking Engine for NavDrishti.

    Key Features:
      - Exponential map / quaternion integration for exact SO(3) attitude updates without gimbal lock.
      - Dynamic gravity projection: g_phone = R_v2w.T @ [0, 0, g_world].
      - Low-pass tilt fusion (0.01 Hz cutoff) to eliminate gyro drift while gating out dynamic accelerations.
      - Online and startup gyro zero-bias calibration.
      - Optional low-pass vibration filtering.
    """

    def __init__(
        self,
        sampling_rate_hz: float = 10.0,
        tilt_fusion_cutoff_hz: float = 0.01,
        g_val: float = STANDARD_GRAVITY,
        accel_gate_threshold: float = 0.35,
        gyro_gate_threshold: float = 0.08,
        enable_gyro_debias: bool = True,
        vibration_filter_hz: Optional[float] = None
    ):
        """
        Parameters:
        -----------
        sampling_rate_hz : IMU sampling frequency (default: 10 Hz for SIH spec).
        tilt_fusion_cutoff_hz : Cutoff frequency for accelerometer tilt fusion (default: 0.01 Hz).
        g_val : Earth gravity magnitude (default: 9.80665 m/s^2).
        accel_gate_threshold : Maximum deviation |norm(a) - g| (m/s^2) for active tilt fusion.
        gyro_gate_threshold : Maximum angular rate norm (rad/s) for active tilt fusion.
        enable_gyro_debias : Whether to automatically estimate and subtract gyro zero-rate bias.
        vibration_filter_hz : Optional low-pass cutoff for vibration attenuation on clean accel.
        """
        self.fs = float(sampling_rate_hz)
        self.g_val = float(g_val)
        self.accel_gate = float(accel_gate_threshold)
        self.gyro_gate = float(gyro_gate_threshold)
        self.enable_debias = bool(enable_gyro_debias)

        # Fusion gain K_p = 2 * pi * cutoff_hz
        self.kp_tilt = float(2.0 * np.pi * tilt_fusion_cutoff_hz)

        # Attitude state: unit quaternion [qw, qx, qy, qz] representing Body-to-World (v2w)
        self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        self.R_v2w = np.eye(3, dtype=np.float64)

        # Gyro bias estimation
        self.gyro_bias = np.zeros(3, dtype=np.float64)
        self.bias_alpha = 0.02  # Slow online updating during verified stationary periods

        # Initialization buffer for startup (first ~1 second)
        self.is_initialized = False
        self.init_samples_acc = []
        self.init_samples_gyr = []
        self.min_init_samples = max(5, int(self.fs * 1.0))

        # World gravity vector: standard convention [0, 0, g] (upward reaction force on stationary sensor)
        self.g_world = np.array([0.0, 0.0, self.g_val], dtype=np.float64)

        # Vibration low-pass filter state
        self.vibration_alpha = None
        if vibration_filter_hz is not None and vibration_filter_hz > 0:
            tau = 1.0 / (2.0 * np.pi * vibration_filter_hz)
            dt = 1.0 / self.fs
            self.vibration_alpha = dt / (tau + dt)
        self.last_accel_clean = np.zeros(3, dtype=np.float64)

    def initialize(
        self,
        stationary_accel: Optional[np.ndarray] = None,
        stationary_gyro: Optional[np.ndarray] = None,
        initial_rpy: Optional[Tuple[float, float, float]] = None,
        initial_heading: float = 0.0
    ):
        """
        Explicitly initialize attitude and gyro bias from stationary data or specified Euler angles.
        """
        if initial_rpy is not None:
            roll, pitch, yaw = initial_rpy
            self.q = _euler_to_quat(roll, pitch, yaw)
            self.R_v2w = _quat_to_rot_matrix(self.q)
            self.is_initialized = True
            return

        if stationary_accel is not None and len(stationary_accel) > 0:
            stationary_accel = np.asarray(stationary_accel, dtype=np.float64)
            mean_acc = np.mean(stationary_accel, axis=0) if stationary_accel.ndim == 2 else stationary_accel
            norm_a = float(np.linalg.norm(mean_acc))

            if norm_a > 1e-3:
                # Accelerometer measures reaction force to gravity: a_norm = [ax, ay, az] / norm_a
                ax, ay, az = mean_acc / norm_a
                pitch = float(np.arcsin(np.clip(-ax, -1.0, 1.0)))
                roll = float(np.arctan2(ay, az))
                self.q = _euler_to_quat(roll, pitch, initial_heading)
                self.R_v2w = _quat_to_rot_matrix(self.q)

        if stationary_gyro is not None and len(stationary_gyro) > 0 and self.enable_debias:
            stationary_gyro = np.asarray(stationary_gyro, dtype=np.float64)
            self.gyro_bias = np.median(stationary_gyro, axis=0) if stationary_gyro.ndim == 2 else stationary_gyro.copy()

        self.is_initialized = True

    def reset(self):
        """Reset state to identity."""
        self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        self.R_v2w = np.eye(3, dtype=np.float64)
        self.gyro_bias = np.zeros(3, dtype=np.float64)
        self.init_samples_acc.clear()
        self.init_samples_gyr.clear()
        self.is_initialized = False
        self.last_accel_clean = np.zeros(3, dtype=np.float64)

    def step(
        self,
        accel_raw: np.ndarray,
        gyro_raw: np.ndarray,
        dt: Optional[float] = None,
        mag_raw: Optional[np.ndarray] = None
    ) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """
        Execute one gravity compensation step.

        Parameters:
        -----------
        accel_raw : (3,) raw accelerometer reading [ax, ay, az] in m/s^2.
        gyro_raw : (3,) raw gyroscope reading [gx, gy, gz] in rad/s.
        dt : Time step in seconds (default: 1.0 / self.fs).
        mag_raw : Optional (3,) magnetometer reading.

        Returns:
        --------
        accel_clean : (3,) true kinematic acceleration with gravity removed (m/s^2).
        g_phone : (3,) estimated gravity vector in phone frame (m/s^2).
        q : (4,) current orientation quaternion [qw, qx, qy, qz].
        R_v2w : (3, 3) current rotation matrix from vehicle/phone to world.
        """
        dt = float(dt if dt is not None else 1.0 / self.fs)
        a_raw = np.asarray(accel_raw[:3], dtype=np.float64)
        g_raw = np.asarray(gyro_raw[:3], dtype=np.float64)

        # 1. Startup calibration buffer
        if not self.is_initialized:
            self.init_samples_acc.append(a_raw)
            self.init_samples_gyr.append(g_raw)
            if len(self.init_samples_acc) >= self.min_init_samples:
                self.initialize(
                    stationary_accel=np.array(self.init_samples_acc),
                    stationary_gyro=np.array(self.init_samples_gyr)
                )
            else:
                # Before initialization finishes, estimate gravity directly from instantaneous measurement
                norm_a = float(np.linalg.norm(a_raw))
                g_est = a_raw.copy() if norm_a > 1e-3 else self.g_world.copy()
                acc_clean = a_raw - g_est
                return acc_clean, g_est, self.q.copy(), self.R_v2w.copy()

        # 2. Debiasing
        gyro_debiased = g_raw - self.gyro_bias if self.enable_debias else g_raw

        # 3. Accel-derived tilt fusion (Complementary / Mahony formulation)
        # Compute predicted gravity direction in phone coordinates
        # g_phone_unit = R_v2w.T @ [0, 0, 1]
        R_v2w_curr = _quat_to_rot_matrix(self.q)
        g_phone_unit = R_v2w_curr[2, :]  # 3rd row of R_v2w is R_v2w.T @ [0, 0, 1]

        acc_norm = float(np.linalg.norm(a_raw))
        gyr_norm = float(np.linalg.norm(gyro_debiased))

        # Gate tilt correction: only fuse tilt when acceleration is predominantly static gravity
        omega_correction = np.zeros(3, dtype=np.float64)
        is_stationary = (abs(acc_norm - self.g_val) < self.accel_gate) and (gyr_norm < self.gyro_gate)

        if is_stationary and acc_norm > 1e-3:
            a_measured_unit = a_raw / acc_norm
            # Error vector: negative feedback cross product between measured gravity direction and predicted gravity
            # e = a_measured_unit x g_phone_unit
            e_tilt = np.cross(a_measured_unit, g_phone_unit)
            omega_correction = self.kp_tilt * e_tilt

            # Slowly update gyro bias during verified stationary periods
            if self.enable_debias:
                self.gyro_bias = (1.0 - self.bias_alpha) * self.gyro_bias + self.bias_alpha * g_raw

        # 4. Gyro Integration via SO(3) Exponential Map
        omega_effective = gyro_debiased + omega_correction
        delta_q = _rodrigues_exp(omega_effective * dt)
        self.q = _quat_multiply(self.q, delta_q)
        self.q = self.q / np.linalg.norm(self.q)  # Enforce strict normalization to avoid drift

        # 5. Compute Gravity Vector in Phone Coordinates
        self.R_v2w = _quat_to_rot_matrix(self.q)
        g_phone = self.R_v2w.T @ self.g_world

        # 6. Gravity Subtraction
        accel_clean = a_raw - g_phone

        # 7. Optional Vibration Filtering
        if self.vibration_alpha is not None:
            accel_clean = (1.0 - self.vibration_alpha) * self.last_accel_clean + self.vibration_alpha * accel_clean
            self.last_accel_clean = accel_clean.copy()

        return accel_clean, g_phone, self.q.copy(), self.R_v2w.copy()

    def batch_process(
        self,
        accel_arr: np.ndarray,
        gyro_arr: np.ndarray,
        dt: Optional[float] = None
    ) -> Dict[str, np.ndarray]:
        """
        Batch process entire time-series for offline evaluation and testing.
        """
        N = len(accel_arr)
        dt = float(dt if dt is not None else 1.0 / self.fs)

        clean_acc = np.zeros((N, 3), dtype=np.float64)
        g_phone_arr = np.zeros((N, 3), dtype=np.float64)
        quats = np.zeros((N, 4), dtype=np.float64)
        headings_deg = np.zeros(N, dtype=np.float64)

        for i in range(N):
            c_acc, g_p, q, R = self.step(accel_arr[i], gyro_arr[i], dt=dt)
            clean_acc[i] = c_acc
            g_phone_arr[i] = g_p
            quats[i] = q
            # Yaw (heading) in degrees
            headings_deg[i] = np.degrees(np.arctan2(R[1, 0], R[0, 0]))

        return {
            "accel_clean": clean_acc,
            "g_phone": g_phone_arr,
            "quaternions": quats,
            "headings_deg": headings_deg
        }
