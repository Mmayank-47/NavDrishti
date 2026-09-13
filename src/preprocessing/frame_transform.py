"""
src/preprocessing/frame_transform.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
Coordinate frame transformations, WGS84 conversions, and attitude kinematics.

Supports:
  - WGS84 Geodetic (lat, lon, alt) <-> Local Cartesian ENU / NED
  - Rotation representations: Euler angles (ZYX), Direction Cosine Matrices (DCM), Quaternions
  - Gravity vector definitions in navigation frames
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np

# WGS84 Ellipsoid constants
WGS84_A = 6378137.0            # Semi-major axis (meters)
WGS84_F = 1.0 / 298.257223563  # Flattening
WGS84_B = WGS84_A * (1.0 - WGS84_F)  # Semi-minor axis
WGS84_E2 = 2.0 * WGS84_F - WGS84_F ** 2  # First eccentricity squared
STANDARD_GRAVITY = 9.80665     # Standard gravity (m/s^2)


# ── WGS84 Geodetic <-> ECEF ──────────────────────────────────────────────────

def geodetic_to_ecef(lat_deg, lon_deg, alt_m):
    """
    Convert geodetic latitude, longitude (degrees), and ellipsoidal height (meters)
    to Earth-Centered, Earth-Fixed (ECEF) coordinates (x, y, z in meters).
    Supports scalars or 1D numpy arrays.
    """
    lat = np.radians(lat_deg)
    lon = np.radians(lon_deg)
    sin_lat = np.sin(lat)
    cos_lat = np.cos(lat)
    sin_lon = np.sin(lon)
    cos_lon = np.cos(lon)

    # Radius of curvature in the prime vertical
    N = WGS84_A / np.sqrt(1.0 - WGS84_E2 * sin_lat ** 2)

    x = (N + alt_m) * cos_lat * cos_lon
    y = (N + alt_m) * cos_lat * sin_lon
    z = (N * (1.0 - WGS84_E2) + alt_m) * sin_lat

    return np.column_stack([x, y, z]) if np.ndim(lat_deg) > 0 else np.array([x, y, z])


def ecef_to_geodetic(x, y, z):
    """
    Convert ECEF coordinates (meters) to geodetic latitude, longitude (degrees),
    and ellipsoidal height (meters) using Bowring's iterative method.
    """
    p = np.sqrt(x ** 2 + y ** 2)
    theta = np.arctan2(z * WGS84_A, p * WGS84_B)
    e_prime2 = (WGS84_A ** 2 - WGS84_B ** 2) / (WGS84_B ** 2)

    lat = np.arctan2(
        z + e_prime2 * WGS84_B * np.sin(theta) ** 3,
        p - WGS84_E2 * WGS84_A * np.cos(theta) ** 3
    )
    lon = np.arctan2(y, x)
    sin_lat = np.sin(lat)
    N = WGS84_A / np.sqrt(1.0 - WGS84_E2 * sin_lat ** 2)
    alt = p / np.cos(lat) - N

    lat_deg = np.degrees(lat)
    lon_deg = np.degrees(lon)

    return (np.column_stack([lat_deg, lon_deg, alt])
            if np.ndim(x) > 0
            else np.array([lat_deg, lon_deg, alt]))


# ── WGS84 <-> Local Tangent Plane (ENU / NED) ────────────────────────────────

def geodetic_to_enu(lat_deg, lon_deg, alt_m, lat0_deg, lon0_deg, alt0_m):
    """
    Convert Geodetic coordinates to local East-North-Up (ENU) coordinates (meters)
    relative to a local reference origin (lat0, lon0, alt0).
    """
    ecef = geodetic_to_ecef(lat_deg, lon_deg, alt_m)
    ecef0 = geodetic_to_ecef(lat0_deg, lon0_deg, alt0_m)

    dx = ecef[:, 0] - ecef0[0] if np.ndim(lat_deg) > 0 else ecef[0] - ecef0[0]
    dy = ecef[:, 1] - ecef0[1] if np.ndim(lat_deg) > 0 else ecef[1] - ecef0[1]
    dz = ecef[:, 2] - ecef0[2] if np.ndim(lat_deg) > 0 else ecef[2] - ecef0[2]

    lat0 = np.radians(lat0_deg)
    lon0 = np.radians(lon0_deg)
    sin_lat0 = np.sin(lat0)
    cos_lat0 = np.cos(lat0)
    sin_lon0 = np.sin(lon0)
    cos_lon0 = np.cos(lon0)

    e = -sin_lon0 * dx + cos_lon0 * dy
    n = -sin_lat0 * cos_lon0 * dx - sin_lat0 * sin_lon0 * dy + cos_lat0 * dz
    u =  cos_lat0 * cos_lon0 * dx + cos_lat0 * sin_lon0 * dy + sin_lat0 * dz

    return np.column_stack([e, n, u]) if np.ndim(lat_deg) > 0 else np.array([e, n, u])


def enu_to_geodetic(e, n, u, lat0_deg, lon0_deg, alt0_m):
    """
    Convert local East-North-Up (ENU) coordinates (meters) back to Geodetic
    coordinates (lat, lon degrees, alt meters) relative to reference origin.
    """
    lat0 = np.radians(lat0_deg)
    lon0 = np.radians(lon0_deg)
    sin_lat0 = np.sin(lat0)
    cos_lat0 = np.cos(lat0)
    sin_lon0 = np.sin(lon0)
    cos_lon0 = np.cos(lon0)

    # Inverse rotation matrix (transpose of ENU-to-ECEF rotation)
    dx = -sin_lon0 * e - sin_lat0 * cos_lon0 * n + cos_lat0 * cos_lon0 * u
    dy =  cos_lon0 * e - sin_lat0 * sin_lon0 * n + cos_lat0 * sin_lon0 * u
    dz =  cos_lat0 * n + sin_lat0 * u

    ecef0 = geodetic_to_ecef(lat0_deg, lon0_deg, alt0_m)
    x = dx + ecef0[0]
    y = dy + ecef0[1]
    z = dz + ecef0[2]

    return ecef_to_geodetic(x, y, z)


def enu_to_ned(enu_coords):
    """Convert ENU [East, North, Up] to NED [North, East, Down]."""
    if enu_coords.ndim == 1:
        return np.array([enu_coords[1], enu_coords[0], -enu_coords[2]])
    return np.column_stack([enu_coords[:, 1], enu_coords[:, 0], -enu_coords[:, 2]])


def ned_to_enu(ned_coords):
    """Convert NED [North, East, Down] to ENU [East, North, Up]."""
    if ned_coords.ndim == 1:
        return np.array([ned_coords[1], ned_coords[0], -ned_coords[2]])
    return np.column_stack([ned_coords[:, 1], ned_coords[:, 0], -ned_coords[:, 2]])


# ── Rotation & Attitude Representations (Euler / Quaternions / DCM) ──────────

def euler_to_rotation_matrix(roll, pitch, yaw):
    """
    Compute 3x3 direction cosine matrix R_b_to_n from Euler angles (radians).
    Uses standard Aerospace ZYX sequence (Yaw -> Pitch -> Roll).
    Body vector v_b maps to Navigation vector v_n as: v_n = R @ v_b
    """
    cr, sr = np.cos(roll), np.sin(roll)
    cp, sp = np.cos(pitch), np.sin(pitch)
    cy, sy = np.cos(yaw), np.sin(yaw)

    R = np.array([
        [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
        [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
        [-sp,     cp * sr,                cp * cr]
    ])
    return R


def rotation_matrix_to_euler(R):
    """
    Extract Euler angles [roll, pitch, yaw] in radians from 3x3 DCM.
    Roll: [-pi, pi], Pitch: [-pi/2, pi/2], Yaw: [-pi, pi].
    """
    pitch = -np.arcsin(np.clip(R[2, 0], -1.0, 1.0))
    if np.abs(np.cos(pitch)) > 1e-6:
        roll = np.arctan2(R[2, 1], R[2, 2])
        yaw  = np.arctan2(R[1, 0], R[0, 0])
    else:
        # Gimbal lock
        roll = 0.0
        yaw  = np.arctan2(-R[0, 1], R[1, 1])
    return np.array([roll, pitch, yaw])


def euler_to_quaternion(roll, pitch, yaw):
    """
    Convert Euler angles (radians) to unit quaternion q = [qw, qx, qy, qz].
    Standard Hamilton convention.
    """
    cr = np.cos(roll * 0.5)
    sr = np.sin(roll * 0.5)
    cp = np.cos(pitch * 0.5)
    sp = np.sin(pitch * 0.5)
    cy = np.cos(yaw * 0.5)
    sy = np.sin(yaw * 0.5)

    qw = cr * cp * cy + sr * sp * sy
    qx = sr * cp * cy - cr * sp * sy
    qy = cr * sp * cy + sr * cp * sy
    qz = cr * cp * sy - sr * sp * cy

    q = np.array([qw, qx, qy, qz])
    return q / np.linalg.norm(q)


def quaternion_to_rotation_matrix(q):
    """
    Convert unit quaternion q = [qw, qx, qy, qz] to 3x3 rotation matrix.
    v_n = R @ v_b
    """
    qw, qx, qy, qz = q / np.linalg.norm(q)

    return np.array([
        [1.0 - 2.0 * (qy**2 + qz**2), 2.0 * (qx*qy - qw*qz),       2.0 * (qx*qz + qw*qy)],
        [2.0 * (qx*qy + qw*qz),       1.0 - 2.0 * (qx**2 + qz**2), 2.0 * (qy*qz - qw*qx)],
        [2.0 * (qx*qz - qw*qy),       2.0 * (qy*qz + qw*qx),       1.0 - 2.0 * (qx**2 + qy**2)]
    ])


def quaternion_to_euler(q):
    """Convert quaternion q = [qw, qx, qy, qz] to Euler angles [roll, pitch, yaw] in radians."""
    R = quaternion_to_rotation_matrix(q)
    return rotation_matrix_to_euler(R)


def quaternion_multiply(q1, q2):
    """Multiply two quaternions: q_out = q1 ⊗ q2 (Hamilton product)."""
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    return np.array([
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2
    ])


def rotate_vector(v, q):
    """Rotate a 3D vector v by quaternion q = [qw, qx, qy, qz]."""
    R = quaternion_to_rotation_matrix(q)
    return R @ v
