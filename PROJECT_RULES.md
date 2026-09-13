# PROJECT RULES — SIH PS 26168 Intelligent Dead Reckoning

> These rules are non-negotiable. They apply to every contributor, notebook, script, and agent action in this project.
> Any violation invalidates the associated result.

---

## 1. REAL DATA ONLY FOR OFFICIAL RESULTS

- **PROHIBITED**: Replacing IO-VNBD sessions with synthetic or mathematically generated trajectories for any official result.
- **PROHIBITED**: Creating artificial vehicle routes to claim SIH performance figures.
- **PROHIBITED**: Presenting any synthetic trajectory as IO-VNBD data.
- **ALLOWED**: Synthetic data tagged `SYNTHETIC_DEBUG_ONLY` for unit tests, software validation, and debugging only.
- **NEVER** use synthetic data for: SIH performance, IO-VNBD benchmarking, drift claims, accuracy claims, PASS/FAIL verdicts, or final results.

## 2. GNSS OUTAGE SIMULATION

- GNSS blackout **must** be simulated by masking GNSS measurements from a **real trajectory**.
- Do not generate a fake trajectory.
- During GNSS-denied inference: no ground truth may be supplied to any model.
- Ground truth is available **only** to the evaluation code **after** inference completes.
- Do not cherry-pick only the outage window that gives the best result.
- Use all qualifying windows or a documented, deterministic selection rule.

## 3. BENCHMARK WINDOW

- **PROHIBITED**: Hardcoding a single outage window (e.g., `85–130 seconds`) as the official benchmark.
- Qualifying windows must be discovered from real held-out data using a transparent rule.
- Multiple durations must be evaluated where the data supports them (~3–5s, ~10s, ~20s, ~30s, ~45s, ~60s, ~50m, ~1km).
- If a duration is not supported by real data: report **NOT TESTED — INSUFFICIENT REAL DATA**. Never fabricate a trajectory to fill the gap.

## 4. RESULTS — NO HARDCODING

- **PROHIBITED**: Hardcoding any benchmark result, metric value, drift percentage, error value, or accuracy figure.
- **PROHIBITED**: Hardcoding `PASS`.
- **PROHIBITED**: Hardcoding `FAIL`.
- All results must be computed from actual inference on real held-out data.

## 5. TRAIN / VALIDATION / TEST SPLIT INTEGRITY

- Splitting must be at session/trajectory level — never random sample-level splitting of adjacent data from the same trajectory.
- **PROHIBITED**: Tuning any threshold, hyperparameter, architecture choice, or benchmark window using the final test set.
- Use validation data for all decisions.
- Use final test data only for the final evaluation — touch it exactly once.

## 6. GROUND TRUTH DURING INFERENCE

- **PROHIBITED**: Supplying ground truth position, velocity, or orientation to any model during GNSS-denied inference.
- Only sensor measurements that would be available in deployment may be used as inference inputs.

## 7. GPU / ONNX INTEGRITY

- **PROHIBITED**: Falling back to CPU during an official GPU benchmark run without explicit warning and re-run on GPU.
- **PROHIBITED**: Reporting CPU inference as a GPU benchmark result.
- **PROHIBITED**: Claiming ONNX GPU inference without verifying `CUDAExecutionProvider` is active.
- Every official GPU run must log and report the actual execution provider.

## 8. DATASET SCHEMA

- **PROHIBITED**: Guessing dataset schemas, column names, timestamps, coordinate systems, or sampling rates.
- All schema facts must be established by the dataset audit notebooks before training or evaluation begins.
- Keep each source traceable to its original session/file.

## 9. CHECKPOINT INTEGRITY

- **PROHIBITED**: Silently overwriting the best checkpoint with a worse one.
- **PROHIBITED**: Silently retraining inside a testing notebook.
- Testing notebooks must load a saved checkpoint and must fail clearly if no checkpoint exists.
- New experiments must use versioned subdirectories (e.g., `checkpoints/limu_bert/experiment_002/`).

## 10. HIDDEN EXPERIMENT STATE

- **PROHIBITED**: Hidden model state that is not reproducible from Kernel Restart → Run All.
- **PROHIBITED**: Concealing failed experiments.
- All experiments must be logged in `logs/` and `artifacts/` with: date/time, experiment ID, notebook name, dataset version, configuration, random seed, GPU, software versions, metrics, checkpoint path, result paths.

## 11. REPORTING

- Pure DR results must always be reported separately.
- NHC improvement and GNN map-matching improvement must be reported separately.
- Recovery jump must be explicitly measured and reported.
- **PROHIBITED**: Reporting only the best map-matched result while hiding the pure DR performance.
- If any SIH requirement cannot be evaluated due to insufficient real data: report **NOT TESTED — INSUFFICIENT REAL DATA**.
- **PROHIBITED**: Hiding any failure.

## 12. MAP MATCHING

- Map matching is a supporting correction layer. It must never conceal poor inertial odometry.
- Always report: Pure DR | DR+NHC | DR+GNN Map Matching | Complete System.

## 13. MOBILE / EDGE CLAIMS

- **PROHIBITED**: Claiming mobile deployment without measuring actual inference latency, memory, and model size.
- ONNX export must be validated numerically against the original PyTorch model.

## 14. SSH / CREDENTIALS

- **PROHIBITED**: Committing SSH private keys, passwords, or credentials to source code, notebooks, Git, or logs.
- **PROHIBITED**: Hardcoding SSH usernames, hostnames, or absolute remote paths in committed source files.
- Use `configs/lightning.env` (gitignored) for machine-specific configuration.

## 15. MASTER SUCCESS CRITERION (Section 66)

The project is ready only when **all** of the following are true:
- Real data used for all official results
- Reproducible training (Kernel Restart → Run All)
- Independent model checkpoints (each model trained and saved independently)
- Validated final integration
- Real held-out testing
- SIH metric calculation from actual inference
- Recovery test explicitly measured
- Mobile/edge performance measured
- Traceable notebooks
- Remote GPU reproducibility confirmed

---

*Last updated: auto-generated during project scaffold creation.*
*Do not modify these rules without updating the roadmap and documenting the reason.*
