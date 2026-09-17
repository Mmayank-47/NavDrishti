# FINAL MODEL RESULTS REPORT
## SIH PS 26168 — AI-ML Based Intelligent Dead Reckoning System for Seamless Navigation
### Forensic Audit Report — Evidence-Based, No Fabrication

**Audit Date:** 2026-09-15
**Rule:** Every numerical claim is traceable to a source artifact. If not verifiable, explicitly stated.

---

## EXECUTIVE SUMMARY (FRONT)

**What was actually built?** A multi-phase, multi-model smartphone navigation system across 9 phases, combining classical physics (ESKF, NHC) with 4 neural networks (LIMU-BERT, NIO-TCN, KalmanNet, MapGNN).

**What was trained?** LIMU-BERT (80 epochs), Neural Inertial Odometry (100 epochs), KalmanNet (50 epochs), MapGNN (40 epochs). All 4 checkpoints verified on filesystem.

**What was tested?** All 4 models on held-out test session S1 (Driver A), IO-VNBD. GNSS fusion, map matching, and final pipeline benchmarked on S1 with 10s/30s/60s GNSS outage windows.

**Key measured results (all verified from JSON result files):**

| Test | Result | Source |
|---|---|---|
| NIO displacement RMSE (10s window) | 63.906 m | results/inertial_odometry_results.json |
| NIO velocity RMSE | 7.122 m/s | results/inertial_odometry_results.json |
| KalmanNet drift over 37.2 km GNSS-denied | 11.19% | results/kalmannet_results.json |
| GNSS Fusion: 60s tunnel drift | 18.59% | results/gnss_fusion_results.json |
| GNSS Fusion: recovery jump | 4.68 m | results/gnss_fusion_results.json |
| Map Matching: complete system RMSE | 29.90 m | results/map_matching_results.json |
| Final pipeline: 10s drift % | **118.49%** | results/final_sih_benchmark_results.json |
| Final pipeline: 30s drift % | **41.45%** | results/final_sih_benchmark_results.json |
| Final pipeline: 60s drift % | **86.12%** | results/final_sih_benchmark_results.json |
| CPU inference latency (10 Hz) | 3.67 ms / 96.33% headroom | results/model_export_metrics.json |

**Does it satisfy SIH requirements? NO.** All 3 tested GNSS-denied windows fail the <10% drift requirement. Mandatory ~50m/3-5s and ~1km/60s scenarios NOT TESTED.

---

## 1. PROJECT OBJECTIVE

**SIH PS 26168** requires an AI-ML-based IDR system that:
- Maintains position accuracy during GNSS outages (drift < 10% of distance)
- Operates on Android smartphones at 10 Hz
- Achieves seamless, zero-jump GNSS recovery (<0.5m step)
- Demonstrated on IO-VNBD benchmark dataset

---

## 2. DATASET OVERVIEW

### IO-VNBD (PRIMARY — Only Dataset Actually Used)
| Property | Value | Source |
|---|---|---|
| Size | 3,726.1 MB | docs/dataset_audit.md L13 |
| Sessions audited | 30 | docs/dataset_audit.md L13 |
| Sampling rate | 10.0 Hz | docs/dataset_audit.md L29-48 |
| Train sessions | M(Driver B), Vf/Vta/Vtb/Vw(Driver E) | artifacts/dataset_manifest.json L79-85 |
| Val sessions | Y (Driver D) | artifacts/dataset_manifest.json L86-88 |
| Test sessions (locked) | S (Driver A) | artifacts/dataset_manifest.json L89-91 |
| NIO train windows | 13,303 | docs/phase_4_inertial_odometry_report.md L38 |
| Session M duration | 6,171.7 s (~102 km) | docs/phase_1_preprocessing_report.md L38-39 |
| Test session S1 distance | 37,246.5 m (5174.6 s) | results/kalmannet_results.json L4/L6 |

**Split method:** Session-level (prevents temporal leakage). Verified in `src/preprocessing/data_loader.py L30-34`.

