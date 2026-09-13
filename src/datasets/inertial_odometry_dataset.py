"""
src/datasets/inertial_odometry_dataset.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Memory-Optimized PyTorch Dataset for Neural Inertial Odometry (TLIO-style).
Uses zero-copy lazy window indexing to maintain <100 MB RAM footprint.
─────────────────────────────────────────────────────────────────────────────
"""

import gc
import numpy as np
import torch
from torch.utils.data import Dataset
from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment


class InertialOdometryDataset(Dataset):
    """
    Memory-efficient sliding window dataset for Neural Inertial Odometry.
    Stores only contiguous session arrays and computes window targets on-the-fly.
    """

    def __init__(
        self,
        split="train",
        window_size=100,    # 10.0s @ 10 Hz
        stride=50,          # 5.0s step (50% window overlap)
        session_names=None
    ):
        self.window_size = window_size
        self.stride = stride

        loader = IOVNBDLoader()
        if session_names is None:
            session_names = loader.get_session_names(split=split)

        self.sessions = []
        self.index_map = []  # List of (session_idx, start_idx)

        print(f"Loading {split} sessions for Neural Inertial Odometry: {session_names}")
        for s_name in session_names:
            try:
                sess = loader.load_session(s_name, preprocess_imu=True)
                acc = sess['accel_filtered']
                gyr = sess['gyro_filtered']
                enu = sess['enu_coords'][:, :2]  # (N, 2) horizontal position

                # Reference vehicle forward speed
                veh_spd = sess['vehicle']['speed_mps']
                if veh_spd is None:
                    veh_spd = sess['gps']['speed_mps']
                if veh_spd is None:
                    veh_spd = np.zeros(len(acc), dtype=np.float32)

                # Calibrate phone-to-vehicle alignment for this session
                aligner = PhoneVehicleAlignment()
                R_p_to_v = aligner.calibrate(
                    sess['accel_raw'],
                    zupt_mask=sess['zupt_mask'],
                    velocity_ref=veh_spd
                )

                # Align IMU into vehicle chassis frame
                acc_aligned = (R_p_to_v @ acc.T).T
                gyr_aligned = (R_p_to_v @ gyr.T).T
                imu_6d = np.hstack([acc_aligned, gyr_aligned]).astype(np.float32)

                s_idx = len(self.sessions)
                self.sessions.append({
                    'imu': imu_6d,
                    'enu': enu.astype(np.float32),
                    'vel': veh_spd.astype(np.float32)
                })

                n_samples = len(imu_6d)
                for start in range(0, n_samples - window_size + 1, stride):
                    self.index_map.append((s_idx, start))

                # Immediately free loaded session dictionary
                del sess
                gc.collect()

            except Exception as e:
                print(f"Warning: Could not process session {s_name}: {e}")

        print(f"InertialOdometryDataset ({split}): Indexed {len(self.index_map)} windows across {len(self.sessions)} sessions.")

    def __len__(self):
        return len(self.index_map)

    def __getitem__(self, idx):
        s_idx, start = self.index_map[idx]
        end = start + self.window_size

        sess_data = self.sessions[s_idx]
        x_imu = sess_data['imu'][start:end]  # (L, 6)

        # Relative ENU displacement over the window
        dp_enu = sess_data['enu'][end - 1] - sess_data['enu'][start]

        # Tangent yaw heading at start of window
        norm_dp = np.linalg.norm(dp_enu)
        if norm_dp > 0.5:
            yaw = np.arctan2(dp_enu[1], dp_enu[0])
        else:
            yaw = 0.0

        # Rotate displacement into vehicle travel frame: [dx_forward, dy_lateral]
        c, s = np.cos(yaw), np.sin(yaw)
        R_yaw = np.array([[c, s], [-s, c]], dtype=np.float32)
        dp_veh = R_yaw @ dp_enu

        # Velocity at end of window: [v_fwd, 0.0]
        v_fwd = sess_data['vel'][end - 1]
        v_target = np.array([v_fwd, 0.0], dtype=np.float32)

        return {
            'imu': torch.from_numpy(x_imu),
            'disp': torch.from_numpy(dp_veh),
            'vel': torch.from_numpy(v_target)
        }
