"""
scripts/train_kalmannet_v3.py
─────────────────────────────────────────────────────────────────────────────
Phase 20: Retrain KalmanNet on Continuous Realistic NIO Velocity Measurements
- Dataset: Remediated KalmanNetDataset with 100% continuous genuine NIO speeds (zero GT leakage)
- Base NIO model: checkpoints/nio_velocity_finetuned/nio_vel_best.pt
- Architecture: KalmanNetNN(state_dim=4, meas_dim=2, hidden_dim=64, num_layers=2)
- Trainable parameters: 55,684
- Optimization: AdamW(lr=1e-3, weight_decay=1e-4) with CosineAnnealingLR
- Loss: Position MSE + 0.5 * Velocity MSE on sequential filter rollouts
- Selection: Strictly on validation data (split='val', Driver D session Y1)
- Output checkpoint: checkpoints/kalmannet_v3/kalmannet_best.pt
─────────────────────────────────────────────────────────────────────────────
"""

import os, sys, time, json
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.models.kalmannet import KalmanNetNN
from src.datasets.kalmannet_dataset import KalmanNetDataset

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
NIO_CKPT_PATH = PROJECT_ROOT / 'checkpoints' / 'nio_velocity_finetuned' / 'nio_vel_best.pt'
OUT_DIR = PROJECT_ROOT / 'checkpoints' / 'kalmannet_v3'
RESULTS_DIR = PROJECT_ROOT / 'results' / 'phase4_kalmannet'


def set_seed(seed=42):
    torch.manual_seed(seed)
    np.random.seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def rollout_kalmannet(model, a_nav, z_meas, init_state, F_m, B_m, H_m):
    B, L, _ = a_nav.shape
    x_curr = init_state
    z_prev = z_meas[:, 0, :]
    h_prev = None

    post_states = []
    gains = []

    for t in range(1, L):
        a_t = a_nav[:, t, :]
        z_t = z_meas[:, t, :]

        # Physics Prior Prediction: x_prior = F @ x + B @ a
        x_prior = torch.matmul(x_curr, F_m.T) + torch.matmul(a_t, B_m.T)

        # KalmanNet Adaptive Filter Step
        x_post, K_gain, h_prev = model.step(
            x_prior=x_prior,
            z_meas=z_t,
            H_matrix=H_m,
            x_prev=x_curr,
            z_prev=z_prev,
            h_prev=h_prev
        )

        post_states.append(x_post)
        gains.append(K_gain)
        x_curr = x_post
        z_prev = z_t

    pred_states = torch.stack(post_states, dim=1)  # (B, L-1, 4)
    stack_gains = torch.stack(gains, dim=1)        # (B, L-1, 4, 2)
    return pred_states, stack_gains


def evaluate(model, val_loader, F_m, B_m, H_m):
    model.eval()
    v_losses, v_pos_rmses, v_vel_rmses = [], [], []

    with torch.no_grad():
        for batch in val_loader:
            a_nav      = batch['a_nav'].to(DEVICE)
            z_meas     = batch['z_meas'].to(DEVICE)
            gt_state   = batch['gt_state'].to(DEVICE)
            init_state = batch['init_state'].to(DEVICE)

            pred_states, _ = rollout_kalmannet(model, a_nav, z_meas, init_state, F_m, B_m, H_m)
            gt_target = gt_state[:, 1:, :]

            pos_diff = pred_states[:, :, 0:2] - gt_target[:, :, 0:2]
            vel_diff = pred_states[:, :, 2:4] - gt_target[:, :, 2:4]
            loss_pos = torch.mean(pos_diff ** 2)
            loss_vel = torch.mean(vel_diff ** 2)
            loss = loss_pos + 0.5 * loss_vel

            v_losses.append(loss.item())
            v_pos_rmses.append(torch.sqrt(loss_pos).item())
            v_vel_rmses.append(torch.sqrt(loss_vel).item())

    return {
        'val_loss': float(np.mean(v_losses)),
        'val_pos_rmse': float(np.mean(v_pos_rmses)),
        'val_vel_rmse': float(np.mean(v_vel_rmses))
    }


