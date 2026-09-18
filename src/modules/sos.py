"""
src/modules/sos.py
─────────────────────────────────────────────────────────────────────────────
NavDrishti Layer 4: Emergency Detection & Dispatch (SOS)
Coordinates emergency response upon collision detection or manual trigger.
Features:
  - Locks last known odometry position & heading
  - 30-second user cancellation window before automated dispatch
  - Recovery logic for post-crash pipeline reset
─────────────────────────────────────────────────────────────────────────────
"""

from typing import Optional, Dict, Any
import time


class SOSCoordinator:
    """
    Emergency Dispatch Coordinator for NavDrishti.
    """

    def __init__(self, countdown_seconds: float = 30.0):
        self.countdown_duration = float(countdown_seconds)
        self.alert_active = False
        self.dispatch_dispatched = False
        self.trigger_time = 0.0
        self.locked_position: Optional[Dict[str, Any]] = None
        self.trigger_reason: str = ""
        self.last_impact_magnitude: float = 0.0
        self.last_confidence: float = 0.0

    def on_crash_detected(
        self,
        impact_magnitude: float,
        confidence: float,
        odometry_state: Dict[str, Any],
        current_time: Optional[float] = None
    ) -> bool:
        """
        Handle crash event from Crashnet.
        Triggers emergency alert if confidence > 0.8.
        """
        if confidence > 0.80 and not self.alert_active:
            now = current_time if current_time is not None else time.time()
            self.alert_active = True
            self.dispatch_dispatched = False
            self.trigger_time = now
            self.locked_position = dict(odometry_state)
            self.trigger_reason = "CRASH_EVENT"
            self.last_impact_magnitude = float(impact_magnitude)
            self.last_confidence = float(confidence)
            return True
        return False

    def trigger_manual_sos(
        self,
        odometry_state: Dict[str, Any],
        current_time: Optional[float] = None
    ):
        """User manual emergency SOS button trigger."""
        now = current_time if current_time is not None else time.time()
        self.alert_active = True
        self.dispatch_dispatched = False
        self.trigger_time = now
        self.locked_position = dict(odometry_state)
        self.trigger_reason = "MANUAL_TRIGGER"
        self.last_impact_magnitude = 0.0
        self.last_confidence = 1.0

    def step(self, current_time: Optional[float] = None) -> Dict[str, Any]:
        """
        Update countdown state on each frame.
        """
        if not self.alert_active:
            return {
                'alert_active': False,
                'countdown_remaining_s': 0.0,
                'dispatch_sent': False,
                'locked_position': None
            }

        now = current_time if current_time is not None else time.time()
        elapsed = now - self.trigger_time
        remaining = max(0.0, self.countdown_duration - elapsed)

        if remaining <= 0.0 and not self.dispatch_dispatched:
            # 30-second window expired without user cancellation -> dispatch
            self.dispatch_dispatched = True

        return {
            'alert_active': True,
            'countdown_remaining_s': float(remaining),
            'dispatch_sent': bool(self.dispatch_dispatched),
            'locked_position': self.locked_position,
            'trigger_reason': self.trigger_reason,
            'impact_g': self.last_impact_magnitude,
            'confidence': self.last_confidence
        }

    def cancel_alert(self):
        """User cancels emergency alert within countdown window."""
        self.alert_active = False
        self.dispatch_dispatched = False
        self.locked_position = None
        self.trigger_reason = ""

    def reset_post_crash(self):
        """Reset emergency state and unlock pipeline."""
        self.cancel_alert()
