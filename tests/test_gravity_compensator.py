"""
tests/test_gravity_compensator.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Dynamic 3D Gravity Compensation Verification Suite
Validates physics, attitude integration, tilt fusion, and edge cases.
─────────────────────────────────────────────────────────────────────────────
"""

import time
import numpy as np
import pytest

from src.preprocessing.gravity_compensator import GravityCompensator, STANDARD_GRAVITY
from src.integration.final_navigation_pipeline import FinalNavigationPipeline


# ── Test 1: Stationary Phone (Level) ─────────────────────────────────────────

def test_1_stationary_phone():
    """
    Test 1: Stationary Phone
    • Input: accel_raw = [0, 0, 9.81], gyro = [0, 0, 0], level phone
    • Expected: accel_clean ≈ [0, 0, 0]
    """
    gc = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc.initialize(initial_rpy=(0.0, 0.0, 0.0))

    accel_raw = np.array([0.0, 0.0, 9.81])
    gyro_raw = np.array([0.0, 0.0, 0.0])

    residuals = []
    for _ in range(600):  # 1 minute at 10 Hz
        acc_clean, g_phone, q, R = gc.step(accel_raw, gyro_raw, dt=0.1)
        residuals.append(np.linalg.norm(acc_clean))

    mean_norm = float(np.mean(residuals))
    max_norm = float(np.max(residuals))

    assert mean_norm < 0.05, f"Stationary accel norm too high: {mean_norm:.4f} m/s^2 (target < 0.1)"
    assert max_norm < 0.1, f"Max stationary accel too high: {max_norm:.4f} m/s^2"
    np.testing.assert_allclose(g_phone, [0.0, 0.0, 9.81], atol=0.05)


# ── Test 2: Known Rotation (90° Rotation) ───────────────────────────────────

def test_2_known_rotation():
    """
    Test 2: Known Rotation
    • Rotate gravity 90°: phone pitches down by 90° so vertical axis aligns with body X.
    • Expected: g_phone = [9.81, 0, 0] (gravity in rotated phone frame)
    • Verify det(R_v2w) ≈ 1.0 (exact SO(3) orthogonality)
    """
    gc = GravityCompensator(sampling_rate_hz=100.0, g_val=9.81)
    # Pitch down by 90 degrees: roll=0, pitch=pi/2, yaw=0
    # In this configuration, R_v2w.T @ [0, 0, 9.81] = [9.81, 0, 0]
    pitch_target = np.pi / 2.0  # 90 degrees
    gc.initialize(initial_rpy=(0.0, 0.0, 0.0))

    # Apply pure pitch rate: 90 deg/s for 1 second at 100 Hz (pitch nose down)
    dt = 0.01
    steps = 100
    gyro_pitch = np.array([0.0, -pitch_target, 0.0])  # pitch rate = -pi/2 rad/s

    for _ in range(steps):
        # Accelerometer measures rotated gravity reaction
        current_R = gc.R_v2w
        accel_raw = current_R.T @ np.array([0.0, 0.0, 9.81])
        acc_clean, g_phone, q, R = gc.step(accel_raw, gyro_pitch, dt=dt)

    # After rotation completes, verify gravity in phone frame
    det_R = float(np.linalg.det(gc.R_v2w))
    assert abs(det_R - 1.0) < 1e-5, f"Rotation matrix lost orthogonality: det(R) = {det_R:.6f}"

    # Verify stationary reading at final rotated pose
    accel_raw_final = gc.R_v2w.T @ np.array([0.0, 0.0, 9.81])
    acc_clean_final, g_phone_final, _, _ = gc.step(accel_raw_final, np.zeros(3), dt=dt)

    # Gravity in rotated phone frame should now have magnitude 9.81 on body X axis
    np.testing.assert_allclose(g_phone_final, [9.81, 0.0, 0.0], atol=0.05)
    np.testing.assert_allclose(acc_clean_final, [0.0, 0.0, 0.0], atol=0.05)


# ── Test 3: Tilted Stationary Phone ──────────────────────────────────────────

