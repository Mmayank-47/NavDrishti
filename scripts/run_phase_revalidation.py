"""
scripts/run_phase_revalidation.py
─────────────────────────────────────────────────────────────────────────────
Comprehensive Post-Phase-2/3 Revalidation Suite
Implements Phases 6, 7, 8, 9, 10, 11:
  - Phase 6: Integration with frozen KalmanNet v2 + NHC (C4 vs C5)
  - Phase 7: Full SIH benchmark across all 6 test sessions (S1, S2, S3a, S3b, S3c, S4)
             Evaluating 10s, 30s, 60s windows across non-overlapping windows.
  - Phase 8: SIH Scenario A search & evaluation (3–5s, 40–60m, >=5 m/s)
  - Phase 9: SIH Scenario B full evaluation (~1 km / ~60s)
  - Phase 10: MapGNN / LIMU-BERT kept offline/frozen (pure DR + NHC reported)
  - Phase 11: Ablation / Causal Check (No NHC vs C4 vs C5)
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
MAP_GNN_PATH = PROJECT_ROOT / 'checkpoints' / 'map_gnn' / 'map_gnn_best.pt'
GRAPH_PATH = PROJECT_ROOT / 'data' / 'OSM' / 'road_graph_coventry.pkl'

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
    if ckpt.get('model_state_dict') is None:
        return None
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
    print("=" * 75)
    print("FULL MULTI-SESSION REVALIDATION SUITE (PHASES 6, 7, 8, 9, 10, 11)")
    print("=" * 75)
    print(f"Device: {DEVICE}")

    loader = IOVNBDLoader()
    
    nio_v2 = load_nio_model(NIO_V2_PATH)
    nio_ft = load_nio_model(NIO_FT_PATH)
    
    assert nio_v2 is not None, f"Could not load NIO v2 from {NIO_V2_PATH}"
    print(f"NIO v2 loaded successfully.")
    print(f"NIO Fine-tuned loaded: {nio_ft is not None} (from {NIO_FT_PATH})")
    
    # ── Preload test sessions and precompute speeds ────────────────────────
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
        
        spd_v2 = precompute_nio_speeds(nio_v2, acc_v, gyr_v, len(acc_v))
        spd_ft = precompute_nio_speeds(nio_ft, acc_v, gyr_v, len(acc_v)) if nio_ft is not None else None
        
        enu = sess['enu_coords'][:, :2]
        cum_d = np.insert(np.cumsum(np.linalg.norm(np.diff(enu, axis=0), axis=1)), 0, 0.0)
        
        session_data[s_name] = {
            'sess': sess,
            'spd_ref': veh_spd,
            'spd_nio_v2': spd_v2,
            'spd_nio_ft': spd_ft,
            'cum_dist': cum_d,
            'N': len(acc_v)
        }

    # ── 1. CONTROLLED COMPARISON: C4 vs C5 (Phase 6) ──────────────────────────
    print("\n" + "=" * 75)
    print("PHASE 6: CONTROLLED COMPARISON (C4: NIO v2 vs C5: Fine-tuned NIO + KNet v2 + NHC)")
    print("=" * 75)
    
    cfg_base = {
        'knet_checkpoint_path': str(KNET_V2_PATH),
        'enable_nhc': True,
        'sigma_nhc': 0.20,
        'yaw_rate_threshold': 0.25,
        'device': DEVICE
    }
    
    c4_vs_c5_results = []
    # Test windows on S1
    test_wins_s1 = [(1000, 100), (1500, 300), (2500, 600)]
    for ws, wl in test_wins_s1:
        s_data = session_data['S1']
        r_c4 = evaluate_window(cfg_base, s_data['sess'], ws, wl, nio_speeds=s_data['spd_nio_v2'])
        r_c5 = evaluate_window(cfg_base, s_data['sess'], ws, wl, nio_speeds=s_data['spd_nio_ft']) if nio_ft else None
        
        c4_vs_c5_results.append({
            'window': f"{wl*0.1:.0f}s",
            'start_idx': ws,
            'duration_s': wl * 0.1,
            'C4_nio_v2': r_c4,
            'C5_nio_ft': r_c5
        })
        print(f"Window {wl*0.1:.0f}s (start {ws}):")
        print(f"  C4 (NIO v2 + NHC):  Final Err = {r_c4['final_error_m']:6.2f}m | Drift = {r_c4['drift_pct']:6.2f}% | RMSE = {r_c4['rmse_m']:6.2f}m")
        if r_c5:
            print(f"  C5 (NIO FT + NHC):  Final Err = {r_c5['final_error_m']:6.2f}m | Drift = {r_c5['drift_pct']:6.2f}% | RMSE = {r_c5['rmse_m']:6.2f}m")

    # ── 2. FULL MULTI-WINDOW BENCHMARK ACROSS ALL 6 SESSIONS (Phase 7) ───────
    print("\n" + "=" * 75)
    print("PHASE 7: FULL MULTI-WINDOW BENCHMARK ACROSS S1, S2, S3a, S3b, S3c, S4")
    print("=" * 75)
    
    full_benchmark = {}
    chosen_spd_key = 'spd_nio_ft' if nio_ft is not None else 'spd_nio_v2'
    print(f"Using speed predictor: {chosen_spd_key}")

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
                spd_arr = s_data[chosen_spd_key]
                r = evaluate_window(cfg_base, s_data['sess'], ws, step_len, nio_speeds=spd_arr)
                records.append(r)
                
            summary = compute_summary_stats(records)
            sess_results[f"{dur_s}s"] = {
                'step_len': step_len,
                'windows_evaluated': len(records),
                'summary': summary,
                'windows': records
            }
            if summary:
                print(f"  {s_name:5s} | {dur_s:2d}s (N={len(records):2d}) | Mean Drift: {summary['drift_pct']['mean']:6.2f}% (P95: {summary['drift_pct']['p95']:6.2f}%) | Mean RMSE: {summary['rmse_m']['mean']:6.2f}m | FinalErr: {summary['final_error_m']['mean']:6.2f}m")
            else:
                print(f"  {s_name:5s} | {dur_s:2d}s | No valid windows (session too short: N={N_sess})")
                
        full_benchmark[s_name] = sess_results

    # ── 3. SCENARIO A EVALUATION (Phase 8) ───────────────────────────────────
    print("\n" + "=" * 75)
    print("PHASE 8: SIH SCENARIO A (3-5s, 40-60m, >=5 m/s) CROSS-SESSION SEARCH")
    print("=" * 75)
    
    scenario_a_all = {}
    for s_name in TEST_SESSIONS:
        s_data = session_data[s_name]
        enu_gt = s_data['sess']['enu_coords'][:, :2]
        cum_d = s_data['cum_dist']
        spd_ref = s_data['spd_ref']
        
        quals = find_qualifying_segments(enu_gt, cum_d, spd_ref, dt=0.1, t_min_s=3.0, t_max_s=5.0, d_min_m=40.0, d_max_m=60.0, min_speed_mps=5.0, max_segments=10)
        print(f"  Session {s_name:5s} -> Found {len(quals)} qualifying Scenario A segments")
        
        evals = []
        for q in quals:
            w_len = q['end_idx'] - q['start_idx']
            spd_arr = s_data[chosen_spd_key]
            r = evaluate_window(cfg_base, s_data['sess'], q['start_idx'], w_len, nio_speeds=spd_arr)
            r['criteria'] = q
            r['sih_pass_5m'] = bool(r['final_error_m'] <= 5.0)
            evals.append(r)
            print(f"    [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | Spd: {q['mean_speed_mps']}m/s | FinalErr: {r['final_error_m']:.3f}m | Pass(<=5m): {r['sih_pass_5m']}")
            
        scenario_a_all[s_name] = {
            'qualifying_count': len(quals),
            'evaluations': evals,
            'pass_count': sum(1 for e in evals if e['sih_pass_5m']),
            'pass_rate_pct': (sum(1 for e in evals if e['sih_pass_5m']) / max(len(evals), 1)) * 100.0 if evals else 0.0
        }

    # ── 4. SCENARIO B EVALUATION (Phase 9) ───────────────────────────────────
    print("\n" + "=" * 75)
    print("PHASE 9: SIH SCENARIO B (~1 km / ~60s) FULL EVALUATION")
    print("=" * 75)
    
    scenario_b_all = {}
    for s_name in ['S1', 'S2', 'S4']:
        s_data = session_data[s_name]
        enu_gt = s_data['sess']['enu_coords'][:, :2]
        cum_d = s_data['cum_dist']
        spd_ref = s_data['spd_ref']
        
        quals_b = find_qualifying_segments(enu_gt, cum_d, spd_ref, dt=0.1, t_min_s=55.0, t_max_s=65.0, d_min_m=850.0, d_max_m=1150.0, min_speed_mps=0.0, max_segments=20)
        print(f"  Session {s_name:5s} -> Found {len(quals_b)} qualifying Scenario B segments")
        
        evals_b = []
        for idx_b, q in enumerate(quals_b):
            w_len = q['end_idx'] - q['start_idx']
            spd_arr = s_data[chosen_spd_key]
            r = evaluate_window(cfg_base, s_data['sess'], q['start_idx'], w_len, nio_speeds=spd_arr)
            r['segment_id'] = f"{s_name}_seg{idx_b}"
            r['criteria'] = q
            r['sih_pass_100m'] = bool(r['final_error_m'] <= 100.0)
            evals_b.append(r)
            print(f"    Seg {idx_b:2d} [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | FinalErr: {r['final_error_m']:6.2f}m ({r['drift_pct']:5.2f}%) | RMSE: {r['rmse_m']:5.2f}m | Pass(<=100m): {r['sih_pass_100m']}")
            
        scenario_b_all[s_name] = {
            'qualifying_count': len(quals_b),
            'evaluations': evals_b,
            'pass_count': sum(1 for e in evals_b if e['sih_pass_100m']),
            'pass_rate_pct': (sum(1 for e in evals_b if e['sih_pass_100m']) / max(len(evals_b), 1)) * 100.0 if evals_b else 0.0
        }

    # ── 5. ABLATION / CAUSAL CHECK TABLE (Phase 11) ──────────────────────────
    print("\n" + "=" * 75)
    print("PHASE 11: ABLATION / CAUSAL CHECK TABLE")
    print("=" * 75)
    
    # Run 3 configs on S1 primary window (30s: 1500..1800):
    # 1. NIO v2 + KNet v2, no NHC
    # 2. NIO v2 + KNet v2 + NHC
    # 3. Fine-tuned NIO + KNet v2 + NHC
    ws_abl, wl_abl = 1500, 300
    s1_data = session_data['S1']
    
    cfg_no_nhc = {
        'knet_checkpoint_path': str(KNET_V2_PATH),
        'enable_nhc': False,
        'device': DEVICE
    }
    r_abl1 = evaluate_window(cfg_no_nhc, s1_data['sess'], ws_abl, wl_abl, nio_speeds=s1_data['spd_nio_v2'])
    r_abl2 = evaluate_window(cfg_base, s1_data['sess'], ws_abl, wl_abl, nio_speeds=s1_data['spd_nio_v2'])
    r_abl3 = evaluate_window(cfg_base, s1_data['sess'], ws_abl, wl_abl, nio_speeds=s1_data['spd_nio_ft']) if nio_ft else None
    
    ablation_table = [
        {'id': 1, 'name': 'NIO v2 + KNet v2 (No NHC)', 'res': r_abl1},
        {'id': 2, 'name': 'NIO v2 + KNet v2 (+ NHC)', 'res': r_abl2},
        {'id': 3, 'name': 'Fine-tuned NIO + KNet v2 (+ NHC)', 'res': r_abl3}
    ]
    
    for row in ablation_table:
        r = row['res']
        if r:
            print(f"  {row['id']}. {row['name']:35s} | FinalErr: {r['final_error_m']:6.2f}m | Drift: {r['drift_pct']:6.2f}% | RMSE: {r['rmse_m']:6.2f}m | Jump: {r['recovery_jump_m']:6.3f}m")

    # ── Save comprehensive results ──────────────────────────────────────────
    out_dir = PROJECT_ROOT / 'results' / 'phase_revalidation'
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / 'revalidation_results.json'
    
    save_data = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'device': DEVICE,
        'chosen_speed_predictor': chosen_spd_key,
        'phase6_c4_vs_c5': c4_vs_c5_results,
        'phase7_full_benchmark': full_benchmark,
        'phase8_scenario_a': scenario_a_all,
        'phase9_scenario_b': scenario_b_all,
        'phase11_ablation': ablation_table
    }
    
    with open(out_file, 'w') as f:
        json.dump(save_data, f, indent=2)
    print(f"\nSaved full revalidation results to: {out_file}")


if __name__ == '__main__':
    main()
