"""
src/filters/gnss_fusion.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Robust GNSS/INS Fusion Engine with Innovation Gating & Seamless Deficit Handler
Adheres to Section 23 of the Roadmap.
─────────────────────────────────────────────────────────────────────────────
"""

from enum import Enum
import numpy as np


class NavigationMode(Enum):
    FULL_FUSION = "FULL_FUSION"          # Clean GNSS + INS + Neural Odometry + NHC
    DEGRADED_GNSS = "DEGRADED_GNSS"      # High HDOP/multipath; adaptive noise inflated
    GNSS_BLACKOUT = "GNSS_BLACKOUT"      # Pure Dead Reckoning (ESKF + KalmanNet + NHC)
    RECOVERY = "RECOVERY"                # Post-blackout smooth reconnection (anti-teleport)


class RobustGNSSFusionEngine:
    """
    Robust GNSS/INS Fusion and Seamless Blackout Deficit Engine.
    Features:
      1. Chi-Square (chi^2) Statistical Innovation Gating (Mahalanobis / NIS test)
      2. Adaptive Covariance Weighting (Huber M-estimator + HDOP inflation)
      3. Anti-Teleport Smooth Recovery Smoother (prevents discontinuous vehicle jumps)
      4. Dynamic State Machine coordinating GNSS, Dead Reckoning, and Recovery
    """

    def __init__(
        self,
        chi2_gate_2d=9.21,          # Chi^2 threshold for 2-DOF at p=0.01 (99% confidence)
        chi2_gate_3d=11.34,         # Chi^2 threshold for 3-DOF at p=0.01
        hdop_nominal=1.0,
        recovery_window_steps=20,   # Steps over which to smoothly blend GNSS upon recovery (2.0s @ 10Hz)
        huber_k=1.5                 # Huber tuning constant for residual downweighting
    ):
        self.chi2_gate_2d = chi2_gate_2d
        self.chi2_gate_3d = chi2_gate_3d
        self.hdop_nominal = hdop_nominal
        self.recovery_window_steps = recovery_window_steps
        self.huber_k = huber_k

        self.mode = NavigationMode.FULL_FUSION
        self.blackout_counter = 0
        self.recovery_step = 0
        self.last_valid_gnss = None

        # Statistics tracking
        self.rejected_outliers = 0
        self.accepted_updates = 0
        self.blackout_steps = 0

    def evaluate_innovation_gate(self, y_innov, S_cov, is_recovery=False):
        """
        Compute Normalized Innovation Squared (NIS) and evaluate statistical gate.
        NIS = y^T * S^-1 * y
        """
        dof = len(y_innov)
        gate_threshold = self.chi2_gate_2d if dof == 2 else self.chi2_gate_3d
        if is_recovery:
            # Scale threshold during recovery to accommodate accumulated blackout drift
            # while the anti-teleport smoother dampens the actual applied innovation
            gate_threshold *= 4.0

        try:
            S_inv = np.linalg.inv(S_cov)
            nis = float(y_innov.T @ S_inv @ y_innov)
        except np.linalg.LinAlgError:
            nis = float('inf')

        is_valid = (nis <= gate_threshold)
        return is_valid, nis, gate_threshold

    def compute_adaptive_covariance(self, R_nominal, hdop=None, nis=None):
        """
        Inflate measurement covariance based on:
          1. HDOP scaling: R = R_nom * (HDOP / HDOP_nom)^2
          2. Huber M-estimator weighting for moderate residuals
        """
        scale_factor = 1.0

        # 1. HDOP scaling
        if hdop is not None and hdop > self.hdop_nominal:
            dop_ratio = hdop / self.hdop_nominal
            scale_factor *= max(1.0, dop_ratio ** 2)

        # 2. Huber weighting: if residual is elevated, inflate R to downweight
        if nis is not None and nis > 1.0:
            residual_sigma = np.sqrt(nis)
            if residual_sigma > self.huber_k:
                huber_scale = residual_sigma / self.huber_k
                scale_factor *= huber_scale

        return R_nominal * scale_factor

    def compute_recovery_weight(self):
        """
        Compute smooth innovation fading weight alpha(t) in [0.0, 1.0]
        upon exiting blackout to prevent trajectory snapping / vehicle teleports.
        """
        if self.mode != NavigationMode.RECOVERY:
            return 1.0

        alpha = min(1.0, float(self.recovery_step) / float(self.recovery_window_steps))
        return alpha

    def process_gnss_observation(
        self,
        p_gnss,
        p_predicted,
        P_prior_pos,
        R_gnss_nominal,
        hdop=1.0,
        is_blackout=False
    ):
        """
        Process incoming GNSS horizontal position observation [east, north].

        Returns:
        --------
        update_allowed : bool
        y_effective : np.ndarray (2,) - gated, recovery-damped innovation
        R_effective : np.ndarray (2, 2) - adaptively scaled measurement covariance
        info : dict - diagnostic metrics (NIS, mode, scale factor)
        """
        # Case 1: Active GNSS Blackout (e.g. tunnel, foliage, complete deficit)
        if is_blackout or p_gnss is None:
            self.blackout_counter += 1
            self.blackout_steps += 1
            self.mode = NavigationMode.GNSS_BLACKOUT
            return False, np.zeros(2), R_gnss_nominal, {
                'mode': self.mode.value,
                'nis': 0.0,
                'gate': self.chi2_gate_2d,
                'scale': 1.0,
                'rejected': False
            }

        # Handle Transition: Blackout -> Recovery
        if self.mode == NavigationMode.GNSS_BLACKOUT:
            self.mode = NavigationMode.RECOVERY
            self.recovery_step = 1
            self.blackout_counter = 0

        # Compute raw innovation: y = z - x_prior
        y_raw = p_gnss[:2] - p_predicted[:2]
        S_cov = P_prior_pos[:2, :2] + R_gnss_nominal[:2, :2]

        # 1. Determine effective innovation & evaluate Chi-Square Statistical Gating
        is_recovery = (self.mode == NavigationMode.RECOVERY)
        if is_recovery:
            alpha = self.compute_recovery_weight()
            # Covariance annealing: smoothly decay R from high uncertainty down to nominal
            # This prevents discontinuous state jumps and maintains valid statistical gating
            anneal_factor = max(1.0, (1.0 / max(0.05, alpha))**2)
            R_recovery = R_gnss_nominal * anneal_factor
            S_cov = P_prior_pos[:2, :2] + R_recovery[:2, :2]
            is_valid_gate, nis, threshold = self.evaluate_innovation_gate(y_raw, S_cov, is_recovery=True)
            y_effective = y_raw * alpha
            R_effective = self.compute_adaptive_covariance(R_nominal=R_recovery, hdop=hdop, nis=nis)
        else:
            is_valid_gate, nis, threshold = self.evaluate_innovation_gate(y_raw, S_cov, is_recovery=False)
            y_effective = y_raw
            R_effective = self.compute_adaptive_covariance(R_nominal=R_gnss_nominal, hdop=hdop, nis=nis)

        if not is_valid_gate:
            # Outlier rejected (e.g. multipath reflection, spoofing jump, tunnel exit echo)
            self.rejected_outliers += 1
            mode_tag = NavigationMode.DEGRADED_GNSS.value
            return False, y_raw, R_gnss_nominal * 100.0, {
                'mode': mode_tag,
                'nis': nis,
                'gate': threshold,
                'scale': 100.0,
                'rejected': True
            }

        # 3. Anti-Teleport Innovation Damping State Advancement
        if is_recovery:
            self.recovery_step += 1
            if self.recovery_step > self.recovery_window_steps:
                self.mode = NavigationMode.FULL_FUSION
                self.recovery_step = 0
        else:
            if hdop > 3.0:
                self.mode = NavigationMode.DEGRADED_GNSS
            else:
                self.mode = NavigationMode.FULL_FUSION

        self.accepted_updates += 1
        self.last_valid_gnss = p_gnss[:2].copy()

        return True, y_effective, R_effective, {
            'mode': self.mode.value,
            'nis': nis,
            'gate': threshold,
            'scale': float(R_effective[0, 0] / R_gnss_nominal[0, 0]),
            'rejected': False
        }
