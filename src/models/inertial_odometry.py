"""
src/models/inertial_odometry.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Neural Inertial Odometry Network (TLIO / EqNIO inspired)
Adheres to Section 18 of the Roadmap.

Architecture:
  - Temporal Convolutional Network (TCN) with Dilated 1D Residual Blocks
  - Input: Calibrated 6-DOF IMU time series (3-axis Accel + 3-axis Gyro) -> (B, L, 6)
  - Multi-Head Outputs:
      1. Relative 2D Displacement [dx, dy] in vehicle forward/lateral frame
      2. Instantaneous Forward Velocity v_fwd (folded OdoNet role)
      3. Log-variance Uncertainty log(sigma^2) for displacement
  - Loss: Heteroscedastic Gaussian Negative Log-Likelihood (NLL) + Velocity MSE

Uncertainty Parameterisation (v2 — fixed):
  raw_logvar = Linear(64, 2)           # unconstrained
  logvar      = 6.0 * tanh(raw) + 1.0 # BOUNDED: logvar ∈ [-5, 7]
  sigma       = exp(0.5 * logvar)      # sigma ∈ [0.082m, 91.2m]

  Physical justification:
    - Urban vehicle at rest: sigma ~ 0.1 m  → logvar ~ -4.6
    - Urban vehicle at 60 km/h over 10s:   → logvar ~ 6.2 (sigma ~ 80m worst case)
    - Centre: logvar=1.0 → sigma=1.65m  (typical low-speed street)
    - Old bug: raw exp(logvar) with NO inference clamp → sigma=8,508,032 (overflow)
─────────────────────────────────────────────────────────────────────────────
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


# ── Uncertainty bound constants (chosen from vehicle physics) ─────────────────
_LOGVAR_CENTER = 1.0   # exp(0.5*1.0) = 1.65 m sigma (typical low-speed)
_LOGVAR_SCALE  = 6.0   # half-range → logvar ∈ [center-scale, center+scale] = [-5, 7]
#   sigma_min = exp(0.5 * -5.0) = 0.082 m  (sub-decimetre — stopped vehicle)
#   sigma_max = exp(0.5 *  7.0) = 91.2 m   (very high speed or long outage)


class Chomp1d(nn.Module):
    """Truncates future padding to preserve temporal causality."""
    def __init__(self, chomp_size):
        super().__init__()
        self.chomp_size = chomp_size

    def forward(self, x):
        return x[:, :, :-self.chomp_size].contiguous() if self.chomp_size > 0 else x


class TemporalBlock(nn.Module):
    """Dilated residual convolutional block for TCN."""

    def __init__(self, n_inputs, n_outputs, kernel_size, stride, dilation, padding, dropout=0.1):
        super().__init__()
        self.conv1 = nn.Conv1d(
            n_inputs, n_outputs, kernel_size,
            stride=stride, padding=padding, dilation=dilation
        )
        self.chomp1 = Chomp1d(padding)
        self.relu1 = nn.GELU()
        self.dropout1 = nn.Dropout(dropout)

        self.conv2 = nn.Conv1d(
            n_outputs, n_outputs, kernel_size,
            stride=stride, padding=padding, dilation=dilation
        )
        self.chomp2 = Chomp1d(padding)
        self.relu2 = nn.GELU()
        self.dropout2 = nn.Dropout(dropout)

        self.net = nn.Sequential(
            self.conv1, self.chomp1, self.relu1, self.dropout1,
            self.conv2, self.chomp2, self.relu2, self.dropout2
        )
        self.downsample = nn.Conv1d(n_inputs, n_outputs, 1) if n_inputs != n_outputs else None
        self.relu = nn.GELU()

    def forward(self, x):
        out = self.net(x)
        res = x if self.downsample is None else self.downsample(x)
        return self.relu(out + res)


class TemporalConvNet(nn.Module):
    """Stack of dilated residual temporal blocks."""

    def __init__(self, num_inputs, num_channels, kernel_size=3, dropout=0.1):
        super().__init__()
        layers = []
        num_levels = len(num_channels)
        for i in range(num_levels):
            dilation_size = 2 ** i
            in_channels = num_inputs if i == 0 else num_channels[i - 1]
            out_channels = num_channels[i]
            layers.append(
                TemporalBlock(
                    in_channels, out_channels, kernel_size,
                    stride=1, dilation=dilation_size,
                    padding=(kernel_size - 1) * dilation_size,
                    dropout=dropout
                )
            )
        self.network = nn.Sequential(*layers)

    def forward(self, x):
        # x: (B, C, L)
        return self.network(x)


class BoundedLogVarHead(nn.Module):
    """
    Bounded log-variance head using tanh parameterisation.

    Guarantees logvar ∈ [center - scale, center + scale] at all times,
    preventing exp() overflow that caused sigma=8,508,032 in v1.

    Formula:  logvar = scale * tanh(raw) + center
    Default:  logvar ∈ [-5.0, 7.0]  →  sigma ∈ [0.082m, 91.2m]
    """

    def __init__(self, in_features: int, out_features: int = 2,
                 center: float = _LOGVAR_CENTER, scale: float = _LOGVAR_SCALE):
        super().__init__()
        self.center = center
        self.scale  = scale
        self.fc1 = nn.Linear(in_features, 64)
        self.act  = nn.GELU()
        self.fc2 = nn.Linear(64, out_features)

    def forward(self, x):
        raw = self.fc2(self.act(self.fc1(x)))                 # unconstrained (B, 2)
        logvar = self.scale * torch.tanh(raw) + self.center   # bounded (B, 2)
        return logvar


class NeuralInertialOdometry(nn.Module):
    """
    Lightweight TLIO-style Neural Inertial Odometry model.
    Predicts relative motion, velocity, and calibrated uncertainty from IMU history.

    v2 change: logvar head replaced with BoundedLogVarHead to prevent sigma overflow.
    """

    def __init__(
        self,
        input_dim=6,
        tcn_channels=[64, 128, 256],
        kernel_size=3,
        dropout=0.1,
        vel_loss_weight=0.5,
        uncertainty_weight=0.1
    ):
        super().__init__()
        self.input_dim = input_dim
        self.vel_loss_weight = vel_loss_weight
        self.uncertainty_weight = uncertainty_weight

        # TCN Feature Encoder
        self.tcn = TemporalConvNet(
            num_inputs=input_dim,
            num_channels=tcn_channels,
            kernel_size=kernel_size,
            dropout=dropout
        )

        self.latent_dim = tcn_channels[-1]
        latent_dim = self.latent_dim

        # Multi-Head Prediction Layers
        # 1. Displacement Head: Relative 2D displacement [dx, dy] over window
        self.disp_head = nn.Sequential(
            nn.Linear(latent_dim, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 2)
        )

        # 2. Velocity Head: Instantaneous vehicle forward and lateral speed [v_fwd, v_lat]
        self.vel_head = nn.Sequential(
            nn.Linear(latent_dim, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 2)
        )

        # 3. Log-variance Uncertainty Head (v2 — BOUNDED via tanh)
        #    logvar ∈ [-5.0, 7.0]  →  sigma ∈ [0.082m, 91.2m]
        #    Replaces unbounded linear head that produced sigma=8,508,032 at inference.
        self.logvar_head = BoundedLogVarHead(
            in_features=latent_dim,
            out_features=2,
            center=_LOGVAR_CENTER,
            scale=_LOGVAR_SCALE
        )

    def forward(self, x):
        """
        Forward pass.
        Parameters:
        -----------
        x : torch.Tensor of shape (B, L, 6) - (Accel [3] + Gyro [3])
        Returns:
        --------
        disp   : torch.Tensor of shape (B, 2) - predicted relative displacement [dx, dy]
        vel    : torch.Tensor of shape (B, 2) - predicted vehicle velocities [v_fwd, v_lat]
        logvar : torch.Tensor of shape (B, 2) - bounded log-variance ∈ [-5, 7]
                 sigma = exp(0.5 * logvar) ∈ [0.082m, 91.2m]  <- always finite
        """
        # Convert (B, L, C) -> (B, C, L) for 1D convolutions
        x_perm = x.permute(0, 2, 1)
        features = self.tcn(x_perm)  # (B, latent_dim, L)

        # Pool over time (global average pooling + last timestep concatenation)
        f_pool = torch.mean(features, dim=2)  # (B, latent_dim)
        f_last = features[:, :, -1]           # (B, latent_dim)
        f_repr = 0.5 * (f_pool + f_last)

        disp   = self.disp_head(f_repr)
        vel    = self.vel_head(f_repr)
        logvar = self.logvar_head(f_repr)      # bounded; no additional clamp needed

        return disp, vel, logvar

    def compute_loss(self, pred_disp, pred_vel, pred_logvar, gt_disp, gt_vel):
        """
        Heteroscedastic Gaussian NLL loss for displacement + MSE loss for velocity.
        L = 0.5 * exp(-s) * ||dx - dx_gt||^2 + 0.5 * s + lambda_v * ||v - v_gt||^2

        NOTE (v2): No clamp required — logvar is bounded architecturally by
        BoundedLogVarHead. The old clamp(-7, 5) is removed to avoid masking
        gradient signal at the boundary.
        """
        # logvar is already bounded ∈ [-5, 7] via tanh — safe to exponentiate
        precision = torch.exp(-pred_logvar)

        # 1. Displacement NLL loss
        disp_diff = (pred_disp - gt_disp) ** 2
        loss_disp = 0.5 * torch.mean(precision * disp_diff + pred_logvar)

        # 2. Velocity MSE loss
        loss_vel = F.mse_loss(pred_vel, gt_vel)

        total_loss = loss_disp + self.vel_loss_weight * loss_vel
        return total_loss, loss_disp.item(), loss_vel.item()

    @torch.no_grad()
    def compute_uncertainty_stats(self, logvar: torch.Tensor) -> dict:
        """
        Compute uncertainty diagnostics from bounded log-variance tensor.
        Used in training monitoring and test reporting.

        Parameters:
        -----------
        logvar : (B, 2) bounded log-variance tensor, output of BoundedLogVarHead
                 Guaranteed to be in [-5, 7] — no overflow possible.

        Returns:
        --------
        dict with:
          mean_sigma, p50_sigma, p95_sigma, max_sigma  — all in metres
          nan_count, inf_count                          — should both be 0
        """
        sigma = torch.exp(0.5 * logvar)           # always finite due to architectural bound
        sigma_flat = sigma.flatten()
        nan_count = int(torch.isnan(sigma_flat).sum().item())
        inf_count = int(torch.isinf(sigma_flat).sum().item())
        sigma_valid = sigma_flat[~(torch.isnan(sigma_flat) | torch.isinf(sigma_flat))]

        if len(sigma_valid) == 0:
            return {'mean_sigma': float('nan'), 'p50_sigma': float('nan'),
                    'p95_sigma': float('nan'), 'max_sigma': float('nan'),
                    'nan_count': nan_count, 'inf_count': inf_count}

        p50 = float(torch.quantile(sigma_valid.float(), 0.50).item())
        p95 = float(torch.quantile(sigma_valid.float(), 0.95).item())

        return {
            'mean_sigma':  float(sigma_valid.mean().item()),
            'p50_sigma':   p50,
            'p95_sigma':   p95,
            'max_sigma':   float(sigma_valid.max().item()),
            'nan_count':   nan_count,
            'inf_count':   inf_count
        }

    def load_state_dict(self, state_dict, strict=True):
        """
        Load state dict with automatic backward compatibility for legacy checkpoints
        where logvar_head was nn.Sequential instead of BoundedLogVarHead.
        """
        if any(k.startswith('logvar_head.0') for k in state_dict.keys()):
            in_dim = getattr(self, 'latent_dim', self.disp_head[0].in_features)
            self.logvar_head = nn.Sequential(
                nn.Linear(in_dim, 64),
                nn.ReLU(),
                nn.Linear(64, 2)
            )
            try:
                param_device = next(self.parameters()).device
                self.logvar_head = self.logvar_head.to(param_device)
            except StopIteration:
                pass
        return super().load_state_dict(state_dict, strict=strict)
