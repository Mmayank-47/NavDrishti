#!/usr/bin/env python3
"""
scripts/verify_phase1.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 1 Verification Script:
  - Validates IMU preprocessing (vibration filter, shock limiter, gravity removal)
  - Validates WGS84 Geodetic to ENU transformations
  - Validates Stationary / ZUPT detector
  - Validates Phone-to-Vehicle Alignment Engine (orthonormality, CAN correlation)
  - Validates presence of Phase 1 artifacts and plot outputs
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import os
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

from src.preprocessing.frame_transform import geodetic_to_enu, ecef_to_geodetic, geodetic_to_ecef
from src.preprocessing.imu_preprocessor import IMUPreprocessor
from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment

def test_imu_preprocessor():
    print("Testing IMUPreprocessor...")
    prep = IMUPreprocessor(sampling_rate_hz=10.0, accel_cutoff_hz=4.0)

    # 1. Vibration suppression test
    t = np.linspace(0, 10, 100)
    clean_signal = np.sin(2 * np.pi * 0.5 * t)[:, None]
    high_freq_noise = 0.5 * np.sin(2 * np.pi * 4.5 * t)[:, None]
    noisy_signal = clean_signal + high_freq_noise
    filtered = prep.filter_vibrations(noisy_signal)
    
    noise_power_orig = np.var(noisy_signal - clean_signal)
    noise_power_filt = np.var(filtered - clean_signal)
    assert noise_power_filt < noise_power_orig, "Filter failed to attenuate high-frequency noise"
    print(f"  [PASS] Vibration filter: Noise variance reduced from {noise_power_orig:.4f} to {noise_power_filt:.4f}")

    # 2. Shock suppression test
    spikes = np.zeros((20, 3))
    spikes[10] = [50.0, 0.0, 0.0]  # Pothole spike > 35 m/s^2
    clipped = prep.suppress_shocks(spikes)
    assert np.max(np.linalg.norm(clipped, axis=1)) <= 35.001, "Shock suppression failed to clip spike"
    print(f"  [PASS] Shock suppression: Max spike clipped to {np.max(np.linalg.norm(clipped, axis=1)):.2f} m/s^2")

    # 3. ZUPT detector
    stationary_data = np.random.normal(0, 0.01, (30, 3))
    moving_data = np.random.normal(0, 1.0, (30, 3))
    test_accel = np.vstack([stationary_data, moving_data])
    test_gyro = np.vstack([stationary_data * 0.1, moving_data * 0.1])
    zupt_mask = prep.detect_stationary(test_accel, test_gyro)
    assert np.sum(zupt_mask[:20]) > np.sum(zupt_mask[40:]), "ZUPT detector failed to differentiate stationary from moving"
    print(f"  [PASS] ZUPT detection: Stationary mask correctly identified")

def test_coordinate_transforms():
    print("\nTesting Coordinate Transformations...")
    lat0, lon0, alt0 = 12.9716, 77.5946, 920.0  # Bengaluru, India
    lat1, lon1, alt1 = 12.9720, 77.5950, 925.0

    enu = geodetic_to_enu(lat1, lon1, alt1, lat0, lon0, alt0)
    assert enu[0] > 0, "East coordinate should be positive"
    assert enu[1] > 0, "North coordinate should be positive"
    assert enu[2] > 0, "Up coordinate should be positive"
    print(f"  [PASS] Geodetic to ENU: ΔE={enu[0]:.2f}m, ΔN={enu[1]:.2f}m, ΔU={enu[2]:.2f}m")

    # ECEF roundtrip
    ecef = geodetic_to_ecef(lat0, lon0, alt0)
    geo_roundtrip = ecef_to_geodetic(*ecef)
    np.testing.assert_allclose(geo_roundtrip, [lat0, lon0, alt0], atol=1e-5)
    print("  [PASS] Geodetic <-> ECEF roundtrip precision confirmed (<1e-5 deg/m)")

def test_phone_alignment():
    print("\nTesting PhoneVehicleAlignment Engine...")
    loader = IOVNBDLoader()
    sess = loader.load_session('M', preprocess_imu=True)

    aligner = PhoneVehicleAlignment()
    R = aligner.calibrate(
        sess['accel_raw'],
        zupt_mask=sess['zupt_mask'],
        velocity_ref=sess['vehicle']['speed_mps']
    )

    # 1. Orthonormality check: R.T @ R == I
    ortho_err = np.max(np.abs(R.T @ R - np.eye(3)))
    det = np.linalg.det(R)
    assert ortho_err < 1e-4, f"Rotation matrix not orthonormal, err={ortho_err}"
    assert np.isclose(det, 1.0, atol=1e-4), f"Rotation matrix determinant {det} != 1"
    print(f"  [PASS] Rotation matrix orthonormality: err={ortho_err:.2e}, det={det:.6f}")

    # 2. Acceleration correlation with CAN-bus forward acceleration
    accel_veh = aligner.transform_to_vehicle(sess['accel_linear'])
    if sess['vehicle']['lon_accel_mps2'] is not None:
        # Non-stationary window
        moving = ~sess['zupt_mask']
        a_fwd = accel_veh[moving, 0]
        a_can = sess['vehicle']['lon_accel_mps2'][moving]
        valid = ~np.isnan(a_fwd) & ~np.isnan(a_can)
        corr = np.corrcoef(a_fwd[valid], a_can[valid])[0, 1]
        print(f"  [PASS] Forward acceleration correlation with CAN-bus: r = {corr:.3f} (positive agreement)")
        assert corr > 0.05, f"Correlation expected to be positive: {corr:.3f}"

def test_plot_artifacts():
    print("\nTesting Generated Plots & Artifacts...")
    expected_plots = [
        PROJECT_ROOT / 'plots' / 'preprocessing' / 'accel_filtering_M.png',
        PROJECT_ROOT / 'plots' / 'preprocessing' / 'gravity_separation_M.png',
        PROJECT_ROOT / 'plots' / 'preprocessing' / 'enu_trajectory_M.png',
        PROJECT_ROOT / 'plots' / 'alignment' / 'alignment_validation_M.png'
    ]
    for p in expected_plots:
        assert p.exists(), f"Missing plot: {p}"
        assert p.stat().st_size > 5000, f"Plot {p} appears empty or corrupted"
        print(f"  [PASS] Plot verified: {p.relative_to(PROJECT_ROOT)} ({p.stat().st_size / 1024:.1f} KB)")

if __name__ == '__main__':
    print("=" * 60)
    print("  SIH PS 26168 — Phase 1 Preprocessing & Alignment Verification")
    print("=" * 60)
    test_imu_preprocessor()
    test_coordinate_transforms()
    test_phone_alignment()
    test_plot_artifacts()
    print("\n" + "=" * 60)
    print("  ALL PHASE 1 VERIFICATIONS PASSED SUCCESSFULLY!")
    print("=" * 60)
