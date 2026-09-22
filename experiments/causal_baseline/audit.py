"""Evaluator-only raw-file audit; never feeds an estimator or converts speed."""
import csv, json
from pathlib import Path
import numpy as np
def audit(path):
    try: text=Path(path).read_text(encoding='utf-8'); enc='utf-8'
    except UnicodeDecodeError: text=Path(path).read_text(encoding='latin1'); enc='latin1'
    rows=list(csv.reader(text.splitlines())); h=[x.strip() for x in rows[0]]; body=rows[1:]
    def f(i): return np.array([float(r[i]) for r in body])
    si='timestamp_ms' in h
    if si:
        t=f(h.index('timestamp_ms')); lat=f(h.index('latitude_deg')) if 'latitude_deg' in h else np.array([]); lon=f(h.index('longitude_deg')) if 'longitude_deg' in h else np.array([]); schema='si_fixture'
    else: t=f(7); lat=f(0); lon=f(1); schema='iovnbd_24_column'
    dt=np.diff(t); moved=np.where((np.diff(lat)!=0)|(np.diff(lon)!=0))[0] if len(lat) else np.array([])
    return {'encoding':enc,'schema':schema,'header':h,'row_count':len(body),'timestamp_unit':'ms','timestamp_monotonic':bool(np.all(dt>0)),'dt_ms':{'min':float(dt.min()) if len(dt) else None,'median':float(np.median(dt)) if len(dt) else None,'max':float(dt.max()) if len(dt) else None},'coordinate_change_interval_samples':np.diff(moved).tolist(),'nonfinite_coordinates':int(np.sum(~np.isfinite(lat)|~np.isfinite(lon))) if len(lat) else None,'zero_sentinel_coordinates':int(np.sum((lat==0)|(lon==0))) if len(lat) else None,'gyro_mapping':['col17 roll','col16 pitch','col15 yaw-label; physical axis unverified'] if not si else ['gyro_x','gyro_y','gyro_z fixture labels'],'speed_label':h[3] if len(h)>3 else None}
def write_audit(path,out): Path(out).write_text(json.dumps(audit(path),indent=2)); return Path(out)
