"""
scripts/verify_phase9.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 9 Verification Suite: Model Export & Lightweight Edge / Mobile Validation
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import os
import json
import unittest
from pathlib import Path

# Ensure project root is on sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))


class TestPhase9ModelExport(unittest.TestCase):
    """Test suite for Phase 9 export, quantization, and edge profiling tools."""

    def test_01_export_module_imports(self):
        """Verify all export API symbols are correctly exposed."""
        import src.export as exp
        required_symbols = [
            "export_limu_bert",
            "export_inertial_odometry",
            "export_kalmannet",
            "export_map_gnn",
            "export_all_models",
            "verify_numeric_equivalence",
            "quantize_onnx_model",
            "benchmark_latency",
            "profile_model_footprint"
        ]
        for sym in required_symbols:
            self.assertTrue(hasattr(exp, sym), f"Missing exported symbol: {sym}")

    def test_02_checkpoint_existence(self):
        """Verify that all 4 trained checkpoints exist before export."""
        ckpts = [
            PROJECT_ROOT / "checkpoints" / "limu_bert" / "limu_bert_best.pt",
            PROJECT_ROOT / "checkpoints" / "inertial_odometry" / "inertial_odometry_best.pt",
            PROJECT_ROOT / "checkpoints" / "kalmannet" / "kalmannet_best.pt",
            PROJECT_ROOT / "checkpoints" / "map_gnn" / "map_gnn_best.pt"
        ]
        for c in ckpts:
            self.assertTrue(c.exists(), f"Required checkpoint missing: {c}")
            self.assertGreater(c.stat().st_size, 10000, f"Checkpoint file too small: {c}")

    def test_03_footprint_profiler(self):
        """Verify footprint profiler on real checkpoints."""
        from src.export.onnx_exporter import profile_model_footprint
        lb_ckpt = PROJECT_ROOT / "checkpoints" / "limu_bert" / "limu_bert_best.pt"
        res = profile_model_footprint(pt_path=lb_ckpt)
        self.assertIn("pytorch_pt_mb", res)
        self.assertGreater(res["pytorch_pt_mb"], 1.0)

    def test_04_notebook_validity(self):
        """Verify 23_model_export_and_mobile_validation.ipynb JSON structure."""
        nb_path = PROJECT_ROOT / "notebooks" / "23_model_export_and_mobile_validation.ipynb"
        if nb_path.exists():
            with open(nb_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.assertIn("cells", data)
            self.assertGreater(len(data["cells"]), 5)
            print(f"Verified notebook 23: {len(data['cells'])} cells.")


if __name__ == "__main__":
    unittest.main(verbosity=2)
