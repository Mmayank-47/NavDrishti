"""
src/datasets/kalmannet_dataset.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Memory-Optimized Sequence Dataset for KalmanNet Adaptive Filtering.
Adheres to Section 19 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

import gc
import numpy as np
import torch
from torch.utils.data import Dataset
from pathlib import Path
from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment


class KalmanNetDataset(Dataset):
    """
    Trajectory sequence dataset for KalmanNet training and evaluation.
    Provides sequences of:
      1. Navigation frame accelerations a_nav [a_east, a_north]
      2. Neural Odometry velocity measurements z_meas [v_east, v_north]
      3. Ground truth navigation state [p_east, p_north, v_east, v_north]
    """

    def __init__(
        self,
        split="train",
        seq_len=50,         # 5.0 seconds @ 10 Hz
        stride=25,          # 2.5 seconds step (50% overlap)
        dt=0.1,             # 10 Hz sampling rate
        session_names=None,
        io_checkpoint_path=None
    ):
        self.seq_len = seq_len
        self.stride = stride
        self.dt = dt

        loader = IOVNBDLoader()
        if session_names is None:
            session_names = loader.get_session_names(split=split)

        self.sessions = []
        self.index_map = []  # (session_idx, start_idx)

        # Optional Phase 4 Neural Inertial Odometry model for generating measurements
        io_model = None
        if io_checkpoint_path and Path(io_checkpoint_path).exists():
            try:
                from src.models.inertial_odometry import NeuralInertialOdometry
                ckpt = torch.load(io_checkpoint_path, map_location="cpu", weights_only=False)
                cfg = ckpt.get("config", {})
                io_model = NeuralInertialOdometry(
                    input_dim=6,
                    tcn_channels=cfg.get("tcn_channels", [64, 128, 256]),
                    kernel_size=cfg.get("tcn_kernel_size", 3)
                )
                io_model.load_state_dict(ckpt["model_state_dict"])
                io_model.eval()
                print(f"KalmanNetDataset: Loaded Phase 4 model from {io_checkpoint_path}")
            except Exception as e:
                print(f"KalmanNetDataset: Could not load Phase 4 checkpoint ({e}). Using kinematic odometry generation.")
                io_model = None

        print(f"Loading {split} sessions for KalmanNet: {session_names}")
        for s_name in session_names:
            try:
                sess = loader.load_session(s_name, preprocess_imu=True)
                acc = sess['accel_filtered']
                gyr = sess['gyro_filtered']
                enu = sess['enu_coords'][:, :2]  # (N, 2) [east, north]
                n_samples = len(enu)

                if n_samples < seq_len + 10:
                    del sess
                    continue

                # Vehicle speed reference
                veh_spd = sess['vehicle']['speed_mps']
                if veh_spd is None:
                    veh_spd = sess['gps']['speed_mps']
                if veh_spd is None:
                    veh_spd = np.zeros(n_samples, dtype=np.float32)

                # Calibrate phone-to-vehicle alignment
                aligner = PhoneVehicleAlignment()
                R_p_to_v = aligner.calibrate(
                    sess['accel_raw'],
                    zupt_mask=sess['zupt_mask'],
                    velocity_ref=veh_spd
                )

                acc_aligned = (R_p_to_v @ acc.T).T
                gyr_aligned = (R_p_to_v @ gyr.T).T

                # 1. Compute Ground Truth ENU Velocity via numerical gradient
                vel_gt = np.zeros_like(enu, dtype=np.float32)
                vel_gt[1:-1] = (enu[2:] - enu[:-2]) / (2.0 * dt)
                vel_gt[0] = (enu[1] - enu[0]) / dt
                vel_gt[-1] = (enu[-1] - enu[-2]) / dt

                # Compute heading from trajectory displacement
                diff_enu = np.diff(enu, axis=0, prepend=enu[0:1])
                headings = np.arctan2(diff_enu[:, 1], diff_enu[:, 0])

                # 2. Derive Navigation Frame Accelerations a_nav [a_east, a_north]
                c_h = np.cos(headings)
                s_h = np.sin(headings)
                a_fwd = acc_aligned[:, 0]
                a_lat = acc_aligned[:, 1]
                a_east = a_fwd * c_h - a_lat * s_h
                a_north = a_fwd * s_h + a_lat * c_h
                a_nav = np.stack([a_east, a_north], axis=1).astype(np.float32)

                # 3. Derive Odometry Velocity Measurements z_meas [v_east, v_north]
                meas_v_fwd = np.copy(veh_spd)
                if io_model is not None:
                    try:
                        imu_6d = np.hstack([acc_aligned, gyr_aligned]).astype(np.float32)
                        with torch.no_grad():
                            for w_start in range(0, n_samples - 100 + 1, 20):
                                w_end = w_start + 100
                                w_x = torch.from_numpy(imu_6d[w_start:w_end]).unsqueeze(0)
                                _, pred_v, _ = io_model(w_x)
                                meas_v_fwd[w_end - 1] = pred_v[0, 0].item()
                    except Exception as err:
                        pass
                else:
                    rng = np.random.RandomState(42 + len(self.sessions))
                    noise = rng.normal(0.0, 0.4, size=n_samples).astype(np.float32)
                    meas_v_fwd = np.maximum(0.0, veh_spd + noise)

                z_east = meas_v_fwd * c_h
                z_north = meas_v_fwd * s_h
                z_meas = np.stack([z_east, z_north], axis=1).astype(np.float32)

                gt_state = np.hstack([enu, vel_gt]).astype(np.float32)

                s_idx = len(self.sessions)
                self.sessions.append({
                    'a_nav': a_nav,
                    'z_meas': z_meas,
                    'gt_state': gt_state
                })

                for start in range(0, n_samples - seq_len + 1, stride):
                    self.index_map.append((s_idx, start))

                del sess
                gc.collect()

            except Exception as e:
                print(f"Warning: Could not process session {s_name} in KalmanNetDataset: {e}")

        print(f"KalmanNetDataset ({split}): Indexed {len(self.index_map)} trajectory sequences across {len(self.sessions)} sessions.")

    def __len__(self):
        return len(self.index_map)

    def __getitem__(self, idx):
        s_idx, start = self.index_map[idx]
        end = start + self.seq_len

        sess_data = self.sessions[s_idx]
        a_nav_seq = sess_data['a_nav'][start:end]       # (L, 2)
        z_meas_seq = sess_data['z_meas'][start:end]     # (L, 2)
        gt_state_seq = sess_data['gt_state'][start:end] # (L, 4)
        init_state = gt_state_seq[0].copy()             # (4,) [p_e0, p_n0, v_e0, v_n0]

        return {
            'a_nav': torch.from_numpy(a_nav_seq),
            'z_meas': torch.from_numpy(z_meas_seq),
            'gt_state': torch.from_numpy(gt_state_seq),
            'init_state': torch.from_numpy(init_state),
            'dt': self.dt
        }
