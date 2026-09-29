"""Strict pre-outage initializer and blackout replay; reference is read only after propagation."""
from dataclasses import dataclass
import numpy as np
from .baselines import ConstantVelocity, GyroHeadingSpeed

@dataclass(frozen=True)
class InitialState:
    position_enu_m: np.ndarray; velocity_enu_mps: np.ndarray; source_time_s: float; heading_rad: float | None; interval_start_s: float = 0.; interval_end_s: float = 0.; source_type: str = "past_chord_approximation"
@dataclass(frozen=True)
class ReplayResult:
    trajectory: np.ndarray; endpoint_error_m: float | None; status: str; reason: str | None = None

def initialize_before(session, t0, min_motion_s=1., max_history_s=5., max_extrapolation_s=2.):
    if not np.isfinite(t0): raise ValueError("nonfinite outage onset")
    if session.reference_enu_m is None: raise ValueError("reference unavailable for pre-outage initialization")
    idx = np.where(session.time_s < t0)[0]
    if len(idx) < 2: raise ValueError("insufficient strictly pre-outage observations")
    i = idx[-1]
    candidates = idx[(session.time_s[i] - session.time_s[idx] >= min_motion_s) & (session.time_s[i] - session.time_s[idx] <= max_history_s)]
    if not len(candidates): raise ValueError("insufficient usable past history")
    j = candidates[-1]; dt = session.time_s[i] - session.time_s[j]
    if t0 - session.time_s[i] > max_extrapolation_s: raise ValueError("initialization extrapolation exceeds policy")
    if not np.all(np.isfinite(session.reference_enu_m[[j,i]])): raise ValueError("invalid pre-outage reference")
    v = (session.reference_enu_m[i] - session.reference_enu_m[j]) / dt
    if np.linalg.norm(v) == 0: raise ValueError("held or insufficient motion; not certified stationary")
    heading = float(np.arctan2(v[1], v[0]))
    return InitialState(session.reference_enu_m[i].copy(), v, float(session.time_s[i]), heading, float(session.time_s[j]), float(session.time_s[i]))

def replay_outage(session, initial, t0, t1, mode, phone_to_vehicle=None, max_gyro_age_s=None, endpoint_atol_s=1e-9):
    if not np.isfinite(t0) or not np.isfinite(t1) or not t1 > t0: raise ValueError("invalid outage bounds")
    if not np.isfinite(initial.source_time_s) or initial.source_time_s >= t0: raise ValueError("initial source must be strictly before t0")
    if not np.all(np.isfinite(initial.position_enu_m)) or not np.all(np.isfinite(initial.velocity_enu_mps)): raise ValueError("invalid initial state")
    if t0 - initial.source_time_s > 2.: raise ValueError("initial extrapolation exceeds policy")
    if np.any((np.diff(session.time_s) > session.policy.max_gap_s) & (session.time_s[:-1] < t1) & (session.time_s[1:] > t0)): raise ValueError("outage crosses timestamp gap")
    p0 = initial.position_enu_m + initial.velocity_enu_mps * (t0 - initial.source_time_s)
    samples = session.time_s[(session.time_s > t0) & (session.time_s <= t1)]
    times = np.r_[t0, samples[samples < t1], t1]
    times = np.unique(times)
    if mode == "constant_velocity":
        b = ConstantVelocity(p0, initial.velocity_enu_mps); positions = np.array([b.position_at(x-t0) for x in times])
    elif mode == "gyro_heading_speed":
        if phone_to_vehicle is None or np.asarray(phone_to_vehicle).shape != (3,3) or not np.all(np.isfinite(phone_to_vehicle)): raise ValueError("valid phone-to-vehicle rotation required")
        b = GyroHeadingSpeed(p0, initial.velocity_enu_mps, initial.heading_rad); positions = [p0.copy()]
        for a, z in zip(times[:-1], times[1:]):
            k = np.searchsorted(session.time_s, a, side="right") - 1
            age = a - session.time_s[k] if k >= 0 else np.inf
            if k < 0 or age > (session.policy.max_gap_s if max_gyro_age_s is None else max_gyro_age_s): raise ValueError("gyro coverage unavailable at interval start")
            yaw = float((phone_to_vehicle @ session.gyro_phone_rad_s[k])[2])
            positions.append(b.step(z-a, yaw))
        positions = np.asarray(positions)
    else: raise ValueError("unknown baseline mode")
    error, status, reason = None, "OK", None
    if session.reference_enu_m is not None:
        k = np.where(np.abs(session.time_s - t1) <= endpoint_atol_s)[0]
        if len(k) and np.all(np.isfinite(session.reference_enu_m[k[0]])): error = float(np.linalg.norm(positions[-1] - session.reference_enu_m[k[0]]))
        else: status, reason = "NOT_EVALUABLE", "reference unavailable at exact t1"
    else:
        status, reason = "NOT_EVALUABLE", "reference unavailable at t1"
    return ReplayResult(np.column_stack([times, positions]), error, status, reason)
