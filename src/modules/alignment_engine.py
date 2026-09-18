"""
src/modules/alignment_engine.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Module 2: Alignment Engine
Calibrate phone mount angle relative to vehicle body frame.
Output: R_p2v (3x3 rotation matrix from phone to vehicle).
Vehicle frame convention:
  X: Forward (longitudinal)
  Y: Right (lateral)
  Z: Up (ENU) or Down (NED)
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Tuple, Dict
import numpy as np

STANDARD_GRAVITY = 9.80665


class AlignmentEngine:
    """
    Two-stage in-vehicle alignment engine:
      Stage 1: Leveling from stationary gravity vector (estimates roll and pitch).
      Stage 2: Heading alignment from longitudinal vehicle acceleration correlation.
    """

    def __init__(self, frame_convention: str = "ENU"):
        self.convention = frame_convention.upper()
        self.R_p2v = np.eye(3, dtype=np.float64)
        self.is_calibrated = False
        self.angles_deg = {'roll': 0.0, 'pitch': 0.0, 'yaw': 0.0}

    def estimate_leveling(self, stationary_accel: np.ndarray) -> Tuple[float, float, np.ndarray]:
        """
        Stage 1: Leveling from stationary gravity reaction.
        In ENU, stationary sensor reads reaction [0, 0, +g].
        """
        acc_mean = np.mean(stationary_accel, axis=0) if stationary_accel.ndim == 2 else stationary_accel
        norm_a = float(np.linalg.norm(acc_mean))
        if norm_a < 1e-3:
            return 0.0, 0.0, np.eye(3)

        ax, ay, az = acc_mean / norm_a
        pitch = float(np.arcsin(np.clip(-ax, -1.0, 1.0)))
        roll = float(np.arctan2(ay, az))

        # Leveling matrix R_level = Ry(pitch) @ Rx(roll)
        cr, sr = np.cos(roll), np.sin(roll)
        cp, sp = np.cos(pitch), np.sin(pitch)

        R_level = np.array([
            [cp,      sp * sr,  sp * cr],
            [0.0,     cr,      -sr],
            [-sp,     cp * sr,  cp * cr]
        ], dtype=np.float64)

        return roll, pitch, R_level

    def estimate_heading_from_acceleration(
        self,
        accel_leveled: np.ndarray,
        speed_ref: Optional[np.ndarray] = None,
        dt: float = 0.1
    ) -> float:
        """
        Stage 2: Heading (yaw about the vertical) alignment.
        Uses PCA or velocity derivative correlation to find forward axis.
        """
        ax = accel_leveled[:, 0]
        ay = accel_leveled[:, 1]
        a_horiz_mag = np.hypot(ax, ay)
        event_mask = a_horiz_mag > 0.4

        if np.sum(event_mask) < 8:
            # Fallback to horizontal covariance principal axis
            cov = np.cov(ax, ay)
            eigenvals, eigenvecs = np.linalg.eigh(cov)
            primary_vec = eigenvecs[:, np.argmax(eigenvals)]
            return float(np.arctan2(primary_vec[1], primary_vec[0]))

        ax_ev = ax[event_mask]
        ay_ev = ay[event_mask]

        if speed_ref is not None and len(speed_ref) == len(accel_leveled):
            dv = np.gradient(speed_ref, dt)[event_mask]
            test_angles = np.linspace(-np.pi, np.pi, 180)
            corrs = []
            for ang in test_angles:
                a_fwd = np.cos(ang) * ax_ev + np.sin(ang) * ay_ev
                corrs.append(np.corrcoef(a_fwd, dv)[0, 1])
            best_idx = int(np.nanargmax(corrs))
            return float(test_angles[best_idx])

        # SVD principal horizontal direction
        stacked = np.column_stack([ax_ev, ay_ev])
        _, _, vh = np.linalg.svd(stacked)
        fwd_dir = vh[0]
        return float(np.arctan2(fwd_dir[1], fwd_dir[0]))

    def calibrate(
        self,
        accel_raw: np.ndarray,
        gyro_raw: Optional[np.ndarray] = None,
        speed_ref: Optional[np.ndarray] = None,
        stationary_mask: Optional[np.ndarray] = None,
        dt: float = 0.1
    ) -> np.ndarray:
        """
        Execute full two-stage mount calibration.
        Returns:
          R_p2v : (3, 3) rotation matrix mapping phone vectors to vehicle body frame.
        """
        if stationary_mask is not None and np.any(stationary_mask):
            acc_stat = accel_raw[stationary_mask]
        else:
            acc_stat = accel_raw[:min(20, len(accel_raw))]

        roll, pitch, R_level = self.estimate_leveling(acc_stat)
        acc_leveled = (R_level @ accel_raw.T).T

        yaw = self.estimate_heading_from_acceleration(acc_leveled, speed_ref=speed_ref, dt=dt)

        cy, sy = np.cos(yaw), np.sin(yaw)
        R_yaw = np.array([
            [cy,  sy, 0.0],
            [-sy, cy, 0.0],
            [0.0, 0.0, 1.0]
        ], dtype=np.float64)

        self.R_p2v = R_yaw @ R_level
        self.is_calibrated = True
        self.angles_deg = {
            'roll': float(np.degrees(roll)),
            'pitch': float(np.degrees(pitch)),
            'yaw': float(np.degrees(yaw))
        }

        return self.R_p2v.copy()
