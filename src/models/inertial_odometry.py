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
─────────────────────────────────────────────────────────────────────────────
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


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


class NeuralInertialOdometry(nn.Module):
    """
    Lightweight TLIO-style Neural Inertial Odometry model.
    Predicts relative motion, velocity, and calibrated uncertainty from IMU history.
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

        latent_dim = tcn_channels[-1]

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

        # 3. Log-variance Uncertainty Head: log(sigma^2) for [dx, dy]
        self.logvar_head = nn.Sequential(
            nn.Linear(latent_dim, 64),
            nn.GELU(),
            nn.Linear(64, 2)
        )

    def forward(self, x):
        """
        Forward pass.
        Parameters:
        -----------
        x : torch.Tensor of shape (B, L, 6) - (Accel [3] + Gyro [3])
        Returns:
        --------
        disp : torch.Tensor of shape (B, 2) - predicted relative displacement [dx, dy]
        vel : torch.Tensor of shape (B, 2) - predicted vehicle velocities [v_fwd, v_lat]
        logvar : torch.Tensor of shape (B, 2) - predicted log-variance uncertainty
        """
        # Convert (B, L, C) -> (B, C, L) for 1D convolutions
        x_perm = x.permute(0, 2, 1)
        features = self.tcn(x_perm)  # (B, latent_dim, L)

        # Pool over time (global average pooling + last timestep concatenation)
        f_pool = torch.mean(features, dim=2)  # (B, latent_dim)
        f_last = features[:, :, -1]            # (B, latent_dim)
        f_repr = 0.5 * (f_pool + f_last)

        disp = self.disp_head(f_repr)
        vel = self.vel_head(f_repr)
        logvar = self.logvar_head(f_repr)

        return disp, vel, logvar

    def compute_loss(self, pred_disp, pred_vel, pred_logvar, gt_disp, gt_vel):
        """
        Heteroscedastic Gaussian NLL loss for displacement + MSE loss for velocity.
        L = 0.5 * exp(-s) * ||dx - dx_gt||^2 + 0.5 * s + lambda_v * ||v - v_gt||^2
        """
        # Clamp log-variance for numerical stability
        clamped_logvar = torch.clamp(pred_logvar, min=-7.0, max=5.0)
        precision = torch.exp(-clamped_logvar)

        # 1. Displacement NLL loss
        disp_diff = (pred_disp - gt_disp) ** 2
        loss_disp = 0.5 * torch.mean(precision * disp_diff + clamped_logvar)

        # 2. Velocity MSE loss
        loss_vel = F.mse_loss(pred_vel, gt_vel)

        total_loss = loss_disp + self.vel_loss_weight * loss_vel
        return total_loss, loss_disp.item(), loss_vel.item()
