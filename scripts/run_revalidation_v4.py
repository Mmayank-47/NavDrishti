"""
scripts/run_revalidation_v4.py
─────────────────────────────────────────────────────────────────────────────
Phase 21 Full SIH Revalidation & Controlled Kinematic Ablation:
- Controlled Ablation A1..A5 on S1 30s master window
- Full Multi-Window Benchmark (10s, 30s, 60s) for C7 across S1..S4
- Full SIH Scenario A & Scenario B Evaluation
- Publication-Ready Plot Generation
─────────────────────────────────────────────────────────────────────────────
"""

import sys, json, time
from pathlib import Path
import numpy as np
import torch
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment
from src.integration.final_navigation_pipeline import FinalNavigationPipeline
from src.models.inertial_odometry import NeuralInertialOdometry

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'

# Checkpoints
NIO_FT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned' / 'nio_vel_best.pt'
KNET_V3_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_v3' / 'kalmannet_best.pt'
KNET_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_fixed_input' / 'kalmannet_best.pt'

TEST_SESSIONS = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']


def load_nio_model(ckpt_path):
    if not Path(ckpt_path).exists():
        return None
    ckpt = torch.load(ckpt_path, map_location=DEVICE, weights_only=False)
    cfg = ckpt.get('config', {})
    model = NeuralInertialOdometry(
        input_dim=6,
        tcn_channels=cfg.get('tcn_channels', [64, 128, 256]),
        kernel_size=cfg.get('tcn_kernel_size', 3),
        dropout=0.0
    ).to(DEVICE)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()
    return model


def precompute_nio_speeds(nio_model, acc_v, gyr_v, n_samples, win_size=100):
    if nio_model is None:
        return None
    imu_6d = np.hstack([acc_v, gyr_v]).astype(np.float32)
    speeds = np.zeros(n_samples, dtype=np.float32)
    
    batch_windows = []
    batch_indices = []
    
    with torch.no_grad():
        for i in range(n_samples):
            if i < win_size:
                pad = np.repeat(imu_6d[0:1], win_size - (i + 1), axis=0)
                w = np.vstack([pad, imu_6d[:i+1]])
            else:
                w = imu_6d[i - win_size + 1 : i + 1]
            batch_windows.append(w)
            batch_indices.append(i)
            
            if len(batch_windows) >= 256 or i == n_samples - 1:
                batch_t = torch.tensor(np.array(batch_windows), dtype=torch.float32, device=DEVICE)
                _, p_v, _ = nio_model(batch_t)
                p_v_np = p_v[:, 0].detach().cpu().numpy()
                for idx_b, target_idx in enumerate(batch_indices):
                    speeds[target_idx] = max(0.0, float(p_v_np[idx_b]))
                batch_windows = []
                batch_indices = []
                
    return speeds


