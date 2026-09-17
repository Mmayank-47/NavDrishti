import os, sys, hashlib, json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

CHECKPOINTS = {
    "nio_v1": "checkpoints/inertial_odometry/inertial_odometry_best.pt",
    "nio_v2_fixed": "checkpoints/nio_fixed/nio_fixed_best.pt",
    "kalmannet_v1": "checkpoints/kalmannet/kalmannet_best.pt",
    "kalmannet_v2": "checkpoints/kalmannet_fixed_input/kalmannet_best.pt",
    "map_gnn": "checkpoints/map_gnn/map_gnn_best.pt",
    "limu_bert": "checkpoints/limu_bert/limu_bert_best.pt"
}

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192 * 1024):
            h.update(chunk)
    return h.hexdigest()

def main():
    print("=" * 70)
    print("  PHASE 1: FREEZING CHECKPOINTS & GENERATING IMMUTABLE HASHES")
    print("=" * 70)
    
    frozen_manifest = {}
    for name, rel_path in CHECKPOINTS.items():
        full_p = PROJECT_ROOT / rel_path
        if full_p.exists():
            h = sha256_file(full_p)
            size_mb = full_p.stat().st_size / (1024 * 1024)
            frozen_manifest[name] = {
                "path": rel_path,
                "size_bytes": full_p.stat().st_size,
                "size_mb": round(size_mb, 3),
                "sha256": h,
                "status": "FROZEN_IMMUTABLE"
            }
            print(f"  {name:15s} | Size: {size_mb:6.2f} MB | SHA256: {h[:16]}... | Path: {rel_path}")
        else:
            frozen_manifest[name] = {"path": rel_path, "status": "NOT_FOUND"}
            print(f"  {name:15s} | NOT FOUND at {rel_path}")

    out_file = PROJECT_ROOT / "results" / "frozen_checkpoint_hashes.json"
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_file, "w") as f:
        json.dump(frozen_manifest, f, indent=2)
    print(f"\nSaved Frozen Manifest: {out_file}")
    print("=" * 70)

if __name__ == '__main__':
    main()