def main():
    set_seed(42)
    print("=" * 70)
    print("PHASE 20: KALMANNET V3 RETRAINING ON CONTINUOUS NIO OBSERVATIONS")
    print("=" * 70)
    print(f"Compute Device: {DEVICE}")
    if torch.cuda.is_available():
        print(f"GPU Hardware: {torch.cuda.get_device_name(0)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"NIO Checkpoint: {NIO_CKPT_PATH}")
    assert NIO_CKPT_PATH.exists(), f"NIO checkpoint not found at {NIO_CKPT_PATH}"

    print("\nLoading datasets with continuous 10 Hz NIO speed generation...")
    train_ds = KalmanNetDataset(
        split='train',
        seq_len=50,
        stride=20,
        io_checkpoint_path=str(NIO_CKPT_PATH),
        device=DEVICE
    )
    val_ds = KalmanNetDataset(
        split='val',
        seq_len=50,
        stride=25,
        io_checkpoint_path=str(NIO_CKPT_PATH),
        device=DEVICE
    )

    BATCH_SIZE = 32
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True, drop_last=True)
    val_loader   = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False)

    print(f"Train Sequences: {len(train_ds):,} ({len(train_loader)} batches)")
    print(f"Val Sequences:   {len(val_ds):,} ({len(val_loader)} batches)")

    model = KalmanNetNN(
        state_dim=4,
        meas_dim=2,
        hidden_dim=64,
        num_layers=2,
        dropout=0.1
    ).to(DEVICE)

    param_count = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"KalmanNet Initialized. Trainable Parameters: {param_count:,}")

    dt = 0.1
    F_mat = torch.tensor([
        [1.0, 0.0, dt,  0.0],
        [0.0, 1.0, 0.0, dt ],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0]
    ], dtype=torch.float32, device=DEVICE)

    B_mat = torch.tensor([
        [0.5 * dt**2, 0.0],
        [0.0, 0.5 * dt**2],
        [dt, 0.0],
        [0.0, dt]
    ], dtype=torch.float32, device=DEVICE)

    H_mat = torch.tensor([
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0]
    ], dtype=torch.float32, device=DEVICE)

    EPOCHS = 35
    LEARNING_RATE = 1e-3
    EARLY_STOP_PATIENCE = 10

    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS, eta_min=1e-5)

    best_val_pos_rmse = float('inf')
    best_epoch = 0
    patience_counter = 0
    best_model_state = None

    history = {
        'epoch': [], 'lr': [],
        'train_loss': [], 'val_loss': [],
        'train_pos_rmse': [], 'val_pos_rmse': [],
        'train_vel_rmse': [], 'val_vel_rmse': []
    }

    # Pre-training validation baseline
    init_val = evaluate(model, val_loader, F_mat, B_mat, H_mat)
    print(f"Pre-training Baseline: Val Loss = {init_val['val_loss']:.4f}, Val Pos RMSE = {init_val['val_pos_rmse']:.3f}m, Val Vel RMSE = {init_val['val_vel_rmse']:.3f}m/s")

    for epoch in range(1, EPOCHS + 1):
        model.train()
        t_losses, t_pos_rmses, t_vel_rmses = [], [], []

        for batch in train_loader:
            a_nav      = batch['a_nav'].to(DEVICE)
            z_meas     = batch['z_meas'].to(DEVICE)
            gt_state   = batch['gt_state'].to(DEVICE)
            init_state = batch['init_state'].to(DEVICE)

            optimizer.zero_grad()
            pred_states, _ = rollout_kalmannet(model, a_nav, z_meas, init_state, F_mat, B_mat, H_mat)
            gt_target = gt_state[:, 1:, :]

            pos_diff = pred_states[:, :, 0:2] - gt_target[:, :, 0:2]
            vel_diff = pred_states[:, :, 2:4] - gt_target[:, :, 2:4]
            loss_pos = torch.mean(pos_diff ** 2)
            loss_vel = torch.mean(vel_diff ** 2)
            loss = loss_pos + 0.5 * loss_vel

            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=2.0)
            optimizer.step()

            t_losses.append(loss.item())
            t_pos_rmses.append(torch.sqrt(loss_pos).item())
            t_vel_rmses.append(torch.sqrt(loss_vel).item())

        scheduler.step()

        val_metrics = evaluate(model, val_loader, F_mat, B_mat, H_mat)
        mean_t_loss = float(np.mean(t_losses))
        mean_t_pos  = float(np.mean(t_pos_rmses))
        mean_t_vel  = float(np.mean(t_vel_rmses))

        history['epoch'].append(epoch)
        history['lr'].append(scheduler.get_last_lr()[0])
        history['train_loss'].append(mean_t_loss)
        history['val_loss'].append(val_metrics['val_loss'])
        history['train_pos_rmse'].append(mean_t_pos)
        history['val_pos_rmse'].append(val_metrics['val_pos_rmse'])
        history['train_vel_rmse'].append(mean_t_vel)
        history['val_vel_rmse'].append(val_metrics['val_vel_rmse'])

        print(f"Epoch {epoch:02d}/{EPOCHS:02d} | Train Loss: {mean_t_loss:.4f} | Val Loss: {val_metrics['val_loss']:.4f} | Val Pos RMSE: {val_metrics['val_pos_rmse']:.3f}m | Val Vel RMSE: {val_metrics['val_vel_rmse']:.3f}m/s")

        if val_metrics['val_pos_rmse'] < best_val_pos_rmse:
            best_val_pos_rmse = val_metrics['val_pos_rmse']
            best_epoch = epoch
            patience_counter = 0
            best_model_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            print(f"  >>> New best validation model saved! Pos RMSE = {best_val_pos_rmse:.3f}m (Epoch {best_epoch})")
        else:
            patience_counter += 1
            if patience_counter >= EARLY_STOP_PATIENCE:
                print(f"Early stopping triggered at epoch {epoch} (patience={EARLY_STOP_PATIENCE}).")
                break

    # Save best checkpoint
    best_ckpt_path = OUT_DIR / 'kalmannet_best.pt'
    ckpt_save_data = {
        'epoch': best_epoch,
        'model_state_dict': best_model_state,
        'config': {
            'state_dim': 4,
            'meas_dim': 2,
            'hidden_dim': 64,
            'num_layers': 2,
            'dropout': 0.1,
            'version': 'v3_continuous_nio_input',
            'nio_source': str(NIO_CKPT_PATH),
            'best_epoch': best_epoch,
            'best_val_pos_rmse': best_val_pos_rmse
        }
    }
    torch.save(ckpt_save_data, best_ckpt_path)
    print(f"\nSaved best KalmanNet v3 checkpoint to: {best_ckpt_path}")

    # Save training log
    log_path = RESULTS_DIR / 'kalmannet_v3_training_log.json'
    with open(log_path, 'w') as f:
        json.dump({
            'best_epoch': best_epoch,
            'best_val_pos_rmse': best_val_pos_rmse,
            'history': history
        }, f, indent=2)
    print(f"Saved training log to: {log_path}")


if __name__ == '__main__':
    main()