def evaluate_window(pipeline_args, sess, w_start, w_len, dt=0.1, nio_speeds=None, return_trajectory=False):
    lat_gps = sess['gps']['lat']
    lon_gps = sess['gps']['lon']
    enu_gt = sess['enu_coords'][:, :2]
    veh_spd = sess['vehicle']['speed_mps']
    if veh_spd is None:
        veh_spd = sess['gps']['speed_mps']
    if veh_spd is None:
        veh_spd = np.zeros(len(enu_gt))
        
    aligner = PhoneVehicleAlignment()
    R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
    
    w_end = w_start + w_len
    seg_start = max(0, w_start - 100)
    seg_end = min(len(enu_gt), w_end + 100)
    
    enu_seg = enu_gt[seg_start:seg_end] - enu_gt[seg_start]
    dist_during_outage = float(np.sum(np.linalg.norm(np.diff(enu_gt[w_start:w_end], axis=0), axis=1)))
    
    diff_init = enu_gt[seg_start + 10] - enu_gt[seg_start]
    h0 = float(np.arctan2(diff_init[1], diff_init[0]))
    
    pipeline = FinalNavigationPipeline(**pipeline_args)
    pipeline.initialize(
        lat0=lat_gps[seg_start],
        lon0=lon_gps[seg_start],
        alt0=sess['gps']['alt0'],
        initial_heading=h0,
        initial_speed=float(veh_spd[seg_start]),
        R_p2v=R_p2v
    )
    
    est_enu = []
    nhc_active_list = []
    nhc_update_counts = []
    cornering_states = []
    v_est_list = []

    for i_global in range(seg_start, seg_end):
        is_blk = (w_start <= i_global < w_end)
        s_ref = float(nio_speeds[i_global]) if nio_speeds is not None else float(veh_spd[i_global])
        
        st = pipeline.step(
            accel_raw=sess['accel_raw'][i_global],
            gyro_raw=sess['gyro_raw'][i_global],
            p_gnss_geodetic=(lat_gps[i_global], lon_gps[i_global]),
            hdop=1.0,
            is_blackout=is_blk,
            speed_ref=s_ref,
            dt=dt
        )
        est_enu.append([st['east_m'], st['north_m']])
        if is_blk:
            nhc_active_list.append(st.get('nhc_active', False))
            nhc_update_counts.append(st.get('nhc_update_count', 0))
            cornering_states.append(st.get('cornering_state', 'UNKNOWN'))
            v_est_list.append(float(st.get('speed_mps', 0.0)))
            
    est_enu = np.array(est_enu)
    b_idx_start = w_start - seg_start
    b_idx_end = w_end - seg_start
    est_outage = est_enu[b_idx_start:b_idx_end]
    gt_outage = enu_seg[b_idx_start:b_idx_end]
    
    pos_errs = np.linalg.norm(est_outage - gt_outage, axis=1)
    final_err = float(pos_errs[-1])
    rmse = float(np.sqrt(np.mean(pos_errs**2)))
    max_err = float(np.max(pos_errs))
    drift_pct = float(final_err / max(dist_during_outage, 1e-3) * 100.0)
    
    recov_idx = min(len(est_enu) - 1, b_idx_end + 5)
    recov_pos_err = float(np.linalg.norm(est_enu[recov_idx] - enu_seg[recov_idx]))
    recovery_jump = float(abs(pos_errs[-1] - recov_pos_err))
    
    gyr_v = (R_p2v @ sess['gyro_filtered'][w_start:w_end].T).T
    heading_change_deg = float(np.degrees(np.sum(gyr_v[:, 2] * dt)))
    mean_speed_mps = float(dist_during_outage / max(w_len * dt, 1e-3))
    
    res = {
        'w_start': int(w_start),
        'w_end': int(w_end),
        'w_len': int(w_len),
        'duration_s': float(w_len * dt),
        'distance_m': float(dist_during_outage),
        'mean_speed_mps': float(mean_speed_mps),
        'heading_change_deg': float(heading_change_deg),
        'final_error_m': float(final_err),
        'drift_pct': float(drift_pct),
        'rmse_m': float(rmse),
        'max_error_m': float(max_err),
        'recovery_jump_m': float(recovery_jump),
        'nhc_update_count': int(nhc_update_counts[-1]) if nhc_update_counts else 0,
        'cornering_count': int(sum(1 for s in cornering_states if s == 'CORNERING')),
        'stationary_count': int(sum(1 for s in cornering_states if s == 'STATIONARY'))
    }
    if return_trajectory:
        res['est_outage'] = est_outage
        res['gt_outage'] = gt_outage
        res['v_est_list'] = np.array(v_est_list)
    return res


def find_qualifying_segments(enu, cum_dist, spd, dt=0.1, t_min_s=3.0, t_max_s=5.0, d_min_m=40.0, d_max_m=60.0, min_speed_mps=5.0, max_segments=30):
    N = len(enu)
    min_steps = int(np.floor(t_min_s / dt))
    max_steps = int(np.ceil(t_max_s / dt))
    qualifying = []
    step_stride = 5
    for s_idx in range(0, N - min_steps, step_stride):
        for e_idx in range(s_idx + min_steps, min(s_idx + max_steps + 1, N)):
            dur_s = (e_idx - s_idx) * dt
            dist_m = float(cum_dist[e_idx] - cum_dist[s_idx])
            mean_spd = float(np.mean(spd[s_idx:e_idx]))
            if (t_min_s <= dur_s <= t_max_s) and (d_min_m <= dist_m <= d_max_m) and (mean_spd >= min_speed_mps):
                qualifying.append({
                    'start_idx': int(s_idx),
                    'end_idx': int(e_idx),
                    'duration_s': float(round(dur_s, 2)),
                    'distance_m': float(round(dist_m, 2)),
                    'mean_speed_mps': float(round(mean_spd, 2))
                })
                break
        if len(qualifying) >= max_segments:
            break
    return qualifying


