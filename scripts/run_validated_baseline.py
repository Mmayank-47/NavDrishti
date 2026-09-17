"""
scripts/run_validated_baseline.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Comprehensive Validated Baseline Execution Suite
Executes on Lightning AI GPU environment.
─────────────────────────────────────────────────────────────────────────────
"""

import os, sys, json, time
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
NIO_V1_PATH = PROJECT_ROOT / 'checkpoints' / 'inertial_odometry' / 'inertial_odometry_best.pt'
NIO_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_fixed' / 'nio_fixed_best.pt'
KNET_V1_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet' / 'kalmannet_best.pt'
KNET_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_fixed_input' / 'kalmannet_best.pt'
MAP_GNN_PATH = PROJECT_ROOT / 'checkpoints' / 'map_gnn' / 'map_gnn_best.pt'
GRAPH_PATH = PROJECT_ROOT / 'data' / 'OSM' / 'road_graph_coventry.pkl'


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


class PipelineWithNHC:
    def __init__(self, base_pipeline, enable_nhc=True, sigma_nhc=0.20, yaw_rate_threshold=0.25):
        self.p = base_pipeline
        self.enable_nhc = enable_nhc
        self.sigma_nhc = sigma_nhc
        self.yaw_thresh = yaw_rate_threshold

    def initialize(self, **kwargs):
        self.p.initialize(**kwargs)

    def step(self, accel_raw, gyro_raw, p_gnss_geodetic=None, hdop=1.0, is_blackout=False, speed_ref=None, dt=0.1):
        st = self.p.step(
            accel_raw=accel_raw,
            gyro_raw=gyro_raw,
            p_gnss_geodetic=p_gnss_geodetic,
            hdop=hdop,
            is_blackout=is_blackout,
            speed_ref=speed_ref,
            dt=dt
        )
        
        if self.enable_nhc and is_blackout:
            theta = self.p.heading_rad
            c_h, s_h = np.cos(theta), np.sin(theta)
            
            v_east, v_north = self.p.vel_enu[0], self.p.vel_enu[1]
            v_lat = -s_h * v_east + c_h * v_north
            
            gyr_v = self.p.R_p2v @ np.asarray(gyro_raw[:3], dtype=np.float64)
            yaw_rate = abs(gyr_v[2])
            cov_scale = 1.0
            if yaw_rate > self.yaw_thresh:
                cov_scale = min(1.0 + ((yaw_rate - self.yaw_thresh) / self.yaw_thresh)**2 * 5.0, 50.0)
            
            R_nhc = (self.sigma_nhc * cov_scale)**2
            H_nhc = np.array([0.0, 0.0, -s_h, c_h])
            P = self.p.P_full
            
            S = float(H_nhc @ P @ H_nhc.T + R_nhc)
            K = (P @ H_nhc.T) / S
            y_innov = 0.0 - v_lat
            
            x_upd = np.array([self.p.pos_enu[0], self.p.pos_enu[1], self.p.vel_enu[0], self.p.vel_enu[1]]) + K * y_innov
            P_upd = (np.eye(4) - np.outer(K, H_nhc)) @ P
            
            self.p.pos_enu = x_upd[0:2]
            self.p.vel_enu = x_upd[2:4]
            self.p.P_full = P_upd
            self.p.pos_cov = P_upd[0:2, 0:2]
            
            st['east_m'] = float(self.p.pos_enu[0])
            st['north_m'] = float(self.p.pos_enu[1])
            st['vel_east_mps'] = float(self.p.vel_enu[0])
            st['vel_north_mps'] = float(self.p.vel_enu[1])
            
        return st