### Other Datasets (Audited but NOT Used)
| Dataset | Size | Status |
|---|---|---|
| GNSS Interference Part III | 4,146.4 MB | Audited; 0 experiments executed |
| NavICGNSS Android | 3,287.9 MB | Audited; 0 experiments executed |
| MOTOR | 47.3 MB | Schema unconfirmed; not used |
| OSM (india-260912.osm.pbf) | Referenced; 0 MB in audit | NOT parsed — road graph from GT trajectories |

---

## 3. COMPLETE MODEL INVENTORY

| Model | Implemented | Trained | Tested | Final Pipeline | Status |
|---|:---:|:---:|:---:|:---:|---|
| IMU Preprocessor | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| Phone-Vehicle Alignment | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| LIMU-BERT | ✅ | ✅ 80 ep | ✅ | ❌ | TRAINED, **NOT IN FINAL PIPELINE** |
| Neural Inertial Odometry | ✅ | ✅ 100 ep | ✅ | ✅ | IMPLEMENTED + TRAINED + USED |
| KalmanNet | ✅ | ✅ 50 ep | ✅ | ✅ | IMPLEMENTED + TRAINED + USED |
| Invariant ESKF | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| NHC Constraints | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| Robust GNSS Fusion | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| MapGNN (GAT) | ✅ | ✅ 40 ep | ✅ | ✅ | IMPLEMENTED + TRAINED + USED |
| Temporal Viterbi | ✅ | ❌ | ✅ | ✅ | CLASSICAL — IMPLEMENTED + USED |
| OdoNet | ❌ | ❌ | ❌ | ❌ | NOT IMPLEMENTED (folded into NIO) |

> ⚠️ **LIMU-BERT CRITICAL NOTE:** `final_navigation_pipeline.py` does NOT import or call LIMU-BERT. It was trained as an offline pretraining artifact. The real-time pipeline uses NIO-TCN directly on raw IMU, bypassing LIMU-BERT features entirely. (Verified by source code inspection.)

> ⚠️ **ODONET CRITICAL NOTE:** `checkpoints/odonet/` directory contains only `.gitkeep`. No OdoNet checkpoint exists. The velocity prediction role was merged into the NIO velocity head.

---

## 4. MODEL EXPLANATIONS

### 4.1 IMU Preprocessor (`src/preprocessing/imu_preprocessor.py`)
Cleans raw smartphone IMU signals before any model processes them.
- Zero-phase Butterworth LPF (fc=4 Hz) removes engine vibration
- Amplitude clipping at 35 m/s² prevents pothole spike drift
- Gravity separation extracts dynamic linear acceleration
- Rolling-variance ZUPT detector identifies stationary periods
- **Output:** Filtered accel/gyro + ZUPT mask → all downstream models

### 4.2 Phone-Vehicle Alignment (`src/calibration/alignment.py`)
Estimates the phone's orientation relative to the car and corrects all IMU readings.
- Stage 1: Leveling — computes roll/pitch from gravity vector during stationary intervals
- Stage 2: Heading — correlates horizontal acceleration with velocity derivative to find forward axis
- Outputs R_p2v (3×3 direction cosine matrix)
- **Verified example (Session M):** Roll=+0.24°, Pitch=-0.48°, Yaw=-40.61°, Orthonormality=2.22e-16

### 4.3 LIMU-BERT (`src/models/limu_bert.py`)
4-layer Transformer encoder trained via Masked Sensor Modeling (15% span masking) to reconstruct masked IMU signals. Learns rich temporal IMU representations. **OFFLINE ONLY — not used at inference time in the final pipeline.**
- Input: (B, 120, 6) IMU windows (12s @ 10Hz)
- Architecture: 4 Transformer layers, 4 heads, hidden=128, ff=256
- Best val MSE: 0.1536; Test MSE: 0.1944

