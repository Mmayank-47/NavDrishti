#!/bin/bash
set -e
cd /home/zeus/content/sih-model-training
export PYTHONPATH="/home/zeus/content/sih-model-training:/home/zeus/content/sih-model-training/src:$PYTHONPATH"
/home/zeus/miniconda3/envs/cloudspace/bin/python - << 'EOF'
import sys
from src.datasets.inertial_odometry_dataset import InertialOdometryDataset
print("Testing InertialOdometryDataset loading...")
ds = InertialOdometryDataset(split="train", window_size=100, stride=50)
print("Loaded train dataset successfully! Samples:", len(ds))
EOF
