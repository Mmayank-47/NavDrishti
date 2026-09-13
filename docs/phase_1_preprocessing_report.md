# Phase 1 Report: Data Preprocessing, Sensor Synchronization & Phone-to-Vehicle Alignment

**SIH PS 26168 — Intelligent Dead Reckoning**  
**Execution Timestamp:** 2026-09-13  
**Status:** Completed & Verified  

---

## 1. Executive Summary

Phase 1 establishes the foundational sensor processing and spatial calibration pipeline for the Intelligent Dead Reckoning system. All sensor operations have been developed and traced strictly notebook-first, operating on real IO-VNBD smartphone and vehicle CAN-bus recordings without synthetic fabrication.

### Core Modules Delivered:
1. **IMU Preprocessor (`src/preprocessing/imu_preprocessor.py`)**:
   - Zero-phase forward-backward Butterworth low-pass filtering ($f_c = 4.0\text{ Hz}$) attenuating engine vibration and road harshness by $>99\%$ variance reduction.
   - Non-linear amplitude limiting ($a_{\text{max}} = 35\text{ m/s}^2$) preventing quadratic integration drift from sharp pothole impacts.
   - Dynamic linear acceleration extraction via gravity vector separation.
   - High-speed rolling variance stationary / Zero-Velocity Update (ZUPT) detector.

2. **Geodetic & Frame Transformation (`src/preprocessing/frame_transform.py`)**:
   - WGS84 Geodetic ($\text{Lat}, \text{Lon}, \text{Alt}$) $\longleftrightarrow$ Earth-Centered Earth-Fixed (ECEF) $\longleftrightarrow$ Local East-North-Up (ENU) Cartesian projection.
   - Numerical roundtrip precision validated to $<10^{-5}$ deg / meters.

3. **In-Vehicle Phone-to-Vehicle Alignment Engine (`src/calibration/alignment.py`)**:
   - Two-stage dynamic calibration:
     - **Stage 1 (Leveling)**: Computes pitch and roll angles from the gravity vector during stationary/constant-speed intervals.
     - **Stage 2 (Heading)**: Resolves yaw misalignment relative to the vehicle longitudinal axis by correlating horizontal acceleration with longitudinal velocity derivative.
   - Computes direction cosine rotation matrix $R_{p \to v}$ transforming arbitrary phone body coordinates into $[X_{\text{fwd}}, Y_{\text{lat}}, Z_{\text{vert}}]$.

---

## 2. Notebook Execution & Traceability Summary

Both required notebooks were executed in-process with execution counts and cell outputs persisted directly back into the notebook structure:

### 2.1 `notebooks/02_preprocessing.ipynb`
- **Session Evaluated**: Primary training session `M` (Driver B).
- **Session Duration**: 6,171.7 seconds (105,974 samples @ 10.0 Hz).
- **Total Distance (GNSS)**: 102,010.4 meters (~102 km driving).
- **Stationary Detection**: 34,774 samples (32.8% of session detected as zero-velocity).
- **Max Vehicle Speed**: 100.8 km/h.
- **Generated Plots**:
  - `plots/preprocessing/accel_filtering_M.png`: Raw vs Butterworth filtered acceleration showing high-frequency vibration removal.
  - `plots/preprocessing/gravity_separation_M.png`: Specific force norm vs dynamic linear acceleration norm.
  - `plots/preprocessing/enu_trajectory_M.png`: Reconstructed local metric 2D trajectory.

### 2.2 `notebooks/03_phone_alignment.ipynb`
- **Single-Session Calibration (Session M)**:
  - Roll Angle (Leveling): $+0.24^\circ$
  - Pitch Angle (Leveling): $-0.48^\circ$
  - Yaw Angle (Heading): $-40.61^\circ$
  - Rotation Matrix $R_{p \to v}$:
    $$\begin{bmatrix} 0.7591 & 0.6509 & -0.0091 \\ -0.6509 & 0.7591 & 0.0022 \\ 0.0083 & 0.0042 & 1.0000 \end{bmatrix}$$
    - Orthonormality error: $2.22 \times 10^{-16}$, Determinant: $1.000000$.
- **Multi-Session Calibration Comparison**:
  | Session | Driver | Leveling Roll ($^\circ$) | Leveling Pitch ($^\circ$) | Heading Yaw ($^\circ$) |
  |---|---|:---:|:---:|:---:|
  | **M** | Driver B | $+0.24$ | $-0.48$ | $-40.61$ |
  | **S1** | Driver A (Test Set) | $-0.22$ | $+0.29$ | $-44.62$ |
  | **Vfa01** | Driver E | $+1.91$ | $+0.01$ | $+108.80$ |
  | **Vta1a** | Driver E | $+1.42$ | $+0.64$ | $+80.72$ |
- **Generated Plots**:
  - `plots/alignment/alignment_validation_M.png`: Aligned phone forward and lateral accelerations compared against CAN-bus reference longitudinal and lateral acceleration.

---

## 3. Automated Verification Results

Automated regression suite `scripts/verify_phase1.py` passed with 100% success:
- **Vibration Filter**: Noise variance reduced from 0.1237 to 0.0002 ($>99\%$ reduction).
- **Pothole / Shock Suppressor**: $50\text{ m/s}^2$ shock spike clamped to $35.00\text{ m/s}^2$.
- **ZUPT Detector**: Clean separation between stationary and moving sensor noise profiles.
- **Coordinate Conversion**: Local ENU metric offsets and ECEF roundtrip precision validated.
- **Alignment Engine**: Orthonormality confirmed; forward acceleration demonstrates positive correlation with vehicle chassis sensors.
- **Artifact Presence**: All 4 diagnostic plot PNGs verified present and non-empty.

---

## 4. Phase Completion Verdict

Phase 1 is **COMPLETE and VERIFIED**.  
All requirements for Section 10, Section 21, and Step 11 of the procedure roadmap are met.

**Next Phase**: Phase 2 — Classical Inertial Navigation & Invariant ESKF Baseline (`notebooks/04_eskf_baseline.ipynb`, strapdown integration, error-state Kalman filter, covariance propagation, and dead-reckoning drift benchmark).
