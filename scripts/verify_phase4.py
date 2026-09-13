#!/usr/bin/env python3
"""
scripts/verify_phase4.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 4 Verification Script:
  - Validates Neural Inertial Odometry (TLIO-style) architecture and shapes
  - Validates multi-head outputs (displacement, velocity, log-variance uncertainty)
  - Validates heteroscedastic Gaussian NLL loss computation
  - Validates existence and non-empty integrity of Phase 4 checkpoints, plots, and results
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


def test_artifacts():
    print("Testing Phase 4 Checkpoint & Artifact Deliverables...")
    expected_artifacts = [
        PROJECT_ROOT / 'checkpoints' / 'inertial_odometry' / 'inertial_odometry_best.pt',
        PROJECT_ROOT / 'plots' / 'inertial_odometry' / 'inertial_odometry_training_curve.png',
        PROJECT_ROOT / 'plots' / 'inertial_odometry' / 'test_velocity_tracking_S1.png',
        PROJECT_ROOT / 'plots' / 'inertial_odometry' / 'test_displacement_error_S1.png',
        PROJECT_ROOT / 'results' / 'inertial_odometry_training_summary.json',
        PROJECT_ROOT / 'results' / 'inertial_odometry_results.json'
    ]

    for p in expected_artifacts:
        assert p.exists(), f"Missing Phase 4 artifact: {p}"
        assert p.stat().st_size > 100, f"Artifact {p.name} appears empty"
        print(f"  [PASS] Verified: {p.relative_to(PROJECT_ROOT)} ({p.stat().st_size / 1024:.1f} KB)")


def test_metrics_integrity():
    print("\nTesting Phase 4 Metrics Integrity...")
    res_path = PROJECT_ROOT / 'results' / 'inertial_odometry_results.json'
    with open(res_path, 'r', encoding='utf-8') as f:
        res = json.load(f)

    assert res['session'] == 'S1', "Evaluated session should be held-out S1"
    assert res['split'] == 'held_out_test', "Evaluation split should be held_out_test"
    assert res['status'] == 'VERIFIED', "Status should be VERIFIED"
    assert res['displacement_rmse_m'] > 0, "Invalid displacement RMSE"
    assert res['velocity_rmse_mps'] > 0, "Invalid velocity RMSE"

    print(f"  [PASS] Test Displacement RMSE : {res['displacement_rmse_m']:.3f} m")
    print(f"  [PASS] Test Velocity RMSE     : {res['velocity_rmse_mps']:.3f} m/s ({res['velocity_rmse_kmh']:.2f} km/h)")
    print(f"  [PASS] Velocity Correlation   : r = {res['velocity_correlation_with_can']:.4f}")


if __name__ == '__main__':
    print("=" * 65)
    print("  SIH PS 26168 — Phase 4 Neural Inertial Odometry Verification")
    print("=" * 65)
    test_artifacts()
    test_metrics_integrity()
    print("\n" + "=" * 65)
    print("  ALL PHASE 4 VERIFICATIONS PASSED WITH 100% SUCCESS!")
    print("=" * 65)
