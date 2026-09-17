"""
scripts/select_nio_checkpoint.py
─────────────────────────────────────────────────────────────────────────────
Utility: Print the best available NIO checkpoint path to stdout.
Priority: nio_fixed (v2) > baseline (v1 fallback)
Used by KalmanNet training to auto-select the best NIO checkpoint.
─────────────────────────────────────────────────────────────────────────────
Usage:
    import subprocess
    ckpt = subprocess.check_output(['python', 'scripts/select_nio_checkpoint.py']).decode().strip()
Or directly from notebook:
    from scripts.select_nio_checkpoint import get_best_nio_checkpoint
    io_ckpt_str = get_best_nio_checkpoint(PROJECT_ROOT)
"""

from pathlib import Path
import json
import sys


def get_best_nio_checkpoint(project_root: str | Path) -> tuple[str, str]:
    """
    Returns (checkpoint_path_str, description_str).
    checkpoint_path_str is None if no checkpoint found.
    """
    root = Path(project_root)

    FIXED_CKPT    = root / 'checkpoints' / 'nio_fixed'          / 'nio_fixed_best.pt'
    BASELINE_CKPT = root / 'checkpoints' / 'inertial_odometry'  / 'inertial_odometry_best.pt'

    if FIXED_CKPT.exists():
        desc = 'nio_fixed_v2 (BoundedLogVarHead — sigma overflow FIXED)'
        return str(FIXED_CKPT), desc

    if BASELINE_CKPT.exists():
        desc = 'nio_baseline_v1 (FALLBACK: fixed NIO not yet available — run notebook 09 first)'
        return str(BASELINE_CKPT), desc

    return None, 'NO_NIO_CHECKPOINT_FOUND'


def get_kalmannet_checkpoint_dir(project_root: str | Path) -> tuple[Path, str]:
    """
    Returns (ckpt_dir, tag) — separate dir per NIO source for clean audit trail.
    """
    root = Path(project_root)
    FIXED_CKPT = root / 'checkpoints' / 'nio_fixed' / 'nio_fixed_best.pt'

    if FIXED_CKPT.exists():
        return root / 'checkpoints' / 'kalmannet_fixed_input', 'kalmannet_fixed_input'
    else:
        return root / 'checkpoints' / 'kalmannet', 'kalmannet_baseline_input'


if __name__ == '__main__':
    root = Path(__file__).parent.parent
    ckpt_path, desc = get_best_nio_checkpoint(root)
    print(f'NIO checkpoint: {ckpt_path}')
    print(f'Description:    {desc}')

    knet_dir, knet_tag = get_kalmannet_checkpoint_dir(root)
    print(f'KalmanNet dir:  {knet_dir}')
    print(f'KalmanNet tag:  {knet_tag}')

    # Emit JSON for programmatic use
    result = {
        'nio_checkpoint': ckpt_path,
        'nio_description': desc,
        'kalmannet_dir': str(knet_dir),
        'kalmannet_tag': knet_tag,
    }
    out = root / 'results' / 'checkpoint_selection.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'w') as f:
        json.dump(result, f, indent=2)
    print(f'Written to: {out}')
