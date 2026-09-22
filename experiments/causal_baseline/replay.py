"""Strict pre-outage initializer and blackout replay; reference is read only after propagation."""
from dataclasses import dataclass
import numpy as np
from .baselines import ConstantVelocity, GyroHeadingSpeed

@dataclass(frozen=True)
class InitialState:
    position_enu_m: np.ndarray; velocity_enu_mps: np.ndarray; source_time_s: float; heading_rad: float | None
@dataclass(frozen=True)
class ReplayResult:
    trajectory: np.ndarray; endpoint_error_m: float | None; status: str; reason: str | None = None

def initialize_before(session, t0, min_motion_s=1.):
    if session.reference_enu_m is None: raise ValueError("reference unavailable for pre-outage initialization")
    idx = np.where(session.time_s < t0)[0]
    if len(idx) < 2: raise ValueError("insufficient strictly pre-outage observations")
    j, i = idx[-2], idx[-1]; dt = session.time_s[i] - session.time_s[j]
    if dt < min_motion_s: raise ValueError("pre-outage motion interval too short")
    v = (session.reference_enu_m[i] - session.reference_enu_m[j]) / dt
    heading = None if np.linalg.norm(v) == 0 else float(np.arctan2(v[1], v[0]))
    return InitialState(session.reference_enu_m[i].copy(), v, float(session.time_s[i]), heading)

def replay_outage(session, initial, t0, t1, mode, phone_to_vehicle=None):
    if not t1 > t0: raise ValueError("t1 must exceed t0")
    p0 = initial.position_enu_m + initial.velocity_enu_mps * (t0 - initial.source_time_s)
    samples = session.time_s[(session.time_s > t0) & (session.time_s <= t1)]
    times = np.r_[t0, samples[samples < t1], t1]
    times = np.unique(times)
    if mode == "constant_velocity":
        b = ConstantVelocity(p0, initial.velocity_enu_mps); positions = np.array([b.position_at(x-t0) for x in times])
    elif mode == "gyro_heading_speed":
        if phone_to_vehicle is None: raise ValueError("phone-to-vehicle rotation required")
        b = GyroHeadingSpeed(p0, initial.velocity_enu_mps, initial.heading_rad); positions = [p0.copy()]
        for a, z in zip(times[:-1], times[1:]):
            k = np.searchsorted(session.time_s, a, side="right") - 1
            yaw = float((phone_to_vehicle @ session.gyro_phone_rad_s[k])[2])
            positions.append(b.step(z-a, yaw))
        positions = np.asarray(positions)
    else: raise ValueError("unknown baseline mode")
    error, status, reason = None, "OK", None
    if session.reference_enu_m is not None:
        k = np.where(np.isclose(session.time_s, t1))[0]
        if not len(k): raise ValueError("reference unavailable at exact t1")
        error = float(np.linalg.norm(positions[-1] - session.reference_enu_m[k[0]]))
    else:
        status, reason = "NOT_EVALUABLE", "reference unavailable at t1"
    return ReplayResult(np.column_stack([times, positions]), error, status, reason)
