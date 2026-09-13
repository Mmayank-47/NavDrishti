"""
src/map_matching/viterbi_path.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Temporal Hidden Markov Model (HMM) Viterbi Path Decoder for Map Matching
Adheres to Section 29 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

from typing import List, Dict, Optional
import numpy as np
from src.map_matching.road_graph import RoadNetworkGraph


class TemporalViterbiMatcher:
    """
    Combines GNN candidate emission probabilities with road topological transition
    probabilities via Viterbi trellis dynamic programming.
    """

    def __init__(
        self,
        road_graph: RoadNetworkGraph,
        p_same_edge: float = 0.75,
        p_connected_edge: float = 0.24,
        p_disconnected_penalty: float = 1e-4
    ):
        self.graph = road_graph
        self.p_same = p_same_edge
        self.p_conn = p_connected_edge
        self.p_disc = p_disconnected_penalty

    def compute_transition_log_prob(
        self,
        prev_cand: Dict,
        curr_cand: Dict,
        expected_distance: float
    ) -> float:
        """
        Compute log transition probability log T(prev -> curr) based on:
          1. Topological connectivity (same edge, directly connected edge, or disconnected gap)
          2. Traveled distance consistency
        """
        eid_prev = prev_cand['edge_id']
        eid_curr = curr_cand['edge_id']

        # Case 1: Continuation along the same road segment
        if eid_prev == eid_curr:
            delta_s = (curr_cand['along_track_frac'] - prev_cand['along_track_frac']) * curr_cand['segment_len']
            # Moving forward along segment
            dist_err = abs(delta_s - expected_distance)
            prob = self.p_same * np.exp(-dist_err / 15.0)
            return float(np.log(max(1e-9, prob)))

        # Case 2: Legal topological transition to an adjacent connected road segment
        outgoing = self.graph.edge_adjacency.get(eid_prev, [])
        if eid_curr in outgoing:
            # Distance from end of prev segment to current position
            prob = self.p_conn
            return float(np.log(max(1e-9, prob)))

        # Case 3: Disconnected gap / impossible jump across topology
        gap_dist = np.linalg.norm(curr_cand['proj_pos'] - prev_cand['proj_pos'])
        prob = self.p_disc * np.exp(-gap_dist / 10.0)
        return float(np.log(max(1e-12, prob)))

    def decode_sequence(
        self,
        candidates_sequence: List[List[Dict]],
        emission_probs_sequence: List[np.ndarray],
        velocities_sequence: Optional[List[float]] = None,
        dt: float = 0.1
    ) -> List[Dict]:
        """
        Run Viterbi trellis forward pass and backtracking.

        Parameters:
        -----------
        candidates_sequence : List of length T, each containing K candidate dicts
        emission_probs_sequence : List of length T, each containing (K,) GNN softmax probabilities
        velocities_sequence : Optional vehicle speed [m/s] at each time step
        dt : time step [s]

        Returns:
        --------
        matched_path : List of length T, each containing the globally optimal candidate dict
        """
        T = len(candidates_sequence)
        if T == 0:
            return []

        # trellis[t][k] = max log-probability ending at candidate k of step t
        trellis = []
        backpointers = []

        # Step 0: Initial prior
        k0_len = len(candidates_sequence[0])
        init_v = np.log(np.maximum(1e-9, emission_probs_sequence[0][:k0_len]))
        trellis.append(init_v)
        backpointers.append(np.zeros(k0_len, dtype=int))

        # Forward pass: t = 1 ... T-1
        for t in range(1, T):
            prev_cands = candidates_sequence[t - 1]
            curr_cands = candidates_sequence[t]
            K_prev = len(prev_cands)
            K_curr = len(curr_cands)

            if K_curr == 0:
                trellis.append(np.array([0.0]))
                backpointers.append(np.zeros(1, dtype=int))
                continue

            # Expected travel distance in 1 time step
            v = velocities_sequence[t] if velocities_sequence is not None else 10.0
            expected_d = max(0.1, v * dt)

            curr_v = np.zeros(K_curr)
            curr_bp = np.zeros(K_curr, dtype=int)
            emissions = emission_probs_sequence[t][:K_curr]

            for j in range(K_curr):
                cand_j = curr_cands[j]
                emiss_j = np.log(max(1e-9, emissions[j]))

                best_logp = -1e12
                best_i = 0
                for i in range(K_prev):
                    cand_i = prev_cands[i]
                    trans_ij = self.compute_transition_log_prob(cand_i, cand_j, expected_d)
                    total_p = trellis[t - 1][i] + trans_ij + emiss_j

                    if total_p > best_logp:
                        best_logp = total_p
                        best_i = i

                curr_v[j] = best_logp
                curr_bp[j] = best_i

            trellis.append(curr_v)
            backpointers.append(curr_bp)

        # Backtracking
        best_path_indices = [0] * T
        best_path_indices[-1] = int(np.argmax(trellis[-1]))

        for t in range(T - 2, -1, -1):
            next_idx = best_path_indices[t + 1]
            best_path_indices[t] = int(backpointers[t + 1][next_idx])

        # Construct final matched trajectory
        matched_path = []
        for t in range(T):
            idx = best_path_indices[t]
            if len(candidates_sequence[t]) > idx:
                matched_path.append(candidates_sequence[t][idx])
            else:
                matched_path.append(candidates_sequence[t][0])

        return matched_path
