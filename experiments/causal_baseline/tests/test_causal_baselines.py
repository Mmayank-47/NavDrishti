"""Independent known-answer checks for the causal replay boundary."""
import json
import numpy as np
import pytest

from experiments.causal_baseline.adapter import CanonicalSession, TimestampPolicy, adapt_arrays
from experiments.causal_baseline.baselines import ConstantVelocity, GyroHeadingSpeed, rotation_phone_to_vehicle_z
from experiments.causal_baseline.replay import initialize_before, replay_outage
from experiments.causal_baseline.export import safe_export


def session(t, gyro=None, reference=None, speed=None):
    n = len(t)
    return CanonicalSession(np.asarray(t, float), np.zeros((n, 3)),
                            np.zeros((n, 3)) if gyro is None else np.asarray(gyro, float),
                            None if reference is None else np.asarray(reference, float), speed)


def test_si_conversions_are_exactly_once_and_timestamp_units_are_explicit():
    s = adapt_arrays([1000, 2000], [[1, 2, 3]] * 2, [[0, 0, 180]] * 2,
                     gyro_unit="deg/s", timestamp_unit="ms")
    assert np.allclose(s.time_s, [0, 1])
    assert np.allclose(s.gyro_phone_rad_s[0, 2], np.pi)
    with pytest.raises(ValueError, match="already SI"):
        adapt_arrays([0, 1], [[0, 0, 0]] * 2, [[0, 0, 0]] * 2,
                     gyro_unit="rad/s", conversion_history=("gyro:deg/s->rad/s",))


def test_timestamp_duplicate_reverse_invalid_and_gap_rules():
    with pytest.raises(ValueError, match="duplicate or reversed"):
        session([0, 1, 1])
    with pytest.raises(ValueError, match="gap"):
        CanonicalSession(np.array([0., 3.]), np.zeros((2, 3)), np.zeros((2, 3)), policy=TimestampPolicy(max_gap_s=2))
    parts = adapt_arrays([0, 1, 5], [[0]*3]*3, [[0]*3]*3, gap_action="segment", max_gap_s=2).segments
    assert [len(x.time_s) for x in parts] == [2, 1]


def test_cv_known_answer_stationary_and_forbidden_gyro_do_not_matter():
    b = ConstantVelocity(np.array([1., 2.]), np.array([10., 0.]))
    assert np.allclose(b.position_at(11), [111, 2])
    assert np.allclose(ConstantVelocity(np.array([3., 4.]), np.zeros(2)).position_at(99), [3, 4])
    assert b.forbidden_inputs == {"gyro", "gnss_speed", "vehicle_speed", "reference_position"}


def test_gyro_heading_circle_and_zero_speed():
    # midpoint integration of v=10, omega=0.1 over 10 seconds: analytic arc
    b = GyroHeadingSpeed(np.zeros(2), np.array([10., 0.]), heading_rad=0.)
    for _ in range(100): b.step(0.1, 0.1)
    assert np.allclose(b.position, [100*np.sin(1), 100*(1-np.cos(1))], atol=0.01)
    z = GyroHeadingSpeed(np.array([2., 3.]), np.zeros(2), heading_rad=None)
    z.step(1, 10); assert np.allclose(z.position, [2, 3])


def test_fixed_phone_mount_inverse_and_equivalent_yaw():
    r = rotation_phone_to_vehicle_z(np.pi / 2)
    assert np.allclose(r @ r.T, np.eye(3))
    phone = np.array([0., 0.4, 0.])
    # 90-degree planar mount maps phone y into vehicle -x; z yaw remains invariant.
    assert np.isclose((r @ phone)[2], 0.)
    assert np.isclose((r @ np.array([0., 0., 0.4]))[2], 0.4)


def test_nontrivial_fixed_mount_matches_identity_yaw_replay():
    t = np.arange(0., 5.); ref = np.column_stack([t * 5, np.zeros_like(t)])
    init = initialize_before(session(t, reference=ref), 2., min_motion_s=1.)
    identity = session(t, gyro=np.array([[0., 0., .4]] * 5), reference=ref)
    # R_x(+90): vehicle z receives phone y, so phone y=.4 is identical yaw input.
    mount = np.array([[1., 0., 0.], [0., 0., -1.], [0., 1., 0.]])
    mounted = session(t, gyro=np.array([[0., .4, 0.]] * 5), reference=ref)
    a = replay_outage(identity, init, 2., 4., "gyro_heading_speed", np.eye(3))
    b = replay_outage(mounted, init, 2., 4., "gyro_heading_speed", mount)
    assert np.allclose(a.trajectory, b.trajectory)


def test_prefix_causality_blackout_and_endpoint_reference_is_scoring_only():
    t = np.arange(0., 5.)
    ref = np.column_stack([t * 10, np.zeros_like(t)])
    s = session(t, reference=ref)
    init = initialize_before(s, t0=2.0, min_motion_s=1.0)
    a = replay_outage(s, init, 2., 4., "constant_velocity")
    poisoned = session(t, gyro=np.array([[91., -4., 17.]] * 5), reference=np.full((5, 2), 999.))
    p = replay_outage(poisoned, init, 2., 4., "constant_velocity")
    assert np.allclose(a.trajectory[:, 1:], p.trajectory[:, 1:])
    assert a.endpoint_error_m == pytest.approx(0.)
    assert np.isclose(a.trajectory[-1, 0], 4.)


def test_gyro_replay_rejects_poison_and_does_not_apply_t1_correction():
    t = np.arange(0., 5.)
    s = session(t, gyro=np.zeros((5, 3)), reference=np.column_stack([t * 5, np.zeros_like(t)]))
    init = initialize_before(s, 2., min_motion_s=1.)
    out = replay_outage(s, init, 2., 4., "gyro_heading_speed", phone_to_vehicle=np.eye(3))
    assert np.allclose(out.trajectory[-1, 1:], [20, 0])
    bad = session(t, gyro=np.zeros((5, 3)), reference=None)
    assert replay_outage(bad, init, 2., 4., "gyro_heading_speed", phone_to_vehicle=np.eye(3)).status == "NOT_EVALUABLE"


def test_shared_initialization_and_finite_failure_export(tmp_path):
    record = safe_export(tmp_path, {"status": "NOT_EVALUABLE", "metric": float("nan"), "reason": "no eligible sessions"})
    data = json.loads(record.read_text())
    assert data["status"] == "NOT_EVALUABLE" and data["metric"] == "NON_FINITE"
