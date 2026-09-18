"""
tests/test_antigravity.py
─────────────────────────────────────────────────────────────────────────────
Unit Tests for Module 1: ANTIGRAVITY
Covers Tests 1-6 from the Architecture Specification.
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
import pytest

from src.modules.antigravity import Antigravity, STANDARD_GRAVITY


def test_1_stationary_phone():
    """
    Test 1: Stationary Phone in Gravity
    Setup: accel_raw=[0,0,9.81], gyro=[0,0,0], level phone
    Expected: accel_clean ≈ [0,0,0], norm < 0.05 m/s²
    """
    ag = Antigravity(sampling_rate_hz=10.0, g_val=9.81)
    ag.initialize(initial_rpy=(0.0, 0.0, 0.0))

    accel_raw = np.array([0.0, 0.0, 9.81])
    gyro = np.array([0.0, 0.0, 0.0])

    residuals = []
    for _ in range(600):  # 1 min
        out = ag.step(accel_raw, gyro, dt=0.1)
        residuals.append(np.linalg.norm(out.accel_clean))

    mean_norm = float(np.mean(residuals))
    assert mean_norm < 0.05, f"Stationary accel norm too high: {mean_norm:.4f} m/s^2"
    np.testing.assert_allclose(out.g_phone, [0.0, 0.0, 9.81], atol=0.05)


def test_2_90deg_yaw_rotation():
    """
    Test 2: 90° Rotation
    Setup: Rotate gravity around pitch axis by 90°
    Expected: g_phone = [9.81, 0, 0] in rotated frame
    """
    ag = Antigravity(sampling_rate_hz=100.0, g_val=9.81)
    ag.initialize(initial_rpy=(0.0, 0.0, 0.0))

    dt = 0.01
    pitch_rate = -np.pi / 2.0  # Nose pitches down at 90 deg/s
    gyro = np.array([0.0, pitch_rate, 0.0])

    for _ in range(100):  # 1 second = 90 deg rotation
        current_R = ag.R_v2w
        accel_raw = current_R.T @ np.array([0.0, 0.0, 9.81])
        out = ag.step(accel_raw, gyro, dt=dt)

    det_R = float(np.linalg.det(out.R_v2w_updated))
    assert abs(det_R - 1.0) < 1e-5, f"Lost SO(3) orthogonality: det={det_R}"

    # Verify stationary measurement at final pose
    final_acc = ag.R_v2w.T @ np.array([0.0, 0.0, 9.81])
    out_final = ag.step(final_acc, np.zeros(3), dt=dt)

    np.testing.assert_allclose(out_final.g_phone, [9.81, 0.0, 0.0], atol=0.05)
    np.testing.assert_allclose(out_final.accel_clean, [0.0, 0.0, 0.0], atol=0.05)


def test_3_tilted_stationary_phone():
    """
    Test 3: Tilted Stationary Phone (30° pitch)
    Setup: Phone mounted at 30° pitch, stationary
    Expected: accel_clean ≈ [0,0,0], norm < 0.05 m/s²
    """
    ag = Antigravity(sampling_rate_hz=10.0, g_val=9.81)
    pitch_30 = np.radians(30.0)
    cy, sy = np.cos(pitch_30), np.sin(pitch_30)
    R_pitch = np.array([
        [cy, 0.0, sy],
        [0.0, 1.0, 0.0],
        [-sy, 0.0, cy]
    ])
    accel_raw = R_pitch.T @ np.array([0.0, 0.0, 9.81])
    gyro = np.zeros(3)

    ag.initialize(stationary_accel=np.tile(accel_raw, (10, 1)))

    residuals = []
    for _ in range(300):
        out = ag.step(accel_raw, gyro, dt=0.1)
        residuals.append(np.linalg.norm(out.accel_clean))

    mean_norm = float(np.mean(residuals))
    assert mean_norm < 0.05, f"Tilted stationary accel norm too high: {mean_norm:.4f} m/s^2"
    assert abs(out.accel_clean[0]) < 0.05, f"Forward bias detected on 30° tilt: {out.accel_clean[0]:.4f}"


def test_4_hard_acceleration():
    """
    Test 4: Hard Acceleration (level phone)
    Setup: Car accelerates 3 m/s² forward, phone level
    Expected: accel_clean ≈ [3.0, 0, 0], norm ≈ 3.0 m/s²
    """
    ag = Antigravity(sampling_rate_hz=10.0, g_val=9.81, accel_gate_threshold=0.35)
    ag.initialize(initial_rpy=(0.0, 0.0, 0.0))

    accel_raw = np.array([3.0, 0.0, 9.81])
    gyro = np.array([0.0, 0.0, 0.0])

    for _ in range(50):
        out = ag.step(accel_raw, gyro, dt=0.1)

    np.testing.assert_allclose(out.accel_clean, [3.0, 0.0, 0.0], atol=0.05)
    np.testing.assert_allclose(out.g_phone, [0.0, 0.0, 9.81], atol=0.05)


def test_5_iovnbd_benchmark():
    """
    Test 5: IO-VNBD 1-hour cruise data
    Expected: accel_clean peak < 0.5 m/s² on straight, drift < 5° / 1 hr
    """
    fs = 10.0
    dt = 1.0 / fs
    N = int(3600 * fs)
    rng = np.random.RandomState(42)

    accel_noise = rng.normal(0.0, 0.04, size=(N, 3))
    gyro_noise = rng.normal(0.0, 0.002, size=(N, 3))
    gyro_bias = np.array([0.001, -0.002, 0.0015])

    accel_raw = accel_noise + np.array([0.0, 0.0, 9.81])
    gyro_raw = gyro_noise + gyro_bias

    ag = Antigravity(sampling_rate_hz=fs, g_val=9.81, tilt_fusion_cutoff_hz=0.01, enable_gyro_debias=True)
    ag.initialize(stationary_accel=accel_raw[:100], stationary_gyro=gyro_raw[:100])

    clean_norms = []
    initial_heading = None
    final_heading = None

    for i in range(N):
        out = ag.step(accel_raw[i], gyro_raw[i], dt=dt)
        if i >= 100:
            clean_norms.append(np.linalg.norm(out.accel_clean))
            h = np.degrees(np.arctan2(out.R_v2w_updated[1, 0], out.R_v2w_updated[0, 0]))
            if initial_heading is None:
                initial_heading = h
            final_heading = h

    p95 = float(np.percentile(clean_norms, 95))
    drift = abs(final_heading - initial_heading)
    drift = abs((drift + 180.0) % 360.0 - 180.0)

    assert p95 < 0.5, f"Cruise clean accel peak too high: {p95:.4f} m/s^2"
    assert drift < 5.0, f"Gyro drift over 1 hr too high: {drift:.2f}°"


def test_6_tilted_mount_with_lateral_accel():
    """
    Test 6: Tilted Mount with Lateral Accel
    Setup: Phone at 45° pitch, inject 2 m/s² lateral accel
    Expected: lateral accel ≈ 2.0 m/s², heading drift < 2°/min
    """
    ag = Antigravity(sampling_rate_hz=10.0, g_val=9.81, accel_gate_threshold=0.15)
    pitch_45 = np.radians(45.0)
    cy, sy = np.cos(pitch_45), np.sin(pitch_45)
    R_pitch = np.array([
        [cy, 0.0, sy],
        [0.0, 1.0, 0.0],
        [-sy, 0.0, cy]
    ])

    ag.initialize(initial_rpy=(0.0, pitch_45, 0.0))

    a_world_total = np.array([0.0, 2.0, 9.81])
    accel_raw = R_pitch.T @ a_world_total
    gyro = np.zeros(3)

    lat_accels = []
    headings = []

    for _ in range(600):  # 1 min
        out = ag.step(accel_raw, gyro, dt=0.1)
        a_veh = R_pitch @ out.accel_clean
        lat_accels.append(a_veh[1])
        headings.append(np.degrees(np.arctan2(out.R_v2w_updated[1, 0], out.R_v2w_updated[0, 0])))

    mean_lat = float(np.mean(lat_accels))
    bias = abs(mean_lat - 2.0)
    drift = abs(headings[-1] - headings[0])

    assert bias < 0.2, f"Lateral accel bias on 45° mount too high: {bias:.4f} m/s^2"
    assert drift < 2.0, f"Heading drift too high: {drift:.4f}°/min"
