"""CLI replay; intentionally does not call the legacy final navigation pipeline."""
import argparse, csv, json
from pathlib import Path
import numpy as np
from src.preprocessing.data_loader import IOVNBDLoader
from .adapter import CanonicalSession, TimestampPolicy
from .replay import initialize_before, replay_outage
from .export import safe_export
from .provenance import manifest
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--config", required=True); ap.add_argument("--output", required=True); args = ap.parse_args()
    cfg = json.loads(Path(args.config).read_text()); out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    loader = IOVNBDLoader(data_root=cfg["dataset_root"]); meta = loader.sessions[cfg["session"]]; raw = loader.load_session(cfg["session"], preprocess_imu=False)
    # Existing loader obtains phone timestamp ms -> s and declares gyro rad/s; no speed fields enter session.
    s = CanonicalSession(raw["time_s"], raw["accel_raw"], raw["gyro_raw"], raw["enu_coords"][:, :2], policy=TimestampPolicy(cfg.get("timestamp_gap_s", 2.0)))
    base = {"session": cfg["session"], "mode": cfg["mode"], "t0_s": cfg["t0_s"], "t1_s": cfg["t1_s"]}
    try:
        initial = initialize_before(s, cfg["t0_s"])
        r = replay_outage(s, initial, cfg["t0_s"], cfg["t1_s"], cfg["mode"], np.asarray(cfg.get("phone_to_vehicle_rotation")) if cfg["mode"] == "gyro_heading_speed" else None)
        base.update({"status": r.status, "reason": r.reason, "endpoint_error_m": r.endpoint_error_m, "initial_source_time_s": initial.source_time_s, "initial_position_source": "pre-outage reference", "initial_velocity_source": "past-only reference chord"})
        with open(out / "trajectory.csv", "w", newline="") as f:
            w = csv.writer(f); w.writerow(["time_s", "east_m", "north_m"]); w.writerows(r.trajectory)
    except (ValueError, KeyError) as e: base.update({"status": "NOT_EVALUABLE", "reason": str(e), "endpoint_error_m": None})
    (out / "manifest.json").write_text(json.dumps(manifest(Path.cwd(), cfg, [meta["smartphone_file"]]), indent=2))
    safe_export(out, base)
if __name__ == "__main__": main()
