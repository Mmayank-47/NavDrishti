"""
src/datasets/limu_bert_dataset.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
PyTorch Dataset for LIMU-BERT Self-Supervised Pretraining on IO-VNBD IMU data.
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
import torch
from torch.utils.data import Dataset
from src.preprocessing.data_loader import IOVNBDLoader


class LIMUBERTDataset(Dataset):
    """
    Sliding window dataset with random span masking for self-supervised IMU pretraining.
    """

    def __init__(
        self,
        split="train",
        window_size=120,    # 12.0s at 10 Hz
        stride=40,          # 4.0s overlap
        mask_ratio=0.15,    # 15% masked timesteps
        mask_span=6,        # consecutive masked span length
        session_names=None
    ):
        self.window_size = window_size
        self.stride = stride
        self.mask_ratio = mask_ratio
        self.mask_span = mask_span

        loader = IOVNBDLoader()
        if session_names is None:
            session_names = loader.get_session_names(split=split)

        self.windows = []

        print(f"Loading {split} sessions for LIMU-BERT: {session_names}")
        for s_name in session_names:
            try:
                sess = loader.load_session(s_name, preprocess_imu=True)
                acc = sess['accel_filtered']
                gyr = sess['gyro_filtered']
                imu_6d = np.hstack([acc, gyr]).astype(np.float32)

                n_samples = len(imu_6d)
                for start in range(0, n_samples - window_size + 1, stride):
                    w = imu_6d[start:start + window_size]
                    self.windows.append(w)
            except Exception as e:
                print(f"Warning: Could not load session {s_name}: {e}")

        self.windows = np.array(self.windows, dtype=np.float32)
        print(f"LIMU-BERT Dataset ({split}): Extracted {len(self.windows)} windows of size {window_size}x6.")

    def __len__(self):
        return len(self.windows)

    def __getitem__(self, idx):
        target = self.windows[idx].copy()  # (L, 6)
        L = self.window_size

        # Create random span mask
        mask = np.zeros(L, dtype=bool)
        n_mask = int(L * self.mask_ratio)

        current_masked = 0
        while current_masked < n_mask:
            start_t = np.random.randint(0, max(1, L - self.mask_span))
            end_t = min(L, start_t + self.mask_span)
            mask[start_t:end_t] = True
            current_masked = np.sum(mask)

        # Apply masking (replace masked timesteps with 0.0)
        masked_input = target.copy()
        masked_input[mask] = 0.0

        return {
            'input': torch.from_numpy(masked_input),    # (L, 6)
            'target': torch.from_numpy(target),          # (L, 6)
            'mask': torch.from_numpy(mask)              # (L,) boolean
        }
