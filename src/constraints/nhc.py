"""
src/constraints/nhc.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Vehicle Kinematic Constraints:
  1. Non-Holonomic Constraints (NHC):
     Under typical driving conditions, ground vehicle lateral velocity (v_y)
     and vertical velocity (v_z) are approximately zero:
       v_lat ≈ 0
       v_vert ≈ 0
  2. Dynamic Side-Slip & Turn Gating:
     During high-rate yaw turning or aggressive cornering, lateral tire slip
     occurs. NHC measurement noise is dynamically scaled by yaw rate (|omega_z|)
     and lateral acceleration to avoid injecting false zero-velocity constraints.
  3. Zero Velocity Updates (ZUPT):
     Full 3-axis velocity clamp (v_x, v_y, v_z ≈ 0) when vehicle is stationary.
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
from src.preprocessing.frame_transform import quaternion_to_rotation_matrix


class VehicleKinematicConstraints:
    """
    Modular Vehicle Kinematic Constraint Engine adhering to Section 22.
    Provides mathematically sound NHC and ZUPT formulation for error-state filters.
    """

    def __init__(
        self,
        sigma_nhc_nominal=0.15,     # Nominal standard deviation for NHC (m/s)
        sigma_zupt_nominal=0.05,    # Nominal standard deviation for ZUPT (m/s)
        yaw_rate_threshold=0.15,    # Yaw rate threshold for slip inflation (rad/s, ~8.6 deg/s)
        max_covariance_scale=50.0   # Max factor to de-weight NHC during hard turns
    ):
        self.sigma_nhc = sigma_nhc_nominal
        self.sigma_zupt = sigma_zupt_nominal
        self.yaw_rate_threshold = yaw_rate_threshold
        self.max_covariance_scale = max_covariance_scale

    def compute_nhc_update(self, v_nav, q_body_to_nav, R_body_to_veh=None, gyro_body=None):
        """
        Compute NHC measurement matrix H, innovation vector y, and adaptive covariance R.

        Parameters:
        -----------
        v_nav : np.ndarray (3,)
            Current estimated velocity in navigation frame (ENU: [e, n, u]).
        q_body_to_nav : np.ndarray (4,)
            Current attitude quaternion [qw, qx, qy, qz] from body to navigation frame.
        R_body_to_veh : np.ndarray (3, 3), optional
            Calibrated rotation matrix from phone body frame to vehicle frame.
        gyro_body : np.ndarray (3,), optional
            Current angular velocity from gyroscope [wx, wy, wz] in rad/s.

        Returns:
        --------
        H : np.ndarray (2, 15)
            Measurement sensitivity matrix for error state (delta_v at indices 3:6).
        y : np.ndarray (2,)
            Innovation vector (pseudo-measurement - predicted vehicle lateral/vertical velocity).
        R : np.ndarray (2, 2)
            Measurement noise covariance matrix.
        """
        R_b_to_n = quaternion_to_rotation_matrix(q_body_to_nav)

        if R_body_to_veh is not None:
            # Vehicle frame to Nav frame: R_v_to_n = R_b_to_n @ R_b_to_v.T
            # Nav to Vehicle frame: R_n_to_v = R_body_to_veh @ R_b_to_n.T
            R_n_to_v = R_body_to_veh @ R_b_to_n.T
        else:
            R_n_to_v = R_b_to_n.T

        # Velocity in vehicle frame: [v_forward, v_lateral, v_vertical]
        v_veh = R_n_to_v @ v_nav

        # NHC pseudo-measurements: target lateral and vertical velocities are 0
        # Innovation y = target - estimated = [0, 0] - [v_lat, v_vert]
        y = -v_veh[1:3]

        # Sensitivity with respect to error state delta_v (indices 3:6 of 15-state ESKF)
        H = np.zeros((2, 15))
        H[0:2, 3:6] = R_n_to_v[1:3, :]

        # Dynamic covariance scaling for side-slip during cornering
        cov_scale = 1.0
        if gyro_body is not None:
            # Vehicle vertical yaw rate
            if R_body_to_veh is not None:
                gyro_veh = R_body_to_veh @ gyro_body
                yaw_rate = abs(gyro_veh[2])
            else:
                yaw_rate = abs(gyro_body[2])

            if yaw_rate > self.yaw_rate_threshold:
                # Smooth quadratic scaling of covariance when turning
                excess = (yaw_rate - self.yaw_rate_threshold) / self.yaw_rate_threshold
                cov_scale = min(1.0 + (excess ** 2) * 5.0, self.max_covariance_scale)

        R = np.eye(2) * ((self.sigma_nhc ** 2) * cov_scale)
        return H, y, R

    def compute_zupt_update(self, v_nav):
        """
        Compute Zero Velocity Update (ZUPT) measurement matrix, innovation, and covariance.

        Parameters:
        -----------
        v_nav : np.ndarray (3,)
            Current estimated velocity in navigation frame.

        Returns:
        --------
        H : np.ndarray (3, 15)
        y : np.ndarray (3,)
        R : np.ndarray (3, 3)
        """
        H = np.zeros((3, 15))
        H[0:3, 3:6] = np.eye(3)

        # Innovation: target [0, 0, 0] - v_nav
        y = -v_nav

        R = np.eye(3) * (self.sigma_zupt ** 2)
        return H, y, R
