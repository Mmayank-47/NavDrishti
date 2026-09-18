"""
scripts/ab_test_gravity_compensation.py
─────────────────────────────────────────────────────────────────────────────
A/B Test: NavDrishti Odometry Performance With vs Without Gravity Compensation
Simulates 1-hour drive with phone mounted at dashboard pitch angle (15°).
Measures:
  - Displacement error over time
  - Lateral acceleration bias
  - Velocity drift
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import numpy as np
from src.preprocessing.gravity_compensator import GravityCompensator, STANDARD_GRAVITY
from src.integration.final_navigation_pipeline import FinalNavigationPipeline


def run_ab_comparison(duration_s: float = 3600.0, fs: float = 10.0, mount_pitch_deg: float = 15.0):
    """
    Run A/B benchmark:
    Baseline: Raw apparent acceleration (gravity leaks into body axes).
    Enhanced: 3D Dynamic Gravity Compensation (GravityCompensator).
    """
    dt = 1.0 / fs
    N = int(duration_s * fs)
    t = np.arange(N) * dt

    pitch_rad = np.radians(mount_pitch_deg)
    cy, sy = np.cos(pitch_rad), np.sin(pitch_rad)
    # Pitch rotation matrix (phone mounted on dashboard tilted back by pitch_rad)
    R_mount = np.array([
        [cy, 0.0, sy],
        [0.0, 1.0, 0.0],
        [-sy, 0.0, cy]
    ])

    rng = np.random.RandomState(42)

    # Simulated vehicle kinematics:
    # Cruising at 15 m/s with small speed variations and straight highway
    true_speed = 15.0 + 0.5 * np.sin(2 * np.pi * 0.005 * t)
    true_accel_fwd = np.gradient(true_speed, dt)
    true_accel_lat = np.zeros(N)

    # Apparent specific force in world frame: [a_fwd, a_lat, 0] + [0, 0, g]
    # Phone measures this force rotated by R_mount.T
    accel_raw_all = np.zeros((N, 3))
    for i in range(N):
        a_world = np.array([true_accel_fwd[i], true_accel_lat[i], STANDARD_GRAVITY])
        # Add realistic sensor noise
        noise = rng.normal(0, 0.04, 3)
        accel_raw_all[i] = R_mount.T @ a_world + noise

    gyro_raw_all = rng.normal(0, 0.001, (N, 3))

    # ── Condition A: Without Gravity Compensation (Naive / Raw Apparent Accel) ─
    # Gravity projects sin(15°) * 9.81 ≈ 2.54 m/s^2 onto the longitudinal axis!
    naive_pos = np.zeros((N, 2))
    naive_vel = np.zeros((N, 2))
    vel_cur_a = np.array([15.0, 0.0])
    pos_cur_a = np.array([0.0, 0.0])

    for i in range(N):
        # Naive approach: assumes level phone and subtracts [0, 0, 9.81] in phone frame
        a_naive = accel_raw_all[i] - np.array([0.0, 0.0, STANDARD_GRAVITY])
        a_fwd_naive = a_naive[0]
        a_lat_naive = a_naive[1]

        vel_cur_a += np.array([a_fwd_naive, a_lat_naive]) * dt
        pos_cur_a += vel_cur_a * dt
        naive_pos[i] = pos_cur_a.copy()
        naive_vel[i] = vel_cur_a.copy()

    # ── Condition B: With 3D Dynamic Gravity Compensation ─────────────────────
    gc = GravityCompensator(sampling_rate_hz=fs, g_val=STANDARD_GRAVITY)
    gc.initialize(stationary_accel=accel_raw_all[:20])

    comp_pos = np.zeros((N, 2))
    comp_vel = np.zeros((N, 2))
    vel_cur_b = np.array([15.0, 0.0])
    pos_cur_b = np.array([0.0, 0.0])

    for i in range(N):
        acc_clean, g_p, q, R = gc.step(accel_raw_all[i], gyro_raw_all[i], dt=dt)
        # Transform back to vehicle leveled frame
        acc_veh = gc.R_v2w @ acc_clean
        a_fwd_comp = acc_veh[0]
        a_lat_comp = acc_veh[1]

        vel_cur_b += np.array([a_fwd_comp, a_lat_comp]) * dt
        pos_cur_b += vel_cur_b * dt
        comp_pos[i] = pos_cur_b.copy()
        comp_vel[i] = vel_cur_b.copy()

    # Ground truth position
    true_pos_x = np.cumsum(true_speed * dt)
    true_pos = np.column_stack([true_pos_x, np.zeros(N)])

    err_naive_final = np.linalg.norm(naive_pos[-1] - true_pos[-1])
    err_comp_final = np.linalg.norm(comp_pos[-1] - true_pos[-1])
    reduction_pct = (err_naive_final - err_comp_final) / err_naive_final * 100.0

    print(f"============================================================")
    print(f"NavDrishti Gravity Compensation A/B Benchmark (1 Hour Drive)")
    print(f"Mount Pitch Angle: {mount_pitch_deg:.1f}°")
    print(f"------------------------------------------------------------")
    print(f"Condition A (Naive Subtraction) Final Error : {err_naive_final:,.1f} m")
    print(f"Condition B (3D Gravity Compensator) Error  : {err_comp_final:,.1f} m")
    print(f"Error Reduction: {reduction_pct:.2f}% (Target: > 30%)")
    print(f"============================================================")

    return {
        'err_naive_m': float(err_naive_final),
        'err_comp_m': float(err_comp_final),
        'reduction_pct': float(reduction_pct)
    }


if __name__ == '__main__':
    run_ab_comparison()
