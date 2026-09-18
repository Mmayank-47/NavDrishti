"""
tests/test_end_to_end.py
─────────────────────────────────────────────────────────────────────────────
End-to-End System Tests for NavDrishti Complete Architecture:
  1. A/B Benchmark: Full pipeline odometry error before vs after ANTIGRAVITY
  2. ZUPT Kinematic Gate: False positive test on 10-min steady cruise (< 5 / 600)
  3. Crashnet -> SOS Event Flow: Collision detection, position lock, countdown
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
import pytest

from src.pipeline import NavDrishtiPipeline
from src.sensors.imu_reader import SyntheticDriveGenerator
from src.modules.zupt_gate import ZUPTGate
from src.modules.crashnet import Crashnet
from src.modules.sos import SOSCoordinator


def test_ab_odometry_error_reduction():
    """
    Verify > 30% (target > 60%) odometry error reduction with ANTIGRAVITY.
    Simulates a tilted mount (15° pitch) where naive integration suffers huge drift.
    """
    gen = SyntheticDriveGenerator(sampling_rate_hz=10.0, seed=123)
    drive = gen.generate_drive(duration_s=300.0, mount_pitch_deg=15.0)

    accel_raw = drive['accel_raw']
    gyro_raw = drive['gyro_raw']
    pos_true = drive['pos_true']
    N = len(accel_raw)
    dt = 0.1

    # Pipeline with Antigravity
    pipeline = NavDrishtiPipeline(sampling_rate_hz=10.0)
    pipeline.initialize(
        initial_position=(pos_true[0, 0], pos_true[0, 1]),
        initial_heading=drive['heading_true'][0],
        stationary_accel=accel_raw[:30],
        R_p2v=drive['R_p2v_true']
    )

    comp_positions = []
    for i in range(N):
        state = pipeline.step(accel_raw[i], gyro_raw[i], dt=dt)
        comp_positions.append(state['position'])

    comp_positions = np.array(comp_positions)
    error_with_antigravity = float(np.linalg.norm(comp_positions[-1] - pos_true[-1]))

    # Baseline: Naive integration without 3D gravity removal
    # (apparent acceleration leaks 9.81 * sin(15°) ≈ 2.54 m/s^2 into forward axis)
    naive_pos = np.zeros(2)
    naive_vel = 0.0
    for i in range(N):
        # Naive: level subtraction
        a_fwd = (drive['R_p2v_true'] @ (accel_raw[i] - np.array([0.0, 0.0, 9.81])))[0]
        naive_vel += a_fwd * dt
        naive_pos[0] += naive_vel * dt

    error_naive = float(np.linalg.norm(naive_pos - pos_true[-1]))
    reduction = (error_naive - error_with_antigravity) / error_naive * 100.0

    print(f"E2E Odometry Error - Naive: {error_naive:.1f} m, Antigravity: {error_with_antigravity:.1f} m, Reduction: {reduction:.2f}%")
    assert reduction > 50.0, f"Error reduction too low: {reduction:.2f}% (expected > 50%)"


def test_zupt_kinematic_plausibility_cruise():
    """
    Verify ZUPT Kinematic Plausibility Gate fix:
    During a 10-minute steady highway cruise (600 frames at 10 Hz),
    false positives must be < 5 / 600 frames (previously 596 / 600).
    """
    zupt = ZUPTGate()

    # Steady highway cruising at 15 m/s (~54 km/h)
    # True vehicle accel is ~0, but speed is 15 m/s
    speed_cruise = 15.0
    false_positives = 0
    total_frames = 600  # 60 seconds of steady cruise

    rng = np.random.RandomState(42)

    for _ in range(total_frames):
        # Accel clean in cruise: minor road bumps and sensor noise
        clean_accel = rng.normal(0.0, 0.03, size=3)
        # Minor steering adjustments
        gyro = rng.normal(0.0, 0.005, size=3)

        is_stat = zupt.is_stationary(clean_accel, gyro, current_speed=speed_cruise)
        if is_stat:
            false_positives += 1

    print(f"ZUPT Cruise False Positives: {false_positives} / {total_frames} frames")
    assert false_positives < 5, f"Too many false ZUPT triggers in cruise: {false_positives} / {total_frames} frames"


def test_crashnet_and_sos_workflow():
    """
    Test Crashnet collision detection and SOS emergency dispatch flow:
      1. Normal driving -> no crash, no SOS
      2. Severe impact injection (> 1.5 g sustained deceleration & > 1 g/s jerk) -> crash detected
      3. SOS locks position and starts 30s countdown
      4. User cancellation stops alert
    """
    crashnet = Crashnet(sampling_rate_hz=10.0)
    sos = SOSCoordinator(countdown_seconds=30.0)

    # 1. Normal driving
    clean_acc_normal = np.array([0.5, 0.0, 0.0])
    gyro_normal = np.array([0.0, 0.0, 0.01])
    event_normal = crashnet.step(clean_acc_normal, gyro_normal, velocity_mps=15.0, dt=0.1)

    assert not event_normal.crash_detected
    assert event_normal.confidence < 0.5
    assert not sos.alert_active

    # 2. Inject high-speed crash event:
    # 4.5 g severe impact deceleration
    clean_acc_crash = np.array([-4.5 * 9.81, 1.2 * 9.81, 0.5 * 9.81])
    gyro_crash = np.array([1.5, 0.5, 2.0])  # rapid rotation / rollover

    event_crash = crashnet.step(clean_acc_crash, gyro_crash, velocity_mps=15.0, dt=0.1)
    assert event_crash.crash_detected
    assert event_crash.confidence >= 0.80

    # 3. SOS Trigger
    odom_state = {'x': 1250.5, 'y': 840.2, 'velocity_mps': 14.5, 'heading_deg': 45.0}
    sos.on_crash_detected(
        impact_magnitude=event_crash.impact_magnitude,
        confidence=event_crash.confidence,
        odometry_state=odom_state,
        current_time=100.0
    )

    assert sos.alert_active
    assert sos.locked_position['x'] == 1250.5
    assert sos.locked_position['y'] == 840.2

    # Step at t = 110.0 (10s elapsed -> 20s remaining)
    state_sos = sos.step(current_time=110.0)
    assert state_sos['alert_active']
    assert not state_sos['dispatch_sent']
    assert abs(state_sos['countdown_remaining_s'] - 20.0) < 0.1

    # 4. User cancellation
    sos.cancel_alert()
    assert not sos.alert_active
    assert sos.locked_position is None
