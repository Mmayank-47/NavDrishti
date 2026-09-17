"""
src/models/limu_bert_nio.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
LIMU-BERT → NIO Integration: Frozen LIMU-BERT encoder feeding NIO TCN backbone.

Architecture:
  Input: (B, L, 6) calibrated IMU sequence
    ↓ LIMU-BERT Encoder (FROZEN, loaded from checkpoint)
  Latent: (B, L, 128) temporal IMU representation
    ↓ Projection Conv (128 → input_dim for TCN)
  Projected: (B, L, proj_dim)
    ↓ NIO TCN backbone + multi-head outputs
  Outputs: displacement (B,2), velocity (B,2), logvar (B,2) [bounded]

Purpose: Ablation experiment — compare:
  A: Raw IMU (B,L,6) → NIO (current production path)
  B: LIMU-BERT features (B,L,128) → NIO (this module)

Usage:
  model = LIMUBERTNIOModel(limu_bert_checkpoint="checkpoints/limu_bert/limu_bert_best.pt")
  disp, vel, logvar = model(imu_seq)   # (B, L, 6) input
─────────────────────────────────────────────────────────────────────────────
"""

from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F

from src.models.limu_bert import LIMUBERT
from src.models.inertial_odometry import (
    NeuralInertialOdometry,
    BoundedLogVarHead,
    _LOGVAR_CENTER,
    _LOGVAR_SCALE,
    TemporalConvNet,
)


class LIMUBERTNIOModel(nn.Module):
    """
    LIMU-BERT (frozen) + NIO TCN end-to-end ablation model.

    The LIMU-BERT encoder replaces the raw 6-DOF IMU input to the TCN.
    Instead of giving the TCN raw sensor readings, we give it rich
    self-supervised temporal representations.

    The LIMU-BERT weights are frozen — only the projection layer and
    NIO heads are trained. This is the Phase 3 ablation (frozen features).
    """

    def __init__(
        self,
        limu_bert_checkpoint: str,
        limu_hidden_dim: int = 128,
        tcn_channels: list = [64, 128, 256],
        kernel_size: int = 3,
        dropout: float = 0.1,
        vel_loss_weight: float = 0.5,
        device: str = "cpu"
    ):
        super().__init__()
        self.vel_loss_weight = vel_loss_weight
        self.device = device

        # ── Load and FREEZE LIMU-BERT encoder ────────────────────────────────
        self.limu_bert = LIMUBERT(
            input_dim=6,
            hidden_dim=limu_hidden_dim,
            num_heads=4,
            num_layers=4,
            dim_feedforward=256,
            dropout=dropout
        )
        ckpt_path = Path(limu_bert_checkpoint)
        if not ckpt_path.exists():
            raise FileNotFoundError(
                f"LIMU-BERT checkpoint not found: {limu_bert_checkpoint}\n"
                f"Run Phase 3 (LIMU-BERT training) before this ablation."
            )

        ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
        state_dict = ckpt.get("model_state_dict", ckpt)
        self.limu_bert.load_state_dict(state_dict, strict=False)

        # Freeze all LIMU-BERT parameters
        for param in self.limu_bert.parameters():
            param.requires_grad = False
        self.limu_bert.eval()

        print(f"[LIMUBERTNIOModel] Loaded LIMU-BERT from {limu_bert_checkpoint}")
        trainable = sum(p.numel() for p in self.limu_bert.parameters() if p.requires_grad)
        frozen    = sum(p.numel() for p in self.limu_bert.parameters() if not p.requires_grad)
        print(f"[LIMUBERTNIOModel] LIMU-BERT: {frozen} frozen params, {trainable} trainable params")

        # ── Projection: LIMU-BERT latent (128) → TCN input ───────────────────
        # We use a 1×1 temporal convolution (= pointwise Linear per timestep)
        # to match LIMU-BERT's 128-dim output to the TCN's expected input.
        # This projection IS trainable.
        proj_in_dim = limu_hidden_dim   # 128
        proj_out_dim = 32               # compact projection before TCN

        self.input_proj = nn.Sequential(
            nn.Linear(proj_in_dim, proj_out_dim),
            nn.GELU(),
            nn.Dropout(dropout)
        )

        # ── NIO TCN Backbone (trainable) ──────────────────────────────────────
        self.tcn = TemporalConvNet(
            num_inputs=proj_out_dim,
            num_channels=tcn_channels,
            kernel_size=kernel_size,
            dropout=dropout
        )

        latent_dim = tcn_channels[-1]

        # ── Multi-head prediction heads (trainable) ───────────────────────────
        self.disp_head = nn.Sequential(
            nn.Linear(latent_dim, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 2)
        )

        self.vel_head = nn.Sequential(
            nn.Linear(latent_dim, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 2)
        )

        # Bounded log-variance head (same as fixed NIO v2)
        self.logvar_head = BoundedLogVarHead(
            in_features=latent_dim,
            out_features=2,
            center=_LOGVAR_CENTER,
            scale=_LOGVAR_SCALE
        )

        n_trainable = sum(p.numel() for p in self.parameters() if p.requires_grad)
        print(f"[LIMUBERTNIOModel] Total trainable params: {n_trainable:,}")

    def forward(self, x: torch.Tensor):
        """
        Forward pass.

        Parameters:
        -----------
        x : torch.Tensor (B, L, 6)  — raw calibrated IMU

        Returns:
        --------
        disp   : (B, 2) — displacement [dx, dy]
        vel    : (B, 2) — velocity [v_fwd, v_lat]
        logvar : (B, 2) — bounded log-variance ∈ [-5, 7]
        """
        # 1. Extract frozen LIMU-BERT features
        with torch.no_grad():
            latent = self.limu_bert.encode(x)   # (B, L, 128)

        # 2. Project to TCN input dim
        h = self.input_proj(latent)             # (B, L, proj_out_dim)

        # 3. TCN (expects B, C, L)
        h_t = h.permute(0, 2, 1)               # (B, proj_out_dim, L)
        features = self.tcn(h_t)               # (B, latent_dim, L)

        # 4. Temporal pooling
        f_pool = torch.mean(features, dim=2)   # (B, latent_dim)
        f_last = features[:, :, -1]            # (B, latent_dim)
        f_repr = 0.5 * (f_pool + f_last)

        # 5. Multi-head outputs
        disp   = self.disp_head(f_repr)
        vel    = self.vel_head(f_repr)
        logvar = self.logvar_head(f_repr)

        return disp, vel, logvar

    def compute_loss(self, pred_disp, pred_vel, pred_logvar, gt_disp, gt_vel):
        """Identical loss to fixed NIO (heteroscedastic NLL + velocity MSE)."""
        precision = torch.exp(-pred_logvar)
        disp_diff = (pred_disp - gt_disp) ** 2
        loss_disp = 0.5 * torch.mean(precision * disp_diff + pred_logvar)
        loss_vel  = F.mse_loss(pred_vel, gt_vel)
        total     = loss_disp + self.vel_loss_weight * loss_vel
        return total, loss_disp.item(), loss_vel.item()

    def trainable_parameters(self):
        """Return only trainable parameters (excludes frozen LIMU-BERT)."""
        return [p for p in self.parameters() if p.requires_grad]
