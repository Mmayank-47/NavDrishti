"""
scripts/verify_phase2_nhc.py
─────────────────────────────────────────────────────────────────────────────
Phase 2: Controlled A/B Verification of NHC Integration in FinalNavigationPipeline
Compares:
  Config A: Pipeline with enable_nhc = False
  Config B: Pipeline with enable_nhc = True

Using identical checkpoints, sessions, outage windows, initialization, and metrics.
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
KNET_V2_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_fixed_input' / 'kalmannet_best.pt'


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


def evaluate_window_nhc(pipeline_cls_args, sess, w_start, w_len, dt=0.1, nio_speeds=None):
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
    
    pipeline = FinalNavigationPipeline(**pipeline_cls_args)
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
    
    # Slice blackout window
    b_idx_start = w_start - seg_start
    b_idx_end = w_end - seg_start
    est_outage = est_enu[b_idx_start:b_idx_end]
    gt_outage = enu_seg[b_idx_start:b_idx_end]
    
    pos_errs = np.linalg.norm(est_outage - gt_outage, axis=1)
    final_err = float(pos_errs[-1])
    rmse = float(np.sqrt(np.mean(pos_errs**2)))
    max_err = float(np.max(pos_errs))
    drift_pct = float(final_err / max(dist_during_outage, 1e-3) * 100.0)
    
    # Recovery jump: error right at end of blackout vs error 5 steps after GNSS resumes
    recov_idx = min(len(est_enu) - 1, b_idx_end + 5)
    recov_pos_err = float(np.linalg.norm(est_enu[recov_idx] - enu_seg[recov_idx]))
    recovery_jump = float(abs(pos_errs[-1] - recov_pos_err))
    
    return {
        'distance_m': dist_during_outage,
        'final_err_m': final_err,
        'rmse_m': rmse,
        'max_err_m': max_err,
        'drift_pct': drift_pct,
        'recovery_jump_m': recovery_jump,
        'nhc_active_all': bool(all(nhc_active_list)) if nhc_active_list else False,
        'nhc_update_total': int(nhc_update_counts[-1]) if nhc_update_counts else 0,
        'nhc_inflated_total': int(nhc_inflated_counts[-1]) if nhc_inflated_counts else 0,
        'cornering_count': int(sum(1 for s in cornering_states if s == 'CORNERING'))
    }


def main():
    print("=" * 70)
    print("PHASE 2: VERIFY + INTEGRATE NHC (CONTROLLED A/B TEST)")
    print("=" * 70)
    print(f"Device: {DEVICE}")
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")

    loader = IOVNBDLoader()
    nio_model = load_nio_model(NIO_V2_PATH)
    assert nio_model is not None, f"Could not load NIO v2 from {NIO_V2_PATH}"

    test_windows = [
        ('S1', 3000, 300),  # Primary baseline window (30s)
        ('S1', 3000, 100),  # 10s
        ('S1', 3000, 600),  # 60s
        ('S2', 1500, 300),  # S2 30s
        ('S3b', 1519, 50),  # S3b Scenario A qualifying segment (5s)
    ]

    results = []

    for s_name, w_start, w_len in test_windows:
        print(f"\nEvaluating session {s_name}, window [{w_start}..{w_start+w_len}] ({w_len*0.1:.1f}s)...")
        sess = loader.load_session(s_name, preprocess_imu=True)
        
        # Precompute NIO v2 speeds
        aligner = PhoneVehicleAlignment()
        veh_spd = sess['vehicle']['speed_mps']
        if veh_spd is None:
            veh_spd = sess['gps']['speed_mps']
        if veh_spd is None:
            veh_spd = np.zeros(len(sess['accel_filtered']))
        R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
        acc_v = (R_p2v @ sess['accel_filtered'].T).T
        gyr_v = (R_p2v @ sess['gyro_filtered'].T).T
        nio_speeds = precompute_nio_speeds(nio_model, acc_v, gyr_v, len(acc_v))

        # Config A: Pipeline WITHOUT NHC
        cfg_a_args = {
            'knet_checkpoint_path': str(KNET_V2_PATH),
            'enable_nhc': False,
            'device': DEVICE
        }
        res_a = evaluate_window_nhc(cfg_a_args, sess, w_start, w_len, nio_speeds=nio_speeds)

        # Config B: Pipeline WITH NHC
        cfg_b_args = {
            'knet_checkpoint_path': str(KNET_V2_PATH),
            'enable_nhc': True,
            'sigma_nhc': 0.20,
            'yaw_rate_threshold': 0.25,
            'device': DEVICE
        }
        res_b = evaluate_window_nhc(cfg_b_args, sess, w_start, w_len, nio_speeds=nio_speeds)

        res_entry = {
            'session': s_name,
            'w_start': w_start,
            'w_len': w_len,
            'duration_s': w_len * 0.1,
            'config_A_no_nhc': res_a,
            'config_B_with_nhc': res_b,
            'drift_reduction_factor': res_a['drift_pct'] / max(res_b['drift_pct'], 1e-4),
            'rmse_reduction_pct': (res_a['rmse_m'] - res_b['rmse_m']) / max(res_a['rmse_m'], 1e-4) * 100.0
        }
        results.append(res_entry)

        print(f"  Config A (No NHC):   Final Err: {res_a['final_err_m']:.2f}m | Drift: {res_a['drift_pct']:.2f}% | RMSE: {res_a['rmse_m']:.2f}m")
        print(f"  Config B (With NHC): Final Err: {res_b['final_err_m']:.2f}m | Drift: {res_b['drift_pct']:.2f}% | RMSE: {res_b['rmse_m']:.2f}m")
        print(f"  Logging (Config B):  Active: {res_b['nhc_active_all']} | Updates: {res_b['nhc_update_total']} | Cornering: {res_b['cornering_count']}")
        print(f"  Improvement:         Drift reduced {res_entry['drift_reduction_factor']:.1f}x (RMSE -{res_entry['rmse_reduction_pct']:.1f}%)")

    # Save results
    out_dir = PROJECT_ROOT / 'results' / 'phase2_nhc'
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / 'phase2_ab_results.json'
    with open(out_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved Phase 2 results to {out_file}")


if __name__ == '__main__':
    main()
