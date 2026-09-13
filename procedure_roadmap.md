# Procedure Roadmap — SIH 26168 Intelligent Dead Reckoning

## Complete Antigravity + Lightning AI + Notebook-First ML/Navigation Pipeline

> **Purpose:** This is the single master procedure for building the complete SIH PS 26168 solution from the beginning.
>
> **Core principle:** Develop and trace every model experimentally in Jupyter notebooks, train and evaluate on the remote Lightning AI GPU, integrate independently trained components through one final navigation pipeline, and produce honest SIH benchmark results from real held-out data.
>
> **Non-negotiable:** Do not skip instructions, fabricate evidence, hardcode desired results, or present synthetic data as official results.

---

# 1. PROJECT OBJECTIVE

Build a lightweight, edge-deployable Intelligent Dead Reckoning (IDR) system with GNSS fusion for:

- smartphone MEMS IMU navigation during GNSS blackout
- vehicle speed/velocity estimation from smartphone IMU
- IMU noise, vibration, pothole and shock handling
- automatic phone-to-vehicle alignment/calibration
- AI/ML-enhanced GNSS + INS fusion
- seamless GNSS → DR → GNSS+INS transitions
- vehicle Non-Holonomic Constraints (NHC)
- offline OSM-based map matching
- GNN-based road-network reasoning
- smartphone 10 Hz navigation output
- higher-rate edge processing, including approximately 200 Hz FOG IMU
- lightweight model export for mobile/edge deployment

SIH PS 26168 targets include:

- positional drift <10% of total distance during GNSS blackout
- example: <5 m over approximately 50 m GNSS-denied travel
- example: <100 m over approximately 1 km GNSS-denied travel at approximately 60 km/h
- GNSS+INS position update rate of 10 Hz on smartphone
- higher-rate edge deployment using approximately 200 Hz FOG IMU

The system must address:

- In-Vehicle Alignment & Calibration Engine
- AI Speed & Vibration Filter
- Advanced Map-Matching & Kinematic Constraints
- GNSS+INS Fusion Engine
- Seamless GNSS Deficit Handler
- Real-time Navigation Interface
- Edge-deployable software engine

---

# 2. OVERALL ARCHITECTURE

Use a **minimal high-performance hybrid architecture**. Do not add a separate model for every small subtask.

The selected core models are:

1. **LIMU-BERT** — self-supervised IMU representation learning/pretraining.
2. **TLIO-style Neural Inertial Odometry** — the main learned vehicle motion estimator; predict relative displacement/velocity and uncertainty from IMU history.
3. **Invariant ESKF/IEKF + KalmanNet** — physics-based state propagation plus learned/adaptive covariance/gain correction and GNSS fusion.
4. **Lightweight GNN map matcher** — local OSM road-graph reasoning only when map context is available.

OdoNet is **not a separate mandatory model**. Its useful velocity-estimation role is included as a velocity head in the neural inertial-odometry model. Likewise, a separate LIMU-GRU vehicle classifier is optional metadata support, not part of the minimum navigation-critical pipeline.

```text
                         REAL SENSOR DATA
                               │
                               ▼
                  IMU/GNSS Preprocessing
                               │
                               ▼
               Phone-to-Vehicle Alignment
                               │
                               ▼
                    LIMU-BERT Encoder
              (self-supervised IMU features)
                               │
                               ▼
             TLIO-STYLE NEURAL INERTIAL
                    ODOMETRY NETWORK
              ┌──────────┬───────────┐
              │ Δpose / │ velocity  │
              │ motion  │ + uncertainty
              └──────────┴───────────┘
                               │
                               ▼
                    Invariant ESKF/IEKF
                (physics state propagation)
                               │
                               ▼
                    KalmanNet Adaptation
               (learned gain/covariance logic)
                               │
               ┌───────────────┴────────────────┐
               │                                │
        GNSS available                    GNSS denied
               │                                │
        Robust GNSS fusion                 NHC/ZUPT
               │                                │
               └───────────────┬────────────────┘
                               ▼
                    Local OSM Candidate Graph
                               │
                               ▼
                   Lightweight GNN Matcher
                               │
                               ▼
                  Temporal/kinematic gating
                               │
                               ▼
                       FINAL POSE
                               │
                               ▼
                 Smooth GNSS Re-acquisition
```

## 2.1 Why these models and not more models?

The objective is **quality per model**, not model count.

- LIMU-BERT learns reusable temporal IMU features and reduces the burden on the final odometry network.
- TLIO-style neural odometry is the main learned motion estimator and directly models displacement/velocity uncertainty.
- Invariant ESKF/IEKF supplies the physically correct navigation state propagation.
- KalmanNet learns/adapts filtering behavior instead of relying on arbitrary fixed gains.
- GNN is used only for road-network reasoning; it does not replace the inertial estimator.

Avoid maintaining separate OdoNet + neural odometry + GRU classifier + multiple redundant fusion networks unless an ablation study proves a measurable benefit.

## 2.2 Navigation state

The core filter state should include, as supported by the data:

```text
position
velocity
orientation
accelerometer bias
gyroscope bias
state covariance / uncertainty
```

The learned components must provide uncertainty/confidence estimates so the filter can down-weight unreliable motion predictions.

## 2.3 Operating modes

```text
NORMAL GNSS
    ↓
GNSS QUALITY DEGRADING
    ↓
ANTICIPATORY / SOFT GNSS BLEND
    ↓
GNSS-DENIED DR
    ↓
GNSS REACQUISITION
    ↓
SMOOTH GNSS + INS HANDOVER
```

The transition must be continuous. Never snap the displayed position directly to the newly reacquired GNSS coordinate.

# 3. EXECUTION ENVIRONMENT

## 3.1 Local development

Use:

- Windows
- Google Antigravity IDE
- local project workspace

Antigravity is the development/agentic interface.

Use it for:

- editing code
- editing notebooks
- planning
- inspecting files
- executing remote tasks
- viewing live logs
- inspecting plots
- debugging
- comparing results
- documentation

## 3.2 Remote computation

Use:

- Lightning AI Studio
- remote GPU
- SSH/SCP

All heavy work MUST run remotely:

- dataset processing
- preprocessing
- feature extraction
- model training
- validation
- inference
- benchmark evaluation
- large-data plotting
- ONNX export
- ONNX inference
- GNN training
- final pipeline evaluation

