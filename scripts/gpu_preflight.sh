#!/usr/bin/env bash
# scripts/gpu_preflight.sh
# ─────────────────────────────────────────────────────────────────────────────
# SIH PS 26168 — Remote GPU environment preflight check.
# Run on Lightning AI before any training or benchmark.
# Per Section 13 of procedure_roadmap.md:
#   If torch.cuda.is_available() == False → STOP. Never silently fall back to CPU.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

if [ -n "${LIGHTNING_PYTHON_BIN:-}" ] && [ -x "$LIGHTNING_PYTHON_BIN" ]; then
    PYTHON="$LIGHTNING_PYTHON_BIN"
elif [ -x "/home/zeus/miniconda3/envs/cloudspace/bin/python" ]; then
    PYTHON="/home/zeus/miniconda3/envs/cloudspace/bin/python"
elif [ -x "/home/zeus/miniconda3/bin/python" ]; then
    PYTHON="/home/zeus/miniconda3/bin/python"
else
    PYTHON="$(command -v python3 || command -v python)"
fi
PROJECT_DIR="${LIGHTNING_REMOTE_DIR:-$(pwd)}"


echo "============================================================"
echo "  SIH PS 26168 — GPU / Environment Preflight"
echo "============================================================"
echo ""

# ── System info ───────────────────────────────────────────────────────────────
echo "── System ───────────────────────────────────────────────────"
echo "Hostname   : $(hostname)"
echo "Date/Time  : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Working dir: $(pwd)"
echo "Python bin : $(which "$PYTHON")"
echo ""

# ── Python version ────────────────────────────────────────────────────────────
echo "── Python ───────────────────────────────────────────────────"
"$PYTHON" --version
echo ""

# ── GPU hardware ──────────────────────────────────────────────────────────────
echo "── nvidia-smi ───────────────────────────────────────────────"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
    echo ""
    echo "GPU summary:"
    nvidia-smi --query-gpu=index,name,memory.total,driver_version \
               --format=csv,noheader
else
    echo "ERROR: nvidia-smi not found. GPU may not be available."
    exit 1
fi
echo ""

# ── PyTorch + CUDA ────────────────────────────────────────────────────────────
echo "── PyTorch / CUDA ───────────────────────────────────────────"
"$PYTHON" - <<'PYEOF'
import sys
import torch

print(f"PyTorch version  : {torch.__version__}")
print(f"CUDA available   : {torch.cuda.is_available()}")

if not torch.cuda.is_available():
    print("\nFATAL: CUDA is NOT available.")
    print("Per PROJECT_RULES.md Section 7: never silently fall back to CPU.")
    print("Fix the CUDA environment before proceeding.")
    sys.exit(1)

print(f"CUDA version     : {torch.version.cuda}")
print(f"cuDNN version    : {torch.backends.cudnn.version()}")
print(f"cuDNN enabled    : {torch.backends.cudnn.enabled}")
print(f"Number of GPUs   : {torch.cuda.device_count()}")
for i in range(torch.cuda.device_count()):
    p = torch.cuda.get_device_properties(i)
    print(f"  GPU {i}: {p.name} | VRAM: {p.total_memory / 1024**3:.1f} GB")

# Quick tensor test
t = torch.randn(4, 4).cuda()
print(f"\nTest tensor on {t.device}: OK")
print("\nGPU PREFLIGHT: PASSED")
PYEOF

if [ $? -ne 0 ]; then
    echo "PREFLIGHT FAILED: PyTorch CUDA check failed."
    exit 1
fi
echo ""

# ── Key packages ──────────────────────────────────────────────────────────────
echo "── Key packages ─────────────────────────────────────────────"
"$PYTHON" - <<'PYEOF'
packages = [
    "numpy", "pandas", "scipy", "matplotlib", "seaborn",
    "sklearn", "torch", "torchvision",
    "yaml",          # pyyaml
    "tqdm",
    "onnx", "onnxruntime",
]
import importlib
for pkg in packages:
    try:
        m = importlib.import_module(pkg)
        ver = getattr(m, "__version__", "?")
        print(f"  {pkg:<20} {ver}")
    except ImportError:
        print(f"  {pkg:<20} NOT INSTALLED")
PYEOF
echo ""

# ── ONNX Runtime providers ────────────────────────────────────────────────────
echo "── ONNX Runtime providers ───────────────────────────────────"
"$PYTHON" - <<'PYEOF'
try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print(f"Available providers: {providers}")
    if "CUDAExecutionProvider" in providers:
        print("ONNX GPU: CUDAExecutionProvider is AVAILABLE")
    else:
        print("WARNING: CUDAExecutionProvider NOT available in ONNX Runtime.")
        print("Official GPU inference benchmark cannot proceed without it.")
except ImportError:
    print("onnxruntime not installed — install onnxruntime-gpu")
PYEOF
echo ""

# ── Disk space ────────────────────────────────────────────────────────────────
echo "── Disk space ───────────────────────────────────────────────"
df -h "$PROJECT_DIR" 2>/dev/null || df -h .
echo ""

echo "============================================================"
echo "  GPU PREFLIGHT COMPLETE"
echo "============================================================"
