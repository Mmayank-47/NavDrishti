"""
scripts/baseline_snapshot.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Forensic Baseline Snapshot: Read existing result files, write to results/baseline/.
NEVER modifies original files. Run once before any retraining.
─────────────────────────────────────────────────────────────────────────────
"""

import json
import shutil
import datetime
from pathlib import Path

ROOT = Path(__file__).parent.parent

RESULT_FILES = [
    "results/inertial_odometry_results.json",
    "results/inertial_odometry_training_summary.json",
    "results/kalmannet_results.json",
    "results/kalmannet_training_metrics.json",
    "results/limu_bert_results.json",
    "results/limu_bert_test_results.json",
    "results/map_matching_results.json",
    "results/gnss_fusion_results.json",
    "results/eskf_baseline.json",
    "results/final_sih_benchmark_results.json",
    "results/final_results_summary.json",
    "results/model_export_metrics.json",
]

CHECKPOINT_META = [
    ("checkpoints/inertial_odometry", "nio_baseline"),
    ("checkpoints/kalmannet",         "kalmannet_baseline"),
    ("checkpoints/limu_bert",         "limu_bert_baseline"),
    ("checkpoints/map_gnn",           "map_gnn_baseline"),
]


def main():
    snap_dir = ROOT / "results" / "baseline"
    snap_dir.mkdir(parents=True, exist_ok=True)

    snapshot_meta = {
        "snapshot_timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "purpose": "Frozen baseline before Phase-1 NIO uncertainty fix retraining",
        "result_files": {},
        "checkpoint_sizes_bytes": {},
        "key_metrics": {}
    }

    # 1. Copy result files
    for rel_path in RESULT_FILES:
        src = ROOT / rel_path
        if src.exists():
            dst = snap_dir / src.name
            shutil.copy2(src, dst)
            try:
                with open(src) as f:
                    data = json.load(f)
                snapshot_meta["result_files"][src.name] = {
                    "copied": True,
                    "size_bytes": src.stat().st_size
                }
            except Exception as e:
                snapshot_meta["result_files"][src.name] = {
                    "copied": True, "parse_error": str(e)
                }
            print(f"  [OK] Copied {src.name}")
        else:
            snapshot_meta["result_files"][rel_path] = {"copied": False, "reason": "NOT_FOUND"}
            print(f"  [--] Not found: {rel_path}")

    # 2. Record checkpoint sizes (do not copy — too large)
    for ckpt_dir, label in CHECKPOINT_META:
        ckpt_path = ROOT / ckpt_dir
        if ckpt_path.exists():
            total_bytes = sum(f.stat().st_size for f in ckpt_path.rglob("*") if f.is_file())
            files = [f.name for f in ckpt_path.iterdir() if f.is_file()]
            snapshot_meta["checkpoint_sizes_bytes"][label] = {
                "path": str(ckpt_dir),
                "total_bytes": total_bytes,
                "total_mb": round(total_bytes / 1e6, 3),
                "files": files
            }
            print(f"  [OK] Checkpoint {label}: {round(total_bytes/1e6,2)} MB, files: {files}")
        else:
            snapshot_meta["checkpoint_sizes_bytes"][label] = {"path": str(ckpt_dir), "exists": False}
            print(f"  [--] Checkpoint dir not found: {ckpt_dir}")

    # 3. Extract key baseline metrics for quick diff
    def _read_json(rel):
        p = ROOT / rel
        if p.exists():
            with open(p) as f:
                return json.load(f)
        return None

    nio_res = _read_json("results/inertial_odometry_results.json")
    if nio_res:
        snapshot_meta["key_metrics"]["nio_displacement_rmse_m"]      = nio_res.get("displacement_rmse_m")
        snapshot_meta["key_metrics"]["nio_displacement_mae_m"]       = nio_res.get("displacement_mae_m")
        snapshot_meta["key_metrics"]["nio_velocity_rmse_mps"]        = nio_res.get("velocity_rmse_mps")
        snapshot_meta["key_metrics"]["nio_uncertainty_sigma_mean"]   = nio_res.get("mean_predicted_uncertainty_sigma")

    knet_res = _read_json("results/kalmannet_results.json")
    if knet_res:
        snapshot_meta["key_metrics"]["knet_drift_pct"]               = knet_res.get("drift_pct")
        snapshot_meta["key_metrics"]["knet_pos_rmse_m"]              = knet_res.get("pos_rmse_m")

    bench = _read_json("results/final_sih_benchmark_results.json")
    if bench and "benchmarks" in bench:
        for b in bench["benchmarks"]:
            key = b["window"].replace(" ", "_").replace("/", "")
            snapshot_meta["key_metrics"][f"benchmark_{key}_drift_pct"]   = b.get("drift_pct_proposed")
            snapshot_meta["key_metrics"][f"benchmark_{key}_recovery_m"]  = b.get("recovery_jump_proposed_m")

    # 4. Write snapshot meta
    out_path = snap_dir / "baseline_summary.json"
    with open(out_path, "w") as f:
        json.dump(snapshot_meta, f, indent=2)

    print(f"\n[DONE] Baseline snapshot written to {out_path}")
    print(f"       Key baseline metrics:")
    for k, v in snapshot_meta["key_metrics"].items():
        print(f"         {k}: {v}")


if __name__ == "__main__":
    main()
