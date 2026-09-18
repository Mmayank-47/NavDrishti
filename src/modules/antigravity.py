"""
src/modules/antigravity.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Layer 2: Signal Processing & Correction (ANTIGRAVITY)

Solves the critical gravity contamination problem on vehicle mounts:
  1. Maintains full 3x3 rotation state (R_v2w) via quaternion gyro integration.
  2. Projects world gravity into phone frame: g_phone = R_v2w.T @ [0, 0, 9.81].
  3. Extracts true kinematic acceleration: accel_clean = accel_raw - g_phone.
  4. Fuses gyro integration with low-pass accelerometer tilt at 0.01 Hz cutoff.
─────────────────────────────────────────────────────────────────────────────
"""

from dataclasses import dataclass
from typing import Optional, Tuple
import numpy as np

STANDARD_GRAVITY = 9.80665


@dataclass
class AntigravityOutput:
    """Standardized output packet from the ANTIGRAVITY engine."""
    accel_clean: np.ndarray        # [3] True kinematic acceleration (m/s^2)
    R_v2w_updated: np.ndarray      # [3x3] Rotation matrix vehicle/phone to world
    g_phone: np.ndarray            # [3] Gravity vector projected into phone frame
    tilt_angle: float              # Pitch/roll tilt magnitude in radians
    drift_confidence: float        # Gyro trust weight (0.0 to 1.0)


def _rodrigues_exp(omega_dt: np.ndarray) -> np.ndarray:
    """Compute unit quaternion [qw, qx, qy, qz] from rotation vector omega * dt."""
    angle = float(np.linalg.norm(omega_dt))
    if angle < 1e-10:
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
    """Hamilton quaternion product q1 ⊗ q2."""
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    return np.array([
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2
    ], dtype=np.float64)


def _quat_to_rot_matrix(q: np.ndarray) -> np.ndarray:
    """Convert unit quaternion [qw, qx, qy, qz] to 3x3 orthogonal rotation matrix."""
    q_norm = q / np.linalg.norm(q)
    qw, qx, qy, qz = q_norm

    return np.array([
        [1.0 - 2.0 * (qy**2 + qz**2), 2.0 * (qx*qy - qw*qz),       2.0 * (qx*qz + qw*qy)],
        [2.0 * (qx*qy + qw*qz),       1.0 - 2.0 * (qx**2 + qz**2), 2.0 * (qy*qz - qw*qx)],
        [2.0 * (qx*qz - qw*qy),       2.0 * (qy*qz + qw*qx),       1.0 - 2.0 * (qx**2 + qy**2)]
    ], dtype=np.float64)


def _rot_matrix_to_quat(R: np.ndarray) -> np.ndarray:
    """Convert 3x3 rotation matrix to unit quaternion."""
    tr = R[0, 0] + R[1, 1] + R[2, 2]
    if tr > 0:
        S = np.sqrt(tr + 1.0) * 2.0
        qw = 0.25 * S
        qx = (R[2, 1] - R[1, 2]) / S
        qy = (R[0, 2] - R[2, 0]) / S
        qz = (R[1, 0] - R[0, 1]) / S
    elif (R[0, 0] > R[1, 1]) and (R[0, 0] > R[2, 2]):
        S = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2.0
        qw = (R[2, 1] - R[1, 2]) / S
        qx = 0.25 * S
        qy = (R[0, 1] + R[1, 0]) / S
        qz = (R[0, 2] + R[2, 0]) / S
    elif R[1, 1] > R[2, 2]:
        S = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2.0
        qw = (R[0, 2] - R[2, 0]) / S
        qx = (R[0, 1] + R[1, 0]) / S
        qy = 0.25 * S
        qz = (R[1, 2] + R[2, 1]) / S
    else:
        S = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2.0
        qw = (R[1, 0] - R[0, 1]) / S
        qx = (R[0, 2] + R[2, 0]) / S
        qy = (R[1, 2] + R[2, 1]) / S
        qz = 0.25 * S

    q = np.array([qw, qx, qy, qz], dtype=np.float64)
    return q / np.linalg.norm(q)


