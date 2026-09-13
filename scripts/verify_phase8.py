"""
scripts/verify_phase8.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 8 Automated Verification Suite: Final Pipeline Integration & SIH Benchmark
Adheres to Sections 33–43 of the Roadmap and Project Rules 1–12.
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import json
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.integration.final_navigation_pipeline import FinalNavigationPipeline


def test_pipeline_initialization_and_schema():
    """Verify FinalNavigationPipeline instantiation, initialization, and output state schema."""
    print("Test 1: Verifying FinalNavigationPipeline initialization & state schema...")
    pipeline = FinalNavigationPipeline()

    pipeline.initialize(
        lat0=52.40166,
        lon0=-1.50529,
        alt0=100.0,
        initial_heading=0.5,
        initial_speed=12.0
    )

    assert pipeline.is_initialized is True
    assert np.isclose(pipeline.lat0, 52.40166)
    assert np.isclose(pipeline.lon0, -1.50529)

    # Execute nominal step
    state = pipeline.step(
        accel_raw=np.array([0.2, 0.0, 9.81]),
        gyro_raw=np.array([0.0, 0.0, 0.01]),
        p_gnss_geodetic=(52.40166, -1.50529),
        hdop=1.1,
        is_blackout=False,
        speed_ref=12.0,
        dt=0.1
    )

    required_keys = {
        'step', 'lat', 'lon', 'east_m', 'north_m',
        'speed_mps', 'heading_deg', 'mode',
        'pos_uncertainty_m', 'gnss_rejected',
        'matched_edge_id', 'map_confidence'
    }
    actual_keys = set(state.keys())
    assert required_keys.issubset(actual_keys), f"Missing keys in state: {required_keys - actual_keys}"
    assert state['mode'] in ('FULL_FUSION', 'DEGRADED_GNSS')
    print("  [PASS] Pipeline initialization & state dictionary schema verified.")


def test_blackout_and_recovery_transitions():
    """Verify state transitions between Full Fusion, Blackout, and Smooth Recovery."""
    print("Test 2: Verifying pipeline blackout and recovery state transitions...")
    pipeline = FinalNavigationPipeline()
    pipeline.initialize(lat0=52.40166, lon0=-1.50529, alt0=100.0, initial_heading=0.0, initial_speed=10.0)

    # Step 1: Nominal GNSS
    st1 = pipeline.step(
        accel_raw=np.array([0.1, 0.0, 9.81]),
        gyro_raw=np.array([0.0, 0.0, 0.0]),
        p_gnss_geodetic=(52.40166, -1.50529),
        is_blackout=False
    )
    assert st1['mode'] == 'FULL_FUSION'

    # Step 2: Enter Blackout
    st2 = pipeline.step(
        accel_raw=np.array([0.1, 0.0, 9.81]),
        gyro_raw=np.array([0.0, 0.0, 0.0]),
        p_gnss_geodetic=None,
        is_blackout=True
    )
    assert st2['mode'] == 'GNSS_BLACKOUT'

    # Step 3: Exit Blackout into Recovery
    st3 = pipeline.step(
        accel_raw=np.array([0.1, 0.0, 9.81]),
        gyro_raw=np.array([0.0, 0.0, 0.0]),
        p_gnss_geodetic=(52.40167, -1.50528),
        is_blackout=False
    )
    assert st3['mode'] == 'RECOVERY'
    print("  [PASS] Blackout and smooth recovery transitions verified.")


def test_phase8_notebooks_integrity():
    """Verify syntax and JSON structure of Phase 8 notebooks."""
    print("Test 3: Verifying Phase 8 notebook JSON structures...")
    notebooks = [
        "20_final_pipeline_integration.ipynb",
        "21_final_sih_benchmark.ipynb"
    ]
    for nb_name in notebooks:
        nb_path = PROJECT_ROOT / "notebooks" / nb_name
        assert nb_path.exists(), f"Missing notebook: {nb_name}"
        with open(nb_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert "cells" in data and len(data["cells"]) > 0
        print(f"  [PASS] Notebook {nb_name} validated.")


def main():
    print("=" * 70)
    print("  SIH PS 26168 — Phase 8: Final Pipeline & SIH Benchmark Verification")
    print("=" * 70)
    test_pipeline_initialization_and_schema()
    test_blackout_and_recovery_transitions()
    test_phase8_notebooks_integrity()
    print("=" * 70)
    print("  ALL PHASE 8 UNIT & STATIC TESTS PASSED (100%)")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
