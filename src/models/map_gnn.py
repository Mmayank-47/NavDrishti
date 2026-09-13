"""
src/models/map_gnn.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Graph Neural Network for Topology-Aware Map Matching & Candidate Road Ranking
Adheres to Sections 24, 27, 28 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class GraphAttentionLayer(nn.Module):
    """
    Edge-Conditioned Graph Attention (GAT) message passing layer.
    Propagates topological road network connectivity across candidate road segments.
    """

    def __init__(self, in_features: int, out_features: int, dropout: float = 0.1, alpha: float = 0.2):
        super().__init__()
        self.in_features = in_features
        self.out_features = out_features
        self.alpha = alpha

        self.W = nn.Linear(in_features, out_features, bias=False)
        self.a = nn.Linear(2 * out_features, 1, bias=False)
        self.dropout = nn.Dropout(dropout)
        self.leakyrelu = nn.LeakyReLU(self.alpha)

    def forward(self, h: torch.Tensor, adj: torch.Tensor) -> torch.Tensor:
        """
        Parameters:
        -----------
        h : torch.Tensor of shape (batch_size, num_nodes, in_features)
        adj : torch.Tensor of shape (batch_size, num_nodes, num_nodes)
            Adjacency matrix (1 if connected, 0 otherwise)

        Returns:
        --------
        h_prime : torch.Tensor of shape (batch_size, num_nodes, out_features)
        """
        B, N, _ = h.size()
        Wh = self.W(h)  # (B, N, out_features)

        # Broadcast for pairwise attention coefficients
        Wh_i = Wh.unsqueeze(2).expand(B, N, N, self.out_features)
        Wh_j = Wh.unsqueeze(1).expand(B, N, N, self.out_features)
        a_input = torch.cat([Wh_i, Wh_j], dim=-1)  # (B, N, N, 2 * out_features)

        e = self.leakyrelu(self.a(a_input).squeeze(-1))  # (B, N, N)

        # Mask disconnected edges with very negative value for softmax
        # Add self-loops to adjacency
        eye = torch.eye(N, device=h.device).unsqueeze(0).expand(B, N, N)
        effective_adj = torch.clamp(adj + eye, 0.0, 1.0)

        zero_vec = -9e15 * torch.ones_like(e)
        attention = torch.where(effective_adj > 0, e, zero_vec)
        attention = F.softmax(attention, dim=-1)
        attention = self.dropout(attention)

        h_prime = torch.bmm(attention, Wh)  # (B, N, out_features)
        return F.elu(h_prime)


class MapGNN(nn.Module):
    """
    Topology-Aware Road Candidate Ranking Network.
    
    Given:
      1. Vehicle state query: [east, north, v_east, v_north, heading, pos_uncertainty]
      2. K candidate road segment features: [perp_dist, heading_diff, length, fraction, cos_h, sin_h]
      3. Topological adjacency matrix A between candidate segments
    
    Outputs:
      Softmax probability distribution over the K candidate segments.
    """

    def __init__(
        self,
        query_dim: int = 6,
        edge_dim: int = 6,
        hidden_dim: int = 64,
        num_heads: int = 2,
        dropout: float = 0.1
    ):
        super().__init__()
        self.query_dim = query_dim
        self.edge_dim = edge_dim
        self.hidden_dim = hidden_dim

        # 1. Feature Encoders
        self.query_encoder = nn.Sequential(
            nn.Linear(query_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim)
        )

        self.candidate_encoder = nn.Sequential(
            nn.Linear(edge_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim)
        )

        # 2. Graph Attention Message Passing
        self.gat_layer1 = GraphAttentionLayer(hidden_dim, hidden_dim, dropout=dropout)
        self.gat_layer2 = GraphAttentionLayer(hidden_dim, hidden_dim, dropout=dropout)

        # 3. Candidate Scoring Head
        # Combines segment embedding, neighborhood context, and global vehicle query
        self.scorer = nn.Sequential(
            nn.Linear(hidden_dim * 2, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, 1)
        )

    def forward(
        self,
        query_feat: torch.Tensor,
        candidate_feats: torch.Tensor,
        adj_matrix: torch.Tensor,
        candidate_mask: torch.Tensor = None
    ) -> torch.Tensor:
        """
        Parameters:
        -----------
        query_feat : torch.Tensor (B, query_dim)
        candidate_feats : torch.Tensor (B, K, edge_dim)
        adj_matrix : torch.Tensor (B, K, K)
        candidate_mask : torch.Tensor (B, K) - bool/float mask of valid candidates

        Returns:
        --------
        log_probs : torch.Tensor (B, K)
            Log-softmax distribution over candidate segments.
        """
        B, K, _ = candidate_feats.size()

        # Encode inputs
        q_emb = self.query_encoder(query_feat)             # (B, hidden_dim)
        c_emb = self.candidate_encoder(candidate_feats)     # (B, K, hidden_dim)

        # Message passing over road graph topology
        h_graph = self.gat_layer1(c_emb, adj_matrix)        # (B, K, hidden_dim)
        h_graph = self.gat_layer2(h_graph, adj_matrix)      # (B, K, hidden_dim)

        # Fuse graph embedding with vehicle query
        q_rep = q_emb.unsqueeze(1).expand(B, K, self.hidden_dim)
        fused = torch.cat([h_graph, q_rep], dim=-1)         # (B, K, 2 * hidden_dim)

        # Compute candidate logits
        logits = self.scorer(fused).squeeze(-1)             # (B, K)

        # Apply candidate mask if some query points have fewer candidates
        if candidate_mask is not None:
            logits = logits.masked_fill(~candidate_mask, -1e9)

        return F.log_softmax(logits, dim=-1)

    def predict_best_candidate(
        self,
        query_feat: torch.Tensor,
        candidate_feats: torch.Tensor,
        adj_matrix: torch.Tensor,
        candidate_mask: torch.Tensor = None
    ) -> torch.Tensor:
        """Return the argmax index of the most plausible candidate road segment."""
        log_probs = self.forward(query_feat, candidate_feats, adj_matrix, candidate_mask)
        return torch.argmax(log_probs, dim=-1)
