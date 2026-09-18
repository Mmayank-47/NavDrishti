# In-vehicle alignment engine

Recovers the phone-to-vehicle rotation from raw IMU plus GNSS speed, so a phone
lying at any angle in a holder, a cupholder or a pocket can feed vehicle-frame
axes to `kalmannet.onnx`, `odonet.onnx` and a VZCrash-trained crash detector,
all of which were trained on vehicle-frame data.

## Why this is priority one

A levelling error `e` leaves `g*sin(e)` of gravity projected onto a horizontal
axis. Dead reckoning cannot tell that from real acceleration, so it integrates it
twice:

| Tilt error | 10 s outage | 60 s outage | 120 s outage |
|---|---|---|---|
| 1.00 deg | 8.6 m | 308.1 m | 1232.4 m |
| 0.10 deg | 0.9 m | 30.8 m | 123.2 m |
| 0.02 deg | 0.2 m | 6.2 m | 24.6 m |

For comparison, the strapdown baseline on IO-VNBD drifts about 56 m over a 60 s
outage in total. A single degree of mount error is five times the entire rest of
the error budget, and no filter downstream recovers from it: the leak looks
exactly like acceleration.

## How it works

**Stage 1, levelling** (2 of 3 degrees of freedom). The static accelerometer
reading points along the local vertical. Tiered on evidence: Android's gravity
sensor, else an iterated "only gravity is acting" gate.

The gate has to test the *horizontal component* of specific force, not its
magnitude, and it has to be iterated because "horizontal" is defined by the answer
being solved for. A steady 2 m/s² acceleration changes `|a|` by only 0.2 m/s²
while tilting its direction 12 deg, so a magnitude gate quietly admits exactly the
samples that bias the result. That single mistake cost 0.6 deg of tilt, 184 m per
60 s outage.

But the direction gate alone has a self-consistent wrong answer: under a steady
brake the iteration re-centres onto the total force, after which every selected
sample has zero horizontal component and the scatter is tiny -- a *confident*
15 deg error. Magnitude breaks that tie, because gravity alone reads exactly 1 g
while the false fixed point reads `sqrt(g² + a²)`. So both tests are needed, and
neither works alone: one pins the direction, the other pins the length.

GNSS speed only *seeds* the iteration. Trusting `speed < 0.5` directly labels a
vehicle still braking at 2.6 m/s² as parked, because a held 1 Hz fix lags the true
speed by up to a second.

**Stage 2, heading** (yaw about the vertical). One weighted least squares against
two physically independent observables:

```
a_horizontal  =  b0  +  f * (dv/dt)  +  l * (v * omega_z)
```

`f` is the forward direction, `l` the lateral direction, both expected to be unit
length. Fitting them jointly, rather than taking the principal axis of each sample
set separately, is what makes this work on a real drive: braking through a corner
excites both channels at once and a principal axis is rotated by the mixture.
Taking them separately gave 1.84 deg of yaw error on a normal drive while each
estimator alone was accurate to 0.03 deg.

The regression's own covariance gives a 1-sigma heading uncertainty in degrees,
which *is* the confidence. No hand-tuned score, it refuses honestly when the drive
never excited either channel, and a channel whose fitted slope is far from unity
is dropped rather than trusted.

**GNSS speed is interpolated, not read as logged.** A 1 Hz fix held across a
100 Hz log lags the truth by up to 1.6 m/s under hard acceleration, and the two
observables read that signal differently -- `dv/dt` directly, `v*omega_z` through
the speed factor. Held speed skewed them apart by 1 deg. `dv/dt` is differenced
across genuine fix instants, because a sliding-window slope is diluted about 20%
by steps sitting at random positions inside the window.

**Gyro bias** is estimated from the same static samples and removed.

## Road grade is not a bug

Levelling finds the local vertical, so on a 5 deg incline the solved frame is the
local-level frame along the direction of travel, pitched 5 deg from the vehicle
body. That is the frame you want: gravity is exactly removed in it and forward
acceleration is scaled by only `cos(5 deg)` = 0.996.

Grade and mount pitch are fundamentally confounded from IMU and speed alone --
both scale the longitudinal slope by `cos(angle)`, a 0.4% effect at 5 deg, far
under the noise. So the engine does not try to separate them, and `validate.py`
scores the grade case against the local-level frame; scoring it against the
vehicle frame reports a 4 deg "error" for the frame we actually want.

