#!/usr/bin/env python3
"""
scripts/verify_phase2.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 2 Verification Script:
  - Validates Invariant ESKF kinematics, nominal propagation, and error state
  - Validates Joseph-form error covariance symmetry and positive-definiteness
  - Validates VehicleKinematicConstraints (NHC + ZUPT with dynamic slip gating)
  - Validates 60s blackout drift bounding compared to open-loop double integration
  - Validates existence and non-empty integrity of Phase 2 diagnostic plots and results
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import os
import json
from pathlib import Path
import numpy as np

# Ensure UTF-8 output encoding on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

PROJECT_ROOT = Path(__file__).resolve().parent.parent
os.chdir(PROJECT_ROOT)
sys.path.insert(0, str(PROJECT_ROOT))

from src.filters.invariant_eskf import InvariantESKF
from src.constraints.nhc import VehicleKinematicConstraints
from src.preprocessing.data_loader import IOVNBDLoader


def test_eskf_propagation():
    print("Testing InvariantESKF propagation kinematics...")
    eskf = InvariantESKF(dt=0.1)
    eskf.initialize(p0=[0.0, 0.0, 0.0], v0=[10.0, 0.0, 0.0])

    # 1. Constant velocity forward motion (accel cancels gravity, zero gyro)
    # Under ENU gravity g_nav = [0, 0, -9.80665], specific force = [0, 0, +9.80665]
    accel_meas = np.array([0.0, 0.0, 9.80665])
    gyro_meas = np.array([0.0, 0.0, 0.0])

    for _ in range(10):  # 1.0 second
        eskf.predict(accel_meas, gyro_meas)

    # Position after 1.0s at 10 m/s should be [10.0, 0.0, 0.0]
    np.testing.assert_allclose(eskf.v, [10.0, 0.0, 0.0], atol=1e-3)
    np.testing.assert_allclose(eskf.p, [10.0, 0.0, 0.0], atol=1e-2)
    print(f"  [PASS] Nominal propagation: Velocity={eskf.v}, Position={eskf.p}")

    # 2. Covariance symmetry and positive eigenvalues
    assert np.allclose(eskf.P, eskf.P.T, atol=1e-8), "Covariance P is not symmetric"
    eigvals = np.linalg.eigvalsh(eskf.P)
    assert np.all(eigvals > 0), f"Covariance P not positive definite, min eigval={np.min(eigvals)}"
    print(f"  [PASS] Covariance symmetry & positive definiteness confirmed (min eigenvalue: {np.min(eigvals):.2e})")


def test_kinematic_constraints():
    print("\nTesting VehicleKinematicConstraints (NHC & ZUPT)...")
    constraints = VehicleKinematicConstraints()

    # 1. Straight driving: v_nav = [10.0, 0.0, 0.0], attitude identity
    q_id = np.array([1.0, 0.0, 0.0, 0.0])
    v_nav = np.array([10.0, 2.0, 0.5])  # Has parasitic lateral and vertical velocity
    H, y, R = constraints.compute_nhc_update(v_nav, q_id)

    assert H.shape == (2, 15), f"H shape mismatch: {H.shape}"
    assert np.allclose(y, [-2.0, -0.5]), f"Innovation mismatch: {y}"
    print(f"  [PASS] NHC innovation extraction: target=[0, 0], estimated=[2.0, 0.5] -> y={y}")

    # 2. Dynamic turning slip gating
    # High yaw rate should inflate covariance R
    _, _, R_turning = constraints.compute_nhc_update(
        v_nav, q_id, gyro_body=np.array([0.0, 0.0, 0.8])  # ~46 deg/s turn
    )
    assert R_turning[0, 0] > R[0, 0], "Slip gating failed to inflate covariance during turn"
    print(f"  [PASS] Dynamic slip gating: R inflated from {R[0, 0]:.4f} to {R_turning[0, 0]:.4f} during high yaw rate")

    # 3. ZUPT update matrices
    H_z, y_z, R_z = constraints.compute_zupt_update(np.array([0.1, -0.05, 0.02]))
    assert H_z.shape == (3, 15), f"H_z shape mismatch: {H_z.shape}"
    assert np.allclose(y_z, [-0.1, 0.05, -0.02]), f"ZUPT innovation mismatch: {y_z}"
    print(f"  [PASS] ZUPT innovation verified: {y_z}")


def test_blackout_drift_bounding():
    print("\nTesting ESKF Drift Bounding on Real IO-VNBD Trajectory...")
    res_path = PROJECT_ROOT / 'results' / 'eskf_baseline.json'
    assert res_path.exists(), f"Missing results file: {res_path}"

    with open(res_path, 'r', encoding='utf-8') as f:
        res = json.load(f)

    win_60s = res['evaluated_windows']['60s']
    pure_drift = win_60s['pure_imu']['drift_m']
    eskf_drift = win_60s['eskf_zupt_nhc']['drift_m']

    assert eskf_drift < pure_drift, f"ESKF drift ({eskf_drift}m) not less than pure IMU ({pure_drift}m)"
    reduction_pct = ((pure_drift - eskf_drift) / pure_drift) * 100.0
    print(f"  [PASS] 60s Outage Drift: Pure IMU = {pure_drift:.1f} m -> ESKF+NHC = {eskf_drift:.1f} m ({reduction_pct:.1f}% reduction)")


def test_diagnostic_artifacts():
    print("\nTesting Phase 2 Diagnostic Plots & Deliverables...")
    expected_artifacts = [
        PROJECT_ROOT / 'results' / 'eskf_baseline.json',
        PROJECT_ROOT / 'plots' / 'eskf' / 'eskf_multi_window_benchmark.png'
    ]
    # Check for at least one session-specific plot
    plots_dir = PROJECT_ROOT / 'plots' / 'eskf'
    traj_plots = list(plots_dir.glob("eskf_trajectory_comparison_*.png"))
    err_plots = list(plots_dir.glob("eskf_error_over_time_*.png"))

    assert len(traj_plots) > 0, "Missing eskf_trajectory_comparison plot"
    assert len(err_plots) > 0, "Missing eskf_error_over_time plot"

    for p in expected_artifacts + [traj_plots[0], err_plots[0]]:
        assert p.exists(), f"Missing artifact: {p}"
        assert p.stat().st_size > 100, f"Artifact {p.name} is empty"
        print(f"  [PASS] Verified: {p.relative_to(PROJECT_ROOT)} ({p.stat().st_size / 1024:.1f} KB)")


if __name__ == '__main__':
    print("=" * 65)
    print("  SIH PS 26168 — Phase 2 Classical ESKF Baseline Verification")
    print("=" * 65)
    test_eskf_propagation()
    test_kinematic_constraints()
    test_blackout_drift_bounding()
    test_diagnostic_artifacts()
    print("\n" + "=" * 65)
    print("  ALL PHASE 2 VERIFICATIONS PASSED WITH 100% SUCCESS!")
    print("=" * 65)
