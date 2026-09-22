# Causal baseline experiment

The package has two deterministic planar baselines: fixed ENU velocity and fixed initial speed with a supplied phone-to-vehicle rotation applied to gyro before yaw integration. It is isolated from `src/integration/final_navigation_pipeline.py`; vehicle speed, GNSS speed and reference position are never estimator inputs during an outage.

`time_s` is monotonic seconds, acceleration is phone-frame m/s², gyro is phone-frame rad/s, and positions/velocities are ENU `[east,north]` metres and m/s. The supplied mount matrix maps phone axes into vehicle axes. GNSS freshness is unknown because the inspected CSV interface supplies no measurement timestamp; coordinate change age is deliberately not reported as fix age. The runner uses a past-only reference chord solely for initialization, then scores at exact `t1` after propagation.

Run: `py -m pytest experiments/causal_baseline/tests -q`; `py -m experiments.causal_baseline.create_source_zip --output causal_baseline_source`; `py -m experiments.causal_baseline.run --config experiments/causal_baseline/configs/example.json --output results/causal_baseline`.

The legacy loader's phone speed `/3.6` behavior is audited but not consumed here; this experiment therefore makes no claim about its disputed source units. A real gyro-heading run requires an independently justified, past-only mount rotation. Identity in the sample config is only a declared fixture, not a real-session calibration.
