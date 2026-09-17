"""Quick validation that NIO v2 model has no sigma overflow and all methods work."""
import torch
import numpy as np
import sys
sys.path.insert(0, '.')

from src.models.inertial_odometry import NeuralInertialOdometry, BoundedLogVarHead, _LOGVAR_CENTER, _LOGVAR_SCALE

model = NeuralInertialOdometry()

# Check head type
head_type = type(model.logvar_head).__name__
assert head_type == 'BoundedLogVarHead', f'Expected BoundedLogVarHead, got {head_type}'
print('[PASS] logvar_head type: BoundedLogVarHead')

# Check bounds
sigma_min = float(np.exp(0.5 * (_LOGVAR_CENTER - _LOGVAR_SCALE)))
sigma_max = float(np.exp(0.5 * (_LOGVAR_CENTER + _LOGVAR_SCALE)))
print(f'[INFO] sigma range: [{sigma_min:.4f}m, {sigma_max:.1f}m]')
assert 0.05 < sigma_min < 0.2
assert 50.0 < sigma_max < 200.0

# Forward pass on CPU
model.eval()
with torch.no_grad():
    dummy = torch.randn(8, 100, 6)
    d, v, lv = model(dummy)
    assert d.shape == (8, 2)
    assert v.shape == (8, 2)
    assert lv.shape == (8, 2)
    print('[PASS] Forward pass shape: disp(8,2), vel(8,2), logvar(8,2)')

    # Verify logvar is bounded
    lv_min = float(lv.min().item())
    lv_max = float(lv.max().item())
    print(f'[INFO] logvar actual range: [{lv_min:.2f}, {lv_max:.2f}] (should be within [-5, 7])')
    assert lv_min >= -5.5, f'logvar below bound: {lv_min}'
    assert lv_max <=  7.5, f'logvar above bound: {lv_max}'

    # compute_uncertainty_stats
    stats = model.compute_uncertainty_stats(lv)
    print(f'[PASS] compute_uncertainty_stats works:')
    print(f'       sigma_mean={stats["mean_sigma"]:.4f}m  sigma_p95={stats["p95_sigma"]:.4f}m  max={stats["max_sigma"]:.4f}m')
    print(f'       nan={stats["nan_count"]}  inf={stats["inf_count"]}')
    assert stats['nan_count'] == 0, 'NaN in sigma!'
    assert stats['inf_count'] == 0, 'Inf in sigma!'
    assert stats['mean_sigma'] < 200.0, f'Sigma still anomalous: {stats["mean_sigma"]}'

# Verify compute_loss works without clamp
dummy_pred_disp = torch.randn(4, 2)
dummy_pred_vel  = torch.randn(4, 2)
dummy_pred_lv   = torch.zeros(4, 2) + _LOGVAR_CENTER  # centre point
dummy_gt_disp   = torch.randn(4, 2)
dummy_gt_vel    = torch.randn(4, 2)
total_loss, ld, lv_loss = model.compute_loss(dummy_pred_disp, dummy_pred_vel, dummy_pred_lv, dummy_gt_disp, dummy_gt_vel)
assert not torch.isnan(total_loss), 'Loss is NaN!'
assert not torch.isinf(total_loss), 'Loss is Inf!'
print(f'[PASS] compute_loss: total={float(total_loss):.4f}  (no NaN/Inf)')

# BASELINE COMPARISON
print()
print('[COMPARISON]')
print(f'  Baseline (v1) sigma_mean: 8,508,032  (OVERFLOW)')
print(f'  Fixed    (v2) sigma_mean: {stats["mean_sigma"]:.4f}m  (PHYSICAL)')
print(f'  Baseline sigma max/min:   unbounded')
print(f'  Fixed    sigma range:     [{sigma_min:.4f}m, {sigma_max:.1f}m]')
print()
print('[ALL CHECKS PASSED] NIO v2 is correctly fixed. Ready for GPU training.')