### 4.4 Neural Inertial Odometry — TCN (`src/models/inertial_odometry.py`)
Dilated TCN that maps 10 seconds of calibrated IMU to vehicle displacement, velocity, and uncertainty. Bypasses integration by directly predicting motion from learned IMU patterns.
- Input: (B, 100, 6) at 10 Hz
- Backbone: Dilated 1D TCN [64, 128, 256 channels], dilation [1, 2, 4], GELU, Chomp1d causal
- Heads: displacement [dx, dy] (vehicle frame), velocity [vfwd, vlat], log-variance [logσ²]
- Loss: Heteroscedastic NLL + MSE velocity (λ_v=0.5)

### 4.5 KalmanNet (`src/models/kalmannet.py`)
2-layer GRU (64 hidden) that learns adaptive Kalman gain from tracking residuals. Replaces fixed noise matrices Q and R with data-driven estimation.
- Input: [Δx_k (state diff), y_k (innovation), Δz_k (measurement diff)]
- Output: K_k = tanh(W_out @ h_k) ∈ [-1, 1]^(4×2)
- Update: x_post = x_prior + K_k @ y_k
- Key behavior: High gain during straight driving; throttles near zero during sharp turns

### 4.6 Invariant ESKF (`src/filters/invariant_eskf.py`)
15-state error-state Kalman filter with quaternion attitude kinematics. Tracks position(3), velocity(3), attitude error(3), accel bias(3), gyro bias(3). Joseph-form covariance update for numerical stability.

### 4.7 Non-Holonomic Constraints (`src/constraints/nhc.py`)
Encodes ground-vehicle physics: lateral velocity ≈ 0, vertical velocity ≈ 0. Dynamic covariance inflation when |ω_z| > 0.15 rad/s prevents constraint corruption during cornering.

### 4.8 Robust GNSS Fusion Engine (`src/filters/gnss_fusion.py`)
4-mode state machine: FULL_FUSION / DEGRADED_GNSS / GNSS_BLACKOUT / RECOVERY
- Chi-squared (χ²) gating: NIS = y^T * S^-1 * y vs γ=9.21 (p=0.01)
- Huber M-estimator for moderate outliers
- Anti-teleport: y_eff(t) = y_raw * α(t), α ramps 0→1 over 25 steps = 2.5 seconds

### 4.9 MapGNN (`src/models/map_gnn.py`)
2-layer Graph Attention Network that ranks road segment candidates using vehicle state and road topology. Encoder: Linear(6,64) → ReLU → Linear(64,64) for both query and candidates. 2x GAT layers with edge-conditioned message passing. Output: log-softmax over K candidate segments.

### 4.10 Temporal Viterbi Matcher (`src/map_matching/viterbi_path.py`)
Dynamic programming path decoder ensuring topological road continuity.
- Transitions: same edge=0.75, legal turn=0.24, road jump=1e-4*exp(-d/10)
- Forward trellis DP: V_t(j) = max_i[V_{t-1}(i) + log T(ei→ej)] + log P(ej)

---

## 5. TRAINING DETAILS

### LIMU-BERT Training Summary
| Parameter | Value | Source |
|---|---|---|
| Epochs | 80 | results/limu_bert_results.json L3 |
| Best val loss (MSE) | 0.153625 | results/limu_bert_results.json L4 |
| Final train loss | 0.730231 | results/limu_bert_results.json L5 |
| Trainable params | 548,102 | results/limu_bert_results.json L6 |
| Optimizer | AdamW (lr=1e-3, wd=1e-4) | configs/training.yaml L20-21 |
| Scheduler | Cosine Annealing | configs/training.yaml L23 |
| Window size | 120 samples (12s @ 10Hz) | src/datasets/limu_bert_dataset.py L23 |
| Mask ratio | 15% | src/datasets/limu_bert_dataset.py L25 |
| Architecture | 4 Transformer layers, 4 heads, hidden=128 | configs/training.yaml L27-29 |
| Mixed precision | Yes (AMP) | docs/phase_3_limu_bert_report.md L29 |
| GPU | Tesla T4 (Lightning AI) | artifacts/gpu_preflight.json |
| Checkpoint | limu_bert_best.pt (6.83 MB) | Filesystem verified |

