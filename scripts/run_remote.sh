#!/usr/bin/env bash
# scripts/run_remote.sh
# ─────────────────────────────────────────────────────────────────────────────
# Universal remote execution wrapper for SIH PS 26168 on Lightning AI.
# Guarantees execution under bash with proper Conda / CUDA / Python environment.
#
# Usage:
#   bash scripts/run_remote.sh notebooks/00_environment_gpu.ipynb
#   bash scripts/run_remote.sh scripts/gpu_preflight.sh
#   bash scripts/run_remote.sh notebooks/01_dataset_audit.ipynb
# ─────────────────────────────────────────────────────────────────────────────

set -eo pipefail

TARGET_FILE="${1:-}"

if [ -z "$TARGET_FILE" ]; then
    echo "ERROR: No target file specified to run."
    echo "Usage: $0 <notebook_or_script_path>"
    exit 1
fi

# Detect working directory
if [ -d "/home/zeus/content/sih-model-training" ]; then
    PROJECT_DIR="/home/zeus/content/sih-model-training"
else
    PROJECT_DIR="$(pwd)"
fi
cd "$PROJECT_DIR"

# Ensure artifacts directory exists
mkdir -p "$PROJECT_DIR/artifacts" "$PROJECT_DIR/logs" "$PROJECT_DIR/plots" "$PROJECT_DIR/results"

# Locate Python environment
if [ -x "/home/zeus/miniconda3/envs/cloudspace/bin/python" ]; then
    ENV_BIN="/home/zeus/miniconda3/envs/cloudspace/bin"
    PYTHON="$ENV_BIN/python"
elif [ -x "/home/zeus/miniconda3/bin/python" ]; then
    ENV_BIN="/home/zeus/miniconda3/bin"
    PYTHON="$ENV_BIN/python"
else
    ENV_BIN="$(dirname "$(command -v python3 || command -v python)")"
    PYTHON="$ENV_BIN/python3"
fi

export PATH="$ENV_BIN:$PATH"
export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/src:${PYTHONPATH:-}"

echo "============================================================"
echo "  SIH PS 26168 — Remote Execution Runner"
echo "============================================================"
echo "Host        : $(hostname)"
echo "Target      : $TARGET_FILE"
echo "Project Dir : $PROJECT_DIR"
echo "Python      : $("$PYTHON" --version 2>&1) at $PYTHON"

# Diagnostics: GPU check
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "Unknown GPU")
    echo "GPU Hardware: $GPU_NAME"
else
    echo "WARNING: nvidia-smi not found!"
fi

# Quick PyTorch sanity check
"$PYTHON" - <<'EOF'
import torch
print(f"PyTorch     : {torch.__version__} | CUDA Available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"Device Name : {torch.cuda.get_device_name(0)} ({torch.cuda.device_count()} GPU(s))")
EOF

echo "============================================================"
echo ""

FULL_PATH="$PROJECT_DIR/$TARGET_FILE"
if [ ! -f "$FULL_PATH" ] && [ -f "$TARGET_FILE" ]; then
    FULL_PATH="$TARGET_FILE"
fi

if [ ! -f "$FULL_PATH" ]; then
    echo "ERROR: Target file not found: $FULL_PATH"
    exit 1
fi

case "$TARGET_FILE" in
    *.ipynb)
        OUT_NB="${TARGET_FILE%.ipynb}_executed.ipynb"
        FULL_OUT="$PROJECT_DIR/$OUT_NB"
        echo ">>> Executing Jupyter Notebook: $TARGET_FILE"
        echo ">>> Output Notebook: $OUT_NB"
        echo ""

        if command -v papermill &>/dev/null; then
            echo ">>> Using papermill..."
            papermill "$FULL_PATH" "$FULL_OUT" --log-output --cwd "$PROJECT_DIR"
        elif command -v jupyter &>/dev/null; then
            echo ">>> Using jupyter nbconvert..."
            jupyter nbconvert --to notebook --execute --inplace "$FULL_PATH"
        else
            echo ">>> papermill and jupyter not found in PATH. Installing papermill..."
            "$PYTHON" -m pip install -q papermill ipykernel
            papermill "$FULL_PATH" "$FULL_OUT" --log-output --cwd "$PROJECT_DIR"
        fi
        ;;

    *.sh)
        echo ">>> Executing Shell Script: $TARGET_FILE"
        bash "$FULL_PATH"
        ;;

    *test*.py|*_test.py)
        echo ">>> Running PyTest: $TARGET_FILE"
        "$PYTHON" -m pytest -v "$FULL_PATH"
        ;;

    *.py)
        echo ">>> Executing Python Script: $TARGET_FILE"
        "$PYTHON" "$FULL_PATH"
        ;;

    *)
        echo "ERROR: Unrecognized file type: $TARGET_FILE"
        exit 1
        ;;
esac

RC=$?
echo ""
if [ $RC -eq 0 ]; then
    echo ">>> Completed successfully: $TARGET_FILE (exit code 0)"
else
    echo ">>> FAILED: $TARGET_FILE (exit code $RC)"
fi
exit $RC
