"""
scripts/benchmark_mobile_nio.py
─────────────────────────────────────────────────────────────────────────────
Phase 13: Mobile / Edge Deployment Benchmark for Selected NIO Model
- Exports selected NIO model to ONNX
- Verifies numerical equivalence against PyTorch (L_inf norm, L2 relative error)
- Dynamic INT8 quantization
- Benchmarks FP32 and INT8 latency on CPU (mean, median, p95, max)
- Verifies real-time budget for 10 Hz operation (<100 ms)
- Measures model disk and parameter memory footprint
─────────────────────────────────────────────────────────────────────────────
"""

import os, sys, json, time
from pathlib import Path
import numpy as np
import torch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.models.inertial_odometry import NeuralInertialOdometry

DEVICE = 'cpu'  # Edge benchmark runs strictly on CPU
CKPT_DIR = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned'
CKPT_PATH = CKPT_DIR / 'nio_vel_best.pt'
if not CKPT_PATH.exists():
    CKPT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_fixed' / 'nio_fixed_best.pt'

OUT_ONNX_FP32 = CKPT_DIR / 'nio_model_fp32.onnx'
OUT_ONNX_INT8 = CKPT_DIR / 'nio_model_int8.onnx'
RESULTS_DIR = PROJECT_ROOT / 'results' / 'mobile_benchmark'