def evaluate_window(pipeline_obj, sess, w_start, w_len, dt=0.1, speed_source='veh_spd', nio_speeds=None):
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
    seg_N = seg_end - seg_start
    
    enu_seg = enu_gt[seg_start:seg_end] - enu_gt[seg_start]
    dist_during_outage = float(np.sum(np.linalg.norm(np.diff(enu_gt[w_start:w_end], axis=0), axis=1)))
    
    diff_init = enu_gt[seg_start + 10] - enu_gt[seg_start]
    h0 = float(np.arctan2(diff_init[1], diff_init[0]))
    
    pipeline_obj.initialize(
        lat0=lat_gps[seg_start],
        lon0=lon_gps[seg_start],
        alt0=sess['gps']['alt0'],
        initial_heading=h0,
        initial_speed=float(veh_spd[seg_start]),
        R_p2v=R_p2v
    )
    
    est_traj = []
    rec_jump = 0.0
    
    for i in range(seg_N):
        global_idx = seg_start + i
        is_outage = (w_start <= global_idx < w_end)
        p_gnss = (lat_gps[global_idx], lon_gps[global_idx]) if not is_outage else None
        
        if speed_source == 'nio' and nio_speeds is not None:
            spd_val = float(nio_speeds[global_idx])
        elif speed_source == 'none':
            spd_val = None
        else:
            spd_val = float(veh_spd[global_idx])
            
        st = pipeline_obj.step(
            accel_raw=acc_filt[global_idx],
            gyro_raw=gyr_filt[global_idx],
            p_gnss_geodetic=p_gnss,
            hdop=1.0,
            is_blackout=is_outage,
            speed_ref=spd_val,
            dt=dt
        )
        est_traj.append((st['east_m'], st['north_m']))
        
        if global_idx == w_end:
            rec_jump = float(np.linalg.norm(np.array(est_traj[-1]) - np.array(est_traj[-2])))
            
    est_traj = np.array(est_traj)
    outage_rel_end = w_end - seg_start - 1
    
    pos_errs = np.linalg.norm(est_traj - enu_seg, axis=1)
    final_error = float(pos_errs[outage_rel_end])
    drift_pct = (final_error / dist_during_outage * 100.0) if dist_during_outage > 0 else 0.0
    
    outage_slice = slice(w_start - seg_start, outage_rel_end + 1)
    outage_errs = pos_errs[outage_slice]
    rmse = float(np.sqrt(np.mean(outage_errs**2)))
    max_err = float(np.max(outage_errs))
    
    return {
        'start_idx': int(w_start),
        'end_idx': int(w_end),
        'start_time_s': round(w_start * dt, 2),
        'end_time_s': round(w_end * dt, 2),
        'duration_s': round(w_len * dt, 2),
        'distance_m': round(dist_during_outage, 2),
        'ground_truth_distance_m': round(dist_during_outage, 2),
        'final_error_m': round(final_error, 3),
        'rmse_m': round(rmse, 3),
        'max_error_m': round(max_err, 3),
        'drift_pct': round(drift_pct, 2),
        'recovery_jump_m': round(rec_jump, 3),
        'sih_pass': bool(drift_pct < 10.0)
    }


def find_qualifying_segments_exact(enu_gt, cum_dist, speed_arr, dt=0.1,
                                   t_min_s=55.0, t_max_s=65.0,
                                   d_min_m=900.0, d_max_m=1100.0,
                                   min_mean_speed_mps=0.0, max_segments=100):
    """Exact logic from 19b_sih_scenarios.ipynb."""
    n_min = int(t_min_s / dt)
    n_max = int(t_max_s / dt)
    qualifying = []
    
    i = 0
    while i < len(enu_gt) - n_max:
        found = False
        for win in range(n_min, n_max + 1):
            j = i + win
            if j >= len(enu_gt):
                break
            seg_dist = cum_dist[j] - cum_dist[i]
            seg_t = win * dt
            if d_min_m <= seg_dist <= d_max_m:
                mean_spd = float(np.mean(speed_arr[i:j]))
                if mean_spd >= min_mean_speed_mps:
                    qualifying.append({
                        'start_idx': i,
                        'end_idx': j,
                        'duration_s': round(seg_t, 1),
                        'distance_m': round(float(seg_dist), 2),
                        'mean_speed_mps': round(mean_spd, 2),
                        'start_t_s': round(i * dt, 1),
                        'end_t_s': round(j * dt, 1),
                    })
                    i = j
                    found = True
                    break
        if not found:
            i += 1
        if len(qualifying) >= max_segments:
            break
            
    return qualifying


