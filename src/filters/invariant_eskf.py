"""
src/filters/invariant_eskf.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Invariant Error-State Kalman Filter (ESKF) for 3D Inertial Navigation.

State vector (15-DOF error state):
  - delta_p:  Position error [3] (meters)
  - delta_v:  Velocity error [3] (m/s)
  - delta_theta: Attitude error [3] (radians)
  - delta_ba: Accelerometer bias error [3] (m/s^2)
  - delta_bg: Gyroscope bias error [3] (rad/s)

Nominal state:
  - position:    [3] (meters in local ENU)
  - velocity:    [3] (m/s in local ENU)
  - orientation: [4] (quaternion qw, qx, qy, qz)
  - accel_bias:  [3] (m/s^2)
  - gyro_bias:   [3] (rad/s)
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
from src.preprocessing.frame_transform import (
    quaternion_to_rotation_matrix,
    quaternion_multiply,
    STANDARD_GRAVITY
)
from src.constraints.nhc import VehicleKinematicConstraints


def skew_symmetric(v):
    """Return 3x3 skew-symmetric cross-product matrix [v]x."""
    return np.array([
        [0.0,   -v[2],  v[1]],
        [v[2],   0.0,  -v[0]],
        [-v[1],  v[0],  0.0]
    ])


class InvariantESKF:
    """
    Classical Invariant Error-State Kalman Filter baseline.
    Serves as the physical foundation and benchmark baseline prior to neural fusion.
    """

    def __init__(
        self,
        dt=0.1,
        sigma_accel=0.15,      # Accelerometer noise (m/s^2)
        sigma_gyro=0.015,      # Gyroscope noise (rad/s)
        sigma_accel_bias=0.001,# Accelerometer random walk
        sigma_gyro_bias=0.0001,# Gyroscope random walk
        sigma_gnss_pos=2.5,    # GNSS horizontal position noise (meters)
        sigma_gnss_vel=0.3,    # GNSS velocity noise (m/s)
        sigma_zupt_vel=0.05,   # ZUPT pseudo-measurement noise (m/s)
        sigma_nhc=0.15,        # NHC non-holonomic constraint noise (m/s)
    ):
        self.dt = dt
        self.g_nav = np.array([0.0, 0.0, -STANDARD_GRAVITY])  # ENU gravity vector

        # Nominal states
        self.p = np.zeros(3)           # [e, n, u]
        self.v = np.zeros(3)           # [ve, vn, vu]
        self.q = np.array([1.0, 0.0, 0.0, 0.0])  # [qw, qx, qy, qz]
        self.ba = np.zeros(3)          # Accel bias
        self.bg = np.zeros(3)          # Gyro bias

        # Covariances
        self.P = np.eye(15) * 1e-2
        self.P[0:3, 0:3] *= 10.0       # Initial position uncertainty
        self.P[3:6, 3:6] *= 1.0        # Initial velocity uncertainty
        self.P[6:9, 6:9] *= 0.1        # Initial attitude uncertainty
        self.P[9:12, 9:12] *= 0.05     # Accel bias uncertainty
        self.P[12:15, 12:15] *= 0.005  # Gyro bias uncertainty

        # Continuous process noise
        self.Q = np.zeros((12, 12))
        self.Q[0:3, 0:3] = np.eye(3) * (sigma_accel ** 2)
        self.Q[3:6, 3:6] = np.eye(3) * (sigma_gyro ** 2)
        self.Q[6:9, 6:9] = np.eye(3) * (sigma_accel_bias ** 2)
        self.Q[9:12, 9:12] = np.eye(3) * (sigma_gyro_bias ** 2)

        # Measurement noises
        self.R_gnss_pos = np.eye(3) * (sigma_gnss_pos ** 2)
        self.R_gnss_vel = np.eye(3) * (sigma_gnss_vel ** 2)
        self.R_zupt     = np.eye(3) * (sigma_zupt_vel ** 2)
        self.R_nhc      = np.eye(2) * (sigma_nhc ** 2)

        # Vehicle kinematic constraints engine
        self.kinematic_constraints = VehicleKinematicConstraints(
            sigma_nhc_nominal=sigma_nhc,
            sigma_zupt_nominal=sigma_zupt_vel
        )

    def initialize(self, p0=None, v0=None, q0=None):
        """Initialize filter state."""
        if p0 is not None: self.p = np.array(p0, dtype=np.float64)
        if v0 is not None: self.v = np.array(v0, dtype=np.float64)
        if q0 is not None: self.q = np.array(q0, dtype=np.float64) / np.linalg.norm(q0)

    def predict(self, accel_meas, gyro_meas, dt=None):
        """
        Propagate nominal state and error covariance with raw/filtered IMU inputs.
        """
        if dt is None: dt = self.dt

        # Unbias measurements
        acc_unbiased = accel_meas - self.ba
        gyr_unbiased = gyro_meas - self.bg

        # 1. Attitude integration via quaternion
        omega_mag = np.linalg.norm(gyr_unbiased)
        if omega_mag > 1e-8:
            axis = gyr_unbiased / omega_mag
            angle = omega_mag * dt
            dq = np.array([
                np.cos(angle / 2.0),
                axis[0] * np.sin(angle / 2.0),
                axis[1] * np.sin(angle / 2.0),
                axis[2] * np.sin(angle / 2.0)
            ])
        else:
            dq = np.array([1.0, 0.5 * gyr_unbiased[0] * dt, 0.5 * gyr_unbiased[1] * dt, 0.5 * gyr_unbiased[2] * dt])

        q_new = quaternion_multiply(self.q, dq)
        self.q = q_new / np.linalg.norm(q_new)

        # 2. Acceleration in navigation frame
        R = quaternion_to_rotation_matrix(self.q)
        a_nav = R @ acc_unbiased + self.g_nav

        # 3. Position and velocity propagation
        self.p = self.p + self.v * dt + 0.5 * a_nav * (dt ** 2)
        self.v = self.v + a_nav * dt

        # 4. Error state Jacobian F (15x15)
        F = np.eye(15)
        F[0:3, 3:6] = np.eye(3) * dt
        F[3:6, 6:9] = -R @ skew_symmetric(acc_unbiased) * dt
        F[3:6, 9:12] = -R * dt
        F[6:9, 12:15] = -R * dt

        # Process noise mapping Fi (15x12)
        Fi = np.zeros((15, 12))
        Fi[3:6, 0:3] = -R
        Fi[6:9, 3:6] = -np.eye(3)
        Fi[9:12, 6:9] = np.eye(3)
        Fi[12:15, 9:12] = np.eye(3)

        # Discrete process covariance Qd
        Qd = Fi @ (self.Q * dt) @ Fi.T

        # Covariance propagation
        self.P = F @ self.P @ F.T + Qd
        # Ensure symmetry
        self.P = 0.5 * (self.P + self.P.T)

    def update_gnss_position(self, p_gnss, R_custom=None):
        """Update state using GNSS position [e, n, u]."""
        H = np.zeros((3, 15))
        H[0:3, 0:3] = np.eye(3)

        y = p_gnss - self.p  # Innovation
        R = R_custom if R_custom is not None else self.R_gnss_pos

        self._apply_kalman_update(H, y, R)

    def update_zupt(self):
        """Zero-Velocity Update: velocity should be [0, 0, 0]."""
        H, y, R_zupt = self.kinematic_constraints.compute_zupt_update(self.v)
        self._apply_kalman_update(H, y, R_zupt)

    def update_nhc(self, R_b_to_v=None, gyro_body=None):
        """
        Non-Holonomic Constraints: lateral and vertical velocities in vehicle frame are ~ 0.
        Uses VehicleKinematicConstraints engine with dynamic slip gating.
        """
        H, y, R_nhc = self.kinematic_constraints.compute_nhc_update(
            v_nav=self.v,
            q_body_to_nav=self.q,
            R_body_to_veh=R_b_to_v,
            gyro_body=gyro_body
        )
        self._apply_kalman_update(H, y, R_nhc)

    def _apply_kalman_update(self, H, y, R_cov):
        """Standard Kalman gain computation and error-state injection."""
        S = H @ self.P @ H.T + R_cov
        K = self.P @ H.T @ np.linalg.inv(S)

        delta_x = K @ y

        # Inject error state into nominal state
        self.p += delta_x[0:3]
        self.v += delta_x[3:6]

        # Attitude error correction
        d_theta = delta_x[6:9]
        angle = np.linalg.norm(d_theta)
        if angle > 1e-8:
            dq = np.array([
                np.cos(angle / 2.0),
                (d_theta[0] / angle) * np.sin(angle / 2.0),
                (d_theta[1] / angle) * np.sin(angle / 2.0),
                (d_theta[2] / angle) * np.sin(angle / 2.0)
            ])
            self.q = quaternion_multiply(self.q, dq)
            self.q /= np.linalg.norm(self.q)

        self.ba += delta_x[9:12]
        self.bg += delta_x[12:15]

        # Joseph form covariance update for numerical stability
        I_KH = np.eye(15) - K @ H
        self.P = I_KH @ self.P @ I_KH.T + K @ R_cov @ K.T
        self.P = 0.5 * (self.P + self.P.T)