Do not perform heavy ML computation on Windows.

Lightning is the compute environment; Antigravity is the development/agent control environment.

---

# 4. REMOTE CLOUD GPU EXECUTION PIPELINE

The project uses an automated headless remote execution pipeline.

Required files:

```text
.vscode/tasks.json
.vscode/sync_and_run.ps1
```

Workflow:

```text
LOCAL WINDOWS
      ↓
ANTIGRAVITY IDE
      ↓
Ctrl + Shift + B
      ↓
.vscode/tasks.json
      ↓
.vscode/sync_and_run.ps1
      ↓
SSH / SCP
      ↓
LIGHTNING AI GPU
      ↓
REMOTE EXECUTION
      ↓
LIVE TRAINING LOGS
      ↓
GENERATED ARTIFACTS
      ↓
SYNC BACK TO LOCAL
```

## 4.1 `Ctrl + Shift + B`

The build task must invoke:

```text
.vscode/sync_and_run.ps1
```

The PowerShell script must:

1. identify current workspace
2. synchronize required source code/configuration/notebooks
3. upload/synchronize them to Lightning using SSH/SCP
4. execute the requested notebook/task remotely
5. stream stdout/stderr and training logs live into Antigravity
6. wait for remote execution
7. synchronize generated artifacts back to local project
8. report success/failure clearly

Do not make this a fragile one-off command.

## 4.2 Never hardcode machine-specific information

Do NOT hardcode:

- Lightning hostname
- SSH username
- SSH private-key contents
- GPU ID
- GPU model
- CUDA version
- absolute Windows paths
- absolute Linux paths
- absolute dataset paths

Use SSH configuration, environment variables and project configuration.

The private SSH key must remain on Windows and must never be copied into:

- source code
- notebooks
- Git
- Lightning files
- logs
- committed configuration

---

# 5. DATASET LOCATION

All project datasets must remain under the local project's `data/` directory.

The current `data/` directory contains these five top-level dataset/resource folders:

```text
data/
├── GNSS Dataset (with Interference and Spoofing)/
├── IO-VNBD/
├── MOTOR/
├── NavICGNSS android raw measurements/
└── OSM/
```

## 5.1 Dataset roles

| Folder | Role in the project |
|---|---|
| `IO-VNBD/` | **Primary real vehicle dataset** for official inertial-odometry and SIH benchmarking, subject to schema/ground-truth validation. |
| `GNSS Dataset (with Interference and Spoofing)/` | GNSS interference/jamming/spoofing experiments and GNSS-quality/degradation detection, subject to documented schema validation. |
| `NavICGNSS android raw measurements/` | Android/NavIC raw GNSS measurement experiments and GNSS-side validation, subject to schema/timestamp/ground-truth validation. |
| `MOTOR/` | Additional real vehicle/motorcycle data source; use only after its sensor schema, timestamps, coordinate system and ground truth are audited. |
| `OSM/` | Offline OpenStreetMap/vector road data used to construct local road graphs for map matching. It is a map resource, not a training trajectory dataset. |

### 5.2 Dataset policy

- Do **not** merge these five folders into one anonymous dataset.
- Keep each source traceable to its original session/file.
- Build adapters for each validated dataset rather than rewriting raw data.
- `IO-VNBD` remains the primary dataset for official vehicle DR benchmarking unless the audit proves another real dataset is more appropriate for a particular SIH criterion.
- Additional datasets can be used for pretraining, robustness analysis, GNSS interference experiments, or supplementary validation only when their labels and coordinate/time systems are verified.
- Never use ground truth position/velocity/orientation as an input during GNSS-denied inference.
- Never replace missing real data with a synthetic trajectory for an official result.
- If a dataset cannot support a required metric because distance, duration, or ground truth is unavailable, report **NOT TESTED** rather than fabricating a result.
- Keep raw data immutable; store processed/cache files outside the raw source directories.

## 5.3 Required dataset manifest

Create:

```text
artifacts/
└── dataset_manifest.json
```

The manifest must record, for every dataset/session:

- source folder
- session/file identifier
- sensor types and sampling rates
- timestamp field and units
- coordinate system / frame
- available ground truth
- GNSS fields
- IMU fields
- vehicle metadata, if available
- valid duration and traveled distance
- missing-data statistics
- synchronization status
- parser/adapter version
- whether the session is eligible for train/validation/test
- reason for exclusion, if excluded

# 6. DATASET AUDIT

Before training, inspect the actual datasets.

Do not guess schemas.

Create:

```text
notebooks/01_dataset_audit.ipynb
artifacts/dataset_manifest.json
docs/dataset_audit.md
```

Record:

- dataset name
- source
- relative path
- files
- sessions
- sensors
- columns
- timestamps
- sampling frequency
- coordinate system
- ground truth
- GNSS availability
- IMU availability
- vehicle information
- synchronization
- missing values
- data quality
- usable portions
- split suitability

---

# 7. REAL-DATA RULE

Never replace real datasets with synthetic trajectories for official results.

Never:

- generate fake IO-VNBD
- create mathematical vehicle trajectories for official results
- create artificial routes for SIH claims
- present synthetic data as IO-VNBD

Synthetic data is allowed only as:

```text
SYNTHETIC_DEBUG_ONLY
```

for:

- unit tests
- debugging
- software validation

Never use it for:

- SIH performance
- IO-VNBD performance
- drift claims
- accuracy claims
- PASS/FAIL
- final results

---

# 8. GNSS OUTAGE SIMULATION

A GNSS blackout may be simulated by masking GNSS measurements from a REAL trajectory:

```text
REAL IMU
+
REAL trajectory
+
GNSS measurement mask
=
GNSS-denied evaluation
```

Do not generate a fake trajectory.

During GNSS-denied inference:

- no ground truth may be supplied to the model
- ground truth is available only to evaluation after inference
- only deployable measurements may be used

Do not select only the outage that gives the best result.

Use all qualifying windows or a deterministic predefined selection rule.

---

# 9. TRAIN / VALIDATION / TEST SPLIT

Use trajectory/session-level splitting.

Never randomly split adjacent samples from the same trajectory across train/test.

The final test set must remain unseen during:

- training
- hyperparameter tuning
- architecture selection
- threshold tuning
- model selection