def main():
    print("=" * 80)
    print("  SIH PS 26168 — VALIDATED BASELINE EXECUTION ON LIGHTNING AI")
    print("  Device:", DEVICE)
    print("=" * 80)
    
    loader = IOVNBDLoader()
    output_dir = PROJECT_ROOT / 'results' / 'validated_baseline'
    output_dir.mkdir(parents=True, exist_ok=True)
    
    nio_v1 = load_nio_model(NIO_V1_PATH)
    nio_v2 = load_nio_model(NIO_V2_PATH)
    print(f"NIO v1 loaded: {nio_v1 is not None} | NIO v2 loaded: {nio_v2 is not None}")
    
    # Load S1
    sess_s1 = loader.load_session('S1', preprocess_imu=True)
    N_s1 = len(sess_s1['enu_coords'])
    acc_v_s1 = sess_s1['accel_filtered']
    gyr_v_s1 = sess_s1['gyro_filtered']
    
    print("Precomputing NIO speeds on S1...")
    nio_v1_spd_s1 = precompute_nio_speeds(nio_v1, acc_v_s1, gyr_v_s1, N_s1)
    nio_v2_spd_s1 = precompute_nio_speeds(nio_v2, acc_v_s1, gyr_v_s1, N_s1)
    
    # ── 1. 2×2 CHECKPOINT GRID ──────────────────────────────────────────────
    print("\n" + "=" * 80)
    print("  1. 2×2 CHECKPOINT GRID (S1)")
    print("=" * 80)
    
    grid_cfgs = [
        ('C1', 'NIO v1 + KalmanNet v1', nio_v1_spd_s1, str(KNET_V1_PATH)),
        ('C2', 'NIO v2 + KalmanNet v1', nio_v2_spd_s1, str(KNET_V1_PATH)),
        ('C3', 'NIO v1 + KalmanNet v2', nio_v1_spd_s1, str(KNET_V2_PATH)),
        ('C4', 'NIO v2 + KalmanNet v2', nio_v2_spd_s1, str(KNET_V2_PATH)),
    ]
    
    BENCH_WINS = [
        {'name': '10s', 'start': 1000, 'duration': 100},
        {'name': '30s', 'start': 1500, 'duration': 300},
        {'name': '60s', 'start': 2500, 'duration': 600}
    ]
    
    grid_results_nio = {}
    grid_results_ref = {}
    
    for cid, cname, spd_arr, knet_p in grid_cfgs:
        print(f"\n--- Running {cid}: {cname} ---")
        
        # A) With NIO-predicted speeds
        p_nio = FinalNavigationPipeline(knet_checkpoint_path=knet_p, map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
        grid_results_nio[cid] = {'config': cname, 'windows': {}}
        for win in BENCH_WINS:
            r = evaluate_window(p_nio, sess_s1, win['start'], win['duration'], speed_source='nio', nio_speeds=spd_arr)
            grid_results_nio[cid]['windows'][win['name']] = r
            print(f"  [NIO] {win['name']:4s} | Dist: {r['distance_m']:6.1f}m | Drift: {r['final_error_m']:7.2f}m ({r['drift_pct']:6.2f}%) | RMSE: {r['rmse_m']:6.2f}m | RecJump: {r['recovery_jump_m']:6.3f}m")
            
        # B) With reference speed (veh_spd) to test KNet in isolation
        p_ref = FinalNavigationPipeline(knet_checkpoint_path=knet_p, map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
        grid_results_ref[cid] = {'config': cname, 'windows': {}}
        for win in BENCH_WINS:
            r = evaluate_window(p_ref, sess_s1, win['start'], win['duration'], speed_source='veh_spd')
            grid_results_ref[cid]['windows'][win['name']] = r
            print(f"  [REF] {win['name']:4s} | Dist: {r['distance_m']:6.1f}m | Drift: {r['final_error_m']:7.2f}m ({r['drift_pct']:6.2f}%) | RMSE: {r['rmse_m']:6.2f}m | RecJump: {r['recovery_jump_m']:6.3f}m")
            
    # ── 2. MULTI-WINDOW STATISTICAL EVALUATION ON S1 ─────────────────────────
    print("\n" + "=" * 80)
    print("  2. MULTI-WINDOW STATISTICAL EVALUATION (S1)")
    print("=" * 80)
    
    multi_win_res = {}
    p_multi = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
    
    for dur_s, step_len in [(10, 100), (30, 300), (60, 600)]:
        stride = step_len + 100
        starts = list(range(200, N_s1 - step_len - 100, stride))
        if len(starts) > 20:
            starts = starts[:20]
            
        records = []
        for ws in starts:
            r = evaluate_window(p_multi, sess_s1, ws, step_len, speed_source='veh_spd')
            records.append(r)
            
        drifts = np.array([r['drift_pct'] for r in records])
        rmses = np.array([r['rmse_m'] for r in records])
        final_errs = np.array([r['final_error_m'] for r in records])
        jumps = np.array([r['recovery_jump_m'] for r in records])
        
        multi_win_res[f"{dur_s}s"] = {
            'num_windows': len(records),
            'drift_pct': {
                'mean': round(float(np.mean(drifts)), 2),
                'median': round(float(np.median(drifts)), 2),
                'std': round(float(np.std(drifts)), 2),
                'min': round(float(np.min(drifts)), 2),
                'max': round(float(np.max(drifts)), 2),
                'p95': round(float(np.percentile(drifts, 95)), 2)
            },
            'final_error_m': {
                'mean': round(float(np.mean(final_errs)), 2),
                'median': round(float(np.median(final_errs)), 2),
                'std': round(float(np.std(final_errs)), 2),
                'min': round(float(np.min(final_errs)), 2),
                'max': round(float(np.max(final_errs)), 2),
                'p95': round(float(np.percentile(final_errs, 95)), 2)
            },
            'rmse_m': {
                'mean': round(float(np.mean(rmses)), 2),
                'median': round(float(np.median(rmses)), 2),
                'std': round(float(np.std(rmses)), 2),
                'min': round(float(np.min(rmses)), 2),
                'max': round(float(np.max(rmses)), 2),
                'p95': round(float(np.percentile(rmses, 95)), 2)
            },
            'recovery_jump_m': {
                'mean': round(float(np.mean(jumps)), 3),
                'median': round(float(np.median(jumps)), 3),
                'p95': round(float(np.percentile(jumps, 95)), 3)
            },
            'windows': records
        }
        dp = multi_win_res[f"{dur_s}s"]['drift_pct']
        print(f"  {dur_s}s ({len(records)} windows) -> Drift%: Mean={dp['mean']}% | Median={dp['median']}% | Std={dp['std']}% | Min={dp['min']}% | Max={dp['max']}% | P95={dp['p95']}%")

    # ── 3. ALL TEST SESSIONS (S1, S2, S3a, S3b, S3c, S4) ────────────────────
    print("\n" + "=" * 80)
    print("  3. ALL TEST SESSIONS BASELINE (Driver A)")
    print("=" * 80)
    
    test_sessions = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']
    all_sess_res = {}
    
    for s_name in test_sessions:
        sess_i = loader.load_session(s_name, preprocess_imu=True)
        N_i = len(sess_i['enu_coords'])
        p_sess = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
        
        s_eval = {}
        for dur_s, step_len in [(10, 100), (30, 300), (60, 600)]:
            mid_start = max(100, (N_i // 2) - (step_len // 2))
            if mid_start + step_len + 100 < N_i:
                r = evaluate_window(p_sess, sess_i, mid_start, step_len, speed_source='veh_spd')
                s_eval[f"{dur_s}s"] = r
                print(f"  {s_name:5s} | {dur_s}s | Dist: {r['distance_m']:6.1f}m | Drift: {r['final_error_m']:7.2f}m ({r['drift_pct']:6.2f}%) | RMSE: {r['rmse_m']:6.2f}m | RecJump: {r['recovery_jump_m']:6.3f}m")
            else:
                s_eval[f"{dur_s}s"] = {'status': 'NOT_TESTABLE', 'reason': 'Session duration too short'}
                print(f"  {s_name:5s} | {dur_s}s | NOT TESTABLE")
        all_sess_res[s_name] = s_eval

    # ── 4. SCENARIO A CROSS-SESSION SEARCH ─────────────────────────────────
    print("\n" + "=" * 80)
    print("  4. SCENARIO A CROSS-SESSION SEARCH (3–5s, 40–60m, ≥5 m/s)")
    print("=" * 80)
    
    scen_a_res = {}
    
    for s_name in test_sessions:
        sess_i = loader.load_session(s_name, preprocess_imu=True)
        enu_i = sess_i['enu_coords'][:, :2]
        cum_d_i = np.insert(np.cumsum(np.linalg.norm(np.diff(enu_i, axis=0), axis=1)), 0, 0.0)
        v_spd_i = sess_i['vehicle']['speed_mps']
        if v_spd_i is None:
            v_spd_i = sess_i['gps']['speed_mps']
        if v_spd_i is None:
            v_spd_i = np.zeros(len(enu_i))
            
        quals = find_qualifying_segments_exact(
            enu_i, cum_d_i, v_spd_i, dt=0.1,
            t_min_s=3.0, t_max_s=5.0,
            d_min_m=40.0, d_max_m=60.0,
            min_mean_speed_mps=5.0, max_segments=20
        )
        print(f"  {s_name:5s} -> Found {len(quals)} qualifying segments")
        
        if quals:
            p_a = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
            evals = []
            for q in quals[:5]:
                w_len = q['end_idx'] - q['start_idx']
                r = evaluate_window(p_a, sess_i, q['start_idx'], w_len, speed_source='veh_spd')
                r['criteria'] = q
                r['sih_pass_5m'] = bool(r['final_error_m'] <= 5.0)
                evals.append(r)
                print(f"    [{q['start_idx']}..{q['end_idx']}] Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | Spd: {q['mean_speed_mps']}m/s | FinalErr: {r['final_error_m']:.3f}m | Pass(≤5m): {r['sih_pass_5m']}")
            scen_a_res[s_name] = {'status': 'TESTED', 'segments_found': len(quals), 'evaluations': evals}
        else:
            scen_a_res[s_name] = {'status': 'NOT_TESTABLE_ON_AVAILABLE_DATA', 'segments_found': 0, 'reason': f"No contiguous 3-5s segment in {s_name} with 40-60m distance at >=5 m/s"}

    # ── 5. SCENARIO B FULL EVALUATION ──────────────────────────────────────
    print("\n" + "=" * 80)
    print("  5. SCENARIO B FULL EVALUATION (~1km / 60s)")
    print("=" * 80)
    
    enu_s1 = sess_s1['enu_coords'][:, :2]
    cum_d_s1 = np.insert(np.cumsum(np.linalg.norm(np.diff(enu_s1, axis=0), axis=1)), 0, 0.0)
    spd_s1 = sess_s1['vehicle']['speed_mps']
    if spd_s1 is None:
        spd_s1 = sess_s1['gps']['speed_mps']
    if spd_s1 is None:
        spd_s1 = np.zeros(len(enu_s1))
        
    quals_b = find_qualifying_segments_exact(
        enu_s1, cum_d_s1, spd_s1, dt=0.1,
        t_min_s=55.0, t_max_s=65.0,
        d_min_m=900.0, d_max_m=1100.0,
        min_mean_speed_mps=0.0, max_segments=50
    )
    print(f"  Qualifying Scenario B segments found in S1: {len(quals_b)}")
    
    p_b = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
    evals_b = []
    
    for idx_b, q in enumerate(quals_b):
        w_len = q['end_idx'] - q['start_idx']
        r = evaluate_window(p_b, sess_s1, q['start_idx'], w_len, speed_source='veh_spd')
        r['segment_id'] = f"ScenarioB_seg{idx_b}"
        r['criteria'] = q
        r['sih_pass_100m'] = bool(r['final_error_m'] <= 100.0)
        evals_b.append(r)
        print(f"    Seg {idx_b:2d} [{q['start_idx']}..{q['end_idx']}] | Dur: {q['duration_s']}s | Dist: {q['distance_m']}m | FinalErr: {r['final_error_m']:7.2f}m ({r['drift_pct']:6.2f}%) | RMSE: {r['rmse_m']:6.2f}m | Pass(≤100m): {r['sih_pass_100m']}")
        
    scen_b_res = {
        'segments_found': len(quals_b),
        'segments_evaluated': len(evals_b),
        'evaluations': evals_b,
        'worst_segment': max(evals_b, key=lambda x: x['final_error_m']) if evals_b else None,
        'best_segment': min(evals_b, key=lambda x: x['final_error_m']) if evals_b else None,
    }

    # ── 6. NHC CONTROLLED A/B COMPARISON ───────────────────────────────────
    print("\n" + "=" * 80)
    print("  6. NHC CONTROLLED A/B COMPARISON (S1)")
    print("=" * 80)
    
    p_base_nhc = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
    pipe_no_nhc = PipelineWithNHC(p_base_nhc, enable_nhc=False)
    
    p_with_nhc = FinalNavigationPipeline(knet_checkpoint_path=str(KNET_V2_PATH), map_gnn_checkpoint_path=str(MAP_GNN_PATH), road_graph_path=str(GRAPH_PATH), device=DEVICE)
    pipe_has_nhc = PipelineWithNHC(p_with_nhc, enable_nhc=True, sigma_nhc=0.20, yaw_rate_threshold=0.25)
    
    nhc_comp = {}
    for win in BENCH_WINS:
        r_no = evaluate_window(pipe_no_nhc, sess_s1, win['start'], win['duration'], speed_source='veh_spd')
        r_yes = evaluate_window(pipe_has_nhc, sess_s1, win['start'], win['duration'], speed_source='veh_spd')
        
        diff_drift = r_yes['final_error_m'] - r_no['final_error_m']
        diff_pct = r_yes['drift_pct'] - r_no['drift_pct']
        diff_rmse = r_yes['rmse_m'] - r_no['rmse_m']
        
        nhc_comp[win['name']] = {
            'without_nhc': r_no,
            'with_nhc': r_yes,
            'delta_final_error_m': round(diff_drift, 3),
            'delta_drift_pct': round(diff_pct, 2),
            'delta_rmse_m': round(diff_rmse, 3)
        }
        print(f"  {win['name']:4s} | Baseline: {r_no['final_error_m']:7.2f}m ({r_no['drift_pct']:6.2f}%) | With NHC: {r_yes['final_error_m']:7.2f}m ({r_yes['drift_pct']:6.2f}%) | Delta: {diff_drift:+7.2f}m ({diff_pct:+6.2f}%) | RMSE Delta: {diff_rmse:+6.2f}m")

    # ── WRITE OUTPUT JSON ──────────────────────────────────────────────────
    out_dict = {
        'metadata': {
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'device': DEVICE,
            'gpu_hardware': torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU',
            'session': 'S1 (and S2, S3a, S3b, S3c, S4)',
            'driver': 'Driver A (held-out test)'
        },
        'grid_2x2_nio_speeds': grid_results_nio,
        'grid_2x2_ref_speeds': grid_results_ref,
        'multi_window_s1': multi_win_res,
        'all_test_sessions': all_sess_res,
        'scenario_a': scen_a_res,
        'scenario_b': scen_b_res,
        'nhc_ab_comparison': nhc_comp
    }
    
    out_p = output_dir / 'validated_baseline_results.json'
    with open(out_p, 'w') as f:
        json.dump(out_dict, f, indent=2)
    print(f"\n>>> SAVED VALIDATED BASELINE TO: {out_p}")
    print("=" * 80)

if __name__ == '__main__':
    main()
