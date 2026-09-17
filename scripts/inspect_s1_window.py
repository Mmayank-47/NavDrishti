"""
scripts/inspect_s1_window.py
"""
import torch, numpy as np
from src.preprocessing.data_loader import IOVNBDLoader
from src.calibration.alignment import PhoneVehicleAlignment
from src.models.inertial_odometry import NeuralInertialOdometry

loader = IOVNBDLoader()
sess = loader.load_session('S1', preprocess_imu=True)
veh_spd = sess['vehicle']['speed_mps']
aligner = PhoneVehicleAlignment()
R_p2v = aligner.calibrate(sess['accel_raw'], zupt_mask=sess['zupt_mask'], velocity_ref=veh_spd)
acc_v = (R_p2v @ sess['accel_filtered'].T).T
gyr_v = (R_p2v @ sess['gyro_filtered'].T).T

ckpt = torch.load('checkpoints/nio_velocity_finetuned/nio_vel_best.pt', map_location='cpu', weights_only=False)
model = NeuralInertialOdometry(input_dim=6, tcn_channels=[64, 128, 256], kernel_size=3, dropout=0.0)
model.load_state_dict(ckpt['model_state_dict'])
model.eval()

imu_6d = np.hstack([acc_v, gyr_v]).astype(np.float32)
speeds = []
for i in range(1500, 1800):
    w = imu_6d[i-99:i+1]
    with torch.no_grad():
        _, v, _ = model(torch.tensor(w).unsqueeze(0))
        speeds.append(float(v[0, 0]))

gt_s = veh_spd[1500:1800]
p_s = np.array(speeds)
print('GT speed [1500..1800]: mean=', np.mean(gt_s), 'min=', np.min(gt_s), 'max=', np.max(gt_s))
print('Pred speed [1500..1800]: mean=', np.mean(p_s), 'min=', np.min(p_s), 'max=', np.max(p_s))
print('Speed RMSE [1500..1800]:', np.sqrt(np.mean((p_s - gt_s)**2)))
print('Speed MAE [1500..1800]:', np.mean(np.abs(p_s - gt_s)))
print('First 10 GT vs Pred:')
for j in range(10):
    print(f'  Step {1500+j}: GT = {gt_s[j]:.2f} m/s | Pred = {p_s[j]:.2f} m/s | Diff = {p_s[j] - gt_s[j]:+.2f} m/s')
