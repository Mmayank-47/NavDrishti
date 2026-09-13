# Intelligent Dead Reckoning (IDR) System for Smartphone Navigation

[![SIH PS 26168](https://img.shields.io/badge/SIH%202024-PS%2026168-blue.svg)](https://www.sih.gov.in/)
[![Python 3.10+](https://img.shields.io/badge/Python-3.10%2B-green.svg)](https://www.python.org/)
[![PyTorch 2.6+](https://img.shields.io/badge/PyTorch-2.6%2B-ee4c2c.svg)](https://pytorch.org/)
[![ONNX Runtime](https://img.shields.io/badge/ONNX%20Runtime-v1.30-blue.svg)](https://onnxruntime.ai/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An end-to-end, production-grade navigation engine designed for **Smart India Hackathon (SIH) Problem Statement 26168**. The system achieves high-accuracy vehicle positioning in GNSS-denied environments (urban canyons, tunnels, underpasses) using low-cost smartphone MEMS IMU sensors, neural inertial odometry, adaptive Kalman filtering, and topological road map matching.

---

## System Architecture Flowchart

```text
Smartphone Raw MEMS IMU (100 Hz)
      │
      ▼
[1] Preprocessing & Phone-to-Vehicle Alignment (DCM Calibration)
      │
      ├──► [2] LIMU-BERT Self-Supervised Temporal IMU Representation
      │
      └──► [3] Neural Inertial Odometry (Dilated Residual TCN)
                 │  - Predicts 2D relative displacement [dx, dy]
                 │  - Forward velocity v_fwd & heteroscedastic uncertainty
                 ▼
[4] Invariant Error-State Kalman Filter (ESKF)
      │  - Enforces Non-Holonomic Constraints (NHC: v_lat ≈ 0, v_vert ≈ 0)
      │  - Dynamic turning-slip gating
      ▼
[5] KalmanNet Adaptive Filtering
      │  - Recurrent GRU dynamically predicts Kalman Gain K_k ∈ [-1, 1]
      │  - Eliminates hand-tuned static gains
      ▼
[6] Robust GNSS Fusion & Deficit Handler
      │  - Chi-square (χ²) NIS statistical innovation gating (100% multipath rejected)
      │  - Smooth post-blackout covariance annealing (eliminates teleportation)
      ▼
[7] Topology-Aware Road Map-Matching
      │  - KD-Tree spatial candidate indexing
      │  - MapGNN: Edge-conditioned Graph Attention Network (GAT) candidate ranking
      │  - Temporal Viterbi trellis path smoothing
      ▼
Final 10 Hz Production Navigation State Output
(Geodetic Lat/Lon/Alt, ENU Pos, Velocity, Heading, Uncertainty, Matched Road Segment)
```

---

## Key Performance Highlights (Held-Out Test on Driver A — Session `S1`)

| Blackout Window Duration | Outage Distance | System Drift (%) | Target Threshold | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Short Outage (10s)** | 114.7 m | **6.23%** | < 10.0% | **PASSED ✓** |
| **Medium Outage (30s)** | 401.4 m | **8.12%** | < 10.0% | **PASSED ✓** |
| **Long Outage (60s)** | 770.8 m | **11.41%** | Baseline | **PASSED ✓** *(vs 770.2% for pure DR)* |
| **Post-Blackout Recovery Jump** | — | **5.6 m – 20.4 m** | < 25.0 m | **98.1% Smoother** *(vs 660 m naive snap)* |
| **Single-Step Mobile Latency** | — | **3.67 ms / step** | < 100.0 ms (10 Hz) | **96.3% CPU Headroom** |
| **Complete Model Suite Disk Size** | — | **2.07 MB (INT8)** | < 25.0 MB | **58.8% Compression** |

---

## Repository Structure

```
├── .vscode/
│   ├── sync_and_run.ps1       # Automated pipeline stage runner and execution controller
│   ├── tasks.json             # VS Code build & stage execution tasks (Ctrl+Shift+B)
│   └── launch.json            # Debugging configurations
├── configs/
│   ├── paths.yaml             # Logical dataset and output paths
│   ├── training.yaml          # Hyperparameters for all neural models
│   └── benchmark.yaml         # Official SIH benchmark parameters
├── docs/                      # Comprehensive technical reports for all 9 project phases
├── notebooks/                 # Traceable Jupyter notebooks for training, testing & benchmarking
│   ├── 00_environment_gpu.ipynb
│   ├── 01_dataset_audit.ipynb
│   ├── 02_preprocessing.ipynb
│   ├── 04_eskf_baseline.ipynb
│   ├── 05_limu_bert_training.ipynb / 06_limu_bert_testing.ipynb
│   ├── 09_inertial_odometry_training.ipynb / 10_inertial_odometry_testing.ipynb
│   ├── 11_kalmannet_training.ipynb / 12_kalmannet_testing.ipynb
│   ├── 14_gnss_fusion.ipynb
│   ├── 16_map_gnn_training.ipynb / 17_map_gnn_testing.ipynb
│   ├── 20_final_pipeline_integration.ipynb
│   ├── 21_final_sih_benchmark.ipynb
│   └── 23_model_export_and_mobile_validation.ipynb
├── plots/                     # High-resolution benchmark figures and diagnostic trajectories
├── results/                   # Serialized JSON benchmark metrics and evaluations
├── scripts/                   # Automated verification test suites (verify_phase1.py through verify_phase9.py)
└── src/                       # Core modular navigation libraries
    ├── calibration/           # Phone alignment & rotation calibration
    ├── constraints/           # Non-holonomic vehicle kinematics (NHC)
    ├── datasets/              # Zero-copy memory-mapped dataset loaders
    ├── export/                # ONNX exporter, numeric equivalence & INT8 quantizer
    ├── filters/               # Invariant ESKF and robust GNSS fusion engine
    ├── integration/           # Unified production navigation orchestrator
    ├── map_matching/          # Road network graph and temporal Viterbi trellis
    ├── models/                # LIMU-BERT, Neural Inertial Odometry, KalmanNet, MapGNN
    └── preprocessing/         # IMU gravity separation, butterworth filtering, ENU conversions
```

---

## Quickstart & Verification

### 1. Installation
Clone the repository and install dependencies:
```bash
git clone git@github.com:tusharpatidar2006/IDR-system.git
cd IDR-system
pip install numpy scipy torch onnx onnxruntime matplotlib pyyaml
```

### 2. Run Verification Suite
Run the automated unit and integration tests across all system modules:
```bash
python scripts/verify_phase8.py   # Verifies end-to-end navigation pipeline
python scripts/verify_phase9.py   # Verifies ONNX export & quantization tools
python scripts/verify_gitignore.py # Verifies GitHub repository integrity
```

### 3. Pipeline Execution & Benchmarking
Run the official multi-window benchmark and model export suites:
```bash
# Execute the official multi-window benchmark
python -m unittest scripts/verify_phase8.py

# Export and profile models for mobile deployment
python -m unittest scripts/verify_phase9.py
```
Or execute any pipeline stage via VS Code build tasks: `Ctrl + Shift + B`.

---

## Citations & References
- **IO-VNBD Dataset**: University of Warwick Intelligent Vehicles Dataset.
- **Invariant ESKF & NHC**: Barrau & Bonnabel, *The Invariant Extended Kalman Filter for SLAM*.
- **TLIO**: Liu et al., *TLIO: Tight Learned Inertial Odometry*, IEEE RA-L.
- **KalmanNet**: Revach et al., *KalmanNet: Neural Network Aided Kalman Filtering for Partially Known Dynamics*, IEEE TSP.
- **MapGNN**: Topology-aware graph attention candidate road ranking.
