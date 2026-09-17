import os, sys, platform, time
from pathlib import Path
import torch

def main():
    print("=" * 70)
    print("  PHASE 0: REMOTE GPU PREFLIGHT VERIFICATION")
    print("=" * 70)
    print(f"Hostname    : {platform.node()}")
    print(f"OS/Platform : {platform.platform()}")
    print(f"Working Dir : {os.getcwd()}")
    print(f"Python Exec : {sys.executable}")
    print(f"Python Ver  : {sys.version.split()[0]}")
    print(f"PyTorch Ver : {torch.__version__}")
    print(f"CUDA Avail  : {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"Device Count: {torch.cuda.device_count()}")
        print(f"Device Name : {torch.cuda.get_device_name(0)}")
        total_mem = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        print(f"VRAM Total  : {total_mem:.2f} GB")
    else:
        print("CRITICAL ERROR: CUDA is NOT available. Stopping.")
        sys.exit(1)
        
    ts = time.strftime('%Y%m%d_%H%M%S', time.gmtime())
    exp_dir = Path(f"experiments/exp_phase_nhc_nio_{ts}")
    exp_dir.mkdir(parents=True, exist_ok=True)
    print(f"Created Experiment Dir: {exp_dir}")
    print("=" * 70)

if __name__ == '__main__':
    main()
