"""
scripts/run_revalidation_v3.py
─────────────────────────────────────────────────────────────────────────────
Phase 20 Full SIH Revalidation: C4 vs C5 vs C6 (Retrained KalmanNet v3)
- C4: NIO v2 + KalmanNet v2 + NHC
- C5: Fine-Tuned NIO + KalmanNet v2 + NHC
- C6: Fine-Tuned NIO + KalmanNet v3 + NHC (New Model)
Full Multi-Window Benchmark across all 6 test sessions: S1, S2, S3a, S3b, S3c, S4.
Full Scenario A & Scenario B Evaluation.
─────────────────────────────────────────────────────────────────────────────
"""

import sys, json, time
from pathlib import Path
import numpy as np
import torch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment
from src.integration.final_navigation_pipeline import FinalNavigationPipeline
from src.models.inertial_odometry import NeuralInertialOdometry

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'

# Checkpoints
NIO_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_fixed' / 'nio_fixed_best.pt'
NIO_FT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned' / 'nio_vel_best.pt'
KNET_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_fixed_input' / 'kalmannet_best.pt'
KNET_V3_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_v3' / 'kalmannet_best.pt'

TEST_SESSIONS = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']


def load_nio_model(ckpt_path):
    if not Path(ckpt_path).exists():
        return None
    ckpt = torch.load(ckpt_path, map_location=DEVICE, weights_only=False)
    if ckpt.get('model_state_dict') is None:
        return None
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
                pad_len = win_size - (i + 1)
                pad = np.repeat(imu_6d[0:1], pad_len, axis=0)
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


