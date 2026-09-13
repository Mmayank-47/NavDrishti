import pathspec
from pathlib import Path

with open('.gitignore', 'r', encoding='utf-8') as f:
    spec = pathspec.PathSpec.from_lines('gitwildmatch', f)

test_files = [
    # Critical Secrets
    ('configs/lightning.env', True),
    ('configs/lightning.env.template', False),
    # Large Datasets (>10GB total)
    ('data/OSM/india-260912.osm.pbf', True),
    ('data/IO-VNBD/Synchronised V abd S datasets/Uncategorised IOVNB Dataset/S-Dataset/S-A10.csv', True),
    ('data/IO-VNBD/.git/config', True),
    ('data/NavICGNSS android raw measurments/some_file.nmea', True),
    ('data/GNSS Dataset (with Interference and Spoofing) Part III/test.mat', True),
    ('data/MOTOR/test.csv', True),
    ('data/.gitkeep', False),
    # Archives (Exceeds GitHub 100MB limit)
    ('iovnbd_sync.tar.gz', True),
    ('motor_sync.tar.gz', True),
    ('sih_sync_bundle.tar.gz', True),
    ('some_file.zip', True),
    # Checkpoints
    ('checkpoints/limu_bert/limu_bert_best.pt', True),
    ('checkpoints/inertial_odometry/inertial_odometry_best.pt', True),
    ('checkpoints/kalmannet/kalmannet_best.pt', True),
    ('checkpoints/map_gnn/map_gnn_best.pt', True),
    ('checkpoints/limu_bert/.gitkeep', False),
    # Exports
    ('exports/onnx/limu_bert.onnx', True),
    ('exports/quantized/limu_bert.quant.onnx', True),
    ('exports/onnx/.gitkeep', False),
    # Code & Docs (MUST BE TRACKED)
    ('src/integration/final_navigation_pipeline.py', False),
    ('src/models/limu_bert.py', False),
    ('notebooks/23_model_export_and_mobile_validation.ipynb', False),
    ('docs/phase_9_model_export_report.md', False),
    ('results/model_export_metrics.json', False),
    ('plots/export/model_latency_comparison.png', False),
    ('procedure_roadmap.md', False),
    ('PROJECT_RULES.md', False),
    # VSCode automation tools (MUST BE TRACKED)
    ('.vscode/tasks.json', False),
    ('.vscode/sync_and_run.ps1', False),
    # VSCode machine specific settings (MUST BE IGNORED)
    ('.vscode/settings.json', True),
    # Executed notebooks (MUST BE IGNORED)
    ('notebooks/20_final_pipeline_integration_executed.ipynb', True),
]

all_ok = True
print(f"{'Target File / Path':<70} {'Expected':<12} {'Actual':<12} {'Status'}")
print("-" * 105)
for path, expected_ignore in test_files:
    actual_ignore = spec.match_file(path)
    ok = (actual_ignore == expected_ignore)
    if not ok:
        all_ok = False
    exp_str = "IGNORED" if expected_ignore else "TRACKED"
    act_str = "IGNORED" if actual_ignore else "TRACKED"
    res_str = "PASS" if ok else "FAIL"
    print(f"{path:<70} {exp_str:<12} {act_str:<12} {res_str}")

print("-" * 105)
if all_ok:
    print("ALL GITIGNORE RULES VERIFIED PERFECTLY (100% PASS).")
else:
    print("SOME RULES FAILED.")
