"""
src/modules/zupt_gate.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Module 3: ZUPT Gate (Zero-Velocity Update)
Fixed with Kinematic Plausibility Gate to eliminate the 596/600 false
positive triggers during steady highway cruising.
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Union
import numpy as np


class ZUPTGate:
    """
    Kinematic Plausibility Zero-Velocity Update (ZUPT) Gate.
    Consumes gravity-removed kinematic acceleration (accel_clean) from ANTIGRAVITY.
    """

    def __init__(
        self,
        accel_threshold: float = 0.1,    # m/s^2 maximum clean accel norm
        yaw_rate_threshold: float = 0.5, # rad/s (~28.6 deg/s) maximum turn rate
        variance_window: int = 5,
        var_acc_threshold: float = 0.02,
        var_gyr_threshold: float = 0.005
    ):
        self.accel_thresh = float(accel_threshold)
        self.yaw_rate_thresh = float(yaw_rate_threshold)
        self.window_size = int(variance_window)
        self.var_a_thresh = float(var_acc_threshold)
        self.var_g_thresh = float(var_gyr_threshold)

        self.acc_mag_buffer = []
        self.gyr_mag_buffer = []
        self.stationary_count = 0

    def reset(self):
        """Reset rolling variance buffers."""
        self.acc_mag_buffer.clear()
        self.gyr_mag_buffer.clear()
        self.stationary_count = 0

    def is_stationary(
        self,
        accel_clean: np.ndarray,
        gyro: np.ndarray,
        current_speed: Optional[float] = None
    ) -> bool:
        """
        Evaluate if vehicle is truly stationary.

        Kinematic Plausibility Condition:
          accel_ok = norm(accel_clean) < 0.1 m/s^2
          heading_ok = abs(gyro[2]) < 0.5 rad/s
          stationary = accel_ok AND heading_ok
        """
        a_clean = np.asarray(accel_clean[:3], dtype=np.float64)
        g = np.asarray(gyro[:3], dtype=np.float64)

        acc_norm = float(np.linalg.norm(a_clean))
        gyr_yaw_rate = float(abs(g[2]))
        gyr_norm = float(np.linalg.norm(g))

        self.acc_mag_buffer.append(acc_norm)
        self.gyr_mag_buffer.append(gyr_norm)
        if len(self.acc_mag_buffer) > self.window_size:
            self.acc_mag_buffer.pop(0)
            self.gyr_mag_buffer.pop(0)

        # 1. Kinematic Plausibility Gate
        accel_ok = acc_norm < self.accel_thresh
        heading_ok = gyr_yaw_rate < self.yaw_rate_thresh

        # 2. Window variance check for micro-vibrations
        var_ok = True
        if len(self.acc_mag_buffer) >= self.window_size:
            var_a = float(np.var(self.acc_mag_buffer))
            var_g = float(np.var(self.gyr_mag_buffer))
            var_ok = (var_a < self.var_a_thresh) and (var_g < self.var_g_thresh)

        # 3. Speed sanity check (if speed estimate is already high, don't abruptly zero on a 1-frame dip)
        speed_ok = True
        if current_speed is not None and current_speed > 3.0:
            speed_ok = False

        stationary = accel_ok and heading_ok and var_ok and speed_ok

        if stationary:
            self.stationary_count += 1
        else:
            self.stationary_count = 0

        return stationary

    def apply_zupt(
        self,
        velocity: np.ndarray,
        accel_clean: np.ndarray,
        gyro: np.ndarray
    ) -> np.ndarray:
        """Apply ZUPT constraint to velocity vector."""
        if self.is_stationary(accel_clean, gyro, current_speed=float(np.linalg.norm(velocity))):
            return np.zeros_like(velocity)
        return velocity
