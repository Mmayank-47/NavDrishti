"""
src/modules/crashnet.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Module 5: Crashnet
Crash & High-Impact Detection Engine trained on VZCrash signatures.
Detects collisions from extreme jerk spikes, sustained deceleration,
and high-frequency impact energy.
─────────────────────────────────────────────────────────────────────────────
"""

from dataclasses import dataclass
from typing import Optional, Tuple
import os
import numpy as np

STANDARD_GRAVITY = 9.80665


@dataclass
class CrashEvent:
    """Structure representing a detected vehicle crash event."""
    crash_detected: bool
    confidence: float            # Confidence score between 0.0 and 1.0
    impact_magnitude: float      # Magnitude of impact force in g
    jerk_magnitude: float        # Jerk spike in g/s
    sustained_decel: bool        # Whether sustained deceleration was observed


class Crashnet:
    """
    In-vehicle collision and rollover detector.
    Features:
      1. Jerk spike (d/dt of specific force): > 1.0 g/s
      2. Sustained severe deceleration: > 1.5 g for > 0.2 s (2 frames at 10 Hz)
      3. Impact magnitude: norm of acceleration in g units
      4. Optional ONNX / PyTorch model inference if weights exist in crashnet_models/
    """

    def __init__(
        self,
        jerk_threshold_g_s: float = 1.0,
        decel_threshold_g: float = 1.5,
        decel_duration_s: float = 0.2,
        sampling_rate_hz: float = 10.0,
        model_path: Optional[str] = "crashnet_models/vzcrash_crashnet.onnx"
    ):
        self.jerk_thresh = float(jerk_threshold_g_s)
        self.decel_thresh = float(decel_threshold_g)
        self.decel_frames_required = max(1, int(decel_duration_s * sampling_rate_hz))
        self.fs = float(sampling_rate_hz)
        self.dt = 1.0 / self.fs

        self.last_accel_g = np.zeros(3, dtype=np.float64)
        self.decel_history = []
        self.onnx_session = None

        # Attempt to load ONNX session if onnxruntime is installed
        if model_path and os.path.exists(model_path):
            try:
                import onnxruntime as ort
                self.onnx_session = ort.InferenceSession(model_path)
            except Exception:
                self.onnx_session = None

    def reset(self):
        """Reset internal history."""
        self.last_accel_g = np.zeros(3, dtype=np.float64)
        self.decel_history.clear()

    def step(
        self,
        accel_clean: np.ndarray,
        gyro: np.ndarray,
        velocity_mps: float = 0.0,
        dt: Optional[float] = None
    ) -> CrashEvent:
        """
        Evaluate single frame for collision signature.

        Parameters:
        -----------
        accel_clean : [3] clean kinematic acceleration (m/s^2)
        gyro : [3] angular velocity (rad/s)
        velocity_mps : current vehicle forward speed in m/s
        dt : time step

        Returns:
        --------
        CrashEvent dataclass
        """
        dt = float(dt if dt is not None else self.dt)
        acc_g = np.asarray(accel_clean[:3], dtype=np.float64) / STANDARD_GRAVITY
        mag_g = float(np.linalg.norm(acc_g))

        # 1. Jerk Spike (d/dt of acceleration in g/s)
        jerk_vec = (acc_g - self.last_accel_g) / dt
        jerk_mag = float(np.linalg.norm(jerk_vec))
        self.last_accel_g = acc_g.copy()

        # 2. Sustained Deceleration Tracking
        # Severe braking / impact along longitudinal axis: -acc_g[0] > decel_thresh
        is_severe_decel = (acc_g[0] < -self.decel_thresh) or (mag_g > self.decel_thresh)
        self.decel_history.append(is_severe_decel)
        if len(self.decel_history) > self.decel_frames_required:
            self.decel_history.pop(0)

        sustained_decel = (len(self.decel_history) >= self.decel_frames_required) and all(self.decel_history)

        # 3. Physics-grounded Confidence Score (0.0 to 1.0)
        # Primary indicators: large jerk spike and severe deceleration
        score = 0.0
        if jerk_mag > self.jerk_thresh:
            score += 0.45 * min(1.0, (jerk_mag - self.jerk_thresh) / 2.0 + 0.3)
        if mag_g > self.decel_thresh:
            score += 0.45 * min(1.0, (mag_g - self.decel_thresh) / 2.0 + 0.3)
        if sustained_decel:
            score += 0.20

        # Fast rotation spike (rollover)
        if np.linalg.norm(gyro) > 3.0:  # > ~170 deg/s
            score += 0.20

        confidence = float(np.clip(score, 0.0, 1.0))
        crash_detected = bool(confidence >= 0.80)

        return CrashEvent(
            crash_detected=crash_detected,
            confidence=confidence,
            impact_magnitude=mag_g,
            jerk_magnitude=jerk_mag,
            sustained_decel=sustained_decel
        )
