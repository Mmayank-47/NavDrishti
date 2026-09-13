"""
src/models/kalmannet.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
KalmanNet: Deep Learning-Driven Adaptive Filtering for Inertial/GNSS Fusion
Adheres to Section 19 of the Roadmap.

Formulation:
  Instead of hand-tuned fixed Kalman gains or fixed noise covariances,
  KalmanNet employs a lightweight Gated Recurrent Unit (GRU) to learn the dynamic
  Kalman Gain matrix K_k from filter innovations and measurement residuals.

State Dimension m = 4 (Position [e, n], Velocity [ve, vn])
Measurement Dimension n = 2 (Neural Odometry Velocity / Displacement [vx, vy])
─────────────────────────────────────────────────────────────────────────────
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class KalmanNetNN(nn.Module):
    """
    KalmanNet recurrent architecture for learned Kalman Gain prediction.
    Combines classical linear state-space models with deep recurrent estimation.
    """

    def __init__(
        self,
        state_dim=4,        # [pos_east, pos_north, vel_east, vel_north]
        meas_dim=2,         # [meas_vx, meas_vy]
        hidden_dim=64,      # GRU hidden units
        num_layers=2,       # Recurrent depth
        dropout=0.1
    ):
        super().__init__()
        self.state_dim = state_dim
        self.meas_dim = meas_dim
        self.hidden_dim = hidden_dim

        # Input feature vector consists of:
        # 1. State innovation / prior difference: delta_x (m)
        # 2. Measurement innovation: y = z - H * x_pred (n)
        # 3. Measurement difference: delta_z = z_k - z_{k-1} (n)
        in_features = state_dim + meas_dim + meas_dim

        # Input linear projection
        self.in_proj = nn.Sequential(
            nn.Linear(in_features, hidden_dim),
            nn.GELU(),
            nn.Dropout(dropout)
        )

        # Recurrent Core (GRU)
        self.gru = nn.GRU(
            input_size=hidden_dim,
            hidden_size=hidden_dim,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0.0
        )

        # Output head: maps hidden state to flattened Kalman Gain matrix K_k (m * n elements)
        self.gain_head = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim),
            nn.GELU(),
            nn.Linear(hidden_dim, state_dim * meas_dim),
            nn.Tanh()  # Bounds Kalman gain elements between [-1.0, 1.0] for filter stability
        )

    def forward(self, delta_x, innovation, delta_z, h_prev=None):
        """
        Compute adaptive Kalman Gain K_k for a single timestep or sequence.

        Parameters:
        -----------
        delta_x : torch.Tensor of shape (B, L, state_dim) or (B, state_dim)
        innovation : torch.Tensor of shape (B, L, meas_dim) or (B, meas_dim)
        delta_z : torch.Tensor of shape (B, L, meas_dim) or (B, meas_dim)
        h_prev : torch.Tensor of shape (num_layers, B, hidden_dim), optional

        Returns:
        --------
        K_gain : torch.Tensor of shape (B, L, state_dim, meas_dim) - Kalman Gain matrix
        h_next : torch.Tensor - updated GRU hidden state
        """
        is_sequence = (delta_x.dim() == 3)
        if not is_sequence:
            delta_x = delta_x.unsqueeze(1)
            innovation = innovation.unsqueeze(1)
            delta_z = delta_z.unsqueeze(1)

        B, L, _ = delta_x.shape

        # Concatenate tracking residuals
        feat = torch.cat([delta_x, innovation, delta_z], dim=-1)  # (B, L, in_features)
        h_proj = self.in_proj(feat)                               # (B, L, hidden_dim)

        gru_out, h_next = self.gru(h_proj, h_prev)               # (B, L, hidden_dim)
        raw_gain = self.gain_head(gru_out)                       # (B, L, state_dim * meas_dim)

        # Reshape to (B, L, state_dim, meas_dim)
        K_gain = raw_gain.view(B, L, self.state_dim, self.meas_dim)

        if not is_sequence:
            K_gain = K_gain.squeeze(1)

        return K_gain, h_next

    def step(self, x_prior, z_meas, H_matrix, x_prev, z_prev, h_prev=None):
        """
        Execute a single filtering step:
          1. Compute innovation y_k = z_k - H * x_prior
          2. Predict adaptive Kalman gain K_k
          3. Compute posterior state: x_post = x_prior + K_k * y_k
        """
        # Innovation y = z - H * x_prior
        y = z_meas - torch.matmul(x_prior, H_matrix.T)  # (B, meas_dim)
        delta_x = x_prior - x_prev                      # (B, state_dim)
        delta_z = z_meas - z_prev                       # (B, meas_dim)

        K_gain, h_next = self.forward(delta_x, y, delta_z, h_prev)  # (B, state_dim, meas_dim)

        # Posterior update: x_post = x_prior + K @ y
        # K: (B, m, n), y: (B, n, 1) -> correction: (B, m)
        correction = torch.bmm(K_gain, y.unsqueeze(-1)).squeeze(-1)
        x_post = x_prior + correction

        return x_post, K_gain, h_next
