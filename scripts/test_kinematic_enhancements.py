"""
scripts/test_kinematic_enhancements.py
Prototype test for:
1. Online Gyro Yaw Bias Estimation & Subtraction
2. Real-Time ZUPT Detection & Zero-Velocity Clamping
3. Forward Accelerometer Bias Compensation
4. Adaptive Cornering-Aware NHC
Evaluated on Session S1 window [1500..1800] (30s blackout) and compared against C6 baseline.
"""

import sys
from pathlib import Path
import numpy as np
import torch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment
from src.models.kalmannet import KalmanNetNN
from src.models.inertial_odometry import NeuralInertialOdometry

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
NIO_FT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned' / 'nio_vel_best.pt'
KNET_V3_PATH = PROJECT_ROOT / 'checkpoints' / 'kalmannet_v3' / 'kalmannet_best.pt'

def main():
    loader = IOVNBDLoader()
    sess = loader.load_session('S1', preprocess_imu=True)
    
    aligner = PhoneVehicleAlignment()
    veh_spd = sess['vehicle']['speed_mps']
    if veh_spd is None: veh_spd = sess['gps']['speed_mps']
    if veh_spd is None: veh_spd = np.zeros(len(sess['accel_raw']))
    R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
    
    acc_v = (R_p2v @ sess['accel_filtered'].T).T
    gyr_v = (R_p2v @ sess['gyro_filtered'].T).T
    
    # Load NIO model
    ckpt_nio = torch.load(NIO_FT_PATH, map_location=DEVICE, weights_only=False)
    cfg_nio = ckpt_nio.get('config', {})
    nio_model = NeuralInertialOdometry(
        input_dim=6,
        tcn_channels=cfg_nio.get('tcn_channels', [64, 128, 256]),
        kernel_size=cfg_nio.get('tcn_kernel_size', 3),
        dropout=0.0
    ).to(DEVICE)
    nio_model.load_state_dict(ckpt_nio['model_state_dict'])
    nio_model.eval()
    
    # Precompute NIO speeds
    imu_6d = np.hstack([acc_v, gyr_v]).astype(np.float32)
    N = len(acc_v)
    nio_speeds = np.zeros(N, dtype=np.float32)
    win_size = 100
    batch_w, batch_idx = [], []
    with torch.no_grad():
        for i in range(N):
            if i < win_size:
                pad = np.repeat(imu_6d[0:1], win_size - (i + 1), axis=0)
                w = np.vstack([pad, imu_6d[:i+1]])
            else:
                w = imu_6d[i - win_size + 1 : i + 1]
            batch_w.append(w)
            batch_idx.append(i)
            if len(batch_w) >= 256 or i == N - 1:
                bw_t = torch.tensor(np.array(batch_w), dtype=torch.float32, device=DEVICE)
                _, p_v, _ = nio_model(bw_t)
                p_v_np = p_v[:, 0].detach().cpu().numpy()
                for b_i, t_i in enumerate(batch_idx):
                    nio_speeds[t_i] = max(0.0, float(p_v_np[b_i]))
                batch_w, batch_idx = [], []
                
    # Evaluate S1 master window [1500..1800]
    w_start, w_len = 1500, 300
    w_end = w_start + w_len
    seg_start = max(0, w_start - 100)
    seg_end = min(N, w_end + 100)
    
    enu_gt = sess['enu_coords'][:, :2]
    enu_seg = enu_gt[seg_start:seg_end] - enu_gt[seg_start]
    dist_during_outage = float(np.sum(np.linalg.norm(np.diff(enu_gt[w_start:w_end], axis=0), axis=1)))
    
    dt = 0.1
    # Estimate pre-outage stationary bias
    pre_zupt = sess['zupt_mask'][:w_start]
    if np.sum(pre_zupt) > 10:
        gyro_bias_est = float(np.mean(gyr_v[:w_start][pre_zupt, 2]))
        acc_bias_est = float(np.mean(acc_v[:w_start][pre_zupt, 0]))
    else:
        gyro_bias_est = 0.0
        acc_bias_est = 0.0
    print(f"Pre-outage Calibrated Yaw Gyro Bias: {gyro_bias_est:+.5f} rad/s ({np.degrees(gyro_bias_est):+.3f} deg/s)")
    print(f"Pre-outage Calibrated Accel Fwd Bias: {acc_bias_est:+.5f} m/s^2")
    
    # Load KalmanNet v3
    ckpt_knet = torch.load(KNET_V3_PATH, map_location=DEVICE, weights_only=False)
    knet = KalmanNetNN(state_dim=4, meas_dim=2, hidden_dim=64, num_layers=2).to(DEVICE)
    knet.load_state_dict(ckpt_knet['model_state_dict'])
    knet.eval()
    
    # Compare 3 variants on window [1500..1800]:
    # 1. C6 Baseline (as-is: no gyro bias removal, no ZUPT during blackout)
    # 2. C6 + Gyro Bias Removal
    # 3. C6 + Gyro Bias Removal + Online ZUPT
    for mode in ['C6_baseline', 'C6_gyro_bias', 'C6_gyro_bias_zupt']:
        # Initial heading
        diff_init = enu_gt[seg_start + 10] - enu_gt[seg_start]
        h_rad = float(np.arctan2(diff_init[1], diff_init[0]))
        pos_enu = np.array([0.0, 0.0])
        vel_enu = np.array([float(veh_spd[seg_start]) * np.cos(h_rad), float(veh_spd[seg_start]) * np.sin(h_rad)])
        P_full = np.diag([2.5**2, 2.5**2, 0.5**2, 0.5**2])
        
        x_prev_knet = torch.tensor([0.0, 0.0, vel_enu[0], vel_enu[1]], dtype=torch.float32, device=DEVICE).unsqueeze(0)
        z_prev_knet = torch.tensor([vel_enu[0], vel_enu[1]], dtype=torch.float32, device=DEVICE).unsqueeze(0)
        h_knet = None
        
        est_enu = []
        
        for i_global in range(seg_start, seg_end):
            is_blk = (w_start <= i_global < w_end)
            
            # Yaw rate with or without bias compensation
            omega_z = gyr_v[i_global, 2]
            if mode in ['C6_gyro_bias', 'C6_gyro_bias_zupt']:
                omega_z -= gyro_bias_est
                
            h_rad = (h_rad + omega_z * dt + np.pi) % (2.0 * np.pi) - np.pi
            c_h, s_h = np.cos(h_rad), np.sin(h_rad)
            
            # Accel
            a_fwd = acc_v[i_global, 0]
            if mode in ['C6_gyro_bias', 'C6_gyro_bias_zupt']:
                a_fwd -= acc_bias_est
            a_lat = acc_v[i_global, 1]
            a_east = a_fwd * c_h - a_lat * s_h
            a_north = a_fwd * s_h + a_lat * c_h
            a_nav = np.array([a_east, a_north])
            
            F_m = np.array([[1.0, 0.0, dt, 0.0], [0.0, 1.0, 0.0, dt], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]])
            B_m = np.array([[0.5*dt**2, 0.0], [0.0, 0.5*dt**2], [dt, 0.0], [0.0, dt]])
            Q_m = np.diag([0.05, 0.05, 0.2, 0.2])
            
            x_prior = F_m @ np.array([pos_enu[0], pos_enu[1], vel_enu[0], vel_enu[1]]) + B_m @ a_nav
            P_prior = F_m @ P_full @ F_m.T + Q_m
            
            if not is_blk:
                # GNSS active: update to GT position for calibration phase
                pos_enu = enu_seg[i_global - seg_start]
                # Update velocity
                vel_enu = x_prior[2:4]
                x_post = np.array([pos_enu[0], pos_enu[1], vel_enu[0], vel_enu[1]])
                P_post = np.diag([2.5**2, 2.5**2, 0.5**2, 0.5**2])
            else:
                x_post = x_prior.copy()
                P_post = P_prior.copy()
                
                # Check ZUPT
                is_stationary = False
                if mode == 'C6_gyro_bias_zupt':
                    # Detect stationary
                    acc_mag = np.linalg.norm(acc_v[i_global])
                    gyr_mag = np.linalg.norm(gyr_v[i_global])
                    if abs(acc_mag - 9.806) < 0.4 and gyr_mag < 0.05:
                        is_stationary = True
                        
                if is_stationary:
                    x_post[2] = 0.0
                    x_post[3] = 0.0
                else:
                    # KalmanNet step with NIO speed
                    v_forward = float(nio_speeds[i_global])
                    z_odo = np.array([v_forward * c_h, v_forward * s_h], dtype=np.float32)
                    H_vel_t = torch.tensor([[0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]], dtype=torch.float32, device=DEVICE)
                    with torch.no_grad():
                        z_odo_t = torch.tensor(z_odo, dtype=torch.float32, device=DEVICE).unsqueeze(0)
                        x_prior_t = torch.tensor(x_post, dtype=torch.float32, device=DEVICE).unsqueeze(0)
                        x_knet_post, _, h_knet = knet.step(
                            x_prior=x_prior_t,
                            z_meas=z_odo_t,
                            H_matrix=H_vel_t,
                            x_prev=x_prev_knet,
                            z_prev=z_prev_knet,
                            h_prev=h_knet
                        )
                        x_post = x_knet_post[0].cpu().numpy()
                        x_prev_knet = x_knet_post
                        z_prev_knet = z_odo_t
                        
                # NHC update
                v_east, v_north = x_post[2], x_post[3]
                v_lat = -s_h * v_east + c_h * v_north
                yaw_rate = abs(float(omega_z))
                cov_scale = 1.0
                if yaw_rate > 0.25:
                    excess = (yaw_rate - 0.25) / 0.25
                    cov_scale = min(1.0 + (excess ** 2) * 5.0, 50.0)
                R_nhc = float((0.20 * cov_scale) ** 2)
                H_nhc = np.array([0.0, 0.0, -s_h, c_h], dtype=np.float64)
                y_innov = 0.0 - v_lat
                S_nhc = float(H_nhc @ P_post @ H_nhc.T + R_nhc)
                K_nhc = (P_post @ H_nhc.T) / S_nhc
                x_post = x_post + K_nhc * y_innov
                P_post = (np.eye(4) - np.outer(K_nhc, H_nhc)) @ P_post
                
                pos_enu = x_post[0:2]
                vel_enu = x_post[2:4]
                P_full = P_post
                
            est_enu.append([pos_enu[0], pos_enu[1]])
            
        est_enu = np.array(est_enu)
        b_s = w_start - seg_start
        b_e = w_end - seg_start
        pos_errs = np.linalg.norm(est_enu[b_s:b_e] - enu_seg[b_s:b_e], axis=1)
        final_err = float(pos_errs[-1])
        rmse = float(np.sqrt(np.mean(pos_errs**2)))
        drift_pct = float(final_err / max(dist_during_outage, 1e-3) * 100.0)
        print(f"Mode {mode:20s}: Final Error = {final_err:7.2f} m | Drift = {drift_pct:6.2f}% | RMSE = {rmse:6.2f} m")

if __name__ == '__main__':
    main()
