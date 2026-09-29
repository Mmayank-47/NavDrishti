"""Run identity: dirty source is recorded, never presented as a pinned revision."""
import hashlib, json, platform, subprocess, sys
from pathlib import Path
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""): h.update(b)
    return h.hexdigest()
def manifest(root, config, inputs=()):
    root = Path(root)
    def git(*args):
        try: return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
        except Exception: return None
    return {"source_revision": git("rev-parse", "HEAD"), "source_dirty": bool(git("status", "--porcelain")),
            "config_sha256": hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
            "input_files": [{"path": str(p), "sha256": sha256(p)} for p in inputs if Path(p).is_file()],
            "runtime": {"python": sys.version, "platform": platform.platform()},
            "observation_policy": "outage estimator reads IMU only; reference is scorer-only; vehicle speed prohibited"}
