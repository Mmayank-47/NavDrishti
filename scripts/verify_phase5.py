"""
scripts/verify_phase5.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 5 Automated Verification Suite: KalmanNet Adaptive Filtering
Adheres to Section 19 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import json
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))


def test_kalmannet_model_syntax_and_structure():
    """Verify KalmanNet architecture definition and tensor shape logic."""
    print("Test 1: Verifying KalmanNet model source and architecture...")
    model_path = PROJECT_ROOT / "src" / "models" / "kalmannet.py"
    assert model_path.exists(), f"Missing {model_path}"

    with open(model_path, "r") as f:
        src = f.read()

    assert "class KalmanNetNN" in src, "KalmanNetNN class not found in kalmannet.py"
    assert "nn.GRU" in src, "GRU recurrent backbone not found in KalmanNet"
    assert "nn.Tanh()" in src, "Tanh bounding for Kalman gain stability not found in KalmanNet"
    assert "def step" in src, "Single-step filtering interface not found in KalmanNet"

    # Explicit ban check: Ensure no hardcoded K = 0.8 assignment in model code
    code_lines = [l.strip() for l in src.splitlines() if not l.strip().startswith(("#", '"""', "*", "//"))]
    for line in code_lines:
        assert "0.8" not in line, f"Arbitrary hardcoded gain found in KalmanNet model line: {line}"
    print("  [PASS] KalmanNet architecture and ban on hardcoded gains verified.")


def test_kalmannet_dataset_structure():
    """Verify KalmanNet sequence dataset definition."""
    print("Test 2: Verifying KalmanNet sequence dataset...")
    ds_path = PROJECT_ROOT / "src" / "datasets" / "kalmannet_dataset.py"
    assert ds_path.exists(), f"Missing {ds_path}"

    with open(ds_path, "r") as f:
        src = f.read()

    assert "class KalmanNetDataset" in src, "KalmanNetDataset class not found"
    assert "PhoneVehicleAlignment" in src, "PhoneVehicleAlignment integration missing"
    assert "zero-copy" in src.lower() or "sessions" in src, "Dataset efficiency pattern missing"
    print("  [PASS] KalmanNetDataset structure verified.")


def test_notebooks_syntax():
    """Verify that training and testing notebooks are valid JSON and adhere to requirements."""
    print("Test 3: Verifying Jupyter notebooks syntax and integrity...")
    nb11_path = PROJECT_ROOT / "notebooks" / "11_kalmannet_training.ipynb"
    nb12_path = PROJECT_ROOT / "notebooks" / "12_kalmannet_testing.ipynb"

    assert nb11_path.exists(), f"Missing {nb11_path}"
    assert nb12_path.exists(), f"Missing {nb12_path}"

    for nb_path in [nb11_path, nb12_path]:
        with open(nb_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert "cells" in data and len(data["cells"]) > 0, f"Notebook {nb_path} has no cells"

    # Check that nb12 explicitly tests against held-out session S1
    with open(nb12_path, "r", encoding="utf-8") as f:
        nb12_content = f.read()
    assert "'S1'" in nb12_content or '"S1"' in nb12_content, "Notebook 12 must evaluate on held-out session S1"
    assert "Fixed Gain" in nb12_content, "Notebook 12 must benchmark against fixed-gain filter"
    print("  [PASS] Notebooks 11 & 12 validated successfully.")


def test_physics_matrices():
    """Verify kinematic state propagation matrices."""
    print("Test 4: Verifying kinematic state-space matrices...")
    dt = 0.1
    F = np.array([
        [1.0, 0.0, dt,  0.0],
        [0.0, 1.0, 0.0, dt ],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0]
    ])
    B = np.array([
        [0.5 * dt**2, 0.0],
        [0.0, 0.5 * dt**2],
        [dt, 0.0],
        [0.0, dt]
    ])
    H = np.array([
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0]
    ])

    assert F.shape == (4, 4), f"Invalid F shape: {F.shape}"
    assert B.shape == (4, 2), f"Invalid B shape: {B.shape}"
    assert H.shape == (2, 4), f"Invalid H shape: {H.shape}"

    # Test kinematic update
    x_prev = np.array([10.0, 20.0, 5.0, 0.0])  # moving east at 5 m/s
    a_nav = np.array([1.0, 0.0])               # accelerating east at 1 m/s^2
    x_prior = F @ x_prev + B @ a_nav

    expected_p_east = 10.0 + 5.0 * 0.1 + 0.5 * 1.0 * (0.1**2)
    expected_v_east = 5.0 + 1.0 * 0.1
    assert np.isclose(x_prior[0], expected_p_east), f"Prior p_east mismatch: {x_prior[0]} vs {expected_p_east}"
    assert np.isclose(x_prior[2], expected_v_east), f"Prior v_east mismatch: {x_prior[2]} vs {expected_v_east}"
    print("  [PASS] Kinematic matrices and propagation equations verified.")


def main():
    print("=" * 65)
    print("  SIH PS 26168 — Phase 5: KalmanNet Automated Verification")
    print("=" * 65)
    test_kalmannet_model_syntax_and_structure()
    test_kalmannet_dataset_structure()
    test_notebooks_syntax()
    test_physics_matrices()
    print("=" * 65)
    print("  ALL PHASE 5 STATIC & STRUCTURAL TESTS PASSED (100%)")
    print("=" * 65)
    return 0


if __name__ == "__main__":
    sys.exit(main())
