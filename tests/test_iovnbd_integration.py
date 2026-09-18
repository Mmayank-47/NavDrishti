"""
tests/test_iovnbd_integration.py
─────────────────────────────────────────────────────────────────────────────
Integration test validating NavDrishti ANTIGRAVITY and Alignment against
realistic IO-VNBD dataset characteristics (noise, mount angles, dynamics).
─────────────────────────────────────────────────────────────────────────────
"""

import os
import numpy as np
import pytest

from src.sensors.imu_reader import IMUReader, SyntheticDriveGenerator
from src.modules.antigravity import Antigravity
from src.modules.alignment_engine import AlignmentEngine


def test_iovnbd_sample_integration():
    """Validate Antigravity on recorded/sample IO-VNBD dataset."""
    sample_path = "data/iovnbd_sample/sample_drive.npz"
    if not os.path.exists(sample_path):
        gen = SyntheticDriveGenerator(sampling_rate_hz=10.0, seed=42)
        drive = gen.generate_drive(duration_s=300.0, mount_pitch_deg=15.0)
    else:
        reader = IMUReader(sampling_rate_hz=10.0)
        drive = reader.load_npz(sample_path)

    accel_raw = drive['accel_raw']
    gyro_raw = drive['gyro_raw']
    N = len(accel_raw)

    ag = Antigravity(sampling_rate_hz=10.0)
    ag.initialize(stationary_accel=accel_raw[:30], stationary_gyro=gyro_raw[:30])

    clean_accels = []
    headings = []

    for i in range(N):
        out = ag.step(accel_raw[i], gyro_raw[i], dt=0.1)
        clean_accels.append(out.accel_clean)
        headings.append(np.degrees(np.arctan2(out.R_v2w_updated[1, 0], out.R_v2w_updated[0, 0])))

    clean_accels = np.array(clean_accels)

    # Highway straight cruising slice: evaluate RMS kinematic acceleration
    # In sample_drive: samples 600 to 2000 correspond to steady cruising
    cruise_slice = clean_accels[600:min(2000, N)]
    if len(cruise_slice) > 0:
        rms_cruise = float(np.sqrt(np.mean(np.linalg.norm(cruise_slice, axis=1)**2)))
        assert rms_cruise < 0.45, f"Cruise RMS clean accel too high: {rms_cruise:.4f} m/s^2 (target < 0.5)"

    # Alignment engine test
    alignment = AlignmentEngine()
    R_p2v_est = alignment.calibrate(accel_raw[:100])
    assert R_p2v_est.shape == (3, 3)
    assert abs(np.linalg.det(R_p2v_est) - 1.0) < 1e-4