Use validation data for decisions.

Use final test data only for final evaluation.

---

# 9A. HOW THE COMPLETE PIPELINE PROCEEDS

The implementation must proceed in this order:

```text
1. Audit all five data folders
        ↓
2. Validate schemas, timestamps, frames and ground truth
        ↓
3. Create session-level train/val/test splits
        ↓
4. Build common preprocessing + phone alignment
        ↓
5. Pretrain LIMU-BERT on allowed real IMU data
        ↓
6. Freeze/use LIMU-BERT features and train TLIO-style
   neural inertial odometry
        ↓
7. Validate neural odometry independently
        ↓
8. Build invariant ESKF/IEKF baseline
        ↓
9. Train KalmanNet against filter innovations/residuals
        ↓
10. Validate ESKF/IEKF + KalmanNet independently
        ↓
11. Add NHC/ZUPT/kinematic constraints
        ↓
12. Add robust GNSS fusion and smooth recovery
        ↓
13. Build local OSM road graphs
        ↓
14. Train/test lightweight GNN map matcher
        ↓
15. Run map-matching ablations
        ↓
16. Connect all independently tested modules
        ↓
17. Run complete end-to-end integration on held-out sessions
        ↓
18. Run SIH blackout scenarios of different durations/distances
        ↓
19. Measure drift, absolute error and recovery jump
        ↓
20. Export the verified pipeline for mobile/edge inference
```

### Critical rule

Do not train the complete pipeline end-to-end first and then claim that every component works. Each model/component must first pass its own independent test notebook. Only then is it allowed into the final integration.

### Minimum navigation-critical model set

```text
LIMU-BERT
    +
TLIO-style Neural Inertial Odometry
    +
Invariant ESKF/IEKF
    +
KalmanNet
    +
NHC/ZUPT constraints
    +
Robust GNSS fusion
    +
Lightweight OSM-GNN map matching
```

This is the **minimum selected stack**. Any additional learned model requires an ablation-based justification.

# 10. NOTEBOOK-FIRST DEVELOPMENT

All model development, training, validation and testing must be notebook-first.

Use `.ipynb` for:

- model training
- model testing
- dataset inspection
- preprocessing exploration
- visualization
- ablation
- integration experiments
- final benchmark
- error analysis
- export validation

Goal: complete traceability.

Do not hide the complete training/testing workflow inside opaque scripts.

---

# 11. REQUIRED NOTEBOOKS

Use approximately:

```text
notebooks/
├── 00_environment_gpu.ipynb
├── 01_dataset_audit.ipynb
├── 02_preprocessing.ipynb
├── 03_phone_alignment.ipynb
├── 04_eskf_baseline.ipynb
│
├── 05_limu_bert_training.ipynb
├── 06_limu_bert_testing.ipynb
│
├── 07_odo_net_training.ipynb
├── 08_odo_net_testing.ipynb
│
├── 09_inertial_odometry_training.ipynb
├── 10_inertial_odometry_testing.ipynb
│
├── 11_kalmannet_training.ipynb
├── 12_kalmannet_testing.ipynb
│
├── 13_vehicle_constraints.ipynb
├── 14_gnss_fusion.ipynb
│
├── 15_osm_graph_generation.ipynb
│
├── 16_map_gnn_training.ipynb
├── 17_map_gnn_testing.ipynb
├── 18_map_matching_visualization.ipynb
│
├── 19_ablation_study.ipynb
├── 20_final_pipeline_integration.ipynb
├── 21_final_sih_benchmark.ipynb
├── 22_error_analysis.ipynb
└── 23_model_export_and_mobile_validation.ipynb
```

Each notebook should contain clear Markdown sections:

1. Environment
2. Configuration
3. Dataset Loading
4. Dataset Inspection
5. Preprocessing
6. Feature Preparation
7. Model Definition
8. Training
9. Validation
10. Visualization
11. Evaluation
12. Error Analysis
13. Checkpoint Saving
14. Conclusions

Prefer:

```text
Kernel Restart
     ↓
Run All
     ↓
Complete Result
```

Avoid hidden state.

---

# 12. NOTEBOOK EXECUTION ON LIGHTNING

Training/testing notebooks must execute on the remote Lightning GPU.

Use, where appropriate:

```text
jupyter nbconvert --execute
```

or:

```text
papermill
```

The executed notebook must preserve outputs.

Flow:

```text
.ipynb
 ↓
SSH/SCP sync
 ↓
Lightning GPU
 ↓
remote notebook execution
 ↓
executed .ipynb
 ↓
checkpoint + plots + metrics + logs
 ↓
sync back to local
```

---

# 13. GPU PREFLIGHT

Create:

```text
notebooks/00_environment_gpu.ipynb
scripts/gpu_preflight.sh
```

Verify:

```text
hostname
pwd
which python
python --version
nvidia-smi
GPU name
GPU VRAM
number of GPUs
CUDA availability
PyTorch CUDA availability
CUDA version
cuDNN availability
ONNX Runtime providers
```

For GPU training:

```text
torch.cuda.is_available() == True
```

If unavailable:

```text
STOP
```

Never silently fall back to CPU.

---

# 14. ONNX GPU VALIDATION

For ONNX inference verify:

```text
CUDAExecutionProvider
```

is available.

If only:

```text
CPUExecutionProvider
```

is available:

- stop official GPU inference benchmark
- configure/fix compatible GPU runtime
- or use another verified GPU backend

Never call CPU inference a GPU benchmark.

Every official GPU inference run must report the actual provider.

---

# 15. PROJECT STRUCTURE

Use:

```text
project/
│
├── data/
├── notebooks/
├── src/
│   ├── datasets/
│   ├── preprocessing/
│   ├── models/
│   │   ├── limu_bert.py
│   │   ├── odonet.py
│   │   ├── inertial_odometry.py
│   │   ├── kalmannet.py
│   │   └── map_gnn.py
│   ├── filters/
│   │   ├── invariant_eskf.py
│   │   └── gnss_fusion.py
│   ├── calibration/
│   │   └── alignment.py
│   ├── constraints/
│   │   └── nhc.py
│   ├── map_matching/
│   │   └── map_matcher.py
│   └── integration/
│       └── final_navigation_pipeline.py
│
├── training/
├── evaluation/
├── configs/
│   ├── paths.yaml
│   ├── runtime.yaml
│   ├── training.yaml
│   └── benchmark.yaml
├── checkpoints/
│   ├── limu_bert/
│   ├── odonet/
│   ├── inertial_odometry/
│   ├── kalmannet/
│   └── map_gnn/
├── results/
├── plots/
├── logs/
├── artifacts/
├── scripts/
│   ├── gpu_preflight.sh
│   ├── audit_dataset.sh
│   ├── train_all.sh
│   ├── benchmark.sh
│   └── run_pipeline.sh
├── .vscode/
│   ├── tasks.json
│   └── sync_and_run.ps1
└── PROJECT_RULES.md
```