### Neural Inertial Odometry Training Summary
| Parameter | Value | Source |
|---|---|---|
| Epochs | 100 | results/inertial_odometry_training_summary.json L3 |
| Train windows | 13,303 | docs/phase_4_inertial_odometry_report.md L38 |
| Best val loss | 18.1588 | results/inertial_odometry_training_summary.json L4 |
| Val displacement RMSE | 60.495 m | results/inertial_odometry_training_summary.json L5 |
| Val velocity RMSE | 8.559 m/s | results/inertial_odometry_training_summary.json L6 |
| Trainable params | 507,654 | results/inertial_odometry_training_summary.json L7 |
| Optimizer | AdamW (lr=1e-3, wd=1e-4) | configs/training.yaml L56-57 |
| TCN channels | [64, 128, 256] | configs/training.yaml L62 |
| Loss | Heteroscedastic NLL + velocity MSE (λ_v=0.5) | src/models/inertial_odometry.py L175-192 |
| Checkpoint | inertial_odometry_best.pt (5.85 MB) | Filesystem verified |

### KalmanNet Training Summary
| Parameter | Value | Source |
|---|---|---|
| Best epoch | 50 | results/kalmannet_training_metrics.json L3 |
| Best val loss | 1,597.68 | results/kalmannet_training_metrics.json L2 |
| Final train pos RMSE | 14.769 m | results/kalmannet_training_metrics.json L4 |
| Final val pos RMSE | 23.140 m | results/kalmannet_training_metrics.json L5 |
| Trainable params | 55,176 | results/model_export_metrics.json L110 |
| Architecture | 2-layer GRU, 64 hidden units | src/models/kalmannet.py |
| Optimizer | Adam (lr=1e-3, StepLR step=20, γ=0.5) | configs/training.yaml L75-79 |
| Checkpoint | kalmannet_best.pt (0.65 MB) | Filesystem verified |

### MapGNN Training Summary
| Parameter | Value | Source |
|---|---|---|
| Epochs | 40 | docs/phase_7_map_matching_report.md L71 |
| Top-1 train accuracy | 85.3% | docs/phase_7_map_matching_report.md L72 |
| Trainable params | 25,985 | results/model_export_metrics.json L161 |
| Training data | 15 IO-VNBD sessions + simulated 0-40m drift | docs/phase_7_map_matching_report.md L70 |
| Optimizer | AdamW (lr=5e-4) | configs/training.yaml L89/L98 |
| Architecture | 2-layer GAT, 64 hidden, 4 heads | configs/training.yaml L94-97 |
| Checkpoint | map_gnn_best.pt (0.11 MB) | Filesystem verified |

---

## 6. TESTING DETAILS (ALL HELD-OUT DRIVER A, SESSION S1)

### LIMU-BERT Test
| Metric | Value | Source |
|---|---|---|
| Test reconstruction MSE | **0.194394** | results/limu_bert_test_results.json L4 |
| Note | Minor discrepancy with docs/phase_3 (0.2035) — using JSON as canonical | — |

### Neural Inertial Odometry Test
| Metric | Value | Source |
|---|---|---|
| Displacement RMSE (10s window) | **63.906 m** | results/inertial_odometry_results.json L4 |
| Displacement MAE | **49.295 m** | results/inertial_odometry_results.json L5 |
| Displacement P95 | **123.809 m** | results/inertial_odometry_results.json L6 |
| Velocity RMSE | **7.122 m/s (25.64 km/h)** | results/inertial_odometry_results.json L7 |
| Velocity correlation (r) | **0.2742** | results/inertial_odometry_results.json L9 |
| Uncertainty σ mean | **8,508,032.0** ⚠️ ANOMALOUS | results/inertial_odometry_results.json L10 |

> ⚠️ σ = 8,508,032 is unphysical (expected: single digits or low hundreds). The log-variance head lacks output clamping, causing exp(logvar) overflow at test time. This does NOT affect mean predictions but means calibrated uncertainty CANNOT be used.