What *does* cost accuracy is a grade **change** between solving and using:

| Grade change | 10 s outage | 60 s outage |
|---|---|---|
| 0.5 deg | 4.3 m | 154.0 m |
| 2.0 deg | 17.1 m | 616.0 m |

Which is the entire reason `AlignmentEngine` re-solves every few seconds instead
of locking once.

## Validated results

500 random mounts, 180 s synthetic drives, raw IMU + GNSS speed only. The engine
never sees the true rotation or the gravity channel.

| Case | Valid | Tilt (median) | Yaw (median) | 60 s outage error |
|---|---|---|---|---|
| A. normal drive: accel, brake, turns | 198/200 | 0.014 deg | 0.086 deg | **4.2 m** |
| B. no turns, forward observable only | 60/60 | 0.009 deg | 0.027 deg | 2.7 m |
| C. constant speed, lateral only | 60/60 | 0.010 deg | 0.021 deg | 3.2 m |
| D. neither: cruise, no turns | 0/30 | — | — | correctly refuses |
| E. 5 deg grade, vs local-level frame | 60/60 | 0.012 deg | 0.088 deg | 3.7 m |
| F. noisy phone: 3x accel noise, 5x gyro bias | 59/60 | 0.078 deg | 0.110 deg | 23.9 m |
| H. streaming, phone re-seated mid-drive | locks in 20 s | 0.024 deg then 0.014 deg | 0.116 / 0.060 deg | 1 re-seat detected |

Health metrics on case A: fitted slopes 1.031 and 1.000 (both want 1.0), the two
observables disagree by 0.11 deg, and 0.003 m/s² of static force is left
unexplained in the level plane.

Runtime: **17.6 ms** to solve over a 120 s buffer of 100 Hz data, single-threaded
CPU. The rolling statistics are prefix-sum based; the naive version took 350 ms,
which a phone re-solving every 5 s cannot afford.

## Using it

```python
from engine import AlignmentEngine

engine = AlignmentEngine(rate_hz=100.0)          # or 10.0 for IO-VNBD smartphone logs
for accel, gyro, speed in stream:                # phone-frame m/s^2, rad/s, GNSS m/s
    engine.add(accel, gyro, speed)

sol = engine.solution
if sol is not None and sol.is_valid:
    imu_vehicle = sol.rotate_imu(imu_window)     # (N, 6) -> vehicle frame, gyro debiased
elif sol is not None and sol.tilt_only:
    pass    # levelling is good, heading is not: seed heading from GNSS course instead
```

`AlignmentSolution` also carries `tilt_sigma_deg`, `yaw_sigma_deg`,
`gyro_bias_phone`, `slope_longitudinal`, `slope_lateral`,
`heading_disagreement_deg`, `static_residual_ms2` and `mount_description_deg()`.
Feed the sigmas into the navigation filter as measurement noise rather than
treating the rotation as exact. Both are inflated 2x from their formal value:
measured across 500 mounts, both stages were optimistic by almost exactly that
factor, and over-confidence is the dangerous direction downstream. Re-measure that
factor on real IO-VNBD drives.

## Where this sits in the pipeline

Between sensor read and every model. `kalmannet.onnx` takes `imu [b, t, 6]`,
`odonet.onnx` reads longitudinal acceleration, and a VZCrash-trained detector
expects X forward / Y left / Z up at 1 g rest -- which is the convention
`frames.py` targets deliberately, so the same rotation serves navigation and crash
detection with no second transform.

The navigation state machine should gate on alignment: no valid solution means no
dead-reckoning claim, only `tilt_only` means heading comes from GNSS course, and a
re-seat event should force a transition out of any GNSS-denied mode, because the
rotation the filter has been using is now wrong.

## Files

- `frames.py` — frame conventions, rotation helpers, and the error-to-metres map
- `engine.py` — `estimate_gravity`, `solve_alignment`, `AlignmentEngine`
- `validate.py` — synthetic drives with a known mount; run it to reproduce the table
- `README.md` — this file

`python validate.py` reproduces everything above; no dependency beyond numpy and
scipy. The three modules import each other flatly, so run from inside this
directory or add it to `sys.path`.
