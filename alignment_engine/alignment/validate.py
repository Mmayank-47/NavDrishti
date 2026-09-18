"""Validate the alignment engine against a KNOWN mount rotation.

Synthesise a drive in the vehicle frame, rotate it by a random R_true to fake an
arbitrary phone mount, add sensor noise and gyro bias, then measure how well
solve_alignment recovers R_true. The engine never sees R_true or the gravity
channel, so this is the raw-IMU-plus-GNSS-speed case.

On a graded road the correct answer is NOT R_true: levelling finds the local
vertical, so the recoverable frame is the vehicle frame pitched by the grade.
level_frame() builds that reference, and the grade cases are scored against it.
Scoring against R_true there would report a 4 deg "error" for a frame that is in
fact the one we want.
"""

from __future__ import annotations

import numpy as np
from scipy.spatial.transform import Rotation

from engine import AlignmentEngine, solve_alignment
from frames import GRAVITY, gravity_leak_position_error_m, rotation_error_deg

RATE = 100.0
DT = 1.0 / RATE


def level_frame(R_true: np.ndarray, grade_deg: float) -> np.ndarray:
    """The phone -> local-level-along-track rotation, which is what gravity observes.

    Its up axis is the local vertical rather than the vehicle's, so it differs
    from R_true by the road grade about the lateral axis.
    """
    if not grade_deg:
        return R_true
    c, s = np.cos(np.radians(grade_deg)), np.sin(np.radians(grade_deg))
    M = np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])
    return M @ R_true


def synth_drive(seconds=180.0, rng=None, *, turns=True, longitudinal=True,
                grade_deg=0.0, accel_noise=0.12, gyro_noise=0.004, gyro_bias=0.002):
    """A drive profile in the VEHICLE frame: stops, accel, cruise, brake, turns."""
    rng = rng or np.random.default_rng(0)
    n = int(seconds * RATE)
    t = np.arange(n) * DT
    speed = np.zeros(n)
    omega = np.zeros(n)

    if not longitudinal:
        speed[0] = 14.0                     # start at cruise: no ramp to learn from
    for i in range(1, n):
        phase = (t[i] % 60.0)
        if phase < 6:      target = 0.0     # stopped: gives the stationary window
        elif phase < 18:   target = 15.0    # accelerating to ~54 km/h
        elif phase < 42:   target = 15.0    # cruise
        elif phase < 50:   target = 4.0     # braking
        else:              target = 12.0
        if not longitudinal:
            target = 14.0
        rate = 1.6 if target > speed[i - 1] else 2.6
        speed[i] = max(0.0, speed[i - 1] + np.clip(target - speed[i - 1], -rate * DT, rate * DT))

    if turns:
        for t0, t1, w in [(20, 26, 0.35), (30, 34, -0.28), (75, 82, 0.30),
                          (95, 99, -0.40), (140, 148, 0.25), (160, 166, -0.33)]:
            omega[(t >= t0) & (t < t1)] = w

    a_lon = np.gradient(speed, DT)
    a_lat = speed * omega
    g_v = Rotation.from_euler("y", -grade_deg, degrees=True).apply([0, 0, GRAVITY])
    accel_v = np.column_stack([a_lon, a_lat, np.zeros(n)]) + g_v
    gyro_v = np.column_stack([np.zeros(n), np.zeros(n), omega])

    R_true = Rotation.random(random_state=int(rng.integers(1 << 30))).as_matrix()
    accel_p = accel_v @ R_true + rng.normal(0, accel_noise, (n, 3))
    gyro_p = gyro_v @ R_true + rng.normal(0, gyro_noise, (n, 3)) + rng.normal(0, gyro_bias, 3)
    # GNSS speed: a 1 Hz fix held across the 100 Hz log. Receiver noise belongs to
    # the fix and is held with it, so the log is a staircase -- exactly what
    # speed_derivative has to cope with on real IO-VNBD data.
    fixes = speed[::int(RATE)] + rng.normal(0, 0.15, len(speed[::int(RATE)]))
    speed_gnss = np.repeat(fixes, int(RATE))[:n]
    return accel_p, gyro_p, np.maximum(0, speed_gnss), R_true


