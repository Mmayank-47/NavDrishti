"""
scripts/train_nio_vel_head.py
─────────────────────────────────────────────────────────────────────────────
Phase 3 & 4: NIO Velocity Head Fine-Tuning with Balanced Speed Sampling
- Base checkpoint: checkpoints/nio_fixed/nio_fixed_best.pt
- Frozen: TCN backbone, disp_head, logvar_head
- Trainable: vel_head only (~33,154 parameters)
- Loss: Huber loss (delta=1.0 m/s) with weight lambda_v = 2.0
- Balanced speed sampling across: [0-5 m/s], [5-15 m/s], [>15 m/s]
- Controlled learning rate comparison: 1e-4 vs 3e-4
- Model selection strictly based on validation split (split='val', Driver D)
- Output checkpoint: checkpoints/nio_velocity_finetuned/nio_vel_best.pt
─────────────────────────────────────────────────────────────────────────────
"""

import sys, json, time, gc
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, WeightedRandomSampler

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.datasets.inertial_odometry_dataset import InertialOdometryDataset
from src.models.inertial_odometry import NeuralInertialOdometry

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
BASE_CKPT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_fixed' / 'nio_fixed_best.pt'
OUT_DIR = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned'
RESULTS_DIR = PROJECT_ROOT / 'results' / 'phase3_nio_vel'


def set_seed(seed=42):
    torch.manual_seed(seed)
    np.random.seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def build_balanced_sampler(dataset):
    """
    Computes inverse frequency weights across 3 speed bins:
      Bin 0: 0 <= v < 5 m/s
      Bin 1: 5 <= v < 15 m/s
      Bin 2: v >= 15 m/s
    """
    targets = []
    for s_idx, start in dataset.index_map:
        end = start + dataset.window_size
        v_fwd = float(dataset.sessions[s_idx]['vel'][end - 1])
        targets.append(v_fwd)
    targets = np.array(targets)

    bin_indices = np.zeros(len(targets), dtype=int)
    bin_indices[(targets >= 5.0) & (targets < 15.0)] = 1
    bin_indices[targets >= 15.0] = 2

    counts = np.bincount(bin_indices, minlength=3)
    print(f"Train speed bin counts: [0-5 m/s]: {counts[0]:,}, [5-15 m/s]: {counts[1]:,}, [>15 m/s]: {counts[2]:,}")

    # Equal 1/3 weight mass for each bin
    weights_per_bin = 1.0 / (3.0 * np.maximum(counts, 1))
    sample_weights = weights_per_bin[bin_indices]
    sample_weights = torch.tensor(sample_weights, dtype=torch.float32)

    sampler = WeightedRandomSampler(sample_weights, num_samples=len(sample_weights), replacement=True)
    return sampler, counts.tolist()


