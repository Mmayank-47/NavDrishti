"""
src/export/onnx_exporter.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Model Export, ONNX Runtime Validation, Dynamic Quantization & Edge Profiler
Adheres to Section 65 (Principles 21, 31) and Sections 46-48 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

import os
import sys
import time
from pathlib import Path
from typing import Dict, Any, Tuple, List, Optional, Union
import numpy as np

# Safe conditional imports for environments where torch/onnx might not be present locally
try:
    import torch
    import torch.nn as nn
    HAS_TORCH = True
except ImportError:
    torch = None
    nn = None
    HAS_TORCH = False

try:
    import onnx
    import onnxruntime as ort
    HAS_ONNX = True
except ImportError:
    onnx = None
    ort = None
    HAS_ONNX = False

try:
    from onnxruntime.quantization import quantize_dynamic, QuantType
    HAS_QUANT = True
except ImportError:
    quantize_dynamic = None
    QuantType = None
    HAS_QUANT = False


def _to_numpy(tensor_or_array) -> np.ndarray:
    """Helper to convert torch.Tensor or numpy array to contiguous float32 numpy array."""
    if HAS_TORCH and isinstance(tensor_or_array, torch.Tensor):
        return tensor_or_array.detach().cpu().numpy().astype(np.float32)
    return np.asarray(tensor_or_array, dtype=np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# 1. MODEL EXPORT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def export_limu_bert(
    ckpt_path: Union[str, Path],
    output_path: Union[str, Path],
    device: str = "cpu",
    opset_version: int = 14
) -> Dict[str, Any]:
    """
    Export pretrained LIMU-BERT model to ONNX.
    Inputs:
      - imu_input: (batch_size, seq_len, 6)
    Outputs:
      - reconstructed_imu: (batch_size, seq_len, 6)
      - latent_features: (batch_size, seq_len, hidden_dim)
    """
    if not HAS_TORCH:
        raise RuntimeError("PyTorch is required to export LIMU-BERT.")

    from src.models.limu_bert import LIMUBERT

    ckpt_path = Path(ckpt_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not ckpt_path.exists():
        raise FileNotFoundError(f"LIMU-BERT checkpoint not found at: {ckpt_path}")

    device = torch.device(device)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    cfg = ckpt.get('config', {})

    model = LIMUBERT(
        input_dim=6,
        hidden_dim=cfg.get('hidden_dim', 128),
        num_heads=cfg.get('num_heads', 4),
        num_layers=cfg.get('num_layers', 4)
    ).to(device)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()

    dummy_input = torch.randn(1, 120, 6, device=device)

    dynamic_axes = {
        'imu_input': {0: 'batch_size', 1: 'seq_len'},
        'reconstructed_imu': {0: 'batch_size', 1: 'seq_len'},
        'latent_features': {0: 'batch_size', 1: 'seq_len'}
    }

    torch.onnx.export(
        model,
        dummy_input,
        str(output_path),
        input_names=['imu_input'],
        output_names=['reconstructed_imu', 'latent_features'],
        dynamic_axes=dynamic_axes,
        opset_version=opset_version,
        do_constant_folding=True
    )

    param_count = sum(p.numel() for p in model.parameters())
    file_size_bytes = output_path.stat().st_size

    return {
        "model_name": "limu_bert",
        "onnx_path": str(output_path),
        "param_count": param_count,
        "size_mb": file_size_bytes / (1024 * 1024),
        "dummy_input_shape": list(dummy_input.shape),
        "model_ref": model
    }


def export_inertial_odometry(
    ckpt_path: Union[str, Path],
    output_path: Union[str, Path],
    device: str = "cpu",
    opset_version: int = 14
) -> Dict[str, Any]:
    """
    Export pretrained Neural Inertial Odometry (TLIO) network to ONNX.
    Inputs:
      - imu_sequence: (batch_size, seq_len, 6)
    Outputs:
      - disp_2d: (batch_size, 2)
      - vel_2d: (batch_size, 2)
      - logvar_2d: (batch_size, 2)
    """
    if not HAS_TORCH:
        raise RuntimeError("PyTorch is required to export Neural Inertial Odometry.")

    from src.models.inertial_odometry import NeuralInertialOdometry

    ckpt_path = Path(ckpt_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not ckpt_path.exists():
        raise FileNotFoundError(f"Inertial Odometry checkpoint not found at: {ckpt_path}")

    device = torch.device(device)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    cfg = ckpt.get('config', {})

    model = NeuralInertialOdometry(
        input_dim=6,
        tcn_channels=cfg.get('tcn_channels', [64, 128, 256]),
        kernel_size=cfg.get('tcn_kernel_size', 3)
    ).to(device)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()

    dummy_input = torch.randn(1, 100, 6, device=device)

    dynamic_axes = {
        'imu_sequence': {0: 'batch_size', 1: 'seq_len'},
        'disp_2d': {0: 'batch_size'},
        'vel_2d': {0: 'batch_size'},
        'logvar_2d': {0: 'batch_size'}
    }

    torch.onnx.export(
        model,
        dummy_input,
        str(output_path),
        input_names=['imu_sequence'],
        output_names=['disp_2d', 'vel_2d', 'logvar_2d'],
        dynamic_axes=dynamic_axes,
        opset_version=opset_version,
        do_constant_folding=True
    )

    param_count = sum(p.numel() for p in model.parameters())
    file_size_bytes = output_path.stat().st_size

    return {
        "model_name": "inertial_odometry",
        "onnx_path": str(output_path),
        "param_count": param_count,
        "size_mb": file_size_bytes / (1024 * 1024),
        "dummy_input_shape": list(dummy_input.shape),
        "model_ref": model
    }


def export_kalmannet(
    ckpt_path: Union[str, Path],
    output_path: Union[str, Path],
    device: str = "cpu",
    opset_version: int = 14
) -> Dict[str, Any]:
    """
    Export pretrained KalmanNet adaptive filtering network to ONNX for single-step online filtering.
    Inputs:
      - delta_x: (batch_size, state_dim=4)
      - innovation: (batch_size, meas_dim=2)
      - delta_z: (batch_size, meas_dim=2)
      - h_prev: (num_layers=2, batch_size, hidden_dim=64)
    Outputs:
      - kalman_gain: (batch_size, 4, 2)
      - h_next: (num_layers=2, batch_size, hidden_dim=64)
    """
    if not HAS_TORCH:
        raise RuntimeError("PyTorch is required to export KalmanNet.")

    from src.models.kalmannet import KalmanNetNN

    ckpt_path = Path(ckpt_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not ckpt_path.exists():
        raise FileNotFoundError(f"KalmanNet checkpoint not found at: {ckpt_path}")

    device = torch.device(device)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    cfg = ckpt.get('config', {})

    model = KalmanNetNN(
        state_dim=cfg.get('state_dim', 4),
        meas_dim=cfg.get('meas_dim', 2),
        hidden_dim=cfg.get('hidden_dim', 64),
        num_layers=cfg.get('num_layers', 2)
    ).to(device)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()

    dummy_delta_x = torch.zeros(1, 4, device=device)
    dummy_innovation = torch.zeros(1, 2, device=device)
    dummy_delta_z = torch.zeros(1, 2, device=device)
    dummy_h_prev = torch.zeros(2, 1, 64, device=device)
    dummy_inputs = (dummy_delta_x, dummy_innovation, dummy_delta_z, dummy_h_prev)

    dynamic_axes = {
        'delta_x': {0: 'batch_size'},
        'innovation': {0: 'batch_size'},
        'delta_z': {0: 'batch_size'},
        'h_prev': {1: 'batch_size'},
        'kalman_gain': {0: 'batch_size'},
        'h_next': {1: 'batch_size'}
    }

    torch.onnx.export(
        model,
        dummy_inputs,
        str(output_path),
        input_names=['delta_x', 'innovation', 'delta_z', 'h_prev'],
        output_names=['kalman_gain', 'h_next'],
        dynamic_axes=dynamic_axes,
        opset_version=opset_version,
        do_constant_folding=True
    )

    param_count = sum(p.numel() for p in model.parameters())
    file_size_bytes = output_path.stat().st_size

    return {
        "model_name": "kalmannet",
        "onnx_path": str(output_path),
        "param_count": param_count,
        "size_mb": file_size_bytes / (1024 * 1024),
        "dummy_input_shapes": [list(d.shape) for d in dummy_inputs],
        "model_ref": model
    }


def export_map_gnn(
    ckpt_path: Union[str, Path],
    output_path: Union[str, Path],
    device: str = "cpu",
    k_candidates: int = 5,
    opset_version: int = 14
) -> Dict[str, Any]:
    """
    Export pretrained MapGNN topology-aware candidate road ranker to ONNX.
    Inputs:
      - query_feat: (batch_size, 6)
      - candidate_feats: (batch_size, K=5, 6)
      - adj_matrix: (batch_size, K=5, K=5)
    Outputs:
      - log_probs: (batch_size, K=5)
    """
    if not HAS_TORCH:
        raise RuntimeError("PyTorch is required to export MapGNN.")

    from src.models.map_gnn import MapGNN

    ckpt_path = Path(ckpt_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not ckpt_path.exists():
        raise FileNotFoundError(f"MapGNN checkpoint not found at: {ckpt_path}")

    device = torch.device(device)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)

    model = MapGNN(query_dim=6, edge_dim=6, hidden_dim=64).to(device)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()

    dummy_query = torch.randn(1, 6, device=device)
    dummy_candidates = torch.randn(1, k_candidates, 6, device=device)
    dummy_adj = torch.eye(k_candidates, device=device).unsqueeze(0)
    dummy_inputs = (dummy_query, dummy_candidates, dummy_adj)

    dynamic_axes = {
        'query_feat': {0: 'batch_size'},
        'candidate_feats': {0: 'batch_size'},
        'adj_matrix': {0: 'batch_size'},
        'log_probs': {0: 'batch_size'}
    }

    torch.onnx.export(
        model,
        dummy_inputs,
        str(output_path),
        input_names=['query_feat', 'candidate_feats', 'adj_matrix'],
        output_names=['log_probs'],
        dynamic_axes=dynamic_axes,
        opset_version=opset_version,
        do_constant_folding=True
    )

    param_count = sum(p.numel() for p in model.parameters())
    file_size_bytes = output_path.stat().st_size

    return {
        "model_name": "map_gnn",
        "onnx_path": str(output_path),
        "param_count": param_count,
        "size_mb": file_size_bytes / (1024 * 1024),
        "dummy_input_shapes": [list(d.shape) for d in dummy_inputs],
        "model_ref": model
    }


def export_all_models(
    checkpoints_dir: Union[str, Path] = "checkpoints",
    output_dir: Union[str, Path] = "exports/onnx",
    device: str = "cpu"
) -> Dict[str, Any]:
    """Export all 4 neural network models in one call."""
    checkpoints_dir = Path(checkpoints_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    results = {}

    # 1. LIMU-BERT
    lb_ckpt = checkpoints_dir / "limu_bert" / "limu_bert_best.pt"
    if lb_ckpt.exists():
        results["limu_bert"] = export_limu_bert(lb_ckpt, output_dir / "limu_bert.onnx", device=device)

    # 2. Neural Inertial Odometry
    io_ckpt = checkpoints_dir / "inertial_odometry" / "inertial_odometry_best.pt"
    if io_ckpt.exists():
        results["inertial_odometry"] = export_inertial_odometry(io_ckpt, output_dir / "inertial_odometry.onnx", device=device)

    # 3. KalmanNet
    kn_ckpt = checkpoints_dir / "kalmannet" / "kalmannet_best.pt"
    if kn_ckpt.exists():
        results["kalmannet"] = export_kalmannet(kn_ckpt, output_dir / "kalmannet.onnx", device=device)

    # 4. MapGNN
    mg_ckpt = checkpoints_dir / "map_gnn" / "map_gnn_best.pt"
    if mg_ckpt.exists():
        results["map_gnn"] = export_map_gnn(mg_ckpt, output_dir / "map_gnn.onnx", device=device)

    return results


# ─────────────────────────────────────────────────────────────────────────────
# 2. NUMERIC EQUIVALENCE VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────

def verify_numeric_equivalence(
    model_pt: Any,
    onnx_path: Union[str, Path],
    sample_inputs: Union[Tuple, List, Any],
    atol: float = 1e-4,
    rtol: float = 1e-3,
    providers: Optional[List[str]] = None
) -> Dict[str, Any]:
    """
    Validate that PyTorch and ONNX Runtime inference outputs match within tolerance.
    """
    if not HAS_ONNX:
        raise RuntimeError("onnx and onnxruntime are required for equivalence verification.")

    onnx_path = Path(onnx_path)
    if not onnx_path.exists():
        raise FileNotFoundError(f"ONNX model not found: {onnx_path}")

    if providers is None:
        providers = ['CPUExecutionProvider']

    sess = ort.InferenceSession(str(onnx_path), providers=providers)

    # Normalize inputs to tuple
    if not isinstance(sample_inputs, (tuple, list)):
        inputs_tuple = (sample_inputs,)
    else:
        inputs_tuple = tuple(sample_inputs)

    # 1. PyTorch Forward Pass
    if HAS_TORCH and isinstance(model_pt, nn.Module):
        model_pt.eval()
        with torch.no_grad():
            pt_out = model_pt(*inputs_tuple)
            if not isinstance(pt_out, (tuple, list)):
                pt_outputs = [pt_out]
            else:
                pt_outputs = list(pt_out)
            pt_arrays = [_to_numpy(o) for o in pt_outputs]
    else:
        raise ValueError("model_pt must be an instance of torch.nn.Module")

    # 2. ONNX Runtime Forward Pass
    input_names = [inp.name for inp in sess.get_inputs()]
    ort_feed = {}
    for name, val in zip(input_names, inputs_tuple):
        ort_feed[name] = _to_numpy(val)

    ort_arrays = sess.run(None, ort_feed)

    # 3. Compare Outputs
    matches = []
    max_abs_diffs = []
    max_rel_diffs = []

    for i, (pt_arr, ort_arr) in enumerate(zip(pt_arrays, ort_arrays)):
        abs_diff = np.max(np.abs(pt_arr - ort_arr))
        denom = np.maximum(np.abs(pt_arr), 1e-7)
        rel_diff = np.max(np.abs(pt_arr - ort_arr) / denom)

        is_close = np.allclose(pt_arr, ort_arr, rtol=rtol, atol=atol)
        matches.append(bool(is_close))
        max_abs_diffs.append(float(abs_diff))
        max_rel_diffs.append(float(rel_diff))

    overall_pass = all(matches)
    return {
        "passed": overall_pass,
        "num_outputs": len(ort_arrays),
        "max_abs_diff": float(max(max_abs_diffs)),
        "max_rel_diff": float(max(max_rel_diffs)),
        "channel_abs_diffs": max_abs_diffs,
        "channel_matches": matches
    }


# ─────────────────────────────────────────────────────────────────────────────
# 3. DYNAMIC QUANTIZATION (INT8)
# ─────────────────────────────────────────────────────────────────────────────

def quantize_onnx_model(
    onnx_path: Union[str, Path],
    quant_path: Union[str, Path]
) -> Dict[str, Any]:
    """
    Apply Dynamic INT8 quantization to an ONNX model for mobile/edge optimization.
    """
    if not HAS_QUANT:
        raise RuntimeError("onnxruntime.quantization is required for dynamic quantization.")

    onnx_path = Path(onnx_path)
    quant_path = Path(quant_path)
    quant_path.parent.mkdir(parents=True, exist_ok=True)

    quantize_dynamic(
        model_input=str(onnx_path),
        model_output=str(quant_path),
        weight_type=QuantType.QUInt8
    )

    orig_size = onnx_path.stat().st_size
    quant_size = quant_path.stat().st_size
    reduction_pct = (1.0 - quant_size / orig_size) * 100.0

    return {
        "original_onnx": str(onnx_path),
        "quantized_onnx": str(quant_path),
        "original_mb": orig_size / (1024 * 1024),
        "quantized_mb": quant_size / (1024 * 1024),
        "size_reduction_pct": reduction_pct,
        "compression_ratio": orig_size / max(quant_size, 1)
    }


# ─────────────────────────────────────────────────────────────────────────────
# 4. LATENCY BENCHMARKING & EDGE RESOURCE PROFILER
# ─────────────────────────────────────────────────────────────────────────────

def benchmark_latency(
    target: Any,
    sample_inputs: Union[Tuple, List, Any],
    is_onnx: bool = False,
    n_runs: int = 100,
    warmup: int = 20,
    input_names: Optional[List[str]] = None
) -> Dict[str, Any]:
    """
    Benchmark inference latency (p50, p95, p99, mean, std) in milliseconds.
    """
    if not isinstance(sample_inputs, (tuple, list)):
        inputs_tuple = (sample_inputs,)
    else:
        inputs_tuple = tuple(sample_inputs)

    if is_onnx:
        sess = target
        if input_names is None:
            input_names = [inp.name for inp in sess.get_inputs()]
        feed_dict = {name: _to_numpy(val) for name, val in zip(input_names, inputs_tuple)}

        # Warmup
        for _ in range(warmup):
            sess.run(None, feed_dict)

        # Timed benchmark
        latencies = []
        for _ in range(n_runs):
            t0 = time.perf_counter()
            sess.run(None, feed_dict)
            t1 = time.perf_counter()
            latencies.append((t1 - t0) * 1000.0)
    else:
        model = target
        if HAS_TORCH and isinstance(model, nn.Module):
            model.eval()
            with torch.no_grad():
                # Warmup
                for _ in range(warmup):
                    _ = model(*inputs_tuple)

                # Timed benchmark
                latencies = []
                for _ in range(n_runs):
                    t0 = time.perf_counter()
                    _ = model(*inputs_tuple)
                    t1 = time.perf_counter()
                    latencies.append((t1 - t0) * 1000.0)
        else:
            raise ValueError("Target must be a PyTorch nn.Module or ONNX InferenceSession")

    latencies = np.array(latencies)
    mean_lat = float(np.mean(latencies))
    std_lat = float(np.std(latencies))
    p50 = float(np.percentile(latencies, 50))
    p95 = float(np.percentile(latencies, 95))
    p99 = float(np.percentile(latencies, 99))
    fps = 1000.0 / mean_lat if mean_lat > 0 else 0.0

    return {
        "mean_ms": mean_lat,
        "std_ms": std_lat,
        "p50_ms": p50,
        "p95_ms": p95,
        "p99_ms": p99,
        "min_ms": float(np.min(latencies)),
        "max_ms": float(np.max(latencies)),
        "throughput_fps": fps,
        "n_runs": n_runs
    }


def profile_model_footprint(
    pt_path: Optional[Union[str, Path]] = None,
    onnx_path: Optional[Union[str, Path]] = None,
    quant_path: Optional[Union[str, Path]] = None
) -> Dict[str, Any]:
    """
    Profile disk footprint and memory requirements of PyTorch, ONNX FP32, and ONNX INT8 models.
    """
    res = {}
    if pt_path and Path(pt_path).exists():
        sz = Path(pt_path).stat().st_size
        res["pytorch_pt_mb"] = sz / (1024 * 1024)

    if onnx_path and Path(onnx_path).exists():
        sz = Path(onnx_path).stat().st_size
        res["onnx_fp32_mb"] = sz / (1024 * 1024)

    if quant_path and Path(quant_path).exists():
        sz = Path(quant_path).stat().st_size
        res["onnx_int8_mb"] = sz / (1024 * 1024)

    if "onnx_fp32_mb" in res and "onnx_int8_mb" in res:
        res["compression_ratio"] = res["onnx_fp32_mb"] / max(res["onnx_int8_mb"], 1e-6)
        res["savings_pct"] = (1.0 - res["onnx_int8_mb"] / res["onnx_fp32_mb"]) * 100.0

    return res
