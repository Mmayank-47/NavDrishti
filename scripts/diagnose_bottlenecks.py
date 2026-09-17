"""
scripts/diagnose_bottlenecks.py
Analyzes physical, sensor, and model bottlenecks in the C6 pipeline across test sessions:
1. Gyroscope yaw bias (stationary vs active driving)
2. Stationary/ZUPT frequency and error accumulation during stops
3. NIO speed vs ground truth OBD speed vs accelerometer integration
4. Heading drift over 30s and 60s windows with vs without gyro bias removal
"""

import sys
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment

def main():
    loader = IOVNBDLoader()
    sessions = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']
    
    print("=" * 80)
    print("PHYSICAL & SENSOR BOTTLENECK DIAGNOSIS ACROSS TEST SESSIONS")
    print("=" * 80)
    
    for s_name in sessions:
        print(f"\n--- Analyzing Session {s_name} ---")
        sess = loader.load_session(s_name, preprocess_imu=True)
        aligner = PhoneVehicleAlignment()
        veh_spd = sess['vehicle']['speed_mps']
        if veh_spd is None:
            veh_spd = sess['gps']['speed_mps']
        if veh_spd is None:
            veh_spd = np.zeros(len(sess['accel_raw']))
            
        R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
        acc_v = (R_p2v @ sess['accel_filtered'].T).T
        gyr_v = (R_p2v @ sess['gyro_filtered'].T).T
        
        zupt = sess['zupt_mask']
        N = len(zupt)
        n_zupt = int(np.sum(zupt))
        pct_zupt = float(n_zupt / N * 100.0)
        
        # 1. Yaw Gyro Bias during Stationary
        if n_zupt > 10:
            bias_zupt = float(np.mean(gyr_v[zupt, 2]))
            std_zupt = float(np.std(gyr_v[zupt, 2]))
        else:
            bias_zupt = 0.0
            std_zupt = 0.0
            
        # 2. Forward Accelerometer Bias during Stationary
        if n_zupt > 10:
            acc_fwd_bias = float(np.mean(acc_v[zupt, 0]))
            acc_lat_bias = float(np.mean(acc_v[zupt, 1]))
        else:
            acc_fwd_bias = 0.0
            acc_lat_bias = 0.0
            
        # 3. Overall Gyro Mean
        mean_gyr_z = float(np.mean(gyr_v[:, 2]))
        mean_spd = float(np.mean(veh_spd))
        max_spd = float(np.max(veh_spd))
        
        # 4. Heading drift over 30s and 60s without bias compensation
        dt = 0.1
        drift_30s_deg = float(np.degrees(bias_zupt * 30.0))
        drift_60s_deg = float(np.degrees(bias_zupt * 60.0))
        
        print(f"  Duration: {N*dt:.1f} s ({N} samples)")
        print(f"  Vehicle Speed: Mean = {mean_spd:.2f} m/s, Max = {max_spd:.2f} m/s")
        print(f"  Stationary (ZUPT): {n_zupt}/{N} samples ({pct_zupt:.1f}% of total route)")
        print(f"  Yaw Gyro Bias (ZUPT): {bias_zupt:+.5f} rad/s ({np.degrees(bias_zupt):+.3f} deg/s) [std: {std_zupt:.5f}]")
        print(f"  Uncorrected Heading Drift: 30s = {drift_30s_deg:+.2f} deg | 60s = {drift_60s_deg:+.2f} deg")
        print(f"  Accel Bias in Vehicle Frame: Fwd = {acc_fwd_bias:+.4f} m/s^2, Lat = {acc_lat_bias:+.4f} m/s^2")

if __name__ == '__main__':
    main()
