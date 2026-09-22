"""Canonical SI adapter.  ENU is [east, north] metres; phone gyro is [x,y,z] rad/s."""
from dataclasses import dataclass, field
import numpy as np

@dataclass(frozen=True)
class TimestampPolicy:
    max_gap_s: float = 2.0  # configurable; chosen to reject gaps >20x the legacy nominal 10 Hz.
    action: str = "reject"

@dataclass(frozen=True)
class CanonicalSession:
    time_s: np.ndarray
    accel_phone_mps2: np.ndarray
    gyro_phone_rad_s: np.ndarray
    reference_enu_m: np.ndarray | None = None  # scorer-only; no measurement-time exists in source CSV.
    gnss_speed_mps: np.ndarray | None = None
    policy: TimestampPolicy = field(default_factory=TimestampPolicy)
    conversion_history: tuple = ()

    def __post_init__(self):
        n = len(self.time_s)
        if n < 1 or self.accel_phone_mps2.shape != (n, 3) or self.gyro_phone_rad_s.shape != (n, 3):
            raise ValueError("time and IMU must be finite Nx3 arrays")
        if not np.all(np.isfinite(self.time_s)) or not np.all(np.isfinite(self.accel_phone_mps2)) or not np.all(np.isfinite(self.gyro_phone_rad_s)):
            raise ValueError("canonical estimator inputs must be finite")
        dt = np.diff(self.time_s)
        if np.any(dt <= 0): raise ValueError("duplicate or reversed timestamps")
        if self.policy.action == "reject" and np.any(dt > self.policy.max_gap_s): raise ValueError("timestamp gap exceeds policy")
        if self.reference_enu_m is not None and self.reference_enu_m.shape != (n, 2): raise ValueError("reference must be Nx2 ENU metres")

    @property
    def segments(self):
        cuts = np.where(np.diff(self.time_s) > self.policy.max_gap_s)[0] + 1
        return tuple(CanonicalSession(self.time_s[a:b], self.accel_phone_mps2[a:b], self.gyro_phone_rad_s[a:b],
                    None if self.reference_enu_m is None else self.reference_enu_m[a:b],
                    None if self.gnss_speed_mps is None else self.gnss_speed_mps[a:b], TimestampPolicy(self.policy.max_gap_s, "segment"), self.conversion_history)
                    for a, b in zip(np.r_[0, cuts], np.r_[cuts, len(self.time_s)]))

def adapt_arrays(timestamps, accel, gyro, *, timestamp_unit="s", gyro_unit="rad/s", max_gap_s=2., gap_action="reject", conversion_history=()):
    if any("gyro:" in str(x) for x in conversion_history) and gyro_unit == "rad/s":
        raise ValueError("gyro already SI; refusing double conversion")
    factor = {"s": 1., "ms": .001}[timestamp_unit]
    gyro_factor = {"rad/s": 1., "deg/s": np.pi / 180.}[gyro_unit]
    t = np.asarray(timestamps, float) * factor
    t -= t[0]
    history = tuple(conversion_history) + (("timestamp:ms->s",) if timestamp_unit == "ms" else ()) + (("gyro:deg/s->rad/s",) if gyro_unit == "deg/s" else ())
    return CanonicalSession(t, np.asarray(accel, float), np.asarray(gyro, float) * gyro_factor, policy=TimestampPolicy(max_gap_s, gap_action), conversion_history=history)