def evaluate_nio(model, val_loader):
    model.eval()
    all_pred_vel = []
    all_gt_vel = []
    all_pred_disp = []
    all_gt_disp = []
    all_logvar = []
    total_val_loss = 0.0
    total_disp_loss = 0.0
    total_vel_loss = 0.0
    n_batches = 0

    with torch.no_grad():
        for batch in val_loader:
            x = batch['imu'].to(DEVICE)
            gt_disp = batch['disp'].to(DEVICE)
            gt_vel = batch['vel'].to(DEVICE)

            pred_disp, pred_vel, pred_logvar = model(x)

            # Heteroscedastic NLL for displacement
            precision = torch.exp(-pred_logvar)
            disp_diff = (pred_disp - gt_disp) ** 2
            loss_disp = 0.5 * torch.mean(precision * disp_diff + pred_logvar)

            # Huber loss for velocity (delta=1.0)
            loss_vel = F.huber_loss(pred_vel, gt_vel, delta=1.0)

            total_loss = loss_disp + 2.0 * loss_vel

            total_val_loss += total_loss.item()
            total_disp_loss += loss_disp.item()
            total_vel_loss += loss_vel.item()
            n_batches += 1

            all_pred_vel.append(pred_vel.cpu().numpy())
            all_gt_vel.append(gt_vel.cpu().numpy())
            all_pred_disp.append(pred_disp.cpu().numpy())
            all_gt_disp.append(gt_disp.cpu().numpy())
            all_logvar.append(pred_logvar.cpu())

    pred_vel_cat = np.concatenate(all_pred_vel, axis=0)
    gt_vel_cat = np.concatenate(all_gt_vel, axis=0)
    pred_disp_cat = np.concatenate(all_pred_disp, axis=0)
    gt_disp_cat = np.concatenate(all_gt_disp, axis=0)
    logvar_cat = torch.cat(all_logvar, dim=0)

    # Uncertainty stats
    unc_stats = model.compute_uncertainty_stats(logvar_cat)

    # Velocity metrics (focus on forward velocity index 0)
    pred_vf = pred_vel_cat[:, 0]
    gt_vf = gt_vel_cat[:, 0]
    v_diff = pred_vf - gt_vf
    vel_rmse = float(np.sqrt(np.mean(v_diff ** 2)))
    vel_mae = float(np.mean(np.abs(v_diff)))
    vel_bias = float(np.mean(v_diff))

    if np.std(pred_vf) > 1e-6 and np.std(gt_vf) > 1e-6:
        r_matrix = np.corrcoef(pred_vf, gt_vf)
        vel_r = float(r_matrix[0, 1])
    else:
        vel_r = 0.0

    # Displacement metrics
    d_diff = np.linalg.norm(pred_disp_cat - gt_disp_cat, axis=1)
    disp_rmse = float(np.sqrt(np.mean(d_diff ** 2)))
    disp_mae = float(np.mean(d_diff))

    # Stratified speed bins on validation
    bins = [
        ('0-5 m/s', (gt_vf >= 0.0) & (gt_vf < 5.0)),
        ('5-15 m/s', (gt_vf >= 5.0) & (gt_vf < 15.0)),
        ('>15 m/s', (gt_vf >= 15.0))
    ]
    bin_metrics = {}
    for b_name, mask in bins:
        if np.sum(mask) > 0:
            b_diff = pred_vf[mask] - gt_vf[mask]
            b_rmse = float(np.sqrt(np.mean(b_diff ** 2)))
            b_mae = float(np.mean(np.abs(b_diff)))
            b_bias = float(np.mean(b_diff))
            bin_metrics[b_name] = {
                'count': int(np.sum(mask)),
                'rmse_mps': b_rmse,
                'mae_mps': b_mae,
                'bias_mps': b_bias
            }
        else:
            bin_metrics[b_name] = {'count': 0, 'rmse_mps': 0.0, 'mae_mps': 0.0, 'bias_mps': 0.0}

    metrics = {
        'val_loss': total_val_loss / max(n_batches, 1),
        'val_disp_loss': total_disp_loss / max(n_batches, 1),
        'val_vel_loss': total_vel_loss / max(n_batches, 1),
        'vel_rmse': vel_rmse,
        'vel_mae': vel_mae,
        'vel_bias': vel_bias,
        'vel_r': vel_r,
        'disp_rmse': disp_rmse,
        'disp_mae': disp_mae,
        'uncertainty': unc_stats,
        'speed_bins': bin_metrics
    }
    return metrics


