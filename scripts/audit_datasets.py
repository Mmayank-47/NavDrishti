#!/usr/bin/env python3
"""
scripts/audit_datasets.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Dataset Audit Script (standalone runnable version of notebooks/01_dataset_audit.ipynb)

Audits all 5 datasets in data/:
  1. IO-VNBD (Primary SIH Benchmark Dataset)
  2. GNSS Dataset (with Interference and Spoofing) Part III
  3. NavICGNSS Android Raw Measurements
  4. MOTOR Dataset
  5. OSM India Road Map

Generates:
  - artifacts/dataset_manifest.json
  - docs/dataset_audit.md
─────────────────────────────────────────────────────────────────────────────
"""

import os
import sys
import json
import datetime
from pathlib import Path

# Ensure UTF-8 output encoding on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

import numpy as np
import pandas as pd
import yaml

# Set root
PROJECT_ROOT = Path(__file__).resolve().parent.parent
os.chdir(PROJECT_ROOT)

with open('configs/paths.yaml', 'r') as f:
    PATHS = yaml.safe_load(f)

ARTIFACTS = PROJECT_ROOT / PATHS['artifacts_dir']
DOCS      = PROJECT_ROOT / PATHS['docs_dir']
PLOTS     = PROJECT_ROOT / PATHS['plots_dir']
ARTIFACTS.mkdir(parents=True, exist_ok=True)
DOCS.mkdir(parents=True, exist_ok=True)
(PLOTS / 'audit').mkdir(parents=True, exist_ok=True)

NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()

print("=" * 60)
print("  SIH PS 26168 — Dataset Audit")
print("=" * 60)
print(f"Timestamp    : {NOW}")
print(f"Project Root : {PROJECT_ROOT}")
print(f"Artifacts Dir: {ARTIFACTS}")
print("")

def folder_size_mb(path):
    p = Path(path)
    if not p.exists():
        return 0.0
    total = sum(f.stat().st_size for f in p.rglob('*') if f.is_file())
    return round(total / 1e6, 2)

def list_files(path, exts=None, max_depth=5):
    root = Path(path)
    if not root.exists():
        return []
    files = []
    for f in root.rglob('*'):
        if not f.is_file():
            continue
        try:
            depth = len(f.relative_to(root).parts)
            if depth > max_depth:
                continue
            if exts and f.suffix.lower() not in exts:
                continue
            files.append(f)
        except Exception:
            continue
    return sorted(files)

def detect_sampling_rate(timestamps):
    try:
        ts = pd.to_numeric(timestamps, errors='coerce').dropna().sort_values()
        if len(ts) < 5:
            return None, None
        diffs = ts.diff().dropna()
        diffs = diffs[diffs > 0]
        if len(diffs) == 0:
            return None, None
        median_dt = diffs.median()
        if median_dt <= 0:
            return None, None
        # Determine time unit
        if median_dt > 1e11: # nanoseconds
            hz = round(1e9 / median_dt, 2)
            dt_s = median_dt / 1e9
        elif median_dt > 1e8: # microseconds
            hz = round(1e6 / median_dt, 2)
            dt_s = median_dt / 1e6
        elif median_dt > 50: # milliseconds
            hz = round(1000.0 / median_dt, 2)
            dt_s = median_dt / 1000.0
        else: # seconds
            hz = round(1.0 / median_dt, 2)
            dt_s = median_dt
        return round(float(dt_s), 6), float(hz)
    except Exception:
        return None, None

def audit_csv(path, label='', max_rows=20000):
    try:
        try:
            df = pd.read_csv(path, nrows=max_rows, low_memory=False)
        except UnicodeDecodeError:
            df = pd.read_csv(path, nrows=max_rows, low_memory=False, encoding='latin1')
        
        # Clean column names (strip whitespace)
        df.columns = [c.strip() for c in df.columns]
        cols = list(df.columns)
        dtypes = {c: str(df[c].dtype) for c in cols}
        missing_count = {c: int(df[c].isnull().sum()) for c in cols}
        missing_pct = {c: round(float(df[c].isnull().mean() * 100), 2) for c in cols}
        
        info = {
            'file': str(path),
            'label': label,
            'rows_sampled': len(df),
            'columns': cols,
            'dtypes': dtypes,
            'missing_count': missing_count,
            'missing_pct': missing_pct,
        }
        return df, info
    except Exception as e:
        return None, {'file': str(path), 'error': str(e)}