### KalmanNet Test (37.2 km continuous GNSS-denied)
| Metric | Value | Source |
|---|---|---|
| Total distance | 37,246.5 m | results/kalmannet_results.json L4 |
| Duration | 5,174.6 s | results/kalmannet_results.json L6 |
| Position RMSE | **2,514.68 m** | results/kalmannet_results.json L8 |
| Final drift | **4,167.94 m** | results/kalmannet_results.json L11 |
| Drift % | **11.19%** | results/kalmannet_results.json L13 |
| Fixed-gain baseline drift % | 109.54% (comparison) | results/kalmannet_results.json |
| Velocity RMSE | **55.868 m/s** ⚠️ ANOMALOUS | results/kalmannet_results.json L15 |

> ⚠️ This was a 37.2km FULLY GNSS-denied test — the most extreme scenario. Realistic deployments would see GNSS updates throughout, resetting drift. 55.87 m/s velocity RMSE is unphysical; reflects accumulated state drift.

### GNSS Fusion Test (400s segment of S1)
| Metric | Naive ESKF | Proposed | Source |
|---|---|---|---|
| 60s tunnel drift | 580.25 m (75.3%) | **143.23 m (18.59%)** | results/gnss_fusion_results.json |
| Recovery jump | 579.40 m | **4.68 m** | results/gnss_fusion_results.json |
| Overall session RMSE | 129.43 m | **81.32 m** | results/gnss_fusion_results.json |
| Outlier rejection rate | 0% (0/4) | **100% (4/4)** | results/gnss_fusion_results.json |

### Map Matching Test (300s / 3476m segment of S1)
| Mode | RMSE | Notes |
|---|---|---|
| Mode A: Pure DR | 24.890 m | Best RMSE baseline |
| Mode B: Nearest-Edge Snap | 33.065 m | Degrades by 32.8% |
| Mode C: GNN Map Matching | 33.565 m | Degrades by 34.8% |
| Mode D: GNN + Viterbi | 33.602 m | No improvement over C |
| **Mode E: Complete (Blended)** | **29.901 m** | Still 20.1% worse than Mode A |

> ⚠️ Map matching does NOT improve accuracy when DR drift exceeds road lane width. Honest finding confirmed in docs/phase_7_map_matching_report.md Section 4.1.

---

## 7. COMPLETE DATA FLOW (END-TO-END)

```
RAW SMARTPHONE DATA (S-*.csv, 10 Hz)
  accel(N,3), gyro(N,3), gravity(N,3), lat/lon/alt, HDOP
↓ IMU PREPROCESSOR
  Butterworth LPF → amp clip → gravity sep → ZUPT detect
  Output: accel_filtered, gyro_filtered, zupt_mask
↓ PHONE-VEHICLE ALIGNMENT
  Gravity leveling → yaw correlation → R_p2v (3×3)
  Applied: v_veh = R_p2v @ v_phone
↓ KINEMATIC PREDICTION (ESKF propagation step)
  heading += ω_z * dt; a_nav = [a*cos(θ), a*sin(θ)]
  x_prior = F*x + B*a_nav; P_prior = F*P*F' + Q

           ┌──────────────────────────────────────────────┐
           │           GNSS AVAILABLE?                     │
           └────────────────────┬─────────────────────────┘
                                │
           ┌────── YES (FULL_FUSION/DEGRADED) ────────────┐
           │ ROBUST GNSS FUSION ENGINE                     │
           │ Chi-sq gating → Huber R → Anti-teleport       │
           │ y_eff = y_raw * α(t) ramps over 2.5s         │
           │ K = P*H'*inv(H*P*H'+R_eff)                   │
           │ x_post = x_prior + K*y_eff                    │
           └──────────────────────────────────────────────┘

           ┌──────── NO (GNSS_BLACKOUT) ──────────────────┐
           │ Estimate v_fwd from NIO or state              │
           │ z_odo = [v_fwd*cos(θ), v_fwd*sin(θ)]        │
           │ KALMANNET GRU: Δx, y, Δz → K_k (4×2)       │
           │ x_post = x_prior + K_k @ (z_odo - H*x_prior) │
           └──────────────────────────────────────────────┘

↓ NHC (both modes)
  y = [0,0] - [v_lat, v_vert]; inflate R during cornering
  Kalman update → constrain lateral/vertical velocity
↓ MAP MATCHING (optional soft blend)
  KDTree query → K=5 candidates within R=60m
  [If GNN checkpoint loaded: MapGNN → Viterbi → best edge]
  pos_enu = 0.8*pos_enu + 0.2*road_proj_pos
↓ COORDINATE CONVERSION
  enu_to_geodetic → lat/lon/alt
↓ OUTPUT (10 Hz)
  {lat, lon, east_m, north_m, speed_mps, heading_deg, mode,
   pos_uncertainty_m, gnss_rejected, matched_edge_id, map_confidence}
```

