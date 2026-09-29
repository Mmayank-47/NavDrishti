"""Single phone-only reader for SI fixtures and documented IO-VNBD S-CSV layout.

IO-VNBD gyro is canonicalized as [roll, pitch, yaw-label].  The recording
app's yaw label is not asserted to be a physical phone-vertical axis; a mount
rotation remains required before treating it as vehicle yaw.
"""
import csv
from pathlib import Path
import numpy as np
from .adapter import CanonicalSession, TimestampPolicy
from src.preprocessing.frame_transform import geodetic_to_enu
_REQ=("timestamp_ms","accel_x_mps2","accel_y_mps2","accel_z_mps2","gyro_x_rad_s","gyro_y_rad_s","gyro_z_rad_s")
def load_phone_csv(path, max_gap_s=2.):
    path=Path(path)
    try: text=path.read_text(encoding='utf-8')
    except UnicodeDecodeError: text=path.read_text(encoding='latin1')
    rows=list(csv.reader(text.splitlines()))
    if len(rows)<2: raise ValueError('empty phone CSV')
    h=[x.strip() for x in rows[0]]; body=rows[1:]
    named=set(_REQ).issubset(h)
    def at(name, fallback):
        i=h.index(name) if name in h else fallback
        try: return np.array([float(r[i]) for r in body])
        except (ValueError,IndexError): raise ValueError(f'unparsable required phone column: {name}')
    if named:
        t=at('timestamp_ms',7); accel=np.c_[at('accel_x_mps2',9),at('accel_y_mps2',10),at('accel_z_mps2',11)]; gyro=np.c_[at('gyro_x_rad_s',17),at('gyro_y_rad_s',16),at('gyro_z_rad_s',15)]; lat=at('latitude_deg',0); lon=at('longitude_deg',1); alt=np.zeros(len(t)); history=('timestamp:ms->s','gyro:fixture-rad/s'); path_name='named_si'
    else:
        # Same named-or-positional fields used by data_loader.py: yaw,pitch,roll at 15,16,17.
        t=at('TIMESTAMP (ms)',7); accel=np.c_[at('ACCELEROMETER X (m/s²)',9),at('ACCELEROMETER Y (m/s²)',10),at('ACCELEROMETER Z (m/s²)',11)]; gyro=np.c_[at('GYROSCOPE Roll (rad/s)',17),at('GYROSCOPE Pitch (rad/s)',16),at('GYROSCOPE Yaw (rad/s)',15)]; lat=at('LATITUDE',0); lon=at('LONGITUDE',1); alt=at('ALTITUDE',2); history=('timestamp:ms->s','gyro:IO-VNBD-rad/s'); path_name='named_iovnbd_or_positional'
    if not np.all(np.isfinite(lat)) or not np.all(np.isfinite(lon)) or np.any(lat==0) or np.any(lon==0): raise ValueError('invalid or zero-sentinel coordinates')
    t=t/1000.; t-=t[0]; ref=geodetic_to_enu(lat,lon,alt,lat[0],lon[0],alt[0])[:,:2]
    out=CanonicalSession(t,accel,gyro,ref,policy=TimestampPolicy(max_gap_s,'reject'),conversion_history=history)
    object.__setattr__(out,'column_mapping_path',path_name)
    return out
