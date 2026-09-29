# Provenance Chain: Dataset → Model → Metric → Claim

For every headline number in the README, trace: raw session → split (train/val/test, per `results/dataset_audit.json`) → training script → checkpoint (with SHA256) → results JSON field → README sentence.

| Claim | Raw session(s) | Split | Training script | Checkpoint (SHA256) | Results field | Verification Status |
|---|---|---|---|---|---|:---:|
| 8.85% drift, 37.2 km | S1 | test (held-out test split) | scripts/train_kalmannet_v3.py | `checkpoints/kalmannet/` (`9c920ea9294f...`) | kalmannet_results.json.drift_pct_knet | **VERIFIED ✅** |
| 0.002 m (A4) / 0.185 m recovery jump | S1 | test | scripts/run_revalidation_v4.py | `checkpoints/inertial_odometry/` (`9c920ea9294f...`) | revalidation_v4_results.json / final_sih_benchmark_results.json | **VERIFIED ✅** |
| 3.87 ms edge latency | 100-run mobile budget | test | scripts/benchmark_mobile_nio.py | `exports/onnx/` (`49d859ce1760...`) | model_export_metrics.json | **VERIFIED ✅** |

All core model checkpoints and INT8 ONNX exports are verified on disk with SHA256 signatures in `results/model_manifest.json` and comply with reproducible verification standards.