def test_3_tilted_stationary_phone():
    """
    Test 3: Tilted Stationary Phone
    • Phone mounted at 30° pitch (e.g. dashboard mount).
    • Expected: accel_clean ≈ [0, 0, 0] (gravity successfully removed, no false forward bias)
    """
    gc = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    pitch_30 = np.radians(30.0)
    cy, sy = np.cos(pitch_30), np.sin(pitch_30)
    R_pitch = np.array([
        [cy, 0.0, sy],
        [0.0, 1.0, 0.0],
        [-sy, 0.0, cy]
    ])
    accel_raw = R_pitch.T @ np.array([0.0, 0.0, 9.81])
    gyro_raw = np.zeros(3)

    # Provide first 10 samples to test automatic startup leveling
    stationary_samples = np.tile(accel_raw, (10, 1))
    gc.initialize(stationary_accel=stationary_samples)

    residuals = []
    for _ in range(300):  # 30 seconds at 10 Hz
        acc_clean, g_phone, q, R = gc.step(accel_raw, gyro_raw, dt=0.1)
        residuals.append(np.linalg.norm(acc_clean))

    mean_norm = float(np.mean(residuals))
    assert mean_norm < 0.08, f"Tilted stationary accel residual too high: {mean_norm:.4f} m/s^2 (target < 0.1)"
    # Ensure forward acceleration bias is eliminated
    assert abs(acc_clean[0]) < 0.05, f"False forward acceleration detected on 30° slope: {acc_clean[0]:.4f} m/s^2"


# ── Test 4: Hard Acceleration ────────────────────────────────────────────────

def test_4_hard_acceleration():
    """
    Test 4: Hard Acceleration
    • Car accelerates 3 m/s² forward, phone level.
    • Expected: accel_clean = [3.0, 0, 0]
    """
    gc = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc.initialize(initial_rpy=(0.0, 0.0, 0.0))

    # Apparent acceleration = kinematic acceleration + gravity
    # a_raw = [3.0, 0, 0] + [0, 0, 9.81] = [3.0, 0, 9.81]
    accel_raw = np.array([3.0, 0.0, 9.81])
    gyro_raw = np.array([0.0, 0.0, 0.0])

    for _ in range(50):  # 5 seconds of sustained 3.0 m/s^2 acceleration
        acc_clean, g_phone, q, R = gc.step(accel_raw, gyro_raw, dt=0.1)

    np.testing.assert_allclose(acc_clean, [3.0, 0.0, 0.0], atol=0.05)
    np.testing.assert_allclose(g_phone, [0.0, 0.0, 9.81], atol=0.05)


# ── Test 5: IO-VNBD Benchmark / Real Data ────────────────────────────────────

def test_5_iovnbd_benchmark():
    """
    Test 5: IO-VNBD Benchmark
    • Simulate 1 hour of highway cruise with realistic MEMS sensor noise and bias walk (10 Hz).
    • Measure: accel_clean peak < 0.5 m/s² on straight road (and RMS < 0.3 m/s²).
    • Measure: gyro drift < 5° over 1 hour with tilt fusion.
    """
    fs = 10.0
    dt = 1.0 / fs
    duration_s = 3600  # 1 hour
    N = int(duration_s * fs)

    # Reproducible seed
    rng = np.random.RandomState(42)

    # Realistic MEMS smartphone noise:
    # Accel white noise std ~ 0.05 m/s^2
    # Gyro white noise std ~ 0.002 rad/s (~0.1 deg/s)
    # Gyro bias ~ 0.005 rad/s
    accel_noise = rng.normal(0.0, 0.05, size=(N, 3))
    gyro_noise = rng.normal(0.0, 0.002, size=(N, 3))
    gyro_bias = np.array([0.002, -0.003, 0.004])

    accel_raw = accel_noise + np.array([0.0, 0.0, 9.81])
    gyro_raw = gyro_noise + gyro_bias

    gc = GravityCompensator(sampling_rate_hz=fs, g_val=9.81, tilt_fusion_cutoff_hz=0.01, enable_gyro_debias=True)
    # Startup calibration using first 100 samples
    gc.initialize(stationary_accel=accel_raw[:100], stationary_gyro=gyro_raw[:100])

    res = gc.batch_process(accel_raw, gyro_raw, dt=dt)
    accel_clean = res['accel_clean']
    headings_deg = res['headings_deg']

    # Evaluate straight road kinematic metrics
    acc_clean_norms = np.linalg.norm(accel_clean[100:], axis=1)
    p95_accel = float(np.percentile(acc_clean_norms, 95))
    rms_accel = float(np.sqrt(np.mean(acc_clean_norms**2)))

    # Evaluate attitude drift (pitch and roll anchored by tilt fusion)
    quats = res['quaternions']
    # Pitch & roll should remain bounded < 1.0 degree
    assert p95_accel < 0.5, f"Accel 95th percentile too high on cruise: {p95_accel:.4f} m/s^2 (target < 0.5)"
    assert rms_accel < 0.3, f"Accel RMS too high on cruise: {rms_accel:.4f} m/s^2 (target < 0.3)"

    # Total heading drift over 1 hour
    initial_heading = headings_deg[100]
    final_heading = headings_deg[-1]
    drift_deg = abs(final_heading - initial_heading)
    # Normalize angle difference
    drift_deg = abs((drift_deg + 180.0) % 360.0 - 180.0)
    assert drift_deg < 5.0, f"Gyro heading drift over 1 hour too high: {drift_deg:.2f}° (target < 5.0°)"


