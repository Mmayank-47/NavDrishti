"""
scripts/inspect_dataset_length.py
Inspects total indexed sequences for KalmanNet training dataset.
"""
import sys, os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.datasets.kalmannet_dataset import KalmanNetDataset


def main():
    ds = KalmanNetDataset(split='train', seq_len=50, stride=20)
    print(f"Dataset indexed {len(ds):,} training sequences.")


if __name__ == '__main__':
    main()
