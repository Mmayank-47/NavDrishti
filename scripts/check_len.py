import sys
from pathlib import Path

import os
PROJECT_ROOT = Path('/home/zeus/content/sih-model-training')
os.chdir(PROJECT_ROOT)
sys.path.insert(0, str(PROJECT_ROOT))

from src.datasets.kalmannet_dataset import KalmanNetDataset

ds = KalmanNetDataset(split='train', seq_len=50, stride=20)
print(f"Dataset indexed {len(ds)} training sequences.")