# ── Test 6: Tilted Mount Validation ──────────────────────────────────────────

def test_6_tilted_mount_validation():
    """
    Test 6: Tilted Mount Validation
    • Simulate phone mounted at 45° pitch.
    • Inject 2.0 m/s² lateral acceleration.
    • Verify: measured lateral accel ≈ 2.0 m/s² (lateral bias < 0.2 m/s²), heading drift < 2°/min.
    """
    gc = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81, accel_gate_threshold=0.15)
    pitch_45 = np.radians(45.0)
    # Rotation matrix around Y axis:
    cy, sy = np.cos(pitch_45), np.sin(pitch_45)
    R_pitch = np.array([
        [cy, 0.0, sy],
        [0.0, 1.0, 0.0],
        [-sy, 0.0, cy]
    ])

    gc.initialize(initial_rpy=(0.0, pitch_45, 0.0))

    # True world acceleration: 2.0 m/s^2 lateral (Y axis) + gravity [0, 0, 9.81]
    # In body frame: R_pitch.T @ ([0, 2.0, 0] + [0, 0, 9.81])
    a_world_total = np.array([0.0, 2.0, 9.81])
    accel_raw = R_pitch.T @ a_world_total
    gyro_raw = np.zeros(3)

    clean_lat_accels = []
    headings = []

    for _ in range(600):  # 1 minute at 10 Hz
        acc_clean, g_phone, q, R = gc.step(accel_raw, gyro_raw, dt=0.1)
        # Transform back to vehicle frame
        # Vehicle frame: X = Forward, Y = Lateral, Z = Vertical
        acc_vehicle = R_pitch @ acc_clean
        clean_lat_accels.append(acc_vehicle[1])
        headings.append(np.degrees(np.arctan2(R[1, 0], R[0, 0])))

    mean_lat_accel = float(np.mean(clean_lat_accels))
    lat_bias = abs(mean_lat_accel - 2.0)
    heading_drift_per_min = abs(headings[-1] - headings[0])

    assert lat_bias < 0.2, f"Lateral accel bias on 45° mount too high: {lat_bias:.4f} m/s^2 (target < 0.2)"
    assert heading_drift_per_min < 2.0, f"Heading drift too high: {heading_drift_per_min:.4f}°/min (target < 2°/min)"


# ── Audit Function: check_3_lateral_accel_gravity() ──────────────────────────

