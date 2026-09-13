"""
scripts/verify_phase6.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 6 Automated Verification Suite: Robust GNSS Fusion & Deficit Handler
Adheres to Section 23 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import json
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.filters.gnss_fusion import RobustGNSSFusionEngine, NavigationMode


def test_engine_initialization_and_modes():
    """Verify class structure and navigation modes."""
    print("Test 1: Verifying RobustGNSSFusionEngine initialization and modes...")
    engine = RobustGNSSFusionEngine()
    assert engine.mode == NavigationMode.FULL_FUSION
    assert len(NavigationMode) == 4
    expected_modes = {"FULL_FUSION", "DEGRADED_GNSS", "GNSS_BLACKOUT", "RECOVERY"}
    actual_modes = {m.value for m in NavigationMode}
    assert expected_modes == actual_modes, f"Mode mismatch: {actual_modes}"
    print("  [PASS] State machine modes verified.")


def test_chi2_innovation_gating():
    """Verify statistical chi-square gating of nominal vs outlier measurements."""
    print("Test 2: Verifying Chi-Square Innovation Gating...")
    engine = RobustGNSSFusionEngine(chi2_gate_2d=9.21)

    P_pos = np.eye(2) * 4.0
    R_nom = np.eye(2) * (2.5 ** 2)
    S_cov = P_pos + R_nom

    # Case A: Nominal small innovation (should pass gate)
    y_nominal = np.array([1.5, -1.0])
    is_valid, nis, thresh = engine.evaluate_innovation_gate(y_nominal, S_cov)
    assert is_valid, f"Nominal innovation failed gate! NIS={nis:.2f}"
    assert nis < thresh, f"NIS {nis:.2f} exceeded threshold {thresh}"

    # Case B: Large multipath outlier jump (should be rejected)
    y_outlier = np.array([75.0, -80.0])
    is_valid_outlier, nis_outlier, _ = engine.evaluate_innovation_gate(y_outlier, S_cov)
    assert not is_valid_outlier, f"Large outlier passed gate! NIS={nis_outlier:.2f}"
    assert nis_outlier > 100.0, f"NIS for outlier should be large, got {nis_outlier}"
    print("  [PASS] Statistical innovation gating correctly accepts nominals and rejects outliers.")


def test_adaptive_covariance_scaling():
    """Verify HDOP and Huber M-estimator covariance inflation."""
    print("Test 3: Verifying adaptive covariance scaling...")
    engine = RobustGNSSFusionEngine(hdop_nominal=1.0, huber_k=1.5)
    R_nom = np.eye(2) * 5.0

    # High HDOP = 3.0 should scale R by (3.0/1.0)^2 = 9.0
    R_high_dop = engine.compute_adaptive_covariance(R_nom, hdop=3.0, nis=1.0)
    assert np.isclose(R_high_dop[0, 0], 5.0 * 9.0), f"Expected 45.0, got {R_high_dop[0, 0]}"

    # Elevated NIS should further scale via Huber
    R_huber = engine.compute_adaptive_covariance(R_nom, hdop=1.0, nis=16.0)
    assert R_huber[0, 0] > R_nom[0, 0], "Huber weighting failed to inflate R"
    print("  [PASS] Adaptive covariance scaling verified.")


def test_seamless_blackout_and_recovery_smoother():
    """Verify state machine handover and anti-teleport innovation damping."""
    print("Test 4: Verifying blackout deficit handling and smooth recovery...")
    engine = RobustGNSSFusionEngine(recovery_window_steps=10)

    P_pos = np.eye(2) * 4.0
    R_nom = np.eye(2) * 4.0

    # Step 1: Normal fusion
    allow, y_eff, _, info = engine.process_gnss_observation(
        p_gnss=np.array([10.0, 20.0]),
        p_predicted=np.array([10.2, 19.8]),
        P_prior_pos=P_pos,
        R_gnss_nominal=R_nom,
        hdop=1.0
    )
    assert allow is True
    assert engine.mode == NavigationMode.FULL_FUSION

    # Step 2: Enter tunnel / blackout
    allow_bo, _, _, info_bo = engine.process_gnss_observation(
        p_gnss=None,
        p_predicted=np.array([15.0, 25.0]),
        P_prior_pos=P_pos,
        R_gnss_nominal=R_nom,
        is_blackout=True
    )
    assert allow_bo is False
    assert engine.mode == NavigationMode.GNSS_BLACKOUT
    assert engine.blackout_steps == 1

    # Step 3: Exit tunnel into RECOVERY
    # Re-emerging GNSS observation with a 15-meter accumulated offset
    p_rec = np.array([25.0, 35.0])
    p_pred = np.array([10.0, 20.0])  # Drifted during blackout
    allow_rec, y_rec, _, info_rec = engine.process_gnss_observation(
        p_gnss=p_rec,
        p_predicted=p_pred,
        P_prior_pos=P_pos * 10.0,  # Covariance grew during blackout
        R_gnss_nominal=R_nom,
        is_blackout=False
    )
    assert engine.mode == NavigationMode.RECOVERY or engine.mode == NavigationMode.FULL_FUSION
    # Damping: effective innovation must be less than raw difference
    y_raw_norm = np.linalg.norm(p_rec - p_pred)
    y_eff_norm = np.linalg.norm(y_rec)
    assert y_eff_norm < y_raw_norm, f"Innovation damping failed: eff={y_eff_norm:.2f}, raw={y_raw_norm:.2f}"
    print("  [PASS] Anti-teleport recovery smoother verified.")


def test_notebook_syntax():
    """Verify syntax of notebooks/14_gnss_fusion.ipynb."""
    print("Test 5: Verifying notebooks/14_gnss_fusion.ipynb integrity...")
    nb_path = PROJECT_ROOT / "notebooks" / "14_gnss_fusion.ipynb"
    assert nb_path.exists(), f"Missing {nb_path}"
    with open(nb_path, "r", encoding="utf-8") as f:
        nb_data = json.load(f)
    assert "cells" in nb_data and len(nb_data["cells"]) > 0
    print("  [PASS] Notebook 14 JSON structure validated.")


def main():
    print("=" * 70)
    print("  SIH PS 26168 — Phase 6: Robust GNSS Fusion Automated Verification")
    print("=" * 70)
    test_engine_initialization_and_modes()
    test_chi2_innovation_gating()
    test_adaptive_covariance_scaling()
    test_seamless_blackout_and_recovery_smoother()
    test_notebook_syntax()
    print("=" * 70)
    print("  ALL PHASE 6 STATIC & UNIT TESTS PASSED (100%)")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