---

# 16. MODEL 1 — LIMU-BERT

Create:

```text
src/models/limu_bert.py
notebooks/05_limu_bert_training.ipynb
notebooks/06_limu_bert_testing.ipynb
```

Use LIMU-BERT-style self-supervised IMU pretraining for temporal IMU representations.

Do not make it directly responsible for final navigation position unless experiments prove it useful.

Save:

```text
checkpoints/limu_bert/
```

Training notebook must show:

- data
- preprocessing
- model
- training progress
- loss
- validation
- checkpoint
- configuration

Testing notebook must load the saved checkpoint and evaluate held-out data.

---

# 17. MODEL 2 — ODONET

Create:

```text
src/models/odonet.py
notebooks/07_odo_net_training.ipynb
notebooks/08_odo_net_testing.ipynb
```

OdoNet estimates vehicle forward velocity from smartphone IMU.

Prefer outputs:

- forward velocity
- confidence/uncertainty

OdoNet is not the complete navigation solution.

Save:

```text
checkpoints/odonet/
```

---

# 18. MODEL 3 — NEURAL INERTIAL ODOMETRY

Create:

```text
src/models/inertial_odometry.py
notebooks/09_inertial_odometry_training.ipynb
notebooks/10_inertial_odometry_testing.ipynb
```

Build a lightweight TLIO/EqNIO-inspired neural inertial odometry model.

Predict where appropriate:

1. relative displacement
2. velocity
3. uncertainty/covariance
4. IMU bias-related corrections
5. confidence/motion quality

Start with:

```text
TCN / ResNet-style temporal encoder
```

Only investigate a Transformer if it improves accuracy without making mobile inference impractical.

Save:

```text
checkpoints/inertial_odometry/
```

---

# 19. MODEL 4 — KALMANNET

Create:

```text
src/models/kalmannet.py
notebooks/11_kalmannet_training.ipynb
notebooks/12_kalmannet_testing.ipynb
```

Use KalmanNet/PC-KalmanNet-style learning for adaptive filtering.

It should adapt:

- covariance
- measurement confidence
- filtering gain
- uncertainty

Do not use KalmanNet as an arbitrary final position correction.

Do not use an arbitrary fixed gain such as:

```text
k_gain = 0.80
```

unless explicitly justified and configurable.

Save:

```text
checkpoints/kalmannet/
```

---

# 20. CLASSICAL PHYSICS FILTER

Create:

```text
src/filters/invariant_eskf.py
notebooks/04_eskf_baseline.ipynb
```

Implement an Invariant Error-State Kalman Filter / IEKF/ESKF-style estimator.

Appropriate state variables may include:

- position
- velocity
- orientation
- accelerometer bias
- gyroscope bias
- uncertainty

Use a strong classical baseline before neural fusion.

---

# 21. PHONE ALIGNMENT / CALIBRATION

Create:

```text
src/calibration/alignment.py
notebooks/03_phone_alignment.ipynb
```

Estimate:

- pitch
- roll
- yaw relative to vehicle travel direction

Support:

- dashboard mounting
- phone holder
- rotated phone

Do not assume perfect alignment.

Test calibration independently.

---

# 22. VEHICLE NHC CONSTRAINTS

Create:

```text
src/constraints/nhc.py
notebooks/13_vehicle_constraints.ipynb
```

Implement appropriate:

- non-holonomic constraint
- lateral velocity approximately zero
- vertical velocity approximately zero
- valid low-speed/ZUPT constraints where appropriate

Do not apply invalid vehicle assumptions.

Keep this module independent for ablation.

---

# 23. ROBUST GNSS FUSION

Create:

```text
src/filters/gnss_fusion.py
notebooks/14_gnss_fusion.ipynb
```

Implement:

- innovation gating
- GNSS outlier rejection
- adaptive GNSS weighting
- GNSS quality/confidence
- smooth recovery

Support:

```text
GNSS + INS
      ↓
GNSS blackout
      ↓
Dead Reckoning
      ↓
GNSS recovery
      ↓
GNSS + INS
```

Do not use an arbitrary fixed gain.

---

# 24. GNN-BASED OFFLINE MAP MATCHING

Create:

```text
src/models/map_gnn.py
notebooks/16_map_gnn_training.ipynb
notebooks/17_map_gnn_testing.ipynb
notebooks/18_map_matching_visualization.ipynb
```

The GNN is an independent model.

Its purpose is to answer:

> Given the current navigation estimate and local road graph, which road/path is most likely?

It must not simply learn:

```text
GPS coordinate → road ID
```

It should reason using:

- topology
- geometry
- heading
- velocity
- uncertainty
- temporal context

---

# 25. OFFLINE OSM ROAD GRAPH

Create:

```text
notebooks/15_osm_graph_generation.ipynb
```

Use offline OpenStreetMap or another validated offline road source.

Possible nodes:

- intersections
- road geometry points
- important road vertices

Possible edges:

- road segments

Possible features:

- coordinates
- road type
- intersection information
- road density
- length
- heading
- curvature
- connectivity
- directionality
- speed information if valid

Do not assume OSM fields exist.

Inspect actual data.

---

# 26. LOCAL GRAPH ONLY

Do not load the entire world road graph for every inference.

Use:

```text
ESKF predicted position
        ↓
nearby OSM road retrieval
        ↓
candidate road segments
        ↓
local graph
        ↓
GNN
```

Local graph radius must be configurable and validated.

---

# 27. GNN INPUTS

Potential query features:

- predicted inertial position
- position uncertainty
- heading
- heading uncertainty
- velocity
- acceleration
- predicted displacement
- ESKF state
- KalmanNet confidence
- previous matched road

