"""
src/models/limu_bert.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
LIMU-BERT: Self-Supervised IMU Representation Learning Network
Adheres to Section 16 of the Roadmap.

Architecture:
  - Input: 6-DOF IMU time series (3-axis Accel + 3-axis Gyro) -> (B, L, 6)
  - Input Projection: Linear(6, hidden_dim) + Positional Encoding
  - Transformer Encoder: Stack of multi-head self-attention layers
  - Reconstruction Head: Linear(hidden_dim, 6) for masked IMU modeling
  - Pretraining Objective: Masked Sensor Modeling (MSM) via MSE on masked timesteps
─────────────────────────────────────────────────────────────────────────────
"""

import math
import torch
import torch.nn as nn


class PositionalEncoding(nn.Module):
    """Sinusoidal positional encoding for temporal IMU sequences."""

    def __init__(self, d_model, max_len=5000, dropout=0.1):
        super().__init__()
        self.dropout = nn.Dropout(p=dropout)

        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))

        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        pe = pe.unsqueeze(0)  # (1, max_len, d_model)
        self.register_buffer('pe', pe)

    def forward(self, x):
        # x shape: (batch_size, seq_len, d_model)
        seq_len = x.size(1)
        x = x + self.pe[:, :seq_len, :]
        return self.dropout(x)


class LIMUBERT(nn.Module):
    """
    LIMU-BERT self-supervised IMU representation model.
    Pretrains reusable temporal representations of vehicle motion,
    attenuating noise and modeling temporal dependencies.
    """

    def __init__(
        self,
        input_dim=6,
        hidden_dim=128,
        num_heads=4,
        num_layers=4,
        dim_feedforward=256,
        dropout=0.1,
        max_len=1000
    ):
        super().__init__()
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim

        # Input projection
        self.input_proj = nn.Linear(input_dim, hidden_dim)
        self.pos_encoder = PositionalEncoding(hidden_dim, max_len=max_len, dropout=dropout)

        # Transformer encoder
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=hidden_dim,
            nhead=num_heads,
            dim_feedforward=dim_feedforward,
            dropout=dropout,
            batch_first=True,
            activation='gelu'
        )
        self.transformer_encoder = nn.TransformerEncoder(
            encoder_layer,
            num_layers=num_layers
        )

        # Reconstruction head (for self-supervised pretraining)
        self.recon_head = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, input_dim)
        )

    def forward(self, x):
        """
        Forward pass for pretraining.
        Parameters:
        -----------
        x : torch.Tensor of shape (B, L, 6) - potentially masked IMU sequence.
        Returns:
        --------
        recon : torch.Tensor of shape (B, L, 6) - reconstructed IMU sequence.
        latent : torch.Tensor of shape (B, L, hidden_dim) - temporal feature representations.
        """
        # 1. Project input to hidden dimension
        h = self.input_proj(x)
        # 2. Add positional encoding
        h = self.pos_encoder(h)
        # 3. Transformer self-attention
        latent = self.transformer_encoder(h)
        # 4. Reconstruct sensor signals
        recon = self.recon_head(latent)

        return recon, latent

    def encode(self, x):
        """
        Extract frozen latent IMU features for downstream models (TLIO / OdoNet).
        Parameters:
        -----------
        x : torch.Tensor of shape (B, L, 6)
        Returns:
        --------
        latent : torch.Tensor of shape (B, L, hidden_dim)
        """
        h = self.input_proj(x)
        h = self.pos_encoder(h)
        latent = self.transformer_encoder(h)
        return latent

    def compute_pretraining_loss(self, recon, target, mask):
        """
        Compute reconstruction loss strictly on masked timesteps.
        Parameters:
        -----------
        recon : (B, L, 6) - model reconstruction
        target : (B, L, 6) - unmasked true IMU signals
        mask : (B, L) - boolean mask (True where masked)
        Returns:
        --------
        loss : scalar torch.Tensor
        """
        # Expand mask to all 6 channels: (B, L, 6)
        mask_expanded = mask.unsqueeze(-1).expand_as(target)
        if mask_expanded.sum() == 0:
            return torch.tensor(0.0, device=recon.device, requires_grad=True)

        diff = (recon - target) ** 2
        loss = (diff * mask_expanded.float()).sum() / mask_expanded.float().sum().clamp(min=1.0)
        return loss