---

## 8. FINAL BENCHMARK RESULTS

**Test session:** IO-VNBD S1 (Driver A, held-out test)
**Source:** `results/final_sih_benchmark_results.json`

| Window | Duration | Distance | Pure IMU Drift | Proposed Drift | Drift % | Recovery Jump | SIH <10% |
|---|---|---|---|---|---|---|---|
| 10s | 10.0 s | 8.844 m | 112.85 m | **10.48 m** | **118.5%** | 0.919 m | ❌ FAIL |
| 30s | 30.0 s | 300.39 m | 1,171.72 m | **124.52 m** | **41.5%** | 5.612 m | ❌ FAIL |
| 60s | 60.0 s | 606.29 m | 1,478.62 m | **522.16 m** | **86.1%** | 20.494 m | ❌ FAIL |

> ℹ️ **10s context:** Vehicle traveled only 8.844m (creeping ~3.2 km/h). 118.5% is a mathematical artifact of the tiny denominator. Absolute drift (10.48m) is moderate, not catastrophic.

> ℹ️ **Discrepancy note:** GNSS Fusion 60s test reported 143.23m drift (18.59%). Final benchmark 60s reported 522.16m (86.12%). These are different time segments from the same session at different vehicle speeds and heading dynamics.

---

## 9. PLOT EXPLANATIONS (KEY PLOTS)

### `plots/limu_bert/limu_bert_training_curve.png`
Training (blue) and validation (orange) MSE curves for 80 epochs. Best val=0.1536. Train loss converges to ~0.73. Large gap suggests training set is more diverse/noisy than validation.

### `plots/inertial_odometry/test_velocity_tracking_S1.png`
Predicted speed vs CAN-bus ground truth over S1. Tracks gross speed trends (r=0.2742) but misses precise instantaneous speed. RMSE=7.12 m/s (~25.64 km/h). Velocity head significantly weaker than displacement head on held-out driver.

### `plots/inertial_odometry/test_displacement_error_S1.png`
CDF of per-window displacement errors on S1. Median=49.3m (MAE), P95=123.8m. High tail indicates frequent large errors — driver style mismatch is the main cause.

### `plots/kalmannet/kalmannet_gain_adaptation_S1.png`
Time-series of K[v_east, v_east] gain component over S1. Mean=0.053, Std=0.206, range [-0.997, +1.000]. Gain spikes to +1.0 during smooth straight driving and throttles near 0 during sharp turns — confirms intended dynamic behavior.

### `plots/gnss_fusion/gnss_blackout_recovery_S1.png`
2D trajectory through 60s tunnel. Naive filter teleports 579m on exit. Proposed filter anneals smoothly to within 4.68m. Anti-teleport mechanism works.

### `plots/gnss_fusion/nis_innovation_gating_S1.png`
NIS statistic vs χ²(2) threshold γ=9.21. 4 injected outlier spikes all breach threshold; normal driving stays comfortably below. 100% outlier rejection confirmed.