def _euler_to_quat(roll: float, pitch: float, yaw: float) -> np.ndarray:
    """Convert Euler angles (radians) to unit quaternion."""
    cr, sr = np.cos(roll * 0.5), np.sin(roll * 0.5)
    cp, sp = np.cos(pitch * 0.5), np.sin(pitch * 0.5)
    cy, sy = np.cos(yaw * 0.5), np.sin(yaw * 0.5)

    qw = cr * cp * cy + sr * sp * sy
    qx = sr * cp * cy - cr * sp * sy
    qy = cr * sp * cy + sr * cp * sy
    qz = cr * cp * sy - sr * sp * cy

    q = np.array([qw, qx, qy, qz], dtype=np.float64)
    return q / np.linalg.norm(q)


class Antigravity:
    """
    Antigravity Module: Precision dynamic gravity removal and orientation tracking.
    """

    def __init__(
        self,
        sampling_rate_hz: float = 10.0,
        tilt_fusion_cutoff_hz: float = 0.01,
        g_val: float = STANDARD_GRAVITY,
        accel_gate_threshold: float = 0.35,
        gyro_gate_threshold: float = 0.08,
        enable_gyro_debias: bool = True
    ):
        self.fs = float(sampling_rate_hz)
        self.g_val = float(g_val)
        self.accel_gate = float(accel_gate_threshold)
        self.gyro_gate = float(gyro_gate_threshold)
        self.enable_debias = bool(enable_gyro_debias)

        # Tilt complementary feedback gain K_p = 2 * pi * cutoff_hz
        self.kp_tilt = float(2.0 * np.pi * tilt_fusion_cutoff_hz)

        # Internal state
        self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        self.R_v2w = np.eye(3, dtype=np.float64)
        self.gyro_bias = np.zeros(3, dtype=np.float64)
        self.bias_alpha = 0.02

        # Startup initialization buffer
        self.is_initialized = False
        self.init_acc_buffer = []
        self.init_gyr_buffer = []
        self.min_init_samples = max(5, int(self.fs * 1.0))

        # World gravity vector: [0, 0, g] reaction in local level frame
        self.g_world = np.array([0.0, 0.0, self.g_val], dtype=np.float64)

        # Drift tracking
        self.time_since_last_tilt_anchor = 0.0

    def initialize(
        self,
        stationary_accel: Optional[np.ndarray] = None,
        stationary_gyro: Optional[np.ndarray] = None,
        initial_rpy: Optional[Tuple[float, float, float]] = None,
        initial_heading: float = 0.0
    ):
        """Calibrate startup pitch/roll leveling and gyro zero-bias."""
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
        self.init_acc_buffer.clear()
        self.init_gyr_buffer.clear()
        self.is_initialized = False
        self.time_since_last_tilt_anchor = 0.0

    def step(
        self,
        accel_raw: np.ndarray,
        gyro: np.ndarray,
        R_v2w: Optional[np.ndarray] = None,
        dt: float = 0.1,
        mag: Optional[np.ndarray] = None
    ) -> AntigravityOutput:
        """
        Execute one gravity compensation & orientation update step.

        Parameters:
        -----------
        accel_raw : [3] raw accelerometer in m/s^2
        gyro : [3] angular velocity in rad/s
        R_v2w : Optional [3x3] prior rotation matrix (if external attitude override)
        dt : Timestep in seconds (default 0.1 s)
        mag : Optional [3] magnetometer reading in uT

        Returns:
        --------
        AntigravityOutput containing accel_clean, R_v2w_updated, g_phone, tilt_angle, drift_confidence.
        """
        dt = float(dt)
        a_raw = np.asarray(accel_raw[:3], dtype=np.float64)
        g_raw = np.asarray(gyro[:3], dtype=np.float64)

        if R_v2w is not None:
            self.R_v2w = np.asarray(R_v2w, dtype=np.float64)
            self.q = _rot_matrix_to_quat(self.R_v2w)

        # 1. First second startup buffer if uninitialized
        if not self.is_initialized:
            self.init_acc_buffer.append(a_raw)
            self.init_gyr_buffer.append(g_raw)
            if len(self.init_acc_buffer) >= self.min_init_samples:
                self.initialize(
                    stationary_accel=np.array(self.init_acc_buffer),
                    stationary_gyro=np.array(self.init_gyr_buffer)
                )
            else:
                norm_a = float(np.linalg.norm(a_raw))
                g_est = a_raw.copy() if norm_a > 1e-3 else self.g_world.copy()
                acc_clean = a_raw - g_est
                return AntigravityOutput(
                    accel_clean=acc_clean,
                    R_v2w_updated=self.R_v2w.copy(),
                    g_phone=g_est,
                    tilt_angle=0.0,
                    drift_confidence=0.5
                )

        # 2. Debiasing
        gyro_debiased = g_raw - self.gyro_bias if self.enable_debias else g_raw

        # 3. Tilt Fusion with Gating
        R_curr = _quat_to_rot_matrix(self.q)
        g_phone_unit = R_curr[2, :]  # Estimated gravity direction in body

        acc_norm = float(np.linalg.norm(a_raw))
        gyr_norm = float(np.linalg.norm(gyro_debiased))

        is_stationary = (abs(acc_norm - self.g_val) < self.accel_gate) and (gyr_norm < self.gyro_gate)
        omega_correction = np.zeros(3, dtype=np.float64)

        if is_stationary and acc_norm > 1e-3:
            a_measured_unit = a_raw / acc_norm
            # Negative feedback error vector
            e_tilt = np.cross(a_measured_unit, g_phone_unit)
            omega_correction = self.kp_tilt * e_tilt
            self.time_since_last_tilt_anchor = 0.0

            if self.enable_debias:
                self.gyro_bias = (1.0 - self.bias_alpha) * self.gyro_bias + self.bias_alpha * g_raw
        else:
            self.time_since_last_tilt_anchor += dt

        # Optional: Magnetometer yaw anchor if provided
        if mag is not None and len(mag) == 3:
            m = np.asarray(mag, dtype=np.float64)
            norm_m = np.linalg.norm(m)
            if norm_m > 1e-3:
                # Project mag into horizontal plane
                m_proj = R_curr @ (m / norm_m)
                yaw_mag = np.arctan2(-m_proj[1], m_proj[0])
                current_yaw = np.arctan2(R_curr[1, 0], R_curr[0, 0])
                d_yaw = (yaw_mag - current_yaw + np.pi) % (2.0 * np.pi) - np.pi
                omega_correction[2] += 0.005 * d_yaw

        # 4. Integrate Gyro via SO(3) Exponential Map
        omega_eff = gyro_debiased + omega_correction
        delta_q = _rodrigues_exp(omega_eff * dt)
        self.q = _quat_multiply(self.q, delta_q)
        self.q = self.q / np.linalg.norm(self.q)

        # 5. Project World Gravity into Phone Frame
        self.R_v2w = _quat_to_rot_matrix(self.q)
        g_phone = self.R_v2w.T @ self.g_world

        # 6. Extract Clean Kinematic Acceleration
        accel_clean = a_raw - g_phone

        # 7. Compute Tilt Magnitude & Drift Confidence
        # Tilt angle is the angle between local vertical [0, 0, 1] and body Z
        cos_tilt = np.clip(self.R_v2w[2, 2], -1.0, 1.0)
        tilt_angle = float(np.arccos(cos_tilt))

        # Drift confidence drops gracefully if tilt anchoring hasn't occurred for > 60s
        drift_confidence = float(np.clip(1.0 - (self.time_since_last_tilt_anchor / 300.0), 0.2, 1.0))

        return AntigravityOutput(
            accel_clean=accel_clean,
            R_v2w_updated=self.R_v2w.copy(),
            g_phone=g_phone,
            tilt_angle=tilt_angle,
            drift_confidence=drift_confidence
        )
