"""In-vehicle alignment: recover the phone -> vehicle rotation from IMU + GNSS speed.

A phone sits at an arbitrary angle in a holder, a cupholder or a pocket, but every
downstream model (odonet, kalmannet, and a VZCrash-trained crash detector) was
trained on vehicle-frame axes. This module estimates that rotation so the runtime
can rotate an IMU window before inference.

Why this module is priority one: a 1 deg levelling error leaves g*sin(1 deg) of
gravity projected onto a horizontal axis, which dead reckoning cannot distinguish
from real acceleration and double-integrates into 308 m of position error over a
60 s GNSS outage. No filter downstream recovers from that. See
frames.gravity_leak_position_error_m.

Two stages, because gravity and driving dynamics observe different axes:

  Stage 1 -- LEVELLING (2 of 3 DoF). The accelerometer's static reading points
  along the local vertical. Tiered estimator, best evidence first: Android's
  gravity sensor, then GNSS-confirmed stops, then an iterative "only gravity is
  acting" gate, then a robust median. The gate has to test the horizontal
  component of specific force directly, not the magnitude: a steady 2 m/s^2
  acceleration changes |a| by only 0.2 m/s^2 while tilting its direction by 12 deg.

  Stage 2 -- HEADING (yaw about the vertical). One weighted least squares against
  two physically independent observables:

      a_horizontal = b0 + f * (dv/dt) + l * (v * omega_z)

  f is the forward direction, l the lateral direction, both expected to be unit
  length. Fitting them jointly (rather than taking the principal axis of each
  sample set separately) is what makes this work on a real drive, where braking
  through a corner excites both channels at once and a principal axis is rotated
  by the mixture. The regression's own covariance gives a 1-sigma heading
  uncertainty in degrees, which is the confidence: no hand-tuned score, and it
  refuses honestly when the drive never excited either channel.

A NOTE ON ROAD GRADE, because it looks like a bug and is not. Levelling finds the
local vertical, so on a 5 deg incline the solved frame is the local-level frame
along the direction of travel, pitched 5 deg from the vehicle body. That is the
frame you want: gravity is exactly removed in it and forward acceleration is
scaled by only cos(5 deg) = 0.996. Grade and mount pitch are fundamentally
confounded from IMU and speed alone (both scale the longitudinal slope by
cos(angle), a 0.4% effect at 5 deg). What actually costs accuracy is a grade
CHANGE between solving and using, which is why the streaming engine re-solves
every few seconds instead of locking once.

Deliberately NOT here: no magnetometer (unreliable inside a steel shell next to
speakers), no recursive filter (a re-solve over a rolling buffer is simpler and
easier to audit), and no attempt to work without GNSS at all -- the sign of
"forward" is unobservable from a bare IMU.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from frames import GRAVITY, horizontal_basis, rotation_from_axes, unit

# Least excitation, in m/s^2 RMS, before a regression channel is used at all.
# Below this the column is indistinguishable from differentiation noise.
MIN_EXCITATION = 0.30
# 1-sigma uncertainties at which confidence reaches zero.
TILT_SIGMA_LIMIT_DEG = 0.60
YAW_SIGMA_LIMIT_DEG = 5.00
# Both stages report a formal 1-sigma from their own residuals, and across 500
# validated random mounts both came out optimistic by almost exactly 2x -- the
# residuals are not quite white and the estimators are not quite unbiased. Inflate
# rather than leave it, because these numbers are consumed as measurement noise by
# the navigation filter downstream, where over-confidence is the dangerous
# direction. Re-measure this factor against real IO-VNBD drives.
SIGMA_CALIBRATION = 2.0


@dataclass
class AlignmentSolution:
    R_pv: np.ndarray                 # 3x3, phone -> vehicle (local-level along track)
    gravity_phone: np.ndarray        # 3, gravity reaction in phone frame
    gyro_bias_phone: np.ndarray      # 3, rad/s, estimated and already removed
    tilt_confidence: float           # 0..1, from the levelling 1-sigma
    yaw_confidence: float            # 0..1, from the heading 1-sigma
    tilt_sigma_deg: float
    yaw_sigma_deg: float
    n_longitudinal: int              # samples with usable dv/dt excitation
    n_turning: int                   # samples with usable v*omega excitation
    gravity_method: str
    yaw_method: str
    heading_disagreement_deg: float  # between the forward and lateral observables
    slope_longitudinal: float        # |f|, want ~1
    slope_lateral: float             # |l|, want ~1
    static_residual_ms2: float       # |b0|, leftover static force after levelling
    notes: list[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        return self.tilt_confidence >= 0.5 and self.yaw_confidence >= 0.5

    @property
    def tilt_only(self) -> bool:
        """Levelling succeeded but heading did not.

        Still worth shipping: it removes the gravity leak, which dominates the
        drift budget, and heading can be seeded from GNSS course instead.
        """
        return self.tilt_confidence >= 0.5 and self.yaw_confidence < 0.5

    @property
    def score(self) -> float:
        """Single number for "is this solution better than that one".

        Tilt is weighted 3x because its error term grows as g*sin(e)*t^2 while a
        yaw error only mis-points an otherwise correct distance.
        """
        return 3.0 * self.tilt_confidence + self.yaw_confidence

    def rotate_imu(self, imu: np.ndarray) -> np.ndarray:
        """Rotate an (N, 6) [ax, ay, az, gx, gy, gz] window into the vehicle frame."""
        imu = np.asarray(imu, dtype=np.float64)
        out = np.empty_like(imu)
        out[:, 0:3] = imu[:, 0:3] @ self.R_pv.T
        out[:, 3:6] = (imu[:, 3:6] - self.gyro_bias_phone) @ self.R_pv.T
        return out

    def mount_description_deg(self) -> dict[str, float]:
        """Human-readable mount attitude, for the status screen and for judges."""
        from scipy.spatial.transform import Rotation

        yaw, pitch, roll = Rotation.from_matrix(self.R_pv).as_euler("zyx", degrees=True)
        return {"yaw_deg": float(yaw), "pitch_deg": float(pitch), "roll_deg": float(roll)}


def _rolling_mean_var(x: np.ndarray, win: int) -> tuple[np.ndarray, np.ndarray]:
    """Centred rolling mean and variance, edge-padded, in O(n) via prefix sums.

    Written this way because it is the hot path: a naive per-sample window over a
    120 s buffer at 100 Hz is 1.2 M slices and took 350 ms per solve, which a phone
    re-solving every 5 s cannot afford. Values are centred first so that
    E[x^2] - E[x]^2 has no cancellation problem.
    """
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    if win < 2 or n < 2:
        return x.copy(), np.zeros(n)
    pad = win // 2
    xp = np.pad(x, (pad, pad), mode="edge") - float(np.mean(x))
    c1 = np.concatenate([[0.0], np.cumsum(xp)])
    c2 = np.concatenate([[0.0], np.cumsum(xp * xp)])
    lo = np.arange(n)
    hi = lo + win
    hi = np.minimum(hi, len(xp))
    k = (hi - lo).astype(np.float64)
    mean = (c1[hi] - c1[lo]) / k
    var = np.maximum((c2[hi] - c2[lo]) / k - mean * mean, 0.0)
    return mean + float(np.mean(x)), var


def _noise_sigma(x: np.ndarray) -> float:
    """Per-axis white-noise level, from the high-frequency content of the signal.

    Successive differences of a smooth physical signal are dominated by sensor
    noise, and differencing inflates it by sqrt(2). Robust to the actual motion,
    which lives at frequencies far below the sample rate.
    """
    d = np.diff(np.asarray(x, dtype=np.float64), axis=0)
    if len(d) == 0:
        return 0.0
    return float(np.median(np.abs(d)) / (0.6745 * np.sqrt(2.0)))


def interpolate_held_speed(speed: np.ndarray, dt: float) -> np.ndarray:
    """Undo the zero-order hold on GNSS speed by interpolating between fixes.

    A 1 Hz fix held across a 100 Hz log lags the true speed by up to a second,
    which during hard acceleration is 1.6 m/s of error. That matters because both
    heading observables read this signal: dv/dt directly, and v*omega_z through the
    speed factor. Held speed skews the two by different amounts, so on a drive
    that brakes through a corner they disagreed by 1 deg even though each was
    accurate to 0.02 deg alone. Interpolating removes the skew and makes them
    consistent, which is the whole basis of the cross-check.
    """
    speed = np.asarray(speed, dtype=np.float64)
    n = len(speed)
    changed = np.diff(speed) != 0.0
    if n < 5 or np.mean(changed) >= 0.7:
        return speed                                  # already sample-rate, or noisy
    idx = np.concatenate([[0], np.flatnonzero(changed) + 1, [n - 1]])
    idx = np.unique(idx)
    if len(idx) < 3:
        return speed
    return np.interp(np.arange(n) * dt, idx * dt, speed[idx])


def speed_derivative(speed: np.ndarray, dt: float, window_s: float = 2.0) -> np.ndarray:
    """dv/dt from GNSS speed, differentiated across genuine fixes.

    GNSS reports speed at about 1 Hz but it is logged at the IMU rate, so adjacent
    samples are usually an identical held value. A plain gradient divides receiver
    noise by dt and amplifies it a hundredfold; a sliding-window slope is better
    but still attenuated, because a step sitting at a random position inside the
    window adds variance that the true acceleration cannot explain and regression
    dilution then shrinks the fitted slope by about 20%.

    So find where the value actually changes, difference between those instants,
    and interpolate back. When the input is not held (already smooth, or resampled)
    fall back to a windowed slope.
    """
    speed = np.asarray(speed, dtype=np.float64)
    n = len(speed)
    if n < 5:
        return np.zeros(n)
    changed = np.diff(speed) != 0.0
    if np.mean(changed) < 0.7:                       # zero-order held: use fix instants
        idx = np.concatenate([[0], np.flatnonzero(changed) + 1])
        if len(idx) >= 3:
            t_fix = idx * dt
            dv = np.gradient(speed[idx], t_fix)
            return np.interp(np.arange(n) * dt, t_fix, dv)
    win = int(round(window_s / dt)) | 1
    if win < 5 or win >= n:
        return np.gradient(speed, dt)
    from scipy.signal import savgol_filter

    return savgol_filter(speed, win, 1, deriv=1, delta=dt)


def _effective_n(x: np.ndarray) -> float:
    """Independent-sample count of a correlated series, via its lag-1 correlation.

    White sensor noise decorrelates every sample, so all N count; a residual left
    by slow vehicle motion is nearly constant across a second, so a thousand
    samples carry the information of one. Assuming AR(1), the effective count is
    N*(1-r)/(1+r), which spans both cases instead of guessing a decorrelation time.
    """
    x = np.asarray(x, dtype=np.float64) - np.mean(x)
    n = len(x)
    if n < 8 or np.all(x == 0):
        return max(1.0, float(n))
    denom = float(x @ x)
    r = 0.0 if denom < 1e-18 else float(np.clip((x[:-1] @ x[1:]) / denom, 0.0, 0.999))
    return max(1.0, n * (1.0 - r) / (1.0 + r))


def estimate_gravity(
    accel: np.ndarray,
    gyro: np.ndarray,
    dt: float,
    speed: np.ndarray | None = None,
    gravity_channel: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, float, str]:
    """Gravity reaction and gyro bias in the phone frame, plus a 1-sigma tilt error.

    Returns (gravity_vector, gyro_bias, sigma_tilt_deg, method).

    The gate that matters tests the HORIZONTAL component of specific force, not
    its magnitude, and it has to be iterated because "horizontal" is defined by
    the answer. A steady 2 m/s^2 acceleration changes |a| by only 0.2 m/s^2 while
    tilting its direction 12 deg, so a magnitude gate quietly admits exactly the
    samples that bias the result. GNSS speed only seeds the iteration: a held 1 Hz
    fix lags the true speed by up to a second, so "speed < 0.5" on its own labels
    a vehicle still braking at 2.6 m/s^2 as parked.

    Every threshold scales with this device's measured noise floor, because a
    cheap phone in a rattling holder has three times the accelerometer noise of a
    flagship on a windscreen mount and would fail any fixed gate.
    """
    accel = np.asarray(accel, dtype=np.float64)
    gyro = np.asarray(gyro, dtype=np.float64)
    n = len(accel)
    win = max(2, int(round(1.0 / dt)))

    sig_a = max(_noise_sigma(accel), 1e-3)
    sig_w = max(_noise_sigma(gyro), 1e-4)
    a_mag = np.linalg.norm(accel, axis=1)
    _, a_var = _rolling_mean_var(a_mag, win)
    w_mag, _ = _rolling_mean_var(np.linalg.norm(gyro, axis=1), win)
    quiet = (a_var < max(6.0 * sig_a ** 2, 1e-4)) & (w_mag < max(8.0 * sig_w, 0.02))

    def finish(mask: np.ndarray, method: str) -> tuple[np.ndarray, np.ndarray, float, str]:
        sel = accel[mask]
        g_vec = np.median(sel, axis=0)
        z = unit(g_vec)
        perp = sel - np.outer(sel @ z, z)             # the levelling residual itself
        scatter = float(np.median(np.abs(perp)) * 1.4826)
        n_ind = min(_effective_n(perp[:, 0]), _effective_n(perp[:, 1]))
        sigma = np.degrees(1.253 * scatter / GRAVITY / np.sqrt(n_ind))   # median, not mean

        # The direction gate alone has a self-consistent wrong answer: under a
        # steady 2.6 m/s^2 brake the iteration re-centres z onto the total force,
        # after which every selected sample has zero horizontal component and the
        # scatter is tiny -- a confident 15 deg error. Magnitude breaks the tie,
        # because gravity alone reads exactly 1 g while that fixed point reads
        # sqrt(g^2 + a^2). This is the same weak magnitude test that must never be
        # used INSTEAD of the direction gate, and is exactly what is needed
        # alongside it: one pins the direction, the other pins the length.
        # Applied as a one-sided significance test, because the mapping back to an
        # angle is brutally steep: a_h = sqrt(2*g*excess), so 0.02 m/s^2 of length
        # error already reads as 3.7 deg. Only excess that survives three standard
        # errors counts, otherwise a noisy phone gets penalised for its own noise.
        # White noise also inflates the median length by sigma^2/g; remove that.
        mags = np.linalg.norm(sel, axis=1)
        m = float(np.median(mags)) - sig_a ** 2 / GRAVITY
        se_m = 1.253 * float(np.median(np.abs(mags - np.median(mags))) * 1.4826) \
            / np.sqrt(_effective_n(mags))
        excess = max(0.0, m - 3.0 * se_m)
        a_h_equiv = float(np.sqrt(max(0.0, excess ** 2 - GRAVITY ** 2)))
        sigma = float(np.hypot(sigma, np.degrees(np.arctan2(a_h_equiv, GRAVITY))))

        sel_q = mask & quiet
        bias = np.median(gyro[sel_q], axis=0) if sel_q.sum() >= win else np.zeros(3)
        return g_vec, bias, max(float(sigma), 0.005), f"{method}_{int(mask.sum())}"

    if gravity_channel is not None:
        gc = np.asarray(gravity_channel, dtype=np.float64)
        if np.all(np.isfinite(gc)) and abs(np.linalg.norm(np.median(gc, axis=0)) - GRAVITY) < 0.5:
            g_vec = np.median(gc, axis=0)
            bias = np.median(gyro[quiet], axis=0) if quiet.sum() >= win else np.zeros(3)
            return g_vec, bias, 0.02, "android_gravity_sensor"

    # Seed from GNSS-reported stops when we have them: even lagged, they are far
    # closer to the answer than a median over the whole drive.
    seed = quiet & (np.asarray(speed, dtype=np.float64) < 0.5) if speed is not None \
        else np.zeros(n, dtype=bool)
    z = unit(np.median(accel[seed], axis=0)) if seed.sum() >= win \
        else unit(np.median(accel, axis=0))

    # Bound the true horizontal acceleration we admit, not the measured one. A
    # measurement of |a_h| carries 2 axes of noise, so the limit that admits at
    # most A_ADMIT of real acceleration is sqrt(A_ADMIT^2 + 2*sigma^2). Scaling the
    # limit linearly with noise instead let a noisy phone admit 1.4 m/s^2 of real
    # braking, which biased levelling by 1.5 deg -- 460 m over a 60 s outage.
    a_h_limit = float(np.sqrt(0.25 ** 2 + 2.0 * sig_a ** 2))
    mask = None
    for _ in range(4):
        a_h = np.linalg.norm(accel - np.outer(accel @ z, z), axis=1)
        cand = quiet & (a_h < a_h_limit)
        if cand.sum() < win:
            break
        mask = cand
        z = unit(np.median(accel[mask], axis=0))
    if mask is not None:
        return finish(mask, "gravity_only")

    g_vec = np.median(accel, axis=0)
    bias = np.median(gyro[quiet], axis=0) if quiet.sum() >= win else np.zeros(3)
    return g_vec, bias, 5.0, "long_window_median"


def _wrap_deg(x: float) -> float:
    return float(np.degrees(np.arctan2(np.sin(np.radians(x)), np.cos(np.radians(x)))))


def _solve_heading(a2: np.ndarray, a_lon: np.ndarray, a_lat: np.ndarray):
    """Joint least squares for forward and lateral directions in the level plane.

    Model, per sample:  a_horizontal = b0 + f * (dv/dt) + l * (v * omega_z)

    Both f and l observe the same single unknown (yaw), through channels excited
    by different manoeuvres, so this is one fit with a built-in cross-check rather
    than two estimators to be averaged. Returns
    (forward2, sigma_deg, disagreement_deg, |f|, |l|, |b0|, method).
    """
    cols, names = [np.ones(len(a2))], ["b0"]
    exc_lon = float(np.sqrt(np.mean(a_lon ** 2)))
    exc_lat = float(np.sqrt(np.mean(a_lat ** 2)))
    if exc_lon > MIN_EXCITATION:
        cols.append(a_lon); names.append("lon")
    if exc_lat > MIN_EXCITATION:
        cols.append(a_lat); names.append("lat")
    if len(cols) == 1:
        return None, float("inf"), float("nan"), float("nan"), float("nan"), float("nan"), "none"

    X = np.column_stack(cols)
    keep = np.ones(len(X), dtype=bool)
    for _ in range(2):                       # one robust re-fit: potholes, kerbs, bumps
        B, *_ = np.linalg.lstsq(X[keep], a2[keep], rcond=None)
        r = np.linalg.norm(a2 - X @ B, axis=1)
        s = float(np.median(r) * 1.4826) or 1e-6
        new = r < 4.0 * s
        if new.sum() < len(X) * 0.2:
            break
        keep = new
    Xk = X[keep]
    resid = a2[keep] - Xk @ B
    # Pooled per-component residual sigma; each response column shares X, so one
    # number covers both and the covariance factor below is the same for each.
    sigma_r = float(np.sqrt(np.mean(resid ** 2)))
    C = np.linalg.pinv(Xk.T @ Xk)

    est = []                                  # (angle_rad, sigma_rad, slope, label)
    for j, nm in enumerate(names):
        if nm == "b0":
            continue
        d = B[j]
        slope = float(np.linalg.norm(d))
        if slope < 1e-6:
            continue
        se = sigma_r * float(np.sqrt(max(C[j, j], 0.0)))
        ang = float(np.arctan2(d[1], d[0]))
        if nm == "lat":
            # The lateral axis is vehicle +Y (left); forward is that turned -90 deg
            # about up, so subtract a quarter turn to express it as a heading.
            ang -= np.pi / 2
        est.append((ang, se / slope, slope, nm))

    slope_lon = next((s for a, sg, s, nm in est if nm == "lon"), float("nan"))
    slope_lat = next((s for a, sg, s, nm in est if nm == "lat"), float("nan"))
    b0 = float(np.linalg.norm(B[0]))
    # A slope far from unity means the model does not describe this data: a
    # sliding mount, a gyro scale error, or speed that is not the vehicle's.
    est = [e for e in est if 0.5 < e[2] < 1.8 and np.isfinite(e[1])]
    if not est:
        return None, float("inf"), float("nan"), slope_lon, slope_lat, b0, "slopes_implausible"

    disagreement = float("nan")
    if len(est) == 2:
        (a1, s1, _, _), (a2_, s2, _, _) = est
        delta = _wrap_deg(np.degrees(a2_ - a1))
        disagreement = abs(delta)
        w1, w2 = 1.0 / max(s1, 1e-9) ** 2, 1.0 / max(s2, 1e-9) ** 2
        ang = a1 + np.radians(delta) * w2 / (w1 + w2)
        sigma = float(np.degrees(np.sqrt(1.0 / (w1 + w2))))
        # If they disagree by far more than their own error bars allow, something
        # unmodelled is present. Inflate sigma to match the evidence instead of
        # reporting a precision the data does not support.
        expect = np.degrees(np.hypot(s1, s2))
        if disagreement > 3.0 * expect:
            sigma *= disagreement / (3.0 * expect)
        method = "longitudinal+centripetal"
    else:
        ang, s, _, nm = est[0]
        sigma = float(np.degrees(s))
        method = "longitudinal" if nm == "lon" else "centripetal"

    return (np.array([np.cos(ang), np.sin(ang)]), sigma, disagreement,
            slope_lon, slope_lat, b0, method)


def solve_alignment(
    accel: np.ndarray,
    gyro: np.ndarray,
    dt: float,
    speed: np.ndarray | None = None,
    gravity_channel: np.ndarray | None = None,
) -> AlignmentSolution:
    """Solve for R_pv over a buffer of phone-frame IMU (and GNSS speed if available).

    Args:
        accel: (N, 3) m/s^2, specific force in the phone frame.
        gyro: (N, 3) rad/s in the phone frame.
        dt: sample period in seconds.
        speed: (N,) m/s from GNSS. Needed to disambiguate forward from backward
            and to excite the heading regression; without it heading stays invalid.
        gravity_channel: (N, 3) optional Android gravity vector.
    """
    accel = np.asarray(accel, dtype=np.float64)
    gyro = np.asarray(gyro, dtype=np.float64)
    notes: list[str] = []

    # ---- Stage 1: levelling -------------------------------------------------
    g_vec, bias, tilt_sigma, g_method = estimate_gravity(
        accel, gyro, dt, speed, gravity_channel)
    z_p = unit(g_vec)                        # local vertical, expressed in phone frame
    gyro = gyro - bias
    tilt_sigma *= SIGMA_CALIBRATION
    tilt_conf = float(np.clip(1.0 - tilt_sigma / TILT_SIGMA_LIMIT_DEG, 0.0, 0.99))
    if abs(np.linalg.norm(g_vec) - GRAVITY) > 1.5:
        tilt_conf *= 0.3
        notes.append("static force is not plausibly 1 g; sensor or mount problem")

    u, v = horizontal_basis(z_p)
    a_dyn = accel - g_vec
    a_h = a_dyn - np.outer(a_dyn @ z_p, z_p)
    a2 = np.column_stack([a_h @ u, a_h @ v])

    def refuse(msg: str) -> AlignmentSolution:
        notes.append(msg)
        return AlignmentSolution(
            R_pv=rotation_from_axes(z_p, u), gravity_phone=g_vec, gyro_bias_phone=bias,
            tilt_confidence=tilt_conf, yaw_confidence=0.0,
            tilt_sigma_deg=tilt_sigma, yaw_sigma_deg=float("inf"),
            n_longitudinal=0, n_turning=0, gravity_method=g_method, yaw_method="none",
            heading_disagreement_deg=float("nan"), slope_longitudinal=float("nan"),
            slope_lateral=float("nan"), static_residual_ms2=float("nan"), notes=notes)

    if speed is None:
        return refuse("no GNSS speed: the forward direction is unobservable")

    # ---- Stage 2: heading ---------------------------------------------------
    speed = interpolate_held_speed(np.asarray(speed, dtype=np.float64), dt)
    a_lon = speed_derivative(speed, dt)
    omega_z = gyro @ z_p
    a_lat = speed * omega_z

    fwd2, yaw_sigma, disagree, s_lon, s_lat, b0, yaw_method = _solve_heading(a2, a_lon, a_lat)
    yaw_sigma *= SIGMA_CALIBRATION
    n_lon = int(np.sum(np.abs(a_lon) > MIN_EXCITATION))
    n_turn = int(np.sum(np.abs(a_lat) > MIN_EXCITATION))
    if fwd2 is None:
        sol = refuse("no usable dynamics: accelerate in a straight line, then turn")
        sol.n_longitudinal, sol.n_turning = n_lon, n_turn
        sol.slope_longitudinal, sol.slope_lateral, sol.static_residual_ms2 = s_lon, s_lat, b0
        return sol

    R_pv = rotation_from_axes(z_p, fwd2[0] * u + fwd2[1] * v)
    yaw_conf = float(np.clip(1.0 - yaw_sigma / YAW_SIGMA_LIMIT_DEG, 0.0, 0.99))
    if np.isfinite(disagree) and disagree > 10.0:
        notes.append(f"forward and lateral observables disagree by {disagree:.1f} deg")
    if b0 > 0.5:
        notes.append(f"{b0:.2f} m/s^2 of static force left in the level plane; "
                     "levelling window may span a changing road grade")

    return AlignmentSolution(
        R_pv=R_pv, gravity_phone=g_vec, gyro_bias_phone=bias,
        tilt_confidence=tilt_conf, yaw_confidence=yaw_conf,
        tilt_sigma_deg=tilt_sigma, yaw_sigma_deg=yaw_sigma,
        n_longitudinal=n_lon, n_turning=n_turn, gravity_method=g_method,
        yaw_method=yaw_method, heading_disagreement_deg=disagree,
        slope_longitudinal=s_lon, slope_lateral=s_lat, static_residual_ms2=b0, notes=notes)


class AlignmentEngine:
    """Streaming wrapper: buffer samples, re-solve periodically, detect re-seating.

    Usage in the runtime loop:

        engine = AlignmentEngine(rate_hz=100.0)
        engine.add(accel, gyro, speed)          # per sample or per block
        sol = engine.solution
        if sol is not None and sol.is_valid:
            imu_vehicle = sol.rotate_imu(imu_window)
    """

    def __init__(self, rate_hz: float = 100.0, buffer_seconds: float = 120.0,
                 resolve_every_seconds: float = 5.0, min_solve_seconds: float = 20.0,
                 reseat_sustain_seconds: float = 3.0):
        self.dt = 1.0 / rate_hz
        self.capacity = int(rate_hz * buffer_seconds)
        self.resolve_every = int(rate_hz * resolve_every_seconds)
        self.min_solve = int(rate_hz * min_solve_seconds)
        self._accel: list[np.ndarray] = []
        self._gyro: list[np.ndarray] = []
        self._speed: list[float] = []
        self._since_solve = 0
        self._since_check = 0
        self._reseat_window = int(rate_hz * 5.0)
        self._check_every = max(1, int(rate_hz * 1.0))
        # Hysteresis in seconds, not in samples: a phone actually slipping stays
        # displaced, while a corner or a pothole moves the mean force for well
        # under a second. Counting raw samples made two strikes 20 ms apart.
        self._reseat_needed = max(1, int(round(reseat_sustain_seconds)))
        self._reseat_strikes = 0
        self.solution: AlignmentSolution | None = None
        self.reseat_events = 0

    def _reset_buffer(self) -> None:
        self._accel, self._gyro, self._speed = [], [], []
        self._since_solve = self.resolve_every
        self._reseat_strikes = 0

    def add(self, accel, gyro, speed: float | None = None) -> None:
        accel = np.atleast_2d(np.asarray(accel, dtype=np.float64))
        gyro = np.atleast_2d(np.asarray(gyro, dtype=np.float64))
        n = len(accel)
        self._accel.extend(accel)
        self._gyro.extend(gyro)
        self._speed.extend([np.nan if speed is None else float(speed)] * n)
        if len(self._accel) > self.capacity:
            drop = len(self._accel) - self.capacity
            del self._accel[:drop], self._gyro[:drop], self._speed[:drop]
        self._since_solve += n
        self._since_check += n

        if self._since_check >= self._check_every:
            self._since_check = 0
            self._check_reseat()

        if self._since_solve >= self.resolve_every and len(self._accel) >= self.min_solve:
            self._since_solve = 0
            sp = np.array(self._speed)
            candidate = solve_alignment(
                np.array(self._accel), np.array(self._gyro), self.dt,
                speed=None if np.all(np.isnan(sp)) else np.nan_to_num(sp))
            # Keep whichever solution the evidence supports better, so an early
            # window with one gentle corner cannot beat a later one with three.
            if self.solution is None or candidate.score >= self.solution.score:
                self.solution = candidate

    def _check_reseat(self) -> None:
        """Has the phone moved in its holder? Then the old rotation is wrong.

        This must be judged WITHOUT the current solution's frame. Screening samples
        by "small horizontal component in the solution frame" is circular: once the
        phone has actually moved, that frame is wrong, so the screen rejects every
        sample and the detector goes permanently blind -- the engine then rotates a
        whole drive with a 106 deg error and reports high confidence. Screening on
        |a| ~ g instead is not circular but is not a static test either, since
        braking at 2.6 m/s^2 shifts |a| by 0.34 m/s^2 while swinging its direction
        15 deg. So re-run the frame-free levelling estimator over the recent window
        and compare the two gravity directions.
        """
        if self.solution is None or not self.solution.is_valid \
                or len(self._accel) < self._reseat_window:
            return
        a = np.array(self._accel[-self._reseat_window:])
        g = np.array(self._gyro[-self._reseat_window:])
        sp = np.array(self._speed[-self._reseat_window:])
        g_now, _, sigma, method = estimate_gravity(
            a, g, self.dt, None if np.all(np.isnan(sp)) else np.nan_to_num(sp))
        if method.startswith("long_window") or sigma > 1.0:
            return                                     # the window cannot tell us
        cos = np.clip(unit(g_now) @ unit(self.solution.gravity_phone), -1, 1)
        moved = np.degrees(np.arccos(cos)) > 8.0
        self._reseat_strikes = self._reseat_strikes + 1 if moved else 0
        if self._reseat_strikes >= self._reseat_needed:
            self.solution = None
            self.reseat_events += 1
            self._reset_buffer()