def train_candidate(lr, num_epochs, train_loader, val_loader, base_ckpt):
    print(f"\n" + "=" * 60)
    print(f"STARTING FINE-TUNING RUN: lr = {lr:.1e}, epochs = {num_epochs}")
    print("=" * 60)

    # Initialize model from base checkpoint
    cfg = base_ckpt.get('config', {})
    model = NeuralInertialOdometry(
        input_dim=6,
        tcn_channels=cfg.get('tcn_channels', [64, 128, 256]),
        kernel_size=cfg.get('tcn_kernel_size', 3),
        dropout=cfg.get('dropout', 0.1),
        vel_loss_weight=2.0
    ).to(DEVICE)
    model.load_state_dict(base_ckpt['model_state_dict'])

    # Freeze everything except vel_head
    for p in model.tcn.parameters():
        p.requires_grad = False
    for p in model.disp_head.parameters():
        p.requires_grad = False
    for p in model.logvar_head.parameters():
        p.requires_grad = False

    for p in model.vel_head.parameters():
        p.requires_grad = True

    trainable_params = [p for p in model.parameters() if p.requires_grad]
    trainable_count = sum(p.numel() for p in trainable_params)
    total_count = sum(p.numel() for p in model.parameters())
    print(f"Trainable parameters: {trainable_count:,} / {total_count:,} ({trainable_count/total_count*100:.2f}%)")

    optimizer = torch.optim.AdamW(trainable_params, lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=num_epochs, eta_min=1e-6)

    # Initial pre-fine-tune validation baseline (epoch 0)
    base_metrics = evaluate_nio(model, val_loader)
    print(f"Pre-training baseline (Epoch 0):")
    print(f"  Val Loss: {base_metrics['val_loss']:.4f} | Vel RMSE: {base_metrics['vel_rmse']:.3f} m/s | Vel r: {base_metrics['vel_r']:.3f}")
    print(f"  Speed Bins: [0-5]: {base_metrics['speed_bins']['0-5 m/s']['rmse_mps']:.3f} m/s | [5-15]: {base_metrics['speed_bins']['5-15 m/s']['rmse_mps']:.3f} m/s | [>15]: {base_metrics['speed_bins']['>15 m/s']['rmse_mps']:.3f} m/s")

    history = [{'epoch': 0, 'train_loss': None, **base_metrics}]
    best_overall_rmse = base_metrics['vel_rmse']
    best_trained_rmse = float('inf')
    best_trained_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
    best_trained_epoch = 0

    for epoch in range(1, num_epochs + 1):
        model.train()
        # Keep frozen modules in eval mode
        model.tcn.eval()
        model.disp_head.eval()
        model.logvar_head.eval()
        model.vel_head.train()

        total_train_loss = 0.0
        total_train_vel_loss = 0.0
        n_train_batches = 0

        for batch in train_loader:
            x = batch['imu'].to(DEVICE)
            gt_disp = batch['disp'].to(DEVICE)
            gt_vel = batch['vel'].to(DEVICE)

            optimizer.zero_grad()
            pred_disp, pred_vel, pred_logvar = model(x)

            # Heteroscedastic NLL for displacement
            precision = torch.exp(-pred_logvar)
            disp_diff = (pred_disp - gt_disp) ** 2
            loss_disp = 0.5 * torch.mean(precision * disp_diff + pred_logvar)

            # Huber loss for velocity
            loss_vel = F.huber_loss(pred_vel, gt_vel, delta=1.0)
            total_loss = loss_disp + 2.0 * loss_vel

            total_loss.backward()
            torch.nn.utils.clip_grad_norm_(trainable_params, max_norm=1.0)
            optimizer.step()

            total_train_loss += total_loss.item()
            total_train_vel_loss += loss_vel.item()
            n_train_batches += 1

        scheduler.step()

        # Validation
        val_metrics = evaluate_nio(model, val_loader)
        train_loss_avg = total_train_loss / max(n_train_batches, 1)
        train_vel_avg = total_train_vel_loss / max(n_train_batches, 1)

        record = {
            'epoch': epoch,
            'lr': scheduler.get_last_lr()[0],
            'train_loss': train_loss_avg,
            'train_vel_loss': train_vel_avg,
            **val_metrics
        }
        history.append(record)

        print(f"Epoch {epoch:02d}/{num_epochs:02d} | Train Loss: {train_loss_avg:.4f} | Val Loss: {val_metrics['val_loss']:.4f} | Vel RMSE: {val_metrics['vel_rmse']:.3f} m/s | Vel r: {val_metrics['vel_r']:.3f} | Disp RMSE: {val_metrics['disp_rmse']:.2f}m")

        if val_metrics['vel_rmse'] < best_trained_rmse:
            best_trained_rmse = val_metrics['vel_rmse']
            best_trained_epoch = epoch
            best_trained_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            print(f"  >>> New best trained validation velocity RMSE: {best_trained_rmse:.3f} m/s (Epoch {best_trained_epoch})")

    return {
        'lr': lr,
        'best_epoch': best_trained_epoch,
        'best_vel_rmse': best_trained_rmse,
        'best_model_state': best_trained_state,
        'history': history
    }


