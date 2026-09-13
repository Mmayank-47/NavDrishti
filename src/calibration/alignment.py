"""
src/calibration/alignment.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Automatic In-Vehicle Smartphone-to-Vehicle Alignment & Calibration Engine.

Estimates:
  1. Pitch & Roll leveling from gravity vector during stationary/constant-speed periods.
  2. Yaw / Heading alignment relative to vehicle longitudinal travel direction
     using acceleration-velocity correlation during forward acceleration events.
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
from src.preprocessing.frame_transform import (
    euler_to_rotation_matrix,
    rotation_matrix_to_euler,
    STANDARD_GRAVITY
)


class PhoneVehicleAlignment:
    """
    Two-stage in-vehicle alignment engine.
    Computes rotation matrix R_p_to_v such that:
        v_vehicle = R_p_to_v @ v_phone
    where vehicle frame is:
        X: Forward (longitudinal)
        Y: Right (lateral)
        Z: Down (vertical, NED) or Up (ENU)
    """

    def __init__(self, frame_convention='ENU'):
        self.convention = frame_convention.upper()  # 'ENU' or 'NED'
        self.R_p_to_v = np.eye(3)
        self.is_calibrated = False
        self.alignment_angles_deg = {'roll': 0.0, 'pitch': 0.0, 'yaw': 0.0}

    def estimate_leveling_from_gravity(self, gravity_or_accel_stationary):
        """
        Stage 1: Leveling.
        Computes roll and pitch from stationary specific force / gravity vector.
        In ENU, gravity is [0, 0, -g]. In NED, gravity is [0, 0, +g].
        """
        g_mean = np.mean(gravity_or_accel_stationary, axis=0)
        norm_g = np.linalg.norm(g_mean)
        if norm_g < 1e-3:
            return 0.0, 0.0, np.eye(3)

        gx, gy, gz = g_mean / norm_g

        if self.convention == 'ENU':
            # Gravity points DOWN (-Z in ENU)
            # a_measured = -g_vector = [0, 0, +1] in upward direction
            pitch = np.arcsin(np.clip(gx, -1.0, 1.0))
            roll  = np.arctan2(-gy, gz)
        else:
            # NED: Gravity points DOWN (+Z in NED)
            pitch = -np.arcsin(np.clip(gx, -1.0, 1.0))
            roll  = np.arctan2(gy, gz)

        # Leveling rotation (roll and pitch only)
        R_level = euler_to_rotation_matrix(roll, pitch, 0.0)
        return roll, pitch, R_level

    def estimate_heading_from_acceleration(self, accel_leveled, velocity_ref=None, min_accel_thresh=0.6):
        """
        Stage 2: Heading (Yaw) Alignment.
        Identifies the vehicle's forward longitudinal axis from horizontal accelerations.
        
        If velocity_ref is provided, correlates leveled horizontal acceleration with
        forward velocity changes (dv/dt) to resolve forward vs backward ambiguity.
        """
        # Horizontal leveled acceleration (X and Y components)
        ax = accel_leveled[:, 0]
        ay = accel_leveled[:, 1]
        a_horiz_mag = np.hypot(ax, ay)

        # Select significant acceleration / braking events
        event_mask = a_horiz_mag > min_accel_thresh
        if np.sum(event_mask) < 10:
            # Fallback to PCA / principal axis of horizontal variance
            cov = np.cov(ax, ay)
            eigenvals, eigenvecs = np.linalg.eigh(cov)
            primary_vec = eigenvecs[:, np.argmax(eigenvals)]
            yaw = np.arctan2(primary_vec[1], primary_vec[0])
            return yaw

        ax_events = ax[event_mask]
        ay_events = ay[event_mask]

        if velocity_ref is not None and len(velocity_ref) == len(accel_leveled):
            # Compute reference acceleration from velocity derivative
            dv = np.gradient(velocity_ref)
            dv_events = dv[event_mask]

            # Project horizontal acceleration onto angles [0, 2*pi] to maximize correlation with dv
            test_angles = np.linspace(-np.pi, np.pi, 360)
            corrs = []
            for ang in test_angles:
                # Forward component under candidate yaw
                a_fwd = np.cos(ang) * ax_events + np.sin(ang) * ay_events
                corrs.append(np.corrcoef(a_fwd, dv_events)[0, 1])
            best_idx = np.nanargmax(corrs)
            yaw = test_angles[best_idx]
        else:
            # SVD / Principal Component
            stacked = np.column_stack([ax_events, ay_events])
            _, _, vh = np.linalg.svd(stacked)
            fwd_dir = vh[0]
            yaw = np.arctan2(fwd_dir[1], fwd_dir[0])

        return yaw

    def calibrate(self, accel_raw, gyro_raw=None, zupt_mask=None, velocity_ref=None):
        """
        Full calibration procedure:
          1. Extract stationary samples (or first 20 samples if no ZUPT mask) for leveling.
          2. Compute roll and pitch.
          3. Level the acceleration signals.
          4. Compute yaw misalignment from acceleration events.
          5. Assemble composite rotation matrix R_p_to_v.
        """
        # Step 1: Leveling
        if zupt_mask is not None and np.any(zupt_mask):
            stationary_accel = accel_raw[zupt_mask]
        else:
            stationary_accel = accel_raw[:min(50, len(accel_raw))]

        roll, pitch, R_level = self.estimate_leveling_from_gravity(stationary_accel)

        # Apply leveling rotation
        accel_leveled = (R_level @ accel_raw.T).T

        # Step 2: Heading
        yaw = self.estimate_heading_from_acceleration(accel_leveled, velocity_ref=velocity_ref)

        # Full alignment matrix: R_p_to_v = R_z(yaw) @ R_level
        R_yaw = euler_to_rotation_matrix(0.0, 0.0, yaw)
        self.R_p_to_v = R_yaw @ R_level
        self.is_calibrated = True

        euler_rad = rotation_matrix_to_euler(self.R_p_to_v)
        self.alignment_angles_deg = {
            'roll':  round(float(np.degrees(euler_rad[0])), 2),
            'pitch': round(float(np.degrees(euler_rad[1])), 2),
            'yaw':   round(float(np.degrees(euler_rad[2])), 2),
        }

        return self.R_p_to_v

    def transform_to_vehicle(self, vectors_phone):
        """
        Rotate 3D vectors from phone frame into vehicle frame:
            v_veh = R_p_to_v @ v_phone
        """
        if not self.is_calibrated:
            raise RuntimeError("PhoneVehicleAlignment must be calibrated before transforming vectors.")
        return (self.R_p_to_v @ vectors_phone.T).T
