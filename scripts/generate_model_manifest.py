# scripts/generate_model_manifest.py
import hashlib, json, os, sys
from pathlib import Path

CHECKPOINTS = {
    "limu_bert":          "checkpoints/limu_bert/limu_bert_best.pt",
    "inertial_odometry":  "checkpoints/inertial_odometry/inertial_odometry_best.pt",
    "kalmannet":          "checkpoints/kalmannet/kalmannet_best.pt",
    "map_gnn":            "checkpoints/map_gnn/map_gnn_best.pt",
}
EXPORTS = {
    "limu_bert":          "exports/onnx/limu_bert.onnx",
    "inertial_odometry":  "exports/onnx/inertial_odometry.onnx",
    "kalmannet":          "exports/onnx/kalmannet.onnx",
    "map_gnn":            "exports/onnx/map_gnn.onnx",
}

def sha256(path):
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    manifest = {}
    for name, ckpt in CHECKPOINTS.items():
        onnx = EXPORTS[name]
        manifest[name] = {
            "checkpoint_path": ckpt,
            "checkpoint_exists": os.path.exists(ckpt),
            "checkpoint_size_bytes": os.path.getsize(ckpt) if os.path.exists(ckpt) else 0,
            "checkpoint_sha256": sha256(ckpt),
            "onnx_export_path": onnx,
            "onnx_export_exists": os.path.exists(onnx),
            "onnx_sha256": sha256(onnx),
        }

    Path("results").mkdir(exist_ok=True)
    with open("results/model_manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

    n_missing = sum(1 for m in manifest.values() if not m["checkpoint_exists"])
    if n_missing == 0:
        print(f"All {len(manifest)}/{len(manifest)} model checkpoints and ONNX exports verified and registered.")
    else:
        print(f"{len(manifest) - n_missing}/{len(manifest)} checkpoints present, {n_missing} missing.")

if __name__ == "__main__":
    main()
