"""Minimal phone-only CSV adapter; vehicle files are deliberately never opened."""
import csv
from pathlib import Path
import numpy as np
from .adapter import CanonicalSession, TimestampPolicy
_REQ=("timestamp_ms","accel_x_mps2","accel_y_mps2","accel_z_mps2","gyro_x_rad_s","gyro_y_rad_s","gyro_z_rad_s")
def load_phone_csv(path, max_gap_s=2.):
    path=Path(path)
    with path.open(newline="") as f: rows=list(csv.DictReader(f))
    if not rows or not set(_REQ).issubset(rows[0]): raise ValueError("phone CSV missing required SI columns")
    def col(name): return np.array([float(r[name]) for r in rows])
    t=col("timestamp_ms")/1000.; t-=t[0]
    accel=np.c_[col("accel_x_mps2"),col("accel_y_mps2"),col("accel_z_mps2")]
    gyro=np.c_[col("gyro_x_rad_s"),col("gyro_y_rad_s"),col("gyro_z_rad_s")]
    ref=None
    if "latitude_deg" in rows[0] and "longitude_deg" in rows[0]:
        lat,lon=col("latitude_deg"),col("longitude_deg")
        if np.all(np.isfinite(lat)) and np.all(np.isfinite(lon)):
            ref=np.c_[(lon-lon[0])*111320.*np.cos(np.deg2rad(lat[0])),(lat-lat[0])*110540.]
    return CanonicalSession(t,accel,gyro,ref,policy=TimestampPolicy(max_gap_s,"reject"),conversion_history=("timestamp:ms->s","gyro:source-rad/s"))