def sweep(trials=200, **kw):
    grade = kw.get("grade_deg", 0.0)
    rows = []
    for k in range(trials):
        rng = np.random.default_rng(1000 + k)
        a, g, sp, R_true = synth_drive(rng=rng, **kw)
        sol = solve_alignment(a, g, DT, speed=sp)
        total, tilt, yaw = rotation_error_deg(sol.R_pv, level_frame(R_true, grade))
        rows.append({"total": total, "tilt": tilt, "yaw": yaw, "valid": sol.is_valid,
                     "tilt_sig": sol.tilt_sigma_deg, "yaw_sig": sol.yaw_sigma_deg,
                     "disagree": sol.heading_disagreement_deg,
                     "s_lon": sol.slope_longitudinal, "s_lat": sol.slope_lateral,
                     "b0": sol.static_residual_ms2, "method": sol.yaw_method,
                     "gm": sol.gravity_method.rsplit("_", 1)[0]})
    return rows


def report(name, rows):
    ok = [r for r in rows if r["valid"]]
    print(f"\n{name}   valid {len(ok)}/{len(rows)}")
    if not ok:
        print("   (no valid solutions -- engine correctly refused)")
        return
    pct = lambda key, p: np.nanpercentile([r[key] for r in ok], p)
    for key in ("tilt", "yaw", "total"):
        print(f"   {key:>5} error deg   median {pct(key,50):7.4f}   p95 {pct(key,95):7.4f}"
              f"   max {max(r[key] for r in ok):7.4f}")
    print(f"   reported 1-sigma: tilt {pct('tilt_sig',50):.4f} deg   yaw {pct('yaw_sig',50):.3f} deg")
    print(f"   slopes  lon {pct('s_lon',50):.3f}  lat {pct('s_lat',50):.3f}   "
          f"disagreement {pct('disagree',50):.2f} deg   static residual {pct('b0',50):.3f} m/s^2")
    print(f"   levelling {ok[0]['gm']} · heading {ok[0]['method']}")
    print(f"   60 s outage position error from residual tilt: "
          f"median {gravity_leak_position_error_m(pct('tilt',50),60):6.1f} m   "
          f"p95 {gravity_leak_position_error_m(pct('tilt',95),60):6.1f} m")


if __name__ == "__main__":
    np.set_printoptions(precision=4, suppress=True)
    print("=" * 80)
    print("ALIGNMENT ENGINE VALIDATION -- random mounts, raw IMU + GNSS speed only")
    print("=" * 80)

    report("A. normal drive (accel/brake + turns)", sweep(200))
    report("B. no turns (forward observable only)", sweep(60, turns=False))
    report("C. constant speed (lateral observable only)", sweep(60, longitudinal=False))
    report("D. neither: cruise, no turns", sweep(30, turns=False, longitudinal=False))
    report("E. 5 deg road grade, scored against the local-level frame", sweep(60, grade_deg=5.0))
    report("F. noisy mount (3x accel noise, 5x gyro bias)",
           sweep(60, accel_noise=0.36, gyro_bias=0.010))

    # How much does a grade CHANGE cost? This is the real grade risk: solve on one
    # slope, use on another. Purely geometric, so state it rather than simulate it.
    print("\nG. cost of a stale solution when the road grade changes")
    for d in (0.5, 1.0, 2.0, 5.0):
        print(f"   grade change {d:4.1f} deg  ->  60 s outage error "
              f"{gravity_leak_position_error_m(d, 60):8.1f} m   "
              f"10 s {gravity_leak_position_error_m(d, 10):6.1f} m")

    print("\n" + "=" * 80)
    print("H. streaming engine + phone re-seated mid-drive")
    a1, g1, s1, R1 = synth_drive(seconds=120, rng=np.random.default_rng(77))
    a2, g2, s2, R2 = synth_drive(seconds=120, rng=np.random.default_rng(78))
    eng = AlignmentEngine(rate_hz=RATE, buffer_seconds=90.0, resolve_every_seconds=5.0)
    first_lock = None
    for i in range(len(a1)):
        eng.add(a1[i], g1[i], s1[i])
        if first_lock is None and eng.solution is not None and eng.solution.is_valid:
            first_lock = i * DT
    e1 = rotation_error_deg(eng.solution.R_pv, R1)
    print(f"   locked after {first_lock:.0f} s   tilt {e1[1]:.4f} deg   yaw {e1[2]:.4f} deg")
    for i in range(len(a2)):                       # phone moved: new R_true
        eng.add(a2[i], g2[i], s2[i])
    e2 = rotation_error_deg(eng.solution.R_pv, R2)
    print(f"   re-seat detected {eng.reseat_events}x   re-converged on the new mount: "
          f"tilt {e2[1]:.4f} deg   yaw {e2[2]:.4f} deg")
