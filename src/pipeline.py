"""
src/pipeline.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Main Pipeline Orchestration
Connects all four architectural layers into a unified step() runtime:
  Layer 1: Raw Sensor Input (IMUReader)
  Layer 2: Signal Processing & Correction (Antigravity)
  Layer 3: Dead Reckoning Pipeline (AlignmentEngine, ZUPTGate, OdometryPipeline)
  Layer 4: Event Detection & Recovery (Crashnet, SOSCoordinator)
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Dict, Any, Tuple
import numpy as np

from src.modules.antigravity import Antigravity, AntigravityOutput
from src.modules.alignment_engine import AlignmentEngine
from src.modules.zupt_gate import ZUPTGate
from src.modules.odometry import OdometryPipeline
from src.modules.crashnet import Crashnet, CrashEvent
from src.modules.sos import SOSCoordinator


class NavDrishtiPipeline:
    """
    Unified Dead-Reckoning & Incident Detection Pipeline.
    """

    def __init__(
        self,
        sampling_rate_hz: float = 10.0,
        enable_crashnet: bool = True,
        enable_sos: bool = True
    ):
        self.fs = float(sampling_rate_hz)
        self.dt = 1.0 / self.fs
        self.step_count = 0

        # Layer 2: Antigravity
        self.antigravity = Antigravity(sampling_rate_hz=self.fs)

        # Layer 3: Alignment, ZUPT, Odometry
        self.alignment = AlignmentEngine()
        self.zupt = ZUPTGate()
        self.odometry = OdometryPipeline()

        # Layer 4: Crashnet & SOS
        self.crashnet = Crashnet(sampling_rate_hz=self.fs) if enable_crashnet else None
        self.sos = SOSCoordinator() if enable_sos else None

        self.R_p2v = np.eye(3, dtype=np.float64)
        self.is_initialized = False

    def initialize(
        self,
        initial_position: Tuple[float, float] = (0.0, 0.0),
        initial_heading: float = 0.0,
        initial_speed: float = 0.0,
        stationary_accel: Optional[np.ndarray] = None,
        stationary_gyro: Optional[np.ndarray] = None,
        R_p2v: Optional[np.ndarray] = None
    ):
        """Initialize all layers."""
        self.step_count = 0
        self.odometry.reset(position=initial_position, heading=initial_heading, velocity=initial_speed)
        self.zupt.reset()

        if R_p2v is not None:
            self.R_p2v = np.asarray(R_p2v, dtype=np.float64)
        else:
            self.R_p2v = np.eye(3, dtype=np.float64)

        self.antigravity.initialize(
            stationary_accel=stationary_accel,
            stationary_gyro=stationary_gyro,
            initial_heading=initial_heading
        )

        if self.crashnet:
            self.crashnet.reset()
        if self.sos:
            self.sos.cancel_alert()

        self.is_initialized = True

    def step(
        self,
        accel_raw: np.ndarray,
        gyro_raw: np.ndarray,
        dt: Optional[float] = None,
        mag_raw: Optional[np.ndarray] = None,
        gnss: Optional[Dict[str, float]] = None,
        current_time: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Execute one complete step of NavDrishti at 10 Hz.

        Data Flow:
          1. ANTIGRAVITY removes gravity and tracks R_v2w
          2. Transform accel_clean and gyro into vehicle body frame (R_p2v)
          3. Kinematic Plausibility ZUPT Gate detects true stationary phase
          4. Odometry integrates clean kinematic acceleration
          5. Crashnet detects collisions and triggers SOS
        """
        dt = float(dt if dt is not None else self.dt)
        self.step_count += 1

        # ── Step 1: ANTIGRAVITY (Layer 2) ──────────────────────────────────
        ag_out: AntigravityOutput = self.antigravity.step(
            accel_raw=accel_raw,
            gyro=gyro_raw,
            dt=dt,
            mag=mag_raw
        )

        # ── Step 2: Transform to Vehicle Reference Frame ───────────────────
        # acc_veh: X = Forward, Y = Lateral, Z = Vertical
        acc_veh = self.R_p2v @ ag_out.accel_clean
        gyr_veh = self.R_p2v @ np.asarray(gyro_raw[:3], dtype=np.float64)

        # ── Step 3: Kinematic Plausibility ZUPT Gate (Layer 3) ──────────────
        current_v = self.odometry.velocity
        is_stationary = self.zupt.is_stationary(
            accel_clean=acc_veh,
            gyro=gyr_veh,
            current_speed=current_v
        )

        # ── Step 4: Dead Reckoning Odometry (Layer 3) ───────────────────────
        mag_corr = 0.0
        if gnss is not None and gnss.get('speed', 0.0) > 3.0 and 'heading' in gnss:
            # Complementary alignment against GNSS course-over-ground
            gnss_h = np.radians(gnss['heading'])
            d_h = (gnss_h - self.odometry.heading + np.pi) % (2.0 * np.pi) - np.pi
            mag_corr = 0.05 * d_h

        odom_state = self.odometry.update(
            accel_clean_veh=acc_veh,
            gyro_veh=gyr_veh,
            dt=dt,
            is_stationary=is_stationary,
            mag_correction=mag_corr
        )

        # ── Step 5: Event Detection & Recovery (Layer 4) ────────────────────
        crash_event = None
        sos_state = None

        if self.crashnet:
            crash_event = self.crashnet.step(
                accel_clean=acc_veh,
                gyro=gyr_veh,
                velocity_mps=self.odometry.velocity,
                dt=dt
            )

            if self.sos and crash_event.crash_detected:
                self.sos.on_crash_detected(
                    impact_magnitude=crash_event.impact_magnitude,
                    confidence=crash_event.confidence,
                    odometry_state=odom_state,
                    current_time=current_time
                )

        if self.sos:
            sos_state = self.sos.step(current_time=current_time)

        return {
            'step': self.step_count,
            'accel_clean': ag_out.accel_clean,
            'accel_veh': acc_veh,
            'g_phone': ag_out.g_phone,
            'R_v2w': ag_out.R_v2w_updated,
            'tilt_angle_rad': ag_out.tilt_angle,
            'drift_confidence': ag_out.drift_confidence,
            'is_stationary': is_stationary,
            'position': np.array([odom_state['x'], odom_state['y']]),
            'velocity_mps': odom_state['velocity_mps'],
            'heading_deg': odom_state['heading_deg'],
            'total_distance_m': odom_state['total_distance_m'],
            'crash': crash_event,
            'sos': sos_state
        }