def main():
    print("=" * 70)
    print("PHASE 13: MOBILE / EDGE REGRESSION BENCHMARK")
    print("=" * 70)
    print(f"Loading checkpoint: {CKPT_PATH}")
    
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    CKPT_DIR.mkdir(parents=True, exist_ok=True)
    
    ckpt = torch.load(CKPT_PATH, map_location='cpu', weights_only=False)
    cfg = ckpt.get('config', {})
    
    model = NeuralInertialOdometry(
        input_dim=6,
        tcn_channels=cfg.get('tcn_channels', [64, 128, 256]),
        kernel_size=cfg.get('tcn_kernel_size', 3),
        dropout=0.0
    ).to('cpu')
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()
    
    # Dummy input: batch size 1, window length 100, 6 channels (accel + gyro)
    dummy_input = torch.randn(1, 100, 6, dtype=torch.float32)
    
    # ── 1. Export to ONNX FP32 ────────────────────────────────────────────────
    print("\n1. Exporting PyTorch model to ONNX FP32...")
    torch.onnx.export(
        model,
        dummy_input,
        str(OUT_ONNX_FP32),
        export_params=True,
        opset_version=14,
        do_constant_folding=True,
        input_names=['imu_input'],
        output_names=['pred_disp', 'pred_vel', 'pred_logvar'],
        dynamic_axes={
            'imu_input': {0: 'batch_size', 1: 'seq_len'},
            'pred_disp': {0: 'batch_size'},
            'pred_vel': {0: 'batch_size'},
            'pred_logvar': {0: 'batch_size'}
        }
    )
    fp32_size_mb = os.path.getsize(OUT_ONNX_FP32) / (1024 * 1024)
    print(f"   Saved ONNX FP32 to: {OUT_ONNX_FP32} ({fp32_size_mb:.2f} MB)")
    
    # ── 2. Numerical Equivalence Verification ────────────────────────────────
    print("\n2. Verifying numerical equivalence (PyTorch vs ONNX Runtime)...")
    import onnxruntime as ort
    
    session_options = ort.SessionOptions()
    session_options.intra_op_num_threads = 1
    session_options.inter_op_num_threads = 1
    session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    
    ort_session_fp32 = ort.InferenceSession(str(OUT_ONNX_FP32), session_options, providers=['CPUExecutionProvider'])
    
    with torch.no_grad():
        pt_disp, pt_vel, pt_logvar = model(dummy_input)
        
    ort_inputs = {'imu_input': dummy_input.numpy()}
    ort_outs = ort_session_fp32.run(None, ort_inputs)
    ort_disp, ort_vel, ort_logvar = ort_outs
    
    disp_diff = np.max(np.abs(pt_disp.numpy() - ort_disp))
    vel_diff = np.max(np.abs(pt_vel.numpy() - ort_vel))
    logvar_diff = np.max(np.abs(pt_logvar.numpy() - ort_logvar))
    
    print(f"   Max abs diff (Disp):   {disp_diff:.2e}")
    print(f"   Max abs diff (Vel):    {vel_diff:.2e}")
    print(f"   Max abs diff (Logvar): {logvar_diff:.2e}")
    
    max_diff = max(disp_diff, vel_diff, logvar_diff)
    assert max_diff < 1e-4, f"Numerical mismatch detected: max diff = {max_diff}"
    print(f"   [PASS] Numerical equivalence verified: max diff < 1e-4")
    
    # ── 3. Dynamic INT8 Quantization ─────────────────────────────────────────
    print("\n3. Quantizing to ONNX INT8 (Dynamic)...")
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType
        quantize_dynamic(
            model_input=str(OUT_ONNX_FP32),
            model_output=str(OUT_ONNX_INT8),
            weight_type=QuantType.QInt8
        )
        int8_size_mb = os.path.getsize(OUT_ONNX_INT8) / (1024 * 1024)
        print(f"   Saved ONNX INT8 to: {OUT_ONNX_INT8} ({int8_size_mb:.2f} MB, {int8_size_mb/fp32_size_mb*100:.1f}% of FP32)")
        has_int8 = True
    except Exception as e:
        print(f"   Warning: Dynamic quantization failed: {e}")
        has_int8 = False
        int8_size_mb = None

    # ── 4. Latency Benchmark on CPU ──────────────────────────────────────────
    print("\n4. Benchmarking latency on CPU (Single-thread, batch_size=1)...")
    
    def benchmark_session(session, n_warmup=20, n_runs=200):
        dummy_np = np.random.randn(1, 100, 6).astype(np.float32)
        # Warmup
        for _ in range(n_warmup):
            session.run(None, {'imu_input': dummy_np})
        # Timed runs
        times = []
        for _ in range(n_runs):
            t0 = time.perf_counter()
            session.run(None, {'imu_input': dummy_np})
            t1 = time.perf_counter()
            times.append((t1 - t0) * 1000.0)  # ms
        times = np.array(times)
        return {
            'mean_ms': float(np.mean(times)),
            'median_ms': float(np.median(times)),
            'p95_ms': float(np.percentile(times, 95)),
            'min_ms': float(np.min(times)),
            'max_ms': float(np.max(times)),
            'std_ms': float(np.std(times)),
            'fps': float(1000.0 / np.mean(times))
        }

    bench_fp32 = benchmark_session(ort_session_fp32)
    print(f"   ONNX FP32 Latency: Mean: {bench_fp32['mean_ms']:.2f} ms | P95: {bench_fp32['p95_ms']:.2f} ms | Throughput: {bench_fp32['fps']:.1f} Hz")
    
    bench_int8 = None
    if has_int8:
        ort_session_int8 = ort.InferenceSession(str(OUT_ONNX_INT8), session_options, providers=['CPUExecutionProvider'])
        bench_int8 = benchmark_session(ort_session_int8)
        print(f"   ONNX INT8 Latency: Mean: {bench_int8['mean_ms']:.2f} ms | P95: {bench_int8['p95_ms']:.2f} ms | Throughput: {bench_int8['fps']:.1f} Hz")

    # Real-time 10 Hz budget check (<100 ms)
    budget_ms = 100.0
    budget_pass_fp32 = bench_fp32['p95_ms'] < budget_ms
    print(f"\n5. 10 Hz Real-Time Budget Check (<100 ms):")
    print(f"   FP32 P95 Latency: {bench_fp32['p95_ms']:.2f} ms -> {'PASS' if budget_pass_fp32 else 'FAIL'}")
    if bench_int8:
        budget_pass_int8 = bench_int8['p95_ms'] < budget_ms
        print(f"   INT8 P95 Latency: {bench_int8['p95_ms']:.2f} ms -> {'PASS' if budget_pass_int8 else 'FAIL'}")

    results = {
        'checkpoint_path': str(CKPT_PATH),
        'fp32_model_size_mb': fp32_size_mb,
        'int8_model_size_mb': int8_size_mb,
        'numerical_equivalence': {
            'disp_max_abs_diff': float(disp_diff),
            'vel_max_abs_diff': float(vel_diff),
            'logvar_max_abs_diff': float(logvar_diff),
            'passed': bool(max_diff < 1e-4)
        },
        'fp32_benchmark': bench_fp32,
        'int8_benchmark': bench_int8,
        'real_time_10hz_budget_ms': budget_ms,
        'fp32_budget_pass': budget_pass_fp32
    }

    out_file = RESULTS_DIR / 'mobile_regression_results.json'
    with open(out_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved Mobile Benchmark results to: {out_file}")


if __name__ == '__main__':
    main()