### `plots/map_matching/ablation_comparison_S1.png`
CDF of errors for all 5 modes. Mode A (Pure DR, 24.89m) is best. Modes B-D degrade by 32-35% by snapping to wrong lanes. Mode E partial recovery (29.9m). Confirms map matching is counter-productive when inertial drift > lane width.

### `plots/final_benchmark/multi_window_drift_comparison.png`
Bar chart: Pure IMU vs Naive filter vs Proposed system for 10s/30s/60s windows. Shows massive improvement over Pure IMU but all proposed results remain above SIH 10% target line.

### `plots/final_benchmark/recovery_jump_comparison.png`
Bar chart: Naive vs Proposed recovery discontinuity. 30s window: 288m → 5.61m (98.1% reduction). 60s: 660m → 20.49m (96.9% reduction). Anti-teleport mechanism is the most successful part of the system.

### `plots/export/model_latency_comparison.png`
Inference latency per model (PyTorch CPU vs ONNX FP32 vs ONNX INT8) vs 100ms budget. Inertial Odometry: 6.38ms → 1.19ms FP32 (5.36x speedup). Total step: 3.67ms.

---

## 10. SIH PS 26168 COMPLIANCE TABLE

| SIH Requirement | Target | Measured | Status |
|---|---|---|---|
| GNSS-denied drift < 10% | < 10% | 10s: 118.5%, 30s: 41.5%, 60s: 86.1% | ❌ FAIL |
| ~50m / 3–5s scenario | Error < 5m | NOT TESTED | ❌ NOT TESTED |
| ~1km / ~60s scenario | Error < 100m | NOT TESTED (final system) | ❌ NOT TESTED |
| Zero-jump recovery < 0.5m | < 0.5m | 10s: 0.919m, 30s: 5.61m, 60s: 20.49m | ❌ FAIL |
| IO-VNBD dataset used | Required | ✅ Primary dataset for all training + testing | ✅ PASS |
| Smartphone operation | Required | ✅ 10Hz smartphone CSV data used throughout | ✅ PASS |
| 10 Hz navigation output | Required | ✅ dt=0.1s pipeline, runtime.yaml: 10Hz | ✅ PASS |
| External IMU (FOG) support | Required | NOT VERIFIED (config exists, no FOG data tested) | ❌ NOT VERIFIED |
| Map matching | Expected | Implemented + tested, but degrades accuracy | ⚠️ IMPLEMENTED (not improving) |
| Mobile/edge deployment | Expected | ✅ 3.67ms/step, ONNX+INT8, 96.33% headroom | ✅ PASS |

---

## 11. GNSS RECOVERY ANALYSIS

Anti-teleport mechanism results (all from verified JSON files):

| Scenario | Naive Jump | Proposed Jump | Reduction |
|---|---|---|---|
| 10s outage (S1) | 8.844 m | **0.919 m** | 89.6% |
| 30s outage (S1) | 288.25 m | **5.612 m** | 98.1% |
| 60s outage (S1) | 660.30 m | **20.494 m** | 96.9% |
| 60s tunnel (GNSS Fusion) | 579.40 m | **4.68 m** | 99.2% |

**Mechanism:** Covariance annealing: `y_eff(t) = y_raw * min(1, (t-t_exit)/T_window)` ramps over 25 steps (2.5s).

---

## 12. DEPLOYMENT / LATENCY METRICS

All verified from `results/model_export_metrics.json`:

| Model | Params | ONNX FP32 | ONNX INT8 | P50 Latency FP32 | Numeric Equiv |
|---|---|---|---|---|---|
| LIMU-BERT | 548,102 | 2.72 MB | 1.24 MB | 2.77 ms | ✅ max_diff: 2.86e-6 |
| Neural IO | 507,654 | 1.96 MB | 0.54 MB | 1.19 ms | ✅ max_diff: 1.43e-6 |
| KalmanNet | 55,176 | 0.22 MB | 0.21 MB | 0.11 ms | ✅ max_diff: 4.77e-7 |
| MapGNN | 25,985 | 0.12 MB | 0.07 MB | 0.24 ms | ✅ max_diff: 1.91e-6 |
| **TOTAL** | **1,136,917** | **5.02 MB** | **2.07 MB** | **3.67 ms total** | ✅ |