Candidate road features may include:

- distance
- heading difference
- road direction
- segment length
- curvature
- connectivity
- road type

Use feature ablation.

---

# 28. GNN TRAINING LABELS

Ground truth may be used during TRAINING to generate road labels:

```text
REAL ground-truth trajectory
        ↓
project onto road network
        ↓
ground-truth road segment
        ↓
training label
```

During GNSS-denied inference:

**ground truth must never be supplied to the GNN.**

Only deployable information may be used.

---

# 29. GNN TEMPORAL REASONING

Do not independently match every frame.

Prefer:

```text
previous road
      ↓
connected road
      ↓
next plausible road
```

Consider:

- previous matched segment
- graph connectivity
- heading
- velocity
- expected travel distance
- transition probability

A lightweight HMM/Viterbi-style layer may be combined with the GNN.

Compare:

```text
GNN only
```

versus:

```text
GNN + temporal path reasoning
```

---

# 30. GNN TESTING

Evaluate:

- road-segment classification accuracy
- top-1 accuracy
- top-3 accuracy
- candidate ranking quality
- distance from selected road to ground truth
- heading consistency
- temporal consistency
- map-matching failure rate

Visualize:

- ground truth road
- inertial trajectory
- candidate roads
- selected road
- GNN confidence
- final matched trajectory

---

# 31. MAP-MATCHING ABLATION

Evaluate separately:

```text
A. No map matching
B. Classical geometric map matching
C. GNN map matching
D. GNN + temporal graph reasoning
E. GNN + temporal reasoning + vehicle constraints
```

Compare:

- DR drift
- final position error
- P95 error
- maximum error
- road-selection accuracy
- recovery behavior

Do not claim improvement without measured evidence.

---

# 32. DO NOT HIDE DR PERFORMANCE WITH MAP MATCHING

Always report:

```text
PURE DR
DR + NHC
DR + GNN MAP MATCHING
COMPLETE SYSTEM
```

Never show only the best map-matched result.

---

# 33. FINAL INTEGRATION

Create:

```text
src/integration/final_navigation_pipeline.py
notebooks/20_final_pipeline_integration.ipynb
```

The Python file is the reusable inference/orchestration engine.

The notebook is the traceable development and validation environment.

Load independently trained checkpoints:

```text
LIMU-BERT
OdoNet
Neural Inertial Odometry
KalmanNet
GNN
```

Connect:

```text
Preprocessing
 ↓
Phone Alignment
 ↓
LIMU-BERT representation
 ↓
Neural Inertial Odometry
 ↓
OdoNet velocity
 ↓
Bias estimation
 ↓
Invariant ESKF
 ↓
KalmanNet
 ↓
NHC
 ↓
Robust GNSS Fusion
 ↓
GNN Map Matching
 ↓
Temporal Path Reasoning
 ↓
Final Navigation State
```

Do not retrain models during integration.

Load saved checkpoints.

---

# 34. FINAL PIPELINE API

Provide a clean API such as:

```text
initialize()
process_imu()
process_gnss()
process_magnetometer()
update()
get_navigation_state()
```

State should contain where available:

- latitude
- longitude
- local x/y
- velocity
- heading
- mode
- uncertainty
- GNSS availability
- confidence
- matched road
- map confidence

Possible modes:

```text
GNSS_INS
DEAD_RECKONING
GNSS_RECOVERY
```

Keep transitions configurable and evidence-based.

---

# 35. INDEPENDENT MODEL TRAINING

Each model must have its own training notebook and testing notebook.

Examples:

```text
05_limu_bert_training.ipynb
06_limu_bert_testing.ipynb

07_odo_net_training.ipynb
08_odo_net_testing.ipynb

09_inertial_odometry_training.ipynb
10_inertial_odometry_testing.ipynb

11_kalmannet_training.ipynb
12_kalmannet_testing.ipynb

16_map_gnn_training.ipynb
17_map_gnn_testing.ipynb
```

Each model is independently:

- trained
- validated
- checkpointed
- tested
- documented

Do not require every model to retrain every time.

---

# 36. CHECKPOINT HANDOFF

Training notebooks save checkpoints; testing notebooks load them.

Examples:

```text
LIMU-BERT:
training notebook
 ↓
checkpoints/limu_bert/
 ↓
testing notebook
```

```text
OdoNet:
training notebook
 ↓
checkpoints/odonet/
 ↓
testing notebook
```

```text
Inertial odometry:
training notebook
 ↓
checkpoints/inertial_odometry/
 ↓
testing notebook
```

```text
KalmanNet:
training notebook
 ↓
checkpoints/kalmannet/
 ↓
testing notebook
```

```text
GNN:
training notebook
 ↓
checkpoints/map_gnn/
 ↓
testing notebook
```

Testing must load actual checkpoints and must not silently retrain.

---

# 37. TRAINING PROGRESS VISIBILITY

Every training notebook must visibly show:

- dataset size
- train sample count
- validation sample count
- batch size
- epochs
- learning rate
- optimizer
- scheduler
- parameter count
- GPU memory where practical
- training loss
- validation loss
- learning curves
- best epoch
- best validation metric

Save plots to:

```text
plots/<model_name>/
```

---

# 38. DATA VISUALIZATION

Before training, visualize relevant data:

- accelerometer
- gyroscope
- velocity
- GNSS trajectory
- ground truth
- sensor noise
- vibration
- missing values
- timestamp intervals
- coordinate transformations
- phone orientation
- heading

Do not alter data just to make plots look better.

---

# 39. FINAL SIH BENCHMARK

Create:

```text
notebooks/21_final_sih_benchmark.ipynb
```

Sections:

1. dataset/session selection
2. benchmark protocol
3. GNSS outage creation by masking real GNSS
4. model loading
5. DR inference
6. GNSS+INS inference
7. NHC
8. map matching
9. recovery
10. metrics
11. SIH requirement comparison
12. plots
13. error analysis
14. conclusion

---

# 40. NO HARDCODED BENCHMARK WINDOW

Do not hardcode one outage such as:

```text
85–130 seconds
```

as the official benchmark.

Discover qualifying real windows from held-out real data.

Evaluate multiple durations where supported:

- approximately 3–5 seconds
- approximately 10 seconds
- approximately 20 seconds
- approximately 30 seconds
- approximately 45 seconds
- approximately 60 seconds

