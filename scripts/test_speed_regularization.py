"""
scripts/test_speed_regularization.py
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
raw_s = np.array(speeds)

# Test different smoothing & kinematic fusion schemes:
# 1. Moving average (window 5 = 0.5s)
w_ma = 5
ma_s = np.convolve(raw_s, np.ones(w_ma)/w_ma, mode='same')

# 2. Kinematic physical rate-limiting: |v[t] - v[t-1]| <= a_max * dt
dt = 0.1
a_max = 3.5  # m/s^2 (0.35g)
rate_s = np.zeros_like(raw_s)
rate_s[0] = raw_s[0]
for t in range(1, len(raw_s)):
    delta = raw_s[t] - rate_s[t-1]
    delta_clamped = np.clip(delta, -a_max * dt, a_max * dt)
    rate_s[t] = rate_s[t-1] + delta_clamped

# 3. Kinematic Complementary Filter fusing forward accelerometer with NIO speed:
# v_est[t] = (v_est[t-1] + a_fwd * dt) * (1 - alpha) + alpha * v_nio
# alpha = 0.05
comp_s = np.zeros_like(raw_s)
comp_s[0] = gt_s[0]  # initialized to pre-outage speed
alpha = 0.08
for t in range(1, len(raw_s)):
    a_fwd = acc_v[1500 + t, 0]
    v_pred = comp_s[t-1] + a_fwd * dt
    comp_s[t] = (1.0 - alpha) * v_pred + alpha * raw_s[t]
    comp_s[t] = max(0.0, comp_s[t])

print("Comparison on S1 [1500..1800] (GT Mean = 11.32 m/s):")
print(f"Raw NIO Pred  : RMSE = {np.sqrt(np.mean((raw_s - gt_s)**2)):.3f} m/s | MAE = {np.mean(np.abs(raw_s - gt_s)):.3f} m/s")
print(f"Moving Avg (5): RMSE = {np.sqrt(np.mean((ma_s - gt_s)**2)):.3f} m/s | MAE = {np.mean(np.abs(ma_s - gt_s)):.3f} m/s")
print(f"Rate Limiter  : RMSE = {np.sqrt(np.mean((rate_s - gt_s)**2)):.3f} m/s | MAE = {np.mean(np.abs(rate_s - gt_s)):.3f} m/s")
print(f"Complementary : RMSE = {np.sqrt(np.mean((comp_s - gt_s)**2)):.3f} m/s | MAE = {np.mean(np.abs(comp_s - gt_s)):.3f} m/s")
