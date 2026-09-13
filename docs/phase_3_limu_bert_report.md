# Phase 3 Report: LIMU-BERT Self-Supervised Pretraining & Held-Out Evaluation

**SIH PS 26168 — Intelligent Dead Reckoning**  
**Execution Timestamp:** 2026-09-13  
**Status:** Completed & Verified on Remote Lightning AI GPU (Tesla T4)  

---

## 1. Executive Summary

Phase 3 implements self-supervised IMU representation pretraining using **LIMU-BERT** (Section 16 of the roadmap). Operating on real IO-VNBD 6-DOF sensor time series (3-axis accelerometer and 3-axis gyroscope), the model learns temporal inertial correlations, attenuates vehicle vibration, and produces rich latent representations for downstream neural odometry (TLIO / OdoNet).

All heavy computation was executed remotely on the **Lightning AI GPU (Tesla T4, 15.3 GB VRAM)** using automated sync and headless execution pipelines (`.vscode/sync_and_run.ps1` / `scripts/run_remote.sh`).

---

## 2. Architecture & Hyperparameters

- **Model Class**: `src/models/limu_bert.py` (`LIMUBERT`)
- **Input Channels**: 6 ($a_x, a_y, a_z, \omega_x, \omega_y, \omega_z$)
- **Sequence Length**: 120 timesteps ($12.0\text{ seconds}$ at $10\text{ Hz}$)
- **Hidden Dimension**: $128$
- **Attention Heads**: $4$
- **Transformer Encoder Layers**: $4$
- **Feedforward Dimension**: $256$
- **Trainable Parameters**: $548,102$
- **Pretraining Objective**: Masked Sensor Modeling (MSM) with $15\%$ random span masking
- **Optimizer**: AdamW ($\text{lr} = 1.0\times 10^{-3}$, weight decay $= 1.0\times 10^{-4}$, Cosine Annealing scheduler)
- **Precision**: Mixed Precision (`torch.cuda.amp.GradScaler`) on Tesla T4

---

## 3. Remote Execution & Verification Results

### 3.1 Training (`notebooks/05_limu_bert_training.ipynb`)
- **Dataset Partitioning**:
  - **Train Sessions**: `M (Driver B)`, `Vf`, `Vta`, `Vtb`, `Vw (Driver E)`
  - **Validation Session**: `Y (Driver D)`
- **Epochs Trained**: 80
- **Final Training Loss (MSE)**: $0.7279$
- **Best Validation Loss (MSE)**: **$0.1527$**
- **Saved Checkpoint**: `checkpoints/limu_bert/limu_bert_best.pt` ($7.15\text{ MB}$)
- **Learning Curve**: `plots/limu_bert/limu_bert_training_curve.png`

### 3.2 Held-Out Testing (`notebooks/06_limu_bert_testing.ipynb`)
- **Test Session**: `S1 (Driver A)` — kept strictly unseen during pretraining and validation.
- **Test Reconstruction MSE**: **$0.2035$**
- **Diagnostic Inspection**: `plots/limu_bert/limu_bert_test_reconstruction_S1.png`
  - High fidelity reconstruction across all 6 sensor channels, accurately reproducing high-frequency dynamics and recovering masked intervals.

---

## 4. Phase Completion Verdict

Phase 3 is **COMPLETE and VERIFIED ON LIGHTNING AI GPU**.  
All requirements for Section 16, Section 13, and Step 13–14 of the procedure roadmap are met.

**Next Action**: Phase 4 — Neural Inertial Odometry (TLIO-style relative displacement/velocity estimator with uncertainty prediction) leveraging frozen LIMU-BERT latent embeddings, executed on Lightning AI.