Also evaluate:

- approximately 50 m
- approximately 1 km

If unsupported:

```text
NOT TESTED — INSUFFICIENT REAL DATA
```

Never fabricate a trajectory.

---

# 41. SIH METRICS

Calculate from actual ground truth after inference:

- travelled distance
- outage duration
- final position error
- maximum position error
- RMSE
- P95 error
- drift percentage
- velocity error
- heading error
- recovery discontinuity/jump
- recovery time
- trajectory error

Clearly define the drift metric.

Never hardcode results.

Never hardcode PASS.

Never hardcode FAIL.

---

# 42. RECOVERY TEST

Explicitly evaluate:

```text
GNSS available
      ↓
GNSS blackout
      ↓
Dead Reckoning
      ↓
GNSS returns
      ↓
GNSS + INS
```

Measure:

- instantaneous position jump
- velocity discontinuity
- heading discontinuity
- recovery time
- post-recovery error

Do not claim seamless recovery without measurement.

---

# 43. FINAL BENCHMARK VISUALIZATION

Generate:

1. ground truth trajectory
2. GNSS trajectory
3. pure DR trajectory
4. GNSS+INS trajectory
5. DR + NHC trajectory
6. DR + map matching trajectory
7. complete proposed system trajectory

Also generate:

- position error vs time
- position error vs distance
- error CDF
- velocity error
- heading error
- recovery jump
- GNSS outage interval
- uncertainty/confidence

Save under:

```text
plots/final_benchmark/
```

---

# 44. ABLATION STUDY

Create:

```text
notebooks/19_ablation_study.ipynb
```

Evaluate:

```text
Baseline:
Classical ESKF

Experiment 1:
OdoNet + ESKF

Experiment 2:
LIMU-BERT + OdoNet + ESKF

Experiment 3:
Neural Inertial Odometry + ESKF

Experiment 4:
Neural Inertial Odometry + OdoNet + ESKF + KalmanNet

Experiment 5:
+ Vehicle Constraints

Experiment 6:
+ Robust GNSS Fusion

Experiment 7:
+ GNN Map Matching

Final:
Complete Proposed System
```

Use validation data for model selection.

Do not use final test data for architecture selection.

---

# 45. COMPUTATIONAL / MOBILE REQUIREMENTS

Track:

- parameter count
- model size
- latency
- memory
- FLOPs where available
- inference frequency
- CPU latency
- GPU latency
- export compatibility

Target:

```text
Android smartphone
+
edge software engine
```

Keep the final system lightweight.

Do not use huge models solely to improve offline metrics.

---

# 46. MULTI-RATE DESIGN

## Smartphone

Support:

- smartphone IMU
- approximately 100/200 Hz raw IMU where available
- 10 Hz navigation output

## Edge

Support:

- approximately 200 Hz FOG IMU
- higher-rate processing/output

Use a common navigation core with rate-specific adapters/configuration.

---

# 47. GNN MOBILE DESIGN

The final map matcher must not require a huge graph in memory.

Use:

```text
local graph
+
candidate pruning
+
lightweight GNN
+
small temporal state
```

Investigate:

- ONNX
- TorchScript
- TensorFlow Lite where appropriate

Choose export format after compatibility testing.

Measure actual inference latency.

---

# 48. CONFIGURATION RULES

Do not hardcode configuration inside Python.

Use:

```text
configs/paths.yaml
configs/runtime.yaml
configs/training.yaml
configs/benchmark.yaml
```

Use relative paths and/or environment variables.

Logical dataset root:

```text
data/
```

but individual datasets must be discovered/validated.

SIH thresholds should be transparent configuration values, not hidden in benchmark code.

---

# 49. CTRL+SHIFT+B STAGES

Ctrl+Shift+B is a pipeline controller, not an automatic full retraining command.

Support:

```text
--preflight
--audit
--preprocess
--train-limu
--test-limu
--train-odo
--test-odo
--train-inertial
--test-inertial
--train-kalmannet
--test-kalmannet
--train-map-gnn
--test-map-gnn
--integration
--benchmark
--export
--full
```

Do not make every Ctrl+Shift+B press retrain every model.

---

# 50. LONG TRAINING / TMUX

Long training should support persistent remote sessions.

Example:

```text
tmux new -s sih-training
```

Run training/notebook execution inside the session.

Detach:

```text
Ctrl+B
D
```

Reattach:

```text
tmux attach -t sih-training
```

Training logs and checkpoints must remain on persistent Lightning storage.

The sync engine must not unnecessarily terminate a remote training process because the IDE disconnects.

---

# 51. SYNC POLICY

## Source files

```text
LOCAL
 ↓
REMOTE LIGHTNING
```

Synchronize:

- source code
- notebooks
- configuration
- scripts required for the requested task

## Generated artifacts

```text
REMOTE LIGHTNING
 ↓
LOCAL
```

Automatically sync newly generated:

- `.pth`
- `.pt`
- `.ckpt`
- `.onnx`
- `.json`
- `.csv`
- `.png`
- `.jpg`
- `.pdf`
- executed `.ipynb`
- logs
- benchmark reports

Do not blindly sync massive temporary files.

Do not overwrite important checkpoints without preserving versions.

---

# 52. DATASET SYNC POLICY

Datasets are large.

Do NOT upload all datasets every time Ctrl+Shift+B is pressed.

Preferred behavior:

First run:

```text
data/
 ↓
Lightning persistent storage
```

Later runs:

```text
reuse remote dataset
```

Only synchronize dataset changes when necessary.

The `data/` folder remains the logical project dataset root.

---

# 53. CHECKPOINT VERSIONING

Use:

```text
checkpoints/
├── limu_bert/
│   ├── experiment_001/
│   └── experiment_002/
├── odonet/
│   └── experiment_001/
├── inertial_odometry/
│   └── experiment_001/
├── kalmannet/
│   └── experiment_001/
└── map_gnn/
    └── experiment_001/
```

Before overwriting:

- preserve previous checkpoint
- record experiment ID
- record configuration
- record validation result

Never silently replace the best model.

---

# 54. EXPERIMENT TRACEABILITY

Every remote run must record:

- date/time
- experiment ID
- source/Git version if available
- notebook name
- dataset version
- configuration
- random seed
- GPU
- software versions
- training parameters
- checkpoint
- metrics
- result paths

