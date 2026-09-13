"""
scripts/verify_phase7.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Phase 7 Automated Verification Suite: Road Graph, MapGNN & Viterbi Decoder
Adheres to Sections 24–32 of the Roadmap and Project Rule 12.
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import json
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.map_matching.road_graph import RoadNetworkGraph, RoadSegment
from src.map_matching.viterbi_path import TemporalViterbiMatcher


def test_road_segment_geometry():
    """Verify segment projection and perpendicular distance math."""
    print("Test 1: Verifying RoadSegment geometry & projection formulas...")
    seg = RoadSegment(
        edge_id=1,
        u_node=0,
        v_node=1,
        start_coord=np.array([0.0, 0.0]),
        end_coord=np.array([100.0, 0.0])
    )
    assert np.isclose(seg.length, 100.0)
    assert np.isclose(seg.heading, 0.0)

    # Point directly above midpoint at (50, 20)
    q = np.array([50.0, 20.0])
    proj, dist, frac = seg.project_point(q)
    assert np.allclose(proj, [50.0, 0.0])
    assert np.isclose(dist, 20.0)
    assert np.isclose(frac, 0.5)

    # Point beyond end at (120, 10) -> should clamp to end (100, 0)
    q_beyond = np.array([120.0, 10.0])
    proj_b, dist_b, frac_b = seg.project_point(q_beyond)
    assert np.allclose(proj_b, [100.0, 0.0])
    assert np.isclose(frac_b, 1.0)
    print("  [PASS] Segment projection formulas verified.")


def test_road_graph_spatial_index():
    """Verify KDTree spatial index and candidate retrieval."""
    print("Test 2: Verifying RoadNetworkGraph & spatial KDTree index...")
    graph = RoadNetworkGraph()
    graph.add_node(0, [0.0, 0.0])
    graph.add_node(1, [100.0, 0.0])
    graph.add_node(2, [100.0, 100.0])
    graph.add_node(3, [0.0, 100.0])

    graph.add_edge(10, 0, 1)  # (0,0) -> (100,0)
    graph.add_edge(11, 1, 2)  # (100,0) -> (100,100)
    graph.add_edge(12, 2, 3)  # (100,100) -> (0,100)

    graph.build_spatial_index()
    assert len(graph.edges) == 3
    assert 11 in graph.edge_adjacency[10], "Edge 10 must connect topologically to Edge 11"

    # Query near intersection (100, 0)
    cands = graph.query_candidate_segments(np.array([95.0, 5.0]), search_radius=40.0)
    assert len(cands) >= 2
    cand_eids = {c['edge_id'] for c in cands}
    assert 10 in cand_eids and 11 in cand_eids
    print("  [PASS] Road graph construction & spatial candidate indexing verified.")


def test_trajectory_to_graph_generation():
    """Verify trajectory discretization into graph edges."""
    print("Test 3: Verifying trajectory discretization into road graph...")
    # Synthetic discrete trajectory
    t = np.linspace(0, 200, 50)
    traj = np.column_stack([t, np.sin(t / 20.0) * 10.0])

    graph = RoadNetworkGraph()
    graph.build_from_trajectories([traj], segment_length=25.0)

    assert len(graph.nodes) > 5
    assert len(graph.edges) > 5
    assert len(graph.edge_adjacency) == len(graph.edges)
    print("  [PASS] Trajectory to road graph generation verified.")


def test_viterbi_path_decoder():
    """Verify Temporal HMM Viterbi path decoding."""
    print("Test 4: Verifying Temporal Viterbi path decoder...")
    graph = RoadNetworkGraph()
    graph.add_node(0, [0, 0])
    graph.add_node(1, [50, 0])
    graph.add_node(2, [100, 0])
    graph.add_edge(1, 0, 1)
    graph.add_edge(2, 1, 2)
    graph.build_spatial_index()

    viterbi = TemporalViterbiMatcher(graph)

    # 3-step candidate sequence
    cand_1 = {'edge_id': 1, 'along_track_frac': 0.2, 'segment_len': 50.0, 'proj_pos': np.array([10.0, 0.0])}
    cand_2 = {'edge_id': 2, 'along_track_frac': 0.1, 'segment_len': 50.0, 'proj_pos': np.array([55.0, 0.0])}
    cand_distractor = {'edge_id': 99, 'along_track_frac': 0.5, 'segment_len': 50.0, 'proj_pos': np.array([0.0, 50.0])}

    cands_seq = [
        [cand_1, cand_distractor],
        [cand_1, cand_distractor],
        [cand_2, cand_distractor]
    ]
    emiss_seq = [
        np.array([0.9, 0.1]),
        np.array([0.8, 0.2]),
        np.array([0.9, 0.1])
    ]

    path = viterbi.decode_sequence(cands_seq, emiss_seq)
    assert len(path) == 3
    assert path[0]['edge_id'] == 1
    assert path[1]['edge_id'] == 1
    assert path[2]['edge_id'] == 2
    print("  [PASS] Temporal Viterbi sequence decoding verified.")


def test_phase7_notebooks():
    """Verify syntax and structure of all 4 Phase 7 notebooks."""
    print("Test 5: Verifying Phase 7 notebook JSON structures...")
    notebooks = [
        "15_osm_graph_generation.ipynb",
        "16_map_gnn_training.ipynb",
        "17_map_gnn_testing.ipynb",
        "18_map_matching_visualization.ipynb"
    ]
    for nb_name in notebooks:
        nb_path = PROJECT_ROOT / "notebooks" / nb_name
        assert nb_path.exists(), f"Missing notebook: {nb_name}"
        with open(nb_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert "cells" in data and len(data["cells"]) > 0
        print(f"  [PASS] Notebook {nb_name} validated.")


def main():
    print("=" * 70)
    print("  SIH PS 26168 — Phase 7: GNN Map Matching Automated Verification")
    print("=" * 70)
    test_road_segment_geometry()
    test_road_graph_spatial_index()
    test_trajectory_to_graph_generation()
    test_viterbi_path_decoder()
    test_phase7_notebooks()
    print("=" * 70)
    print("  ALL PHASE 7 UNIT & STATIC TESTS PASSED (100%)")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