manifest = {
    'audit_timestamp_utc': NOW,
    'project': 'SIH PS 26168 — Intelligent Dead Reckoning',
    'datasets': {}
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. IO-VNBD AUDIT (Primary Dataset)
# ─────────────────────────────────────────────────────────────────────────────
print("── [1/5] Auditing IO-VNBD ────────────────────────────────────")
IO_ROOT = PROJECT_ROOT / PATHS['datasets']['io_vnbd']['root']
IO_SYNC = PROJECT_ROOT / PATHS['datasets']['io_vnbd']['synchronised']
IO_UNSYNC = PROJECT_ROOT / PATHS['datasets']['io_vnbd']['unsynchronised']

print(f"Root: {IO_ROOT}")
print(f"Sync path: {IO_SYNC} (exists: {IO_SYNC.exists()})")
io_size = folder_size_mb(IO_ROOT)
print(f"Size: {io_size} MB")

csv_files = list_files(IO_SYNC, exts=['.csv'], max_depth=6) if IO_SYNC.exists() else []
if not csv_files:
    csv_files = list_files(IO_ROOT, exts=['.csv'], max_depth=6)
print(f"Total CSV files found: {len(csv_files)}")

io_sessions = []
v_count = 0
s_count = 0

for csv_path in csv_files:
    # Audit all sessions for manifest
    is_smartphone = csv_path.name.startswith('S-')
    is_vehicle = csv_path.name.startswith('V-')
    if is_smartphone: s_count += 1
    if is_vehicle: v_count += 1
    
    # Detailed row audit on a subset of sessions
    if len(io_sessions) < 30:
        df, info = audit_csv(csv_path, label=csv_path.stem)
        if df is None:
            print(f"  Error reading {csv_path.name}: {info.get('error')}")
            continue
        cols = info['columns']
        ts_candidates = [c for c in cols if any(k in c.lower() for k in ['time', 'ts', 't_', 'date', 'epoch'])]
        dt, hz = (None, None)
        if ts_candidates:
            dt, hz = detect_sampling_rate(df[ts_candidates[0]])
        
        imu_cols = [c for c in cols if any(k in c.lower() for k in ['acc', 'gyro', 'mag', 'gyr', 'imu', 'linear_acc'])]
        gnss_cols = [c for c in cols if any(k in c.lower() for k in ['lat', 'lon', 'alt', 'gps', 'gnss', 'speed', 'hdop', 'pdop'])]
        gt_cols = [c for c in cols if any(k in c.lower() for k in ['gt', 'ground', 'truth', 'ref', 'vel', 'vx', 'vy', 'true'])]
        
        missing_pct = {k: v for k, v in info['missing_pct'].items() if v > 0}
        
        io_sessions.append({
            'file': str(csv_path.relative_to(PROJECT_ROOT)),
            'stem': csv_path.stem,
            'type': 'smartphone' if is_smartphone else ('vehicle' if is_vehicle else 'unknown'),
            'driver': csv_path.parent.name,
            'rows_sampled': info['rows_sampled'],
            'columns': cols,
            'timestamp_candidates': ts_candidates,
            'sampling_rate_hz': hz,
            'sampling_interval_s': dt,
            'imu_columns': imu_cols,
            'gnss_columns': gnss_cols,
            'ground_truth_columns': gt_cols,
            'missing_pct': missing_pct,
        })

print(f"Audited {len(io_sessions)} representative sessions ({v_count} Vehicle sessions, {s_count} Smartphone sessions total).")
if io_sessions:
    print(f"  Sample Vehicle Session: {next((s['file'] for s in io_sessions if s['type']=='vehicle'), 'N/A')}")
    print(f"  Sample Smartphone Session: {next((s['file'] for s in io_sessions if s['type']=='smartphone'), 'N/A')}")

manifest['datasets']['io_vnbd'] = {
    'source_folder': str(IO_ROOT.relative_to(PROJECT_ROOT)),
    'role': 'Primary real vehicle dataset for official SIH inertial-odometry benchmarking',
    'primary': True,
    'size_mb': io_size,
    'total_csv_files': len(csv_files),
    'vehicle_session_count': v_count,
    'smartphone_session_count': s_count,
    'audited_sessions': len(io_sessions),
    'sessions': io_sessions,
    'notes': [
        'Primary benchmark dataset containing vehicle and smartphone IMU + GNSS + GT data.',
        'Session-level train/validation/test splits defined to prevent data leakage.',
        'Ground truth reference used exclusively for loss calculation and evaluation, never during GNSS-denied inference.'
    ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. GNSS INTERFERENCE DATASET AUDIT
# ─────────────────────────────────────────────────────────────────────────────
print("\n── [2/5] Auditing GNSS Interference Dataset ──────────────────")
GNSS_ROOT = PROJECT_ROOT / PATHS['datasets']['gnss_interference']['root']
print(f"Root: {GNSS_ROOT} (exists: {GNSS_ROOT.exists()})")
gnss_size = folder_size_mb(GNSS_ROOT)
print(f"Size: {gnss_size} MB")

gnss_json_files = list_files(GNSS_ROOT, exts=['.json'], max_depth=5)
gnss_csv_files  = list_files(GNSS_ROOT, exts=['.csv', '.txt'], max_depth=5)
print(f"Found {len(gnss_json_files)} JSON files and {len(gnss_csv_files)} text/CSV files.")

gnss_sessions = []
# Audit sample pvtSolution files
pvt_files = [f for f in gnss_json_files if 'pvtsolution' in f.name.lower()]
obs_files = [f for f in gnss_json_files if 'observation' in f.name.lower()]

for pf in pvt_files[:5]:
    try:
        with open(pf, 'r', encoding='utf-8') as f:
            pdata = json.load(f)
        fields = list(pdata.keys()) if isinstance(pdata, dict) else []
        n_records = len(pdata[fields[0]]) if (fields and isinstance(pdata[fields[0]], list)) else 1
        gnss_sessions.append({
            'file': str(pf.relative_to(PROJECT_ROOT)),
            'type': 'pvt_solution',
            'fields': fields,
            'records': n_records,
            'has_velocities': any('vel' in k.lower() for k in fields),
            'has_numSV': 'numSV' in fields,
        })
    except Exception as e:
        print(f"  Error reading {pf.name}: {e}")

print(f"Audited {len(gnss_sessions)} PVT solution files (total PVT files: {len(pvt_files)}, observation files: {len(obs_files)}).")

manifest['datasets']['gnss_interference'] = {
    'source_folder': str(GNSS_ROOT.relative_to(PROJECT_ROOT)) if GNSS_ROOT.exists() else str(PATHS['datasets']['gnss_interference']['root']),
    'role': 'GNSS interference, jamming, and spoofing experiments',
    'primary': False,
    'size_mb': gnss_size,
    'total_json_files': len(gnss_json_files),
    'pvt_solution_files': len(pvt_files),
    'observation_files': len(obs_files),
    'sessions': gnss_sessions,
    'notes': [
        'Contains rich JSON observations and PVT solutions (velN, velE, velD, lat, lon, height, numSV).',
        'Use for GNSS quality/degradation detection experiments and covariance estimation.',
        'Validate schemas before use in any fusion pipeline.'
    ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. NavICGNSS ANDROID RAW MEASUREMENTS AUDIT
# ─────────────────────────────────────────────────────────────────────────────
print("\n── [3/5] Auditing NavICGNSS Android Raw Measurements ─────────")
NAVIC_ROOT = PROJECT_ROOT / PATHS['datasets']['navic_gnss']['root']
print(f"Root: {NAVIC_ROOT} (exists: {NAVIC_ROOT.exists()})")
navic_size = folder_size_mb(NAVIC_ROOT)
print(f"Size: {navic_size} MB")

navic_files = list_files(NAVIC_ROOT, max_depth=5)
print(f"Total files: {len(navic_files)}")

navic_sessions = []
navic_csvs = list_files(NAVIC_ROOT, exts=['.csv', '.txt', '.log', '.nmea'], max_depth=5)
for f in navic_csvs[:10]:
    df, info = audit_csv(f, label=f.stem)
    if df is not None:
        navic_sessions.append({
            'file': str(f.relative_to(PROJECT_ROOT)),
            'rows_sampled': info['rows_sampled'],
            'columns': info['columns'],
        })

# Check for ground truth reference
gt_file = NAVIC_ROOT / 'ublox_ground_truth_positions.txt'
gt_info = None
if gt_file.exists():
    with open(gt_file, 'r', encoding='utf-8', errors='ignore') as f:
        gt_content = f.read()
    gt_info = {
        'file': str(gt_file.relative_to(PROJECT_ROOT)),
        'content_snippet': gt_content.strip()[:200]
    }
    print(f"  Found ground truth file: {gt_file.name}")

manifest['datasets']['navic_gnss'] = {
    'source_folder': str(NAVIC_ROOT.relative_to(PROJECT_ROOT)) if NAVIC_ROOT.exists() else str(PATHS['datasets']['navic_gnss']['root']),
    'role': 'Android/NavIC raw GNSS measurement experiments and GNSS-side validation',
    'primary': False,
    'size_mb': navic_size,
    'total_files': len(navic_files),
    'ground_truth': gt_info,
    'sessions': navic_sessions,
    'notes': [
        'Contains Android raw GNSS measurements across multiple inclination angles (0, 45, 90, 135, 180 deg).',
        'Includes reference Ublox ground truth static positions.',
        'Supports NavIC (IRNSS) constellation raw measurements.'
    ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. MOTOR DATASET AUDIT
# ─────────────────────────────────────────────────────────────────────────────
print("\n── [4/5] Auditing MOTOR Dataset ──────────────────────────────")
MOTOR_ROOT = PROJECT_ROOT / PATHS['datasets']['motor']['root']
MOTOR_ANN  = PROJECT_ROOT / PATHS['datasets']['motor']['annotations']
print(f"Root: {MOTOR_ROOT} (exists: {MOTOR_ROOT.exists()})")
motor_size = folder_size_mb(MOTOR_ROOT)
print(f"Size: {motor_size} MB")

motor_ann_info = None
if MOTOR_ANN.exists():
    df_m, info_m = audit_csv(MOTOR_ANN, label='motor_annotations')
    if df_m is not None:
        print(f"  annotations.csv: {info_m['rows_sampled']} rows | {len(info_m['columns'])} columns")
        print(f"  Columns: {info_m['columns'][:8]}")
        motor_ann_info = {
            'rows_sampled': info_m['rows_sampled'],
            'columns': info_m['columns'],
            'missing_pct': info_m['missing_pct']
        }

clips_dir = MOTOR_ROOT / 'clips'
n_clips = len(list(clips_dir.rglob('*'))) if clips_dir.exists() else 0
if n_clips == 0:
    hf_dir = MOTOR_ROOT / '.cache'
    n_clips = len(list(hf_dir.rglob('*'))) if hf_dir.exists() else 0

manifest['datasets']['motor'] = {
    'source_folder': str(MOTOR_ROOT.relative_to(PROJECT_ROOT)) if MOTOR_ROOT.exists() else str(PATHS['datasets']['motor']['root']),
    'role': 'Additional real vehicle/motorcycle data — schema must be audited before use',
    'primary': False,
    'size_mb': motor_size,
    'annotations_info': motor_ann_info,
    'clips_file_count': n_clips,
    'notes': [
        'Annotations cover Road Type, Lanes, Markings, Divider, Traffic Density.',
        'Use only after coordinate system, sensor schema, and ground truth are confirmed.'
    ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. OSM MAP DATA AUDIT
# ─────────────────────────────────────────────────────────────────────────────
print("\n── [5/5] Auditing OSM Map Data ───────────────────────────────")
OSM_ROOT = PROJECT_ROOT / PATHS['datasets']['osm']['root']
PBF_FILE = PROJECT_ROOT / PATHS['datasets']['osm']['pbf_file']
print(f"Root: {OSM_ROOT} (exists: {OSM_ROOT.exists()})")
print(f"PBF file: {PBF_FILE} (exists: {PBF_FILE.exists()})")
pbf_size = PBF_FILE.stat().st_size / 1e6 if PBF_FILE.exists() else 0.0
print(f"PBF size: {pbf_size:.1f} MB")

manifest['datasets']['osm'] = {
    'source_folder': str(OSM_ROOT.relative_to(PROJECT_ROOT)) if OSM_ROOT.exists() else str(PATHS['datasets']['osm']['root']),
    'role': 'Offline OpenStreetMap road data for GNN map matching — not a trajectory dataset',
    'primary': False,
    'pbf_file': str(PBF_FILE.relative_to(PROJECT_ROOT)) if PBF_FILE.exists() else None,
    'pbf_size_mb': round(pbf_size, 2),
    'notes': [
        'india-260912.osm.pbf covers India road network (1.7 GB).',
        'Local subgraphs extracted per session bounding box during GNN training.',
        'Never load full India road network into memory at once.'
    ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. CROSS-DATASET SUMMARY & SPLIT STRATEGY
# ─────────────────────────────────────────────────────────────────────────────
split_strategy = {
    'method': 'session_level',
    'rationale': (
        'Adjacent samples from the same trajectory must never be split randomly. '
        'Session-level splitting prevents temporal leakage.'
    ),
    'io_vnbd': {
        'train_drivers': ['M (Driver B)', 'Vf (Driver E)', 'Vta (Driver E)', 'Vtb (Driver E)', 'Vw (Driver E)'],
        'val_drivers':   ['Y (Driver D)'],
        'test_drivers':  ['S (Driver A)'],
        'note': (
            'Test set (Driver A / S sessions) locked and held-out completely until final evaluation. '
            'Never tune hyperparameters on test sessions.'
        )
    },
    'final_test_set_locked': True,
    'warning': 'Do NOT use final test sessions for ANY hyperparameter tuning or architecture selection.'
}
manifest['split_strategy'] = split_strategy

# ─────────────────────────────────────────────────────────────────────────────
# 7. SAVE OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
manifest_path = ARTIFACTS / 'dataset_manifest.json'
with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2, default=str)
print(f"\nManifest saved: {manifest_path}")

audit_md_path = DOCS / 'dataset_audit.md'
lines = [
    '# Dataset Audit Report — SIH PS 26168',
    '',
    '**Intelligent Dead Reckoning with GNSS Fusion**  ',
    f'**Audit Timestamp:** {NOW}  ',
    f'**Status:** Complete  ',
    '',
    '---',
    '',
    '## Executive Summary',
    '',
    '| Dataset | Role | Primary? | Size (MB) | Sessions / Files Audited |',
    '|---|---|:---:|---|---|',
]

for ds_name, ds in manifest['datasets'].items():
    primary_str = 'Yes' if ds.get('primary') else 'No'
    n_sess = len(ds.get('sessions', []))
    lines.append(f"| **{ds_name.upper()}** | {ds['role'][:45]}... | {primary_str} | {ds.get('size_mb', 0):.1f} | {n_sess} |")

lines += ['', '---', '']

for ds_name, ds in manifest['datasets'].items():
    primary_tag = ' ★ PRIMARY' if ds.get('primary') else ''
    lines += [
        f"### {ds_name.upper()}{primary_tag}",
        '',
        f"- **Source Folder:** `{ds['source_folder']}`",
        f"- **Role:** {ds['role']}",
        f"- **Size:** {ds.get('size_mb', 0):.1f} MB",
        '',
    ]
    if ds.get('sessions'):
        lines.append('| Session File | Sampled Rows | Columns | Timestamp Col | IMU Cols | GNSS Cols | GT Cols | Est. Hz |')
        lines.append('|---|---|---|---|---|---|---|---|')
        for s in ds['sessions'][:20]:
            fname = Path(s['file']).name
            rows = s.get('rows_sampled', 0)
            cols = len(s.get('columns', []))
            ts = ', '.join(s.get('timestamp_candidates', []))[:20] or 'N/A'
            imu = len(s.get('imu_columns', []))
            gnss = len(s.get('gnss_columns', []))
            gt = len(s.get('ground_truth_columns', []))
            hz = s.get('sampling_rate_hz', 'N/A')
            lines.append(f"| `{fname}` | {rows:,} | {cols} | {ts} | {imu} | {gnss} | {gt} | {hz} |")
        lines.append('')
    
    if ds.get('notes'):
        lines.append('**Notes:**')
        for note in ds['notes']:
            lines.append(f"- ⚠ {note}")
        lines.append('')
    lines.append('---')

lines += [
    '',
    '## Proposed Train / Validation / Test Split Strategy',
    '',
    f"- **Method:** `{split_strategy['method']}`",
    f"- **Rationale:** {split_strategy['rationale']}",
    '',
    '### IO-VNBD Split Assignment',
    f"- **Training Drivers:** {', '.join(split_strategy['io_vnbd']['train_drivers'])}",
    f"- **Validation Drivers:** {', '.join(split_strategy['io_vnbd']['val_drivers'])}",
    f"- **Test Drivers (Locked):** {', '.join(split_strategy['io_vnbd']['test_drivers'])}",
    '',
    f"> ⚠ **WARNING:** {split_strategy['warning']}",
    ''
]

with open(audit_md_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f"Audit report saved: {audit_md_path}")
print("\n" + "=" * 60)
print("  DATASET AUDIT COMPLETED SUCCESSFULLY")
print("=" * 60)
