"""
scripts/run_revalidation.py
Canonical runner for Full SIH Revalidation & Controlled Kinematic Ablation:
- Controlled Ablation A1..A5 on S1 30s master window
- Full Multi-Window Benchmark (10s, 30s, 60s) for C7 across S1..S4
- Full SIH Scenario A & Scenario B Evaluation
- Publication-Ready Plot Generation
"""
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from scripts.run_revalidation_v4 import main

if __name__ == '__main__':
    main()
