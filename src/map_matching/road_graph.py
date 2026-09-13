"""
src/map_matching/road_graph.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Road Network Graph Representation, Spatial Indexing & Candidate Projection
Adheres to Sections 24–27 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

from typing import List, Dict, Tuple, Optional
import numpy as np
from scipy.spatial import cKDTree


class RoadSegment:
    """Represents a directed road edge connecting two nodes in navigation ENU frame."""

    def __init__(
        self,
        edge_id: int,
        u_node: int,
        v_node: int,
        start_coord: np.ndarray,
        end_coord: np.ndarray,
        road_type: str = "primary",
        one_way: bool = False
    ):
        self.edge_id = edge_id
        self.u_node = u_node
        self.v_node = v_node
        self.start_coord = np.asarray(start_coord[:2], dtype=np.float64)
        self.end_coord = np.asarray(end_coord[:2], dtype=np.float64)
        self.road_type = road_type
        self.one_way = one_way

        # Geometric vectors
        self.vec = self.end_coord - self.start_coord
        self.length = float(np.linalg.norm(self.vec))
        if self.length > 1e-6:
            self.unit_vec = self.vec / self.length
            self.heading = float(np.arctan2(self.unit_vec[1], self.unit_vec[0]))
        else:
            self.unit_vec = np.array([1.0, 0.0])
            self.heading = 0.0

        # Midpoint for spatial KDTree indexing
        self.midpoint = (self.start_coord + self.end_coord) * 0.5

    def project_point(self, query_pos: np.ndarray) -> Tuple[np.ndarray, float, float]:
        """
        Compute perpendicular projection of a query point onto this road segment.

        Returns:
        --------
        proj_point : np.ndarray (2,)
            Coordinates of nearest point on segment.
        perp_dist : float
            Euclidean distance from query_pos to proj_point.
        fraction : float
            Along-track fraction s in [0.0, 1.0].
        """
        p = np.asarray(query_pos[:2], dtype=np.float64)
        if self.length < 1e-6:
            dist = float(np.linalg.norm(p - self.start_coord))
            return self.start_coord.copy(), dist, 0.0

        # Scalar projection: s = (p - start) · unit_vec / length
        w = p - self.start_coord
        s_dist = float(np.dot(w, self.unit_vec))
        s_frac = np.clip(s_dist / self.length, 0.0, 1.0)

        proj_point = self.start_coord + s_frac * self.vec
        perp_dist = float(np.linalg.norm(p - proj_point))

        return proj_point, perp_dist, s_frac


class RoadNetworkGraph:
    """
    Topological road network graph with spatial indexing for fast local query retrieval.
    """

    def __init__(self):
        self.nodes: Dict[int, np.ndarray] = {}         # node_id -> [east, north]
        self.edges: Dict[int, RoadSegment] = {}        # edge_id -> RoadSegment
        self.adjacency: Dict[int, List[int]] = {}      # node_id -> outgoing edge_ids
        self.edge_adjacency: Dict[int, List[int]] = {} # edge_id -> next connected edge_ids

        # Spatial index structures
        self._kdtree: Optional[cKDTree] = None
        self._edge_id_list: List[int] = []

    def add_node(self, node_id: int, coord: np.ndarray):
        self.nodes[node_id] = np.asarray(coord[:2], dtype=np.float64)
        if node_id not in self.adjacency:
            self.adjacency[node_id] = []

    def add_edge(
        self,
        edge_id: int,
        u_node: int,
        v_node: int,
        road_type: str = "primary",
        one_way: bool = False
    ) -> RoadSegment:
        assert u_node in self.nodes and v_node in self.nodes, "Both endpoints must exist"
        start_coord = self.nodes[u_node]
        end_coord = self.nodes[v_node]

        segment = RoadSegment(edge_id, u_node, v_node, start_coord, end_coord, road_type, one_way)
        self.edges[edge_id] = segment
        self.adjacency[u_node].append(edge_id)
        self._kdtree = None  # Invalidate tree
        return segment

    def build_spatial_index(self):
        """Construct KDTree of segment midpoints for local subgraph candidate retrieval."""
        if not self.edges:
            return

        self._edge_id_list = list(self.edges.keys())
        midpoints = np.array([self.edges[eid].midpoint for eid in self._edge_id_list])
        self._kdtree = cKDTree(midpoints)
        self.max_segment_length = max((seg.length for seg in self.edges.values()), default=50.0)

        # Build edge-to-edge topological connectivity: edge A connects to edge B if A.v_node == B.u_node
        self.edge_adjacency = {eid: [] for eid in self.edges}
        for eid_a, seg_a in self.edges.items():
            outgoing = self.adjacency.get(seg_a.v_node, [])
            for eid_b in outgoing:
                if eid_b != eid_a:
                    self.edge_adjacency[eid_a].append(eid_b)

    def query_candidate_segments(
        self,
        query_pos: np.ndarray,
        query_heading: Optional[float] = None,
        search_radius: float = 60.0,
        max_candidates: int = 10
    ) -> List[Dict]:
        """
        Retrieve all candidate road segments within search_radius of query_pos.

        Returns:
        --------
        candidates : List[Dict]
            Ranked list of candidate dictionaries containing:
            - edge_id
            - perp_dist
            - heading_diff (rad)
            - along_track_frac
            - proj_pos
            - segment_len
            - next_edges
        """
        if self._kdtree is None:
            self.build_spatial_index()

        q_pos = np.asarray(query_pos[:2], dtype=np.float64)
        # Expand search radius by half the maximum segment length so endpoints are never missed
        r_kdtree = search_radius + 0.5 * getattr(self, 'max_segment_length', 50.0)
        indices = self._kdtree.query_ball_point(q_pos, r=r_kdtree)

        candidates = []
        for idx in indices:
            eid = self._edge_id_list[idx]
            seg = self.edges[eid]
            proj_pos, perp_dist, frac = seg.project_point(q_pos)

            if perp_dist > search_radius:
                continue

            # Heading difference in [-pi, pi]
            if query_heading is not None:
                d_theta = (query_heading - seg.heading + np.pi) % (2.0 * np.pi) - np.pi
                abs_d_theta = abs(d_theta)
            else:
                abs_d_theta = 0.0

            candidates.append({
                'edge_id': eid,
                'perp_dist': perp_dist,
                'heading_diff': abs_d_theta,
                'along_track_frac': frac,
                'proj_pos': proj_pos,
                'segment_len': seg.length,
                'next_edges': self.edge_adjacency.get(eid, [])
            })

        # Sort primarily by perpendicular distance
        candidates.sort(key=lambda c: c['perp_dist'])
        return candidates[:max_candidates]

    def build_from_trajectories(
        self,
        trajectories: List[np.ndarray],
        segment_length: float = 25.0
    ):
        """
        Construct a clean road network graph from ground truth reference trajectories.
        Discretizes continuous trajectories into nodes and connected segments.
        """
        node_id_counter = 0
        edge_id_counter = 0

        for traj in trajectories:
            if len(traj) < 2:
                continue

            # Resample trajectory to approximately uniform spacing
            dists = np.linalg.norm(np.diff(traj[:, :2], axis=0), axis=1)
            cum_dists = np.insert(np.cumsum(dists), 0, 0.0)
            total_len = cum_dists[-1]

            if total_len < segment_length:
                n_samples = 2
            else:
                n_samples = max(2, int(np.ceil(total_len / segment_length)))

            target_dists = np.linspace(0.0, total_len, n_samples)
            sampled_east = np.interp(target_dists, cum_dists, traj[:, 0])
            sampled_north = np.interp(target_dists, cum_dists, traj[:, 1])

            prev_nid = None
            for pt_idx in range(n_samples):
                coord = np.array([sampled_east[pt_idx], sampled_north[pt_idx]])

                # Check if close to an existing node to merge intersections (threshold 8m)
                matched_nid = None
                for nid, ncoord in self.nodes.items():
                    if np.linalg.norm(coord - ncoord) < 8.0:
                        matched_nid = nid
                        break

                if matched_nid is None:
                    curr_nid = node_id_counter
                    self.add_node(curr_nid, coord)
                    node_id_counter += 1
                else:
                    curr_nid = matched_nid

                if prev_nid is not None and prev_nid != curr_nid:
                    # Check if edge already exists
                    edge_exists = False
                    for existing_eid in self.adjacency.get(prev_nid, []):
                        if self.edges[existing_eid].v_node == curr_nid:
                            edge_exists = True
                            break
                    if not edge_exists:
                        self.add_edge(edge_id_counter, prev_nid, curr_nid)
                        edge_id_counter += 1

                prev_nid = curr_nid

        self.build_spatial_index()
        return self
