"""Deterministic two-dimensional causal propagation baselines."""
import numpy as np

def rotation_phone_to_vehicle_z(yaw_rad):
    c, s = np.cos(yaw_rad), np.sin(yaw_rad)
    return np.array([[c, -s, 0.], [s, c, 0.], [0., 0., 1.]])

class ConstantVelocity:
    forbidden_inputs = {"gyro", "gnss_speed", "vehicle_speed", "reference_position"}
    def __init__(self, position_enu_m, velocity_enu_mps): self.position0, self.velocity = np.array(position_enu_m, float), np.array(velocity_enu_mps, float)
    def position_at(self, elapsed_s): return self.position0 + self.velocity * float(elapsed_s)

class GyroHeadingSpeed:
    forbidden_inputs = {"gnss_speed", "vehicle_speed", "reference_position"}
    def __init__(self, position_enu_m, velocity_enu_mps, heading_rad=None):
        self.position = np.array(position_enu_m, float); self.speed = float(np.linalg.norm(velocity_enu_mps)); self.heading = 0. if heading_rad is None else float(heading_rad)
    def step(self, dt_s, yaw_rate_rad_s):
        if not np.isfinite(yaw_rate_rad_s): raise ValueError("forbidden or invalid gyro input")
        mid = self.heading + .5 * yaw_rate_rad_s * dt_s
        self.position += self.speed * dt_s * np.array([np.cos(mid), np.sin(mid)])
        self.heading += yaw_rate_rad_s * dt_s
        return self.position.copy()
