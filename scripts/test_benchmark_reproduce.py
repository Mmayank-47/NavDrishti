import os, sys, json
from pathlib import Path
import numpy as np
import torch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.integration.final_navigation_pipeline import FinalNavigationPipeline
from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment

def run_outage_eval(knet_path, label):
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    print(f"\n--- Running evaluation with {label} ({knet_path}) on {device} ---")
    
    loader = IOVNBDLoader()
    sess = loader.load_session('S1', preprocess_imu=True)
    
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
    
    map_gnn_ckpt = str(PROJECT_ROOT / 'checkpoints' / 'map_gnn' / 'map_gnn_best.pt')
    graph_path = str(PROJECT_ROOT / 'data' / 'OSM' / 'road_graph_coventry.pkl')
    
    pipeline = FinalNavigationPipeline(
        knet_checkpoint_path=knet_path,
        map_gnn_checkpoint_path=map_gnn_ckpt,
        road_graph_path=graph_path,
        device=device
    )
    
    OUTAGE_WINDOWS = [
        {'name': '10s Outage', 'start': 1000, 'duration': 100},
        {'name': '30s Outage', 'start': 1500, 'duration': 300},
        {'name': '60s Outage', 'start': 2500, 'duration': 600}
    ]
    
    results = []
    dt = 0.1
    for win in OUTAGE_WINDOWS:
        w_start = win['start']
        w_len = win['duration']
        w_end = w_start + w_len
        
        seg_start = max(0, w_start - 100)
        seg_end = min(len(enu_gt), w_end + 100)
        seg_N = seg_end - seg_start
        
        enu_seg = enu_gt[seg_start:seg_end] - enu_gt[seg_start]
        dist_during_outage = float(np.sum(np.linalg.norm(np.diff(enu_gt[w_start:w_end], axis=0), axis=1)))
        
        diff_init = enu_gt[seg_start + 10] - enu_gt[seg_start]
        h0 = float(np.arctan2(diff_init[1], diff_init[0]))
        
        pipeline.initialize(
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
            
            st = pipeline.step(
                accel_raw=acc_filt[global_idx],
                gyro_raw=gyr_filt[global_idx],
                p_gnss_geodetic=p_gnss,
                hdop=1.0,
                is_blackout=is_outage,
                speed_ref=float(veh_spd[global_idx]),
                dt=dt
            )
            est_traj.append((st['east_m'], st['north_m']))
            
            if global_idx == w_end:
                rec_jump = float(np.linalg.norm(np.array(est_traj[-1]) - np.array(est_traj[-2])))
                
        est_traj = np.array(est_traj)
        outage_rel_end = w_end - seg_start - 1
        drift = float(np.linalg.norm(est_traj[outage_rel_end] - enu_seg[outage_rel_end]))
        drift_pct = (drift / dist_during_outage) * 100.0
        
        outage_slice = slice(w_start - seg_start, outage_rel_end + 1)
        rmse = float(np.sqrt(np.mean(np.linalg.norm(est_traj[outage_slice] - enu_seg[outage_slice], axis=1)**2)))
        
        res = {
            'window': win['name'],
            'start_idx': w_start,
            'end_idx': w_end,
            'distance_m': dist_during_outage,
            'drift_m': drift,
            'drift_pct': drift_pct,
            'rmse_m': rmse,
            'recovery_jump_m': rec_jump
        }
        print(f"  {win['name']:10s} | Dist: {dist_during_outage:6.1f}m | Drift: {drift:7.2f}m ({drift_pct:6.2f}%) | RMSE: {rmse:6.2f}m | RecJump: {rec_jump:6.3f}m")
        results.append(res)
    return results

def main():
    knet_v1 = str(PROJECT_ROOT / 'checkpoints' / 'kalmannet' / 'kalmannet_best.pt')
    knet_v2 = str(PROJECT_ROOT / 'checkpoints' / 'kalmannet_fixed_input' / 'kalmannet_best.pt')
    
    print("=== Testing Reproduction of v1 vs v2 Benchmark on S1 ===")
    res_v1 = run_outage_eval(knet_v1, "KalmanNet_v1")
    res_v2 = run_outage_eval(knet_v2, "KalmanNet_v2")

if __name__ == '__main__':
    main()