def main():
    set_seed(42)
    print("=" * 70)
    print("PHASE 3: NIO VELOCITY HEAD FINE-TUNING")
    print("=" * 70)
    print(f"Device: {DEVICE}")
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    assert BASE_CKPT_PATH.exists(), f"Base checkpoint not found at {BASE_CKPT_PATH}"
    base_ckpt = torch.load(BASE_CKPT_PATH, map_location=DEVICE, weights_only=False)

    print("\nLoading datasets...")
    train_ds = InertialOdometryDataset(split='train', window_size=100, stride=20)
    val_ds = InertialOdometryDataset(split='val', window_size=100, stride=30)

    sampler, bin_counts = build_balanced_sampler(train_ds)
    train_loader = DataLoader(train_ds, batch_size=64, sampler=sampler, num_workers=2, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=64, shuffle=False, num_workers=2, pin_memory=True)

    print(f"Train windows: {len(train_ds):,} | Val windows: {len(val_ds):,}")

    # Best learning rate from comparison: 3e-4
    epochs = 5
    candidates = [3e-4]
    all_runs = {}

    best_overall_rmse = float('inf')
    best_overall_run = None

    for lr in candidates:
        res = train_candidate(lr, epochs, train_loader, val_loader, base_ckpt)
        all_runs[str(lr)] = {
            'lr': lr,
            'best_epoch': res['best_epoch'],
            'best_vel_rmse': res['best_vel_rmse'],
            'history': res['history']
        }
        if res['best_vel_rmse'] < best_overall_rmse:
            best_overall_rmse = res['best_vel_rmse']
            best_overall_run = res

    print("\n" + "=" * 70)
    print("HYPERPARAMETER SELECTION RESULTS (ON VALIDATION SET ONLY):")
    print("=" * 70)
    for lr_str, run_info in all_runs.items():
        print(f"LR {lr_str}: Best Epoch = {run_info['best_epoch']}, Best Val Vel RMSE = {run_info['best_vel_rmse']:.3f} m/s")

    print(f"\nSelected Model: LR = {best_overall_run['lr']}, Epoch = {best_overall_run['best_epoch']}, Val Vel RMSE = {best_overall_run['best_vel_rmse']:.3f} m/s")

    # Save best checkpoint
    best_ckpt_path = OUT_DIR / 'nio_vel_best.pt'
    ckpt_save_data = {
        'epoch': best_overall_run['best_epoch'],
        'model_state_dict': best_overall_run['best_model_state'],
        'config': {
            **base_ckpt.get('config', {}),
            'vel_head_finetuned': True,
            'finetuned_lr': best_overall_run['lr'],
            'finetuned_epoch': best_overall_run['best_epoch'],
            'val_vel_rmse': best_overall_run['best_vel_rmse'],
            'vel_loss_weight': 2.0,
            'loss_type': 'Huber_delta_1.0'
        }
    }
    torch.save(ckpt_save_data, best_ckpt_path)
    print(f"Saved best fine-tuned NIO checkpoint to: {best_ckpt_path}")

    # Save full training log
    log_path = RESULTS_DIR / 'nio_vel_training_log.json'
    with open(log_path, 'w') as f:
        json.dump({
            'bin_counts': bin_counts,
            'comparison': all_runs,
            'selected_lr': best_overall_run['lr'],
            'selected_best_epoch': best_overall_run['best_epoch'],
            'selected_val_vel_rmse': best_overall_run['best_vel_rmse']
        }, f, indent=2)
    print(f"Saved training log to: {log_path}")


if __name__ == '__main__':
    main()