Store information in:

```text
artifacts/
logs/
results/
```

The final result must be traceable to the exact notebook, dataset, configuration and checkpoint.

---

# 55. NOTEBOOK OUTPUT STORAGE

Important outputs must not exist only in temporary notebook state.

Save:

```text
results/
├── limu_bert_results.json
├── odonet_results.json
├── inertial_odometry_results.json
├── kalmannet_results.json
├── map_gnn_results.json
├── ablation_results.json
└── final_results.json
```

Preserve meaningful notebook outputs.

---

# 56. MODEL EXPORT

Create:

```text
notebooks/23_model_export_and_mobile_validation.ipynb
```

Export neural models to an appropriate edge format.

Validate:

- numerical consistency
- latency
- memory
- output shapes
- model size
- execution provider
- mobile compatibility

Compare exported model outputs against the original model.

Never assume export works without testing.

---

# 57. FINAL REPORT

Generate:

```text
results/
├── final_results.json
├── final_results.csv
└── final_report.md
```

Separate:

1. training data
2. validation data
3. final test data
4. pure DR
5. GNSS+INS
6. NHC
7. GNN map matching
8. complete system
9. recovery
10. computational performance

For each SIH requirement:

```text
REQUIREMENT
ACTUAL RESULT
THRESHOLD
NUMBER OF TESTS
PASS / FAIL / NOT TESTED
```

If unsupported:

```text
NOT TESTED — INSUFFICIENT REAL DATA
```

Never hide failures.

---

# 58.1 FINAL MODEL SELECTION — KEEP THE STACK SMALL

For the final SIH system, do not combine multiple competing models simply because they exist.

**Selected models:**

| Function | Selected model | Status |
|---|---|---|
| IMU representation | LIMU-BERT | Core |
| Learned inertial motion | TLIO-style neural inertial odometry | Core |
| Physical state propagation | Invariant ESKF/IEKF | Core |
| Adaptive filtering | KalmanNet | Core |
| Vehicle constraints | NHC + ZUPT where valid | Non-neural |
| GNSS fusion | Robust innovation-gated filter fusion | Non-neural + KalmanNet |
| Offline map matching | Lightweight GraphSAGE/GATv2-style GNN | Core only when map context exists |
| Separate OdoNet | Not required | Fold velocity into odometry head |
| Separate vehicle-class GRU | Optional | Only if data/ablation proves useful |

**Decision rule:** a model enters the final pipeline only if its independent held-out test shows a useful improvement in accuracy, robustness, uncertainty calibration, latency, or recovery behavior that justifies its compute and complexity.

# 58. TRAINING STRATEGY

Use:

- GPU training
- mixed precision when safe
- efficient data loaders
- pinned memory where useful
- suitable worker count
- checkpointing
- validation monitoring
- reproducible seeds

Automatically detect GPU capabilities.

Do not hardcode:

- CUDA device index
- GPU model
- batch size solely for one GPU
- absolute filesystem path

Detect and log configuration.

---

# 59. ERROR ANALYSIS

Create:

```text
notebooks/22_error_analysis.ipynb
```

If the system fails a requirement, diagnose:

- velocity error
- heading error
- IMU bias
- vibration
- phone misalignment
- filter instability
- GNSS outlier
- map-matching error
- temporal graph failure
- neural-model limitation

Do not immediately replace the entire architecture.

Use evidence from ablation/error analysis.

---

# 60. ANTIGRAVITY AGENT WORKFLOW

Use Antigravity's agentic capabilities intelligently.

Do not build and execute everything in one uncontrolled step.

Use:

```text
PLAN
 ↓
INSPECT
 ↓
IMPLEMENT
 ↓
TEST
 ↓
VERIFY
 ↓
DOCUMENT
 ↓
NEXT PHASE
```

Use separate tasks/subtasks for:

- dataset
- preprocessing
- LIMU-BERT
- OdoNet
- inertial odometry
- KalmanNet
- ESKF
- constraints
- GNSS fusion
- OSM
- GNN
- integration
- benchmark
- deployment

Do not start expensive training while architecture is still being modified.

---

# 61. PROJECT RULES

Create:

```text
PROJECT_RULES.md
```

It must explicitly prohibit:

- synthetic official results
- synthetic IO-VNBD replacement
- hardcoded benchmark windows
- hardcoded benchmark results
- hardcoded PASS/FAIL
- test-set tuning
- ground-truth use during GNSS-denied inference
- CPU fallback during official GPU runs
- unverified ONNX GPU claims
- dataset schema guessing
- checkpoint destruction
- hidden experiment state
- reporting only the best map-matched result

---

# 62. FIRST ACTION — DO NOT TRAIN

When this roadmap is first given to Antigravity:

DO NOT start training.

DO NOT create synthetic data.

DO NOT modify the model architecture.

DO NOT run the official benchmark.

Perform ONLY the initial audit.

Inspect:

1. remote Lightning GPU
2. Python environment
3. repository
4. `data/`
5. IO-VNBD
6. additional datasets
7. schemas
8. timestamps
9. sensors
10. ground truth
11. existing code
12. dependencies
13. existing checkpoints
14. existing benchmark code
15. `.vscode/tasks.json`
16. `.vscode/sync_and_run.ps1`

Produce:

A. GPU audit
B. Python audit
C. dataset audit
D. dataset compatibility report
E. current repository architecture
F. current remote-sync architecture
G. real vs synthetic data status
H. train/validation/test strategy
I. model-by-model training plan
J. GNN/map-matching plan
K. final integration plan
L. benchmark plan
M. deployment plan
N. risks
O. files to create/change

STOP after the audit.

Wait for the next instruction before implementation.

---

# 63. COMPLETE PROCEDURE

Follow this order:

