"""
src/modules/odometry.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Module 4: Odometry Pipeline
Dead-reckoning integration of gravity-removed acceleration into velocity,
2D planar position, and fused heading state.
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Dict, Tuple
import numpy as np


class OdometryPipeline:
    """
    Dead-reckoning odometry integrator.
    Consumes gravity-free kinematic acceleration from ANTIGRAVITY.
    """

    def __init__(
        self,
        initial_position: Tuple[float, float] = (0.0, 0.0),
        initial_heading: float = 0.0,
        initial_speed: float = 0.0
    ):
        self.x = float(initial_position[0])
        self.y = float(initial_position[1])
        self.heading = float(initial_heading)  # radians [-pi, pi]
        self.velocity = float(initial_speed)   # longitudinal velocity m/s
        self.total_distance = 0.0

    def reset(
        self,
        position: Tuple[float, float] = (0.0, 0.0),
        heading: float = 0.0,
        velocity: float = 0.0
    ):
        """Reset odometry state."""
        self.x = float(position[0])
        self.y = float(position[1])
        self.heading = float(heading)
        self.velocity = float(velocity)
        self.total_distance = 0.0

    def update(
        self,
        accel_clean_veh: np.ndarray,
        gyro_veh: np.ndarray,
        dt: float = 0.1,
        is_stationary: bool = False,
        mag_correction: float = 0.0
    ) -> Dict[str, float]:
        """
        Execute one odometry step.

        Parameters:
        -----------
        accel_clean_veh : [3] clean kinematic acceleration in vehicle frame (m/s^2)
        gyro_veh : [3] angular velocity in vehicle frame (rad/s)
        dt : timestep in seconds
        is_stationary : ZUPT flag from ZUPTGate
        mag_correction : optional heading innovation from magnetometer / GNSS
        """
        dt = float(dt)
        a_fwd = float(accel_clean_veh[0])
        yaw_rate = float(gyro_veh[2])

        # 1. Heading integration
        self.heading = (self.heading + yaw_rate * dt + mag_correction + np.pi) % (2.0 * np.pi) - np.pi

        # 2. Longitudinal velocity integration with ZUPT gating
        if is_stationary:
            self.velocity = 0.0
        else:
            self.velocity = max(0.0, self.velocity + a_fwd * dt)

        # 3. Position integration
        dx = self.velocity * np.cos(self.heading) * dt
        dy = self.velocity * np.sin(self.heading) * dt

        self.x += dx
        self.y += dy
        self.total_distance += float(np.hypot(dx, dy))

        return self.get_state()

    def get_state(self) -> Dict[str, float]:
        """Return current kinematics for downstream modules (e.g. SOS position lock)."""
        return {
            'x': float(self.x),
            'y': float(self.y),
            'heading_rad': float(self.heading),
            'heading_deg': float(np.degrees(self.heading)),
            'velocity_mps': float(self.velocity),
            'speed_kmh': float(self.velocity * 3.6),
            'total_distance_m': float(self.total_distance)
        }