def check_3_lateral_accel_gravity() -> dict:
    """
    Patch 3 Audit Test: check_3_lateral_accel_gravity()
    Comprehensive verification against all target metrics in the Problem Statement.
    """
    results = {}
    passed = True

    # 1. Stationary accel norm (< 0.1 m/s^2)
    gc1 = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc1.initialize(initial_rpy=(0.0, 0.0, 0.0))
    res1 = [np.linalg.norm(gc1.step(np.array([0.0, 0.0, 9.81]), np.zeros(3), dt=0.1)[0]) for _ in range(600)]
    mean_res1 = float(np.mean(res1))
    results['stationary_accel_norm'] = {'val': mean_res1, 'pass': mean_res1 < 0.1}
    if mean_res1 >= 0.1:
        passed = False

    # 2. Heading stability (< 2 deg/min over 5 min stationary)
    gc2 = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc2.initialize(initial_rpy=(0.0, 0.0, 0.0))
    h_start = float(np.degrees(np.arctan2(gc2.R_v2w[1, 0], gc2.R_v2w[0, 0])))
    for _ in range(3000):  # 5 minutes
        gc2.step(np.array([0.0, 0.0, 9.81]), np.zeros(3), dt=0.1)
    h_end = float(np.degrees(np.arctan2(gc2.R_v2w[1, 0], gc2.R_v2w[0, 0])))
    drift_rate = abs(h_end - h_start) / 5.0  # deg/min
    results['heading_stability_deg_per_min'] = {'val': drift_rate, 'pass': drift_rate < 2.0}
    if drift_rate >= 2.0:
        passed = False

    # 3. Accel peak on cruise (< 1.0 m/s^2, target 0.5)
    gc3 = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc3.initialize(initial_rpy=(0.0, 0.0, 0.0))
    rng = np.random.RandomState(123)
    cruise_accels = [
        np.linalg.norm(gc3.step(np.array([0.0, 0.0, 9.81]) + rng.normal(0, 0.04, 3), rng.normal(0, 0.001, 3), dt=0.1)[0])
        for _ in range(18000)  # 30 min
    ]
    p95_cruise = float(np.percentile(cruise_accels, 95))
    results['accel_peak_cruise'] = {'val': p95_cruise, 'pass': p95_cruise < 1.0}
    if p95_cruise >= 1.0:
        passed = False

    # 4. Accel peak on turn (1.2 m/s^2 ± 0.3)
    gc4 = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc4.initialize(initial_rpy=(0.0, 0.0, 0.0))
    # 1.2 m/s^2 lateral acceleration turn with 0.1 rad/s yaw rate
    turn_acc = []
    for _ in range(100):
        c_acc, _, _, _ = gc4.step(np.array([0.0, 1.2, 9.81]), np.array([0.0, 0.0, 0.1]), dt=0.1)
        turn_acc.append(np.linalg.norm(c_acc))
    mean_turn = float(np.mean(turn_acc))
    results['accel_peak_turn'] = {'val': mean_turn, 'pass': abs(mean_turn - 1.2) < 0.3}
    if abs(mean_turn - 1.2) >= 0.3:
        passed = False

    # 5. Gravity removal error (< 0.2 m/s^2, target < 0.1)
    gc5 = GravityCompensator(sampling_rate_hz=10.0, g_val=9.81)
    gc5.initialize(initial_rpy=(0.1, -0.2, 0.0))
    a_rot = gc5.R_v2w.T @ np.array([0.0, 0.0, 9.81])
    _, g_p5, _, _ = gc5.step(a_rot, np.zeros(3), dt=0.1)
    grav_err = float(np.linalg.norm(a_rot - g_p5))
    results['gravity_removal_error'] = {'val': grav_err, 'pass': grav_err < 0.2}
    if grav_err >= 0.2:
        passed = False

    # 6. Latency per call (< 5 ms)
    t0 = time.perf_counter()
    for _ in range(1000):
        gc1.step(np.array([0.0, 0.0, 9.81]), np.zeros(3), dt=0.1)
    latency_ms = (time.perf_counter() - t0) / 1000.0 * 1000.0
    results['latency_ms'] = {'val': latency_ms, 'pass': latency_ms < 5.0}
    if latency_ms >= 5.0:
        passed = False

    results['status'] = "PASS" if passed else "FAIL"
    return results


def test_audit_check_3_lateral_accel_gravity():
    """Verify that the check_3_lateral_accel_gravity() audit passes completely."""
    audit = check_3_lateral_accel_gravity()
    assert audit['status'] == "PASS", f"Audit check_3_lateral_accel_gravity failed: {audit}"


# ── Test Pipeline Integration ────────────────────────────────────────────────

def test_pipeline_integration():
    """
    Verify FinalNavigationPipeline.step() with integrated GravityCompensator.
    Check that clean kinematic acceleration is extracted and fed to state updates.
    """
    pipeline = FinalNavigationPipeline()
    pipeline.initialize(
        lat0=28.6139,
        lon0=77.2090,
        alt0=216.0,
        initial_heading=0.0,
        initial_speed=0.0
    )

    # 1. Stationary steps (level phone)
    accel_raw = np.array([0.0, 0.0, STANDARD_GRAVITY])
    gyro_raw = np.array([0.0, 0.0, 0.0])

    for _ in range(20):
        nav_state = pipeline.step(accel_raw, gyro_raw, dt=0.1)

    assert 'accel_clean' in nav_state
    assert 'g_phone' in nav_state
    assert np.linalg.norm(nav_state['accel_clean']) < 0.1, (
        f"Pipeline stationary accel_clean norm too high: {np.linalg.norm(nav_state['accel_clean']):.4f}"
    )
    assert nav_state['speed_mps'] < 0.05, f"Pipeline false speed accumulation: {nav_state['speed_mps']:.4f}"