```text
STEP 1
Create Lightning AI Studio
        ↓
STEP 2
Connect Windows to Lightning using SSH
        ↓
STEP 3
Connect Antigravity to remote SSH workspace
        ↓
STEP 4
Verify hostname/GPU/CUDA from Antigravity terminal
        ↓
STEP 5
Create project structure
        ↓
STEP 6
Place all datasets under data/
        ↓
STEP 7
Configure .vscode/tasks.json
        ↓
STEP 8
Configure .vscode/sync_and_run.ps1
        ↓
STEP 9
Run GPU preflight
        ↓
STEP 10
Run dataset audit
        ↓
STEP 11
Build preprocessing
        ↓
STEP 12
Build ESKF baseline
        ↓
STEP 13
Train LIMU-BERT
        ↓
STEP 14
Test LIMU-BERT
        ↓
STEP 15
Train OdoNet
        ↓
STEP 16
Test OdoNet
        ↓
STEP 17
Train Neural Inertial Odometry
        ↓
STEP 18
Test Neural Inertial Odometry
        ↓
STEP 19
Train KalmanNet
        ↓
STEP 20
Test KalmanNet
        ↓
STEP 21
Implement phone alignment
        ↓
STEP 22
Implement NHC
        ↓
STEP 23
Implement robust GNSS fusion
        ↓
STEP 24
Generate offline OSM graph
        ↓
STEP 25
Train GNN map matcher
        ↓
STEP 26
Test GNN map matcher
        ↓
STEP 27
Perform map-matching visualization
        ↓
STEP 28
Perform ablation study
        ↓
STEP 29
Build final_navigation_pipeline.py
        ↓
STEP 30
Validate final integration notebook
        ↓
STEP 31
Run final SIH benchmark
        ↓
STEP 32
Perform error analysis
        ↓
STEP 33
Export lightweight models
        ↓
STEP 34
Validate edge/mobile inference
        ↓
STEP 35
Prepare final SIH report and plots
```

---

# 64. FINAL DAILY WORKFLOW

Once configured:

```text
Windows
   │
   ▼
Antigravity IDE
   │
   │ Ctrl + Shift + B
   ▼
.vscode/tasks.json
   │
   ▼
.vscode/sync_and_run.ps1
   │
   │ SSH/SCP
   ▼
Lightning AI Studio
   │
   ├── data/
   ├── GPU
   ├── notebooks/
   ├── checkpoints/
   ├── logs/
   └── results/
   │
   ▼
Remote notebook execution
   │
   ▼
Live logs → Antigravity terminal
   │
   ▼
Artifacts sync back
   │
   ▼
Local notebook/results inspection
```

---

# 65. FINAL NON-NEGOTIABLE PRINCIPLES

1. Real IO-VNBD data for official preliminary evaluation.
2. All datasets live logically under `data/`.
3. No synthetic official trajectories.
4. GNSS blackout simulation may mask GNSS from real trajectories.
5. No ground truth during GNSS-denied inference.
6. Session/trajectory-level splits.
7. Final test set remains untouched.
8. Each model has its own `.ipynb` training notebook.
9. Each model has its own `.ipynb` testing notebook.
10. Each model has its own checkpoint.
11. GNN has its own training/testing notebooks.
12. Final integration uses one reusable Python pipeline file.
13. Final integration is developed/validated in a notebook.
14. All heavy computation runs on Lightning GPU.
15. Antigravity controls development and remote execution.
16. Ctrl+Shift+B triggers remote sync/run workflow.
17. Datasets are not repeatedly uploaded on every run.
18. Generated checkpoints, plots, metrics and executed notebooks sync back.
19. Long jobs support tmux/persistent remote execution.
20. GPU usage is explicitly verified.
21. ONNX CUDA provider is explicitly verified.
22. No silent CPU fallback.
23. No hardcoded GPU/path/host values.
24. No hardcoded outage window.
25. No hardcoded benchmark results.
26. No hardcoded PASS/FAIL.
27. Pure DR results remain visible.
28. NHC and GNN improvements are separately reported.
29. Recovery jump is explicitly measured.
30. Unsupported tests are reported as NOT TESTED.
31. Mobile/edge constraints are measured.
32. Failed experiments are not hidden.
33. Every experiment is traceable.
34. Final results are based on actual held-out data.
35. Never optimize the benchmark to make the project pass; optimize the system and let the benchmark determine PASS/FAIL.

---

# 66. MASTER SUCCESS CRITERION

The project is ready only when:

```text
REAL DATA
   +
REPRODUCIBLE TRAINING
   +
INDEPENDENT MODEL CHECKPOINTS
   +
VALIDATED FINAL INTEGRATION
   +
REAL HELD-OUT TESTING
   +
SIH METRIC CALCULATION
   +
RECOVERY TEST
   +
MOBILE/EDGE PERFORMANCE
   +
TRACEABLE NOTEBOOKS
   +
REMOTE GPU REPRODUCIBILITY
   =
FINAL SIH-READY SYSTEM
```

Do not declare success merely because a model trains.

Do not declare SIH compliance until the complete final benchmark produces actual measured evidence.


# 67. CURRENT DATA DIRECTORY SNAPSHOT

The current project data directory snapshot supplied during roadmap revision shows exactly these five top-level folders:

```text
data/
├── GNSS Dataset (with Interference and Spoofing)
├── IO-VNBD
├── MOTOR
├── NavICGNSS android raw measurements
└── OSM
```

This folder listing establishes the available top-level sources/resources, but it does **not** by itself establish their internal file schemas, sampling rates, ground-truth quality, or eligibility for a specific benchmark. Those facts must be established by the dataset-audit notebooks before training/evaluation.

# 68. FINAL END-TO-END PIPELINE SUMMARY

```text
DATA/
  ├── IO-VNBD                         ─┐
  ├── MOTOR                            │
  ├── GNSS interference/spoofing      ├─→ Dataset Audit → Validated Sessions
  ├── NavIC Android measurements      │
  └── OSM                             ─┘

Validated IMU
      ↓
Preprocessing + synchronization
      ↓
Phone alignment/calibration
      ↓
LIMU-BERT
      ↓
TLIO-style Neural Inertial Odometry
      ↓
Invariant ESKF/IEKF
      ↓
KalmanNet adaptive filtering
      ↓
NHC/ZUPT + robust GNSS fusion
      ↓
Local OSM candidate generation
      ↓
Lightweight GNN map matching
      ↓
Temporal/kinematic consistency
      ↓
Final 10 Hz smartphone navigation output
      ↓
Smooth GNSS recovery
      ↓
SIH benchmark + ablation + error analysis
      ↓
ONNX/mobile/edge export
```

**Important:** map matching is a supporting correction/reasoning layer. It must never be allowed to conceal poor inertial odometry. Report pure DR and map-assisted DR separately.