def evaluate_window(pipeline_args, sess, w_start, w_len, dt=0.1, nio_speeds=None):
    acc_filt = sess['accel_filtered']
    gyr_filt = sess['gyro_filtered']
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
    nhc_inflated_counts = []
    cornering_states = []

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
            nhc_inflated_counts.append(st.get('nhc_rejected_or_inflated_count', 0))
            cornering_states.append(st.get('cornering_state', 'UNKNOWN'))
            
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
    
    # Heading change over outage
    gyr_v = (R_p2v @ sess['gyro_filtered'][w_start:w_end].T).T
    heading_change_deg = float(np.degrees(np.sum(gyr_v[:, 2] * dt)))
    mean_speed_mps = float(dist_during_outage / max(w_len * dt, 1e-3))
    
    return {
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
        'nhc_active_all': bool(all(nhc_active_list)) if nhc_active_list else False,
        'nhc_update_count': int(nhc_update_counts[-1]) if nhc_update_counts else 0,
        'nhc_inflated_count': int(nhc_inflated_counts[-1]) if nhc_inflated_counts else 0,
        'cornering_count': int(sum(1 for s in cornering_states if s == 'CORNERING'))
    }


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
    print("PHASE 20: FULL REVALIDATION — C4 vs C5 vs C6 (KALMANNET V3)")
    print("=" * 80)
    print(f"Device: {DEVICE}")

    loader = IOVNBDLoader()
    nio_ft = load_nio_model(NIO_FT_PATH)
    nio_v2 = load_nio_model(NIO_V2_PATH)
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
        spd_v2 = precompute_nio_speeds(nio_v2, acc_v, gyr_v, len(acc_v))
        
        enu = sess['enu_coords'][:, :2]
        cum_d = np.insert(np.cumsum(np.linalg.norm(np.diff(enu, axis=0), axis=1)), 0, 0.0)
        
        session_data[s_name] = {
            'sess': sess,
            'spd_ref': veh_spd,
            'spd_nio_ft': spd_ft,
            'spd_nio_v2': spd_v2,
            'cum_dist': cum_d,
            'N': len(acc_v)
        }

    # ── 1. Master Configuration Comparison: C4 vs C5 vs C6 on S1 ──────────────
    print("\n" + "=" * 80)
    print("1. MASTER COMPARISON: C4 vs C5 vs C6 (S1 Window [1500..1800], 30s Outage)")
    print("=" * 80)
    
    ws_comp, wl_comp = 1500, 300
    s1_data = session_data['S1']
    
    cfg_c4 = {'knet_checkpoint_path': str(KNET_V2_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25, 'device': DEVICE}
    cfg_c5 = {'knet_checkpoint_path': str(KNET_V2_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25, 'device': DEVICE}
    cfg_c6 = {'knet_checkpoint_path': str(KNET_V3_PATH), 'enable_nhc': True, 'sigma_nhc': 0.20, 'yaw_rate_threshold': 0.25, 'device': DEVICE}
    
    r_c4 = evaluate_window(cfg_c4, s1_data['sess'], ws_comp, wl_comp, nio_speeds=s1_data['spd_nio_v2'])
    r_c5 = evaluate_window(cfg_c5, s1_data['sess'], ws_comp, wl_comp, nio_speeds=s1_data['spd_nio_ft'])
    r_c6 = evaluate_window(cfg_c6, s1_data['sess'], ws_comp, wl_comp, nio_speeds=s1_data['spd_nio_ft'])
    
    print(f"  C4 (NIO v2 + KNet v2 + NHC): FinalErr: {r_c4['final_error_m']:7.2f}m | Drift: {r_c4['drift_pct']:6.2f}% | RMSE: {r_c4['rmse_m']:6.2f}m | Jump: {r_c4['recovery_jump_m']:.3f}m")
    print(f"  C5 (NIO FT + KNet v2 + NHC): FinalErr: {r_c5['final_error_m']:7.2f}m | Drift: {r_c5['drift_pct']:6.2f}% | RMSE: {r_c5['rmse_m']:6.2f}m | Jump: {r_c5['recovery_jump_m']:.3f}m")
    print(f"  C6 (NIO FT + KNet v3 + NHC): FinalErr: {r_c6['final_error_m']:7.2f}m | Drift: {r_c6['drift_pct']:6.2f}% | RMSE: {r_c6['rmse_m']:6.2f}m | Jump: {r_c6['recovery_jump_m']:.3f}m")

    # ── 2. Full Multi-Window Benchmark for C6 Across All 6 Sessions ─────────
    print("\n" + "=" * 80)
    print("2. FULL MULTI-WINDOW BENCHMARK FOR C6 (NIO FT + KNet v3 + NHC)")
    print("=" * 80)
    
    full_benchmark = {}
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        N_sess = s_data['N']
        sess_results = {}
        
        for dur_s, step_len in [(10, 100), (30, 300), (60, 600)]:
            stride = step_len + 50
            starts = list(range(100, N_sess - step_len - 50, stride))
            if len(starts) > 15:
                starts = starts[:15]
                
            records = []
            for ws in starts:
                r = evaluate_window(cfg_c6, s_data['sess'], ws, step_len, nio_speeds=s_data['spd_nio_ft'])
                records.append(r)
                
            summary = compute_summary_stats(records)
            sess_results[f"{dur_s}s"] = {
                'step_len': step_len,
                'windows_evaluated': len(records),
                'summary': summary,
                'windows': records
            }
            if summary:
                print(f"  {s_name:5s} | {dur_s:2d}s (N={len(records):2d}) | Mean Drift: {summary['drift_pct']['mean']:6.2f}% (Med: {summary['drift_pct']['median']:6.2f}%) | Mean RMSE: {summary['rmse_m']['mean']:6.2f}m | FinalErr: {summary['final_error_m']['mean']:6.2f}m")
            else:
                print(f"  {s_name:5s} | {dur_s:2d}s | N=0")
        full_benchmark[s_name] = sess_results

    # ── 3. Scenario A Evaluation for C6 ───────────────────────────────────────
    print("\n" + "=" * 80)
    print("3. SIH SCENARIO A EVALUATION (C6)")
    print("=" * 80)
    
    scenario_a_all = {}
    total_a_pass = 0
    total_a_quals = 0
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        enu_gt = s_data['sess']['enu_coords'][:, :2]
        cum_d = s_data['cum_dist']
        spd_ref = s_data['spd_ref']
        
        quals = find_qualifying_segments(enu_gt, cum_d, spd_ref, dt=0.1, t_min_s=3.0, t_max_s=5.0, d_min_m=40.0, d_max_m=60.0, min_speed_mps=5.0, max_segments=10)
        total_a_quals += len(quals)
        evals = []
        for q in quals:
            w_len = q['end_idx'] - q['start_idx']
            r = evaluate_window(cfg_c6, s_data['sess'], q['start_idx'], w_len, nio_speeds=s_data['spd_nio_ft'])
            r['criteria'] = q
            r['sih_pass_5m'] = bool(r['final_error_m'] <= 5.0)
            if r['sih_pass_5m']:
                total_a_pass += 1
            evals.append(r)
            print(f"    [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | FinalErr: {r['final_error_m']:.3f}m | Pass(<=5m): {r['sih_pass_5m']}")
            
        scenario_a_all[s_name] = {
            'qualifying_count': len(quals),
            'evaluations': evals,
            'pass_count': sum(1 for e in evals if e['sih_pass_5m'])
        }

    # ── 4. Scenario B Evaluation for C6 ───────────────────────────────────────
    print("\n" + "=" * 80)
    print("4. SIH SCENARIO B EVALUATION (C6)")
    print("=" * 80)
    
    scenario_b_all = {}
    for s_name in ['S1', 'S2', 'S4']:
        s_data = session_data[s_name]
        enu_gt = s_data['sess']['enu_coords'][:, :2]
        cum_d = s_data['cum_dist']
        spd_ref = s_data['spd_ref']
        
        quals_b = find_qualifying_segments(enu_gt, cum_d, spd_ref, dt=0.1, t_min_s=55.0, t_max_s=65.0, d_min_m=850.0, d_max_m=1150.0, min_speed_mps=0.0, max_segments=20)
        evals_b = []
        for idx_b, q in enumerate(quals_b):
            w_len = q['end_idx'] - q['start_idx']
            r = evaluate_window(cfg_c6, s_data['sess'], q['start_idx'], w_len, nio_speeds=s_data['spd_nio_ft'])
            r['segment_id'] = f"{s_name}_seg{idx_b}"
            r['criteria'] = q
            r['sih_pass_100m'] = bool(r['final_error_m'] <= 100.0)
            evals_b.append(r)
            print(f"    Seg {idx_b:2d} [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | FinalErr: {r['final_error_m']:6.2f}m ({r['drift_pct']:5.2f}%) | RMSE: {r['rmse_m']:5.2f}m | Pass(<=100m): {r['sih_pass_100m']}")
            
        scenario_b_all[s_name] = {
            'qualifying_count': len(quals_b),
            'evaluations': evals_b,
            'pass_count': sum(1 for e in evals_b if e['sih_pass_100m'])
        }

    # ── Save Results ────────────────────────────────────────────────────────
    out_dir = PROJECT_ROOT / 'results' / 'phase_revalidation_v3'
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / 'revalidation_v3_results.json'
    
    save_data = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'device': DEVICE,
        'c4_vs_c5_vs_c6': {
            'C4': r_c4,
            'C5': r_c5,
            'C6': r_c6
        },
        'full_benchmark_c6': full_benchmark,
        'scenario_a_c6': scenario_a_all,
        'scenario_b_c6': scenario_b_all
    }
    
    with open(out_file, 'w') as f:
        json.dump(save_data, f, indent=2)
    print(f"\nSaved Phase 20 Revalidation results to: {out_file}")


if __name__ == '__main__':
    main()