def compute_summary_stats(records):
    if not records:
        return {}
    drifts = [r['drift_pct'] for r in records]
    final_errs = [r['final_error_m'] for r in records]
    rmses = [r['rmse_m'] for r in records]
    max_errs = [r['max_error_m'] for r in records]
    jumps = [r['recovery_jump_m'] for r in records]
    
    def stat_dict(arr):
        a = np.array(arr)
        return {
            'mean': float(np.mean(a)),
            'median': float(np.median(a)),
            'std': float(np.std(a)),
            'min': float(np.min(a)),
            'max': float(np.max(a)),
            'p95': float(np.percentile(a, 95))
        }
        
    return {
        'count': len(records),
        'drift_pct': stat_dict(drifts),
        'final_error_m': stat_dict(final_errs),
        'rmse_m': stat_dict(rmses),
        'max_error_m': stat_dict(max_errs),
        'recovery_jump_m': stat_dict(jumps)
    }


def main():
    print("=" * 80)
    print("PHASE 21: FULL SIH REVALIDATION & CONTROLLED KINEMATIC ABLATION")
    print("=" * 80)
    print(f"Device: {DEVICE}")

    loader = IOVNBDLoader()
    nio_ft = load_nio_model(NIO_FT_PATH)
    assert nio_ft is not None, f"Could not load NIO Fine-tuned from {NIO_FT_PATH}"
    assert Path(KNET_V3_PATH).exists(), f"KalmanNet v3 checkpoint not found at {KNET_V3_PATH}"

    session_data = {}
    for s_name in TEST_SESSIONS:
        print(f"Loading session {s_name}...")
        sess = loader.load_session(s_name, preprocess_imu=True)
        aligner = PhoneVehicleAlignment()
        veh_spd = sess['vehicle']['speed_mps']
        if veh_spd is None:
            veh_spd = sess['gps']['speed_mps']
        if veh_spd is None:
            veh_spd = np.zeros(len(sess['accel_filtered']))
        R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
        acc_v = (R_p2v @ sess['accel_filtered'].T).T
        gyr_v = (R_p2v @ sess['gyro_filtered'].T).T
        
        spd_ft = precompute_nio_speeds(nio_ft, acc_v, gyr_v, len(acc_v))
        
        enu = sess['enu_coords'][:, :2]
        cum_d = np.insert(np.cumsum(np.linalg.norm(np.diff(enu, axis=0), axis=1)), 0, 0.0)
        
        session_data[s_name] = {
            'sess': sess,
            'spd_ref': veh_spd,
            'spd_nio_ft': spd_ft,
            'cum_dist': cum_d,
            'N': len(acc_v)
        }

    # ── 1. Controlled Kinematic Ablation: A1..A5 on S1 [1500..1800] ──────────
    print("\n" + "=" * 80)
    print("1. CONTROLLED KINEMATIC ABLATION (Session S1 Window [1500..1800], 30s Outage)")
    print("=" * 80)
    
    ws_comp, wl_comp = 1500, 300
    s1_data = session_data['S1']
    
    ablation_cfgs = {
        'A1_C6_Baseline': {
            'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25,
            'enable_zupt': False, 'enable_bias_tracking': False, 'enable_kinematic_speed': False, 'enable_adaptive_nhc': False, 'device': DEVICE
        },
        'A2_Plus_ZUPT': {
            'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25,
            'enable_zupt': True, 'enable_bias_tracking': False, 'enable_kinematic_speed': False, 'enable_adaptive_nhc': False, 'device': DEVICE
        },
        'A3_Plus_Bias_Comp': {
            'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25,
            'enable_zupt': True, 'enable_bias_tracking': True, 'enable_kinematic_speed': False, 'enable_adaptive_nhc': False, 'device': DEVICE
        },
        'A4_Plus_Speed_Observer': {
            'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25,
            'enable_zupt': True, 'enable_bias_tracking': True, 'enable_kinematic_speed': True, 'enable_adaptive_nhc': False, 'device': DEVICE
        },
        'A5_C7_Full_Enhanced': {
            'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25,
            'enable_zupt': True, 'enable_bias_tracking': True, 'enable_kinematic_speed': True, 'enable_adaptive_nhc': True, 'device': DEVICE
        }
    }
    
    ablation_results = {}
    trajectory_data = {}
    for aname, acfg in ablation_cfgs.items():
        r = evaluate_window(acfg, s1_data['sess'], ws_comp, wl_comp, nio_speeds=s1_data['spd_nio_ft'], return_trajectory=True)
        trajectory_data[aname] = {
            'est': r.pop('est_outage'),
            'gt': r.pop('gt_outage'),
            'v_est': r.pop('v_est_list')
        }
        ablation_results[aname] = r
        print(f"  {aname:24s} | FinalErr: {r['final_error_m']:7.2f}m | Drift: {r['drift_pct']:6.2f}% | RMSE: {r['rmse_m']:6.2f}m | RecJump: {r['recovery_jump_m']:.3f}m")

    # ── 2. Full Multi-Window Benchmark for C7 Across All 6 Sessions ─────────
    print("\n" + "=" * 80)
    print("2. FULL MULTI-WINDOW BENCHMARK FOR C7 (ENHANCED PIPELINE)")
    print("=" * 80)
    
    c7_cfg = ablation_cfgs['A5_C7_Full_Enhanced']
    full_benchmark_c7 = {}
    
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        N_sess = s_data['N']
        sess_results = {}
        
        for dur_s, step_len in [(10, 100), (30, 300), (60, 600)]:
            stride = step_len + 50
            window_records = []
            
            for w_s in range(500, N_sess - step_len - 100, stride):
                rec = evaluate_window(c7_cfg, s_data['sess'], w_s, step_len, nio_speeds=s_data['spd_nio_ft'])
                window_records.append(rec)
                if len(window_records) >= 15:
                    break
                    
            summary = compute_summary_stats(window_records)
            sess_results[f"{dur_s}s"] = {
                'count': len(window_records),
                'summary': summary,
                'windows': window_records
            }
            if summary:
                print(f"  {s_name:4s} {dur_s:2d}s (N={len(window_records):2d}) | Mean Drift: {summary['drift_pct']['mean']:7.2f}% (Med: {summary['drift_pct']['median']:6.2f}%) | Final Err: {summary['final_error_m']['mean']:6.2f}m | RMSE: {summary['rmse_m']['mean']:6.2f}m | RecJump: {summary['recovery_jump_m']['mean']:.3f}m | Stn: {sum(r['stationary_count'] for r in window_records)}")
                
        full_benchmark_c7[s_name] = sess_results

    # ── 3. SIH Scenario A Re-evaluation (Autonomous NIO vs Reference Speed) ──
    print("\n" + "=" * 80)
    print("3. SIH SCENARIO A EVALUATION (3–5s, 40–60m, >=5 m/s, Pass <= 5m)")
    print("=" * 80)
    
    scenario_a_all = {}
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        quals_a = find_qualifying_segments(
            s_data['sess']['enu_coords'][:, :2],
            s_data['cum_dist'],
            s_data['spd_ref'],
            t_min_s=3.0, t_max_s=5.0, d_min_m=40.0, d_max_m=60.0, min_speed_mps=5.0, max_segments=10
        )
        print(f"  {s_name:4s} -> Found {len(quals_a)} qualifying Scenario A segments")
        
        evals_nio = []
        evals_ref = []
        for idx_a, q in enumerate(quals_a):
            w_len = q['end_idx'] - q['start_idx']
            # Autonomous NIO Mode
            r_nio = evaluate_window(c7_cfg, s_data['sess'], q['start_idx'], w_len, nio_speeds=s_data['spd_nio_ft'])
            r_nio['sih_pass_5m'] = bool(r_nio['final_error_m'] <= 5.0)
            evals_nio.append(r_nio)
            
            # Reference Speed Mode (Wheel speed upper bound)
            r_ref = evaluate_window(c7_cfg, s_data['sess'], q['start_idx'], w_len, nio_speeds=None)
            r_ref['sih_pass_5m'] = bool(r_ref['final_error_m'] <= 5.0)
            evals_ref.append(r_ref)
            
            print(f"    [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | Spd: {q['mean_speed_mps']}m/s | NIO Err: {r_nio['final_error_m']:5.2f}m (Pass: {r_nio['sih_pass_5m']}) | Ref Err: {r_ref['final_error_m']:5.2f}m (Pass: {r_ref['sih_pass_5m']})")
            
        scenario_a_all[s_name] = {
            'qualifying_count': len(quals_a),
            'evaluations_nio': evals_nio,
            'pass_count_nio': sum(1 for e in evals_nio if e['sih_pass_5m']),
            'evaluations_ref': evals_ref,
            'pass_count_ref': sum(1 for e in evals_ref if e['sih_pass_5m'])
        }

    # ── 4. SIH Scenario B Re-evaluation (~60s Outage, ~1km, Pass <= 100m) ────
    print("\n" + "=" * 80)
    print("4. SIH SCENARIO B EVALUATION (~60s, ~1km Outage, Pass <= 100m)")
    print("=" * 80)
    
    scenario_b_all = {}
    scenario_b_traj_passes = []
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        quals_b = find_qualifying_segments(
            s_data['sess']['enu_coords'][:, :2],
            s_data['cum_dist'],
            s_data['spd_ref'],
            t_min_s=55.0, t_max_s=65.0, d_min_m=850.0, d_max_m=1150.0, min_speed_mps=10.0, max_segments=20
        )
        print(f"  {s_name:4s} -> Found {len(quals_b)} qualifying Scenario B segments")
        
        evals_b = []
        for idx_b, q in enumerate(quals_b):
            w_len = q['end_idx'] - q['start_idx']
            r = evaluate_window(c7_cfg, s_data['sess'], q['start_idx'], w_len, nio_speeds=s_data['spd_nio_ft'], return_trajectory=True)
            r['sih_pass_100m'] = bool(r['final_error_m'] <= 100.0)
            if r['sih_pass_100m']:
                scenario_b_traj_passes.append({
                    'session': s_name,
                    'seg_idx': idx_b,
                    'criteria': q,
                    'est': r.pop('est_outage'),
                    'gt': r.pop('gt_outage'),
                    'final_err': r['final_error_m'],
                    'drift_pct': r['drift_pct']
                })
            else:
                r.pop('est_outage', None)
                r.pop('gt_outage', None)
                r.pop('v_est_list', None)
            evals_b.append(r)
            print(f"    Seg {idx_b:2d} [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | FinalErr: {r['final_error_m']:6.2f}m ({r['drift_pct']:5.2f}%) | RMSE: {r['rmse_m']:5.2f}m | Pass(<=100m): {r['sih_pass_100m']}")
            
        scenario_b_all[s_name] = {
            'qualifying_count': len(quals_b),
            'evaluations': evals_b,
            'pass_count': sum(1 for e in evals_b if e['sih_pass_100m'])
        }

    # ── 5. Generate Publication-Ready Plots ──────────────────────────────────
    print("\n" + "=" * 80)
    print("5. GENERATING PUBLICATION-READY EVALUATION PLOTS")
    print("=" * 80)
    
    plots_dir = PROJECT_ROOT / 'plots' / 'phase_revalidation_v4'
    plots_dir.mkdir(parents=True, exist_ok=True)
    
    # Plot 1: Ablation Trajectory Comparison on S1 [1500..1800]
    plt.figure(figsize=(10, 8))
    gt_traj = trajectory_data['A1_C6_Baseline']['gt']
    plt.plot(gt_traj[:, 0], gt_traj[:, 1], 'k-', linewidth=2.5, label='Ground Truth (GNSS/INS)')
    for aname, c_color in [('A1_C6_Baseline', 'red'), ('A3_Plus_Bias_Comp', 'orange'), ('A5_C7_Full_Enhanced', 'blue')]:
        est = trajectory_data[aname]['est']
        err = ablation_results[aname]['final_error_m']
        d_p = ablation_results[aname]['drift_pct']
        plt.plot(est[:, 0], est[:, 1], '--', color=c_color, linewidth=2.0, label=f'{aname} (Err: {err:.1f}m, {d_p:.1f}%)')
    plt.xlabel('East Displacement [m]', fontsize=12)
    plt.ylabel('North Displacement [m]', fontsize=12)
    plt.title('Controlled Kinematic Ablation: 30s Blackout Trajectory Comparison (S1)', fontsize=13, fontweight='bold')
    plt.legend(loc='best', fontsize=10)
    plt.grid(True, linestyle=':', alpha=0.6)
    plt.axis('equal')
    p1_path = plots_dir / 's1_30s_ablation_trajectory_comparison.png'
    plt.savefig(p1_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  Saved Plot 1: {p1_path}")

    # Plot 2: Velocity Regularization Profile (Raw NIO vs Kinematic Observer vs GT)
    plt.figure(figsize=(12, 5))
    t_axis = np.arange(wl_comp) * 0.1
    s1_gt_v = s1_data['spd_ref'][ws_comp:ws_comp+wl_comp]
    raw_v = s1_data['spd_nio_ft'][ws_comp:ws_comp+wl_comp]
    obs_v = trajectory_data['A5_C7_Full_Enhanced']['v_est']
    plt.plot(t_axis, s1_gt_v, 'k-', linewidth=2.0, label='Ground Truth Vehicle Speed (OBD)')
    plt.plot(t_axis, raw_v, 'r:', linewidth=1.5, alpha=0.7, label='Raw NIO Speed (Sawtooth Noise)')
    if len(obs_v) == len(t_axis):
        plt.plot(t_axis, obs_v, 'b-', linewidth=2.0, label='Kinematic Speed Observer (C7)')
    plt.xlabel('Outage Time [s]', fontsize=12)
    plt.ylabel('Forward Velocity [m/s]', fontsize=12)
    plt.title('Vehicle Forward Velocity: Raw NIO Noise vs Kinematic Fusion Observer', fontsize=13, fontweight='bold')
    plt.legend(loc='best', fontsize=11)
    plt.grid(True, linestyle=':', alpha=0.6)
    p2_path = plots_dir / 'velocity_regularization_profile.png'
    plt.savefig(p2_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  Saved Plot 2: {p2_path}")

    # Plot 3: Scenario B Passing Trajectories (S4)
    if scenario_b_traj_passes:
        plt.figure(figsize=(10, 8))
        for p_idx, p_item in enumerate(scenario_b_traj_passes[:3]):
            gt_b = p_item['gt']
            est_b = p_item['est']
            plt.plot(gt_b[:, 0], gt_b[:, 1], 'k-', linewidth=2.0, label='Ground Truth' if p_idx == 0 else None)
            plt.plot(est_b[:, 0], est_b[:, 1], '--', linewidth=2.0, label=f"Pass {p_idx+1}: {p_item['criteria']['distance_m']:.0f}m ({p_item['final_err']:.1f}m err, {p_item['drift_pct']:.1f}%)")
        plt.xlabel('East Displacement [m]', fontsize=12)
        plt.ylabel('North Displacement [m]', fontsize=12)
        plt.title('SIH Scenario B Passing Trajectories (Session S4 Highway, Target <= 100m)', fontsize=13, fontweight='bold')
        plt.legend(loc='best', fontsize=10)
        plt.grid(True, linestyle=':', alpha=0.6)
        plt.axis('equal')
        p3_path = plots_dir / 'scenario_b_passing_trajectories_s4.png'
        plt.savefig(p3_path, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"  Saved Plot 3: {p3_path}")

    # ── 6. Save Comprehensive JSON Results ──────────────────────────────────
    out_dir = PROJECT_ROOT / 'results' / 'phase_revalidation_v4'
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / 'revalidation_v4_results.json'
    
    save_data = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'device': DEVICE,
        'controlled_ablation_s1_30s': ablation_results,
        'full_benchmark_c7': full_benchmark_c7,
        'scenario_a': scenario_a_all,
        'scenario_b': scenario_b_all
    }
    
    with open(out_file, 'w') as f:
        json.dump(save_data, f, indent=2)
    print(f"\nSaved Phase 21 Revalidation results to: {out_file}")


if __name__ == '__main__':
    main()