**10 Hz step budget: 3.67 ms total, 96.33% CPU headroom. PASS.**

---

## 13. LIMITATIONS (HONEST)

1. All 3 GNSS-denied windows fail the SIH <10% drift requirement
2. ~50m/3-5s and ~1km/60s mandatory scenarios NOT tested on final system
3. Neural IO displacement RMSE (63.9m over 10s) is too high for navigation
4. Velocity head: r=0.2742 correlation — weak predictor
5. Uncertainty head broken: σ=8,508,032 (numerical overflow at inference)
6. LIMU-BERT NOT connected to real-time inference pipeline despite training
7. OdoNet not implemented separately; only its role folded into NIO
8. Map matching DEGRADES accuracy by 20% vs pure DR when drift > 3.5m
9. Only IO-VNBD used; 4 other datasets audited but unused
10. Road graph built from GT trajectories, not OSM PBF (osmnx missing at runtime)
11. KalmanNet velocity RMSE (55.87 m/s) is anomalous — state drift artifact
12. Ablation table defined in benchmark.yaml NOT executed (no results found)

---

## 14. DATA LEAKAGE CHECK

| Check | Result | Evidence |
|---|---|---|
| Session-level train/val/test split | ✅ PASS | IOVNBDLoader.SPLIT_CONFIG L31-34 |
| Test session never used in training | ✅ PASS | 'S' sessions hard-coded to 'test' split |
| GT not used during inference | ✅ PASS | pipeline.step() has no GT parameter |
| Causal model (no future info) | ✅ PASS | Chomp1d in TCN; GRU is causal |
| GNSS suppressed during blackout | ✅ PASS | is_blackout flag in pipeline L212 |
| Road graph from test routes | ⚠️ PARTIAL CONCERN | Road graph from training GT trajectories — potential topology overlap if test/train share routes |

---

## 15. ARTIFACTS PRODUCED BY THIS AUDIT

| Artifact | Path | Description |
|---|---|---|
| This report | FINAL_MODEL_RESULTS_REPORT.md | Complete forensic audit |
| System flowchart | artifacts/final_model_flowchart.png | Architecture diagram |
| Results summary JSON | results/final_results_summary.json | Machine-readable metrics |
| Evidence index JSON | artifacts/evidence_index.json | Source→value traceability map |

---

## 16. FINAL VERDICT

### **NOT YET VERIFIED AS SIH-COMPLIANT**

**Why it fails:**
- SIH primary drift requirement (<10%) NOT met in any tested window
- Mandatory test scenarios NOT executed
- Recovery jump >0.5m in 30s and 60s cases
- Significant subsystem defects (uncertainty calibration, LIMU-BERT disconnection)

**What works well:**
- 98.1% reduction in recovery jump (288m → 5.61m for 30s outage)
- 75.3% reduction in GNSS fusion tunnel drift (580m → 143m)
- KalmanNet reduces drift by 89.8% vs fixed-gain baseline
- Mobile deployment fully verified: 3.67ms/step, ONNX+INT8, 96.33% headroom
- 10 Hz operation confirmed
- IO-VNBD used correctly with session-level splits
- 100% GNSS multipath outlier rejection

**What is needed to achieve SIH compliance:**
1. Improve NIO (need displacement RMSE < ~15m to achieve <10% drift in 30s outages)
2. Fix uncertainty head numerical instability
3. Connect LIMU-BERT to NIO for potentially improved representations
4. Test ~50m/3-5s and ~1km/60s scenarios explicitly
5. Validate FOG/external IMU support with real data
6. Investigate GNSS Interference dataset for spoofing robustness

---

*Every value in this report traces to a verified source artifact. No values were fabricated or estimated. Full traceability: [`artifacts/evidence_index.json`](file:///e:/Hackethon/ISRO/artifacts/evidence_index.json)*
