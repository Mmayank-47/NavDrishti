"""
scripts/summarize_revalidation.py
Summarizes results from results/phase_revalidation/revalidation_results.json
"""
import json
from pathlib import Path
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES_FILE = PROJECT_ROOT / 'results' / 'phase_revalidation' / 'revalidation_results.json'

with open(RES_FILE, 'r') as f:
    data = json.load(f)

print("=" * 80)
print("1. CONTROLLED COMPARISON: C4 vs C5 (S1)")
print("=" * 80)
for entry in data['phase6_c4_vs_c5']:
    w = entry['window']
    c4 = entry['C4_nio_v2']
    c5 = entry['C5_nio_ft']
    print(f"Window {w:4s} | Dist: {c4['distance_m']:.1f}m")
    print(f"  C4 (NIO v2 + NHC): FinalErr: {c4['final_error_m']:7.2f}m | Drift: {c4['drift_pct']:6.2f}% | RMSE: {c4['rmse_m']:6.2f}m | Jump: {c4['recovery_jump_m']:.3f}m")
    if c5:
        print(f"  C5 (NIO FT + NHC): FinalErr: {c5['final_error_m']:7.2f}m | Drift: {c5['drift_pct']:6.2f}% | RMSE: {c5['rmse_m']:6.2f}m | Jump: {c5['recovery_jump_m']:.3f}m")
    print()

print("=" * 80)
print("2. FULL MULTI-WINDOW BENCHMARK ACROSS ALL 6 SESSIONS (Phase 7)")
print("=" * 80)
bench = data['phase7_full_benchmark']
for sess, durs in bench.items():
    print(f"--- Session {sess} ---")
    for dur, info in durs.items():
        s = info.get('summary', {})
        if s:
            d = s['drift_pct']
            fe = s['final_error_m']
            rmse = s['rmse_m']
            rec = s['recovery_jump_m']
            print(f"  {dur:3s} (N={s['count']:2d}) | Mean Drift: {d['mean']:8.2f}% (Med: {d['median']:6.2f}%, P95: {d['p95']:8.2f}%) | Mean RMSE: {rmse['mean']:6.2f}m (Med: {rmse['median']:6.2f}m) | Mean FinalErr: {fe['mean']:6.2f}m | Mean Jump: {rec['mean']:.3f}m")
        else:
            print(f"  {dur:3s} | N=0 (Session duration too short)")
    print()

print("=" * 80)
print("3. SCENARIO A CROSS-SESSION SUMMARY (Phase 8)")
print("=" * 80)
scen_a = data['phase8_scenario_a']
total_a_quals = 0
total_a_pass = 0
for sess, info in scen_a.items():
    q_cnt = info['qualifying_count']
    p_cnt = info['pass_count']
    total_a_quals += q_cnt
    total_a_pass += p_cnt
    print(f"  Session {sess:5s}: {q_cnt:2d} segments found | Pass (<=5.0m): {p_cnt:2d} ({info['pass_rate_pct']:.1f}%)")
    for idx_e, e in enumerate(info['evaluations']):
        crit = e['criteria']
        print(f"    [{crit['start_idx']}..{crit['end_idx']}] Dur: {crit['duration_s']}s | Dist: {crit['distance_m']}m | Spd: {crit['mean_speed_mps']}m/s | FinalErr: {e['final_error_m']:.3f}m | Pass: {e['sih_pass_5m']}")
print(f"  TOTAL Scenario A: {total_a_pass} / {total_a_quals} passed ({(total_a_pass/max(total_a_quals,1))*100:.1f}%)")
print()

print("=" * 80)
print("4. SCENARIO B FULL SUMMARY (Phase 9)")
print("=" * 80)
scen_b = data['phase9_scenario_b']
total_b_quals = 0
total_b_pass = 0
for sess, info in scen_b.items():
    q_cnt = info['qualifying_count']
    p_cnt = info['pass_count']
    total_b_quals += q_cnt
    total_b_pass += p_cnt
    errs = [e['final_error_m'] for e in info['evaluations']] if info['evaluations'] else [0]
    rmses = [e['rmse_m'] for e in info['evaluations']] if info['evaluations'] else [0]
    drifts = [e['drift_pct'] for e in info['evaluations']] if info['evaluations'] else [0]
    print(f"  Session {sess:5s}: {q_cnt:2d} segments evaluated | Pass (<=100m): {p_cnt:2d} | Mean FinalErr: {np.mean(errs):.2f}m (Min: {np.min(errs):.2f}m, Max: {np.max(errs):.2f}m) | Mean RMSE: {np.mean(rmses):.2f}m | Mean Drift: {np.mean(drifts):.2f}%")
print()

print("=" * 80)
print("5. ABLATION / CAUSAL CHECK TABLE (Phase 11)")
print("=" * 80)
for row in data['phase11_ablation']:
    r = row['res']
    if r:
        print(f"  {row['id']}. {row['name']:35s} | FinalErr: {r['final_error_m']:7.2f}m | Drift: {r['drift_pct']:6.2f}% | RMSE: {r['rmse_m']:6.2f}m | Jump: {r['recovery_jump_m']:.3f}m")
