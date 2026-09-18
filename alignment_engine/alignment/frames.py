"""Frame conventions and rotation helpers for in-vehicle phone alignment.

CONVENTIONS (fix these once, never re-derive them mid-pipeline)

Phone body frame, Android: +X right across the screen, +Y up the screen,
+Z out of the screen toward the user. Face-up on a table the accelerometer
reads (0, 0, +9.81): it measures specific force, i.e. the reaction to gravity.

Vehicle frame: +X forward, +Y left, +Z up. At rest on level ground the
accelerometer reads (0, 0, +9.81). Right-handed, so yaw rate about +Z is
positive counter-clockwise seen from above -- a left turn.

This matches the VZCrash IMU convention ("X forward, Y leftward, Z upward and
measures 1 g at rest"), so a model trained there consumes our output directly.

The alignment we solve for is R_pv, phone -> vehicle:

    a_vehicle = R_pv @ a_phone          omega_vehicle = R_pv @ omega_phone

Its rows are the vehicle axes expressed in the phone frame:

    R_pv[0] = forward   R_pv[1] = left   R_pv[2] = up
"""

from __future__ import annotations

import numpy as np

GRAVITY = 9.80665


def unit(v: np.ndarray) -> np.ndarray:
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    if n < 1e-12:
        raise ValueError("cannot normalise a zero-length vector")
    return v / n


def horizontal_basis(z_p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Two orthonormal vectors spanning the plane perpendicular to ``z_p``.

    Returned so that (u, v, z_p) is right-handed: u x v = z_p. The choice of u
    within the plane is arbitrary; only the plane matters to the caller.
    """
    z = unit(z_p)
    seed = np.array([1.0, 0.0, 0.0]) if abs(z[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    u = unit(seed - (seed @ z) * z)
    v = np.cross(z, u)
    return u, v


def rotation_from_axes(z_p: np.ndarray, forward_hint_p: np.ndarray) -> np.ndarray:
    """Build R_pv from the vehicle up-axis and an approximate forward axis.

    ``forward_hint_p`` need not be perpendicular to ``z_p``; its component along
    ``z_p`` is projected out. Gram-Schmidt, so the result is exactly orthonormal.
    """
    z = unit(z_p)
    x = np.asarray(forward_hint_p, dtype=np.float64)
    x = x - (x @ z) * z
    x = unit(x)
    y = np.cross(z, x)          # X x Y = Z  =>  Y = Z x X
    return np.vstack([x, y, z])


def rotation_error_deg(R_est: np.ndarray, R_true: np.ndarray) -> tuple[float, float, float]:
    """Split the alignment error into (total, tilt, yaw), all in degrees.

    The relative rotation is expressed in the vehicle frame, so its rotation
    vector separates cleanly:

      - the component about +Z (up) is YAW error: it rotates the forward axis
        within the horizontal plane, and shows up as heading error, i.e. as
        cross-track drift.
      - the component in the horizontal plane is TILT error (pitch/roll): it
        leaks gravity into the horizontal axes, and shows up as a phantom
        acceleration that double-integrates into position.

    Tilt is the dangerous one. See ``gravity_leak_position_error_m``.
    """
    from scipy.spatial.transform import Rotation

    rotvec = Rotation.from_matrix(R_est @ R_true.T).as_rotvec()
    tilt = float(np.degrees(np.linalg.norm(rotvec[:2])))
    yaw = float(np.degrees(abs(rotvec[2])))
    total = float(np.degrees(np.linalg.norm(rotvec)))
    return total, tilt, yaw


def gravity_leak_position_error_m(tilt_error_deg: float, seconds: float) -> float:
    """Position error from an un-modelled tilt, over ``seconds`` of pure INS.

    A tilt error e leaves g*sin(e) of gravity projected onto a horizontal axis.
    Dead reckoning cannot tell that from real acceleration, so it integrates
    twice: 0.5 * g * sin(e) * t^2.

    This is why levelling accuracy dominates the drift budget. At 1 deg and 60 s
    it is over 300 m; the whole point of the alignment engine is to push it to
    a few metres.
    """
    a = GRAVITY * np.sin(np.radians(tilt_error_deg))
    return float(0.5 * a * seconds ** 2)
