import csv, json, subprocess, sys
from pathlib import Path
import numpy as np
import pytest
from experiments.causal_baseline.adapter import CanonicalSession, TimestampPolicy
from experiments.causal_baseline.replay import initialize_before, replay_outage
from experiments.causal_baseline.phone_csv import load_phone_csv
from src.preprocessing.frame_transform import geodetic_to_enu

def s(t, ref=None, gyro=None, policy=None):
    n=len(t); return CanonicalSession(np.array(t,float),np.zeros((n,3)),np.zeros((n,3)) if gyro is None else np.array(gyro,float),None if ref is None else np.array(ref,float),policy=policy or TimestampPolicy())

def test_10hz_history_chord_initializes_and_future_cannot_change_it():
    t=np.arange(0,3,.1); ref=np.c_[2*t,np.zeros_like(t)]
    a=initialize_before(s(t,ref),2.0)
    changed=ref.copy(); changed[t>=2]=999
    b=initialize_before(s(t,changed),2.0)
    assert a.source_time_s == pytest.approx(1.9)
    assert a.interval_start_s == pytest.approx(.9)
    assert np.allclose(a.velocity_enu_mps,[2,0]) and np.allclose(a.velocity_enu_mps,b.velocity_enu_mps)

def test_held_position_is_ineligible_not_certified_stationary():
    t=np.arange(0,2,.1); ref=np.zeros((len(t),2))
    with pytest.raises(ValueError,match='held or insufficient motion'):
        initialize_before(s(t,ref),1.5)

def test_replay_rejects_bad_initial_and_gyro_prefix_coverage_and_exact_reference():
    t=np.array([10.,10.4,11.]); ref=np.c_[t,np.zeros(3)]
    init=initialize_before(s(np.arange(0,2,.1),np.c_[np.arange(0,2,.1),np.zeros(20)]),1.5)
    with pytest.raises(ValueError,match='initial source'):
        replay_outage(s(t,ref),init,1.,2.,'constant_velocity')
    with pytest.raises(ValueError,match='gyro coverage'):
        replay_outage(s(t,ref),init,2.,10.2,'gyro_heading_speed',np.eye(3))
    r=replay_outage(s(np.array([0.,1.,2.]),np.array([[0,0],[1,0],[999,0.]])),initialize_before(s(np.arange(0,2,.1),np.c_[np.arange(0,2,.1),np.zeros(20)]),1.5),1.6,2.0000002,'constant_velocity')
    assert r.status=='NOT_EVALUABLE' and len(r.trajectory)>0

def write_phone(path, n=30, bad=False):
    cols=['timestamp_ms','accel_x_mps2','accel_y_mps2','accel_z_mps2','gyro_x_rad_s','gyro_y_rad_s','gyro_z_rad_s','latitude_deg','longitude_deg']
    with open(path,'w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=cols); w.writeheader()
        for i in range(n): w.writerow(dict(zip(cols,[i*100,0,0,0,0,0,0 if not bad else 'bad',12.,77.+i*1e-6])))

def test_real_cli_phone_csv_success_and_runtime_diagnostics(tmp_path):
    phone=tmp_path/'S-tiny.csv'; write_phone(phone)
    cfg=tmp_path/'cfg.json'; cfg.write_text(json.dumps({'phone_csv':str(phone),'session':'synthetic-training-fixture','t0_s':1.5,'t1_s':2.,'mode':'constant_velocity','timestamp_gap_s':.5}))
    out=tmp_path/'out'; p=subprocess.run([sys.executable,'-m','experiments.causal_baseline.run','--config',str(cfg),'--output',str(out)],text=True,capture_output=True)
    assert p.returncode==0 and (out/'trajectory.csv').exists()
    bad=tmp_path/'missing.json'; bad.write_text(json.dumps({'phone_csv':str(tmp_path/'none.csv')}))
    q=subprocess.run([sys.executable,'-m','experiments.causal_baseline.run','--config',str(bad),'--output',str(out)],text=True,capture_output=True)
    assert q.returncode!=0 and json.loads((out/'status.json').read_text())['status']=='RUNTIME_ERROR' and (out/'diagnostic.log').exists() and not (out/'trajectory.csv').exists()

def test_documented_iovnbd_header_maps_roll_pitch_yaw_and_wgs84_enu(tmp_path):
    h=['LATITUDE','LONGITUDE','ALTITUDE','speed','accuracy','heading','x','TIMESTAMP (ms)','x','ACCELEROMETER X (m/s²)','ACCELEROMETER Y (m/s²)','ACCELEROMETER Z (m/s²)','x','x','x','GYROSCOPE Yaw (rad/s)','GYROSCOPE Pitch (rad/s)','GYROSCOPE Roll (rad/s)']
    p=tmp_path/'S-real-header.csv'; p.write_text(','.join(h)+'\n12,77,10,0,0,0,0,1000,0,1,2,3,0,0,0,30,20,10\n12.0001,77.0001,10,0,0,0,0,1100,0,1,2,3,0,0,0,30,20,10\n',encoding='utf-8')
    x=load_phone_csv(p); expected=geodetic_to_enu(np.array([12.,12.0001]),np.array([77.,77.0001]),np.array([10.,10.]),12.,77.,10.)[:,:2]
    assert np.allclose(x.reference_enu_m,expected) and np.allclose(x.gyro_phone_rad_s[0],[10,20,30]) and x.column_mapping_path=='named_iovnbd_or_positional'
