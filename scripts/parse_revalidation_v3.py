"""
scripts/parse_revalidation_v3.py
Parses results/phase_revalidation_v3/revalidation_v3_results.json
"""
import json
import numpy as np

def main():
    with open('results/phase_revalidation_v3/revalidation_v3_results.json') as f:
        d = json.load(f)

    print("================================================================================")
    print("1. MASTER COMPARISON: C4 vs C5 vs C6 (S1 Window [1500..1800], 30s Outage)")
    print("================================================================================")
    for k in ['C4', 'C5', 'C6']:
        v = d['c4_vs_c5_vs_c6'][k]
        print(f"{k:4s} | Final Err: {v['final_error_m']:7.2f}m | Drift: {v['drift_pct']:6.2f}% | RMSE: {v['rmse_m']:6.2f}m | Max Err: {v['max_error_m']:7.2f}m | Jump: {v['recovery_jump_m']:.3f}m | Cornering: {v['cornering_count']}")

    print("\n================================================================================")
    print("2. FULL BENCHMARK C6 (NIO FT + KNet v3 + NHC) BY SESSION AND DURATION")
    print("================================================================================")
    sessions = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']
    for dur in ['10s', '30s', '60s']:
        print(f"\n--- Duration {dur} ---")
        d_drifts, d_errs, d_rmses, d_jumps = [], [], [], []
        for s in sessions:
            stat = d['full_benchmark_c6'][s][dur]['summary']
            if stat.get('count', 0) > 0:
                m_drift = stat['drift_pct']['mean']
                med_drift = stat['drift_pct']['median']
                p95_drift = stat['drift_pct']['p95']
                m_err = stat['final_error_m']['mean']
                m_rmse = stat['rmse_m']['mean']
                m_jump = stat['recovery_jump_m']['mean']
                d_drifts.append(m_drift)
                d_errs.append(m_err)
                d_rmses.append(m_rmse)
                d_jumps.append(m_jump)
                print(f"  {s:4s} (N={stat['count']:2d}) | Mean Drift: {m_drift:6.2f}% (Med: {med_drift:5.2f}%, P95: {p95_drift:6.2f}%) | Final Err: {m_err:6.2f}m | RMSE: {m_rmse:6.2f}m | Jump: {m_jump:5.2f}m")
        if d_drifts:
            print(f"  --> OVERALL {dur:3s} MEAN: Drift = {np.mean(d_drifts):.2f}% | Final Err = {np.mean(d_errs):.2f}m | RMSE = {np.mean(d_rmses):.2f}m | Jump = {np.mean(d_jumps):.3f}m")

    print("\n================================================================================")
    print("3. SIH SCENARIO A EVALUATION (C6) (Short Outages 3-5s, 40-60m, Pass <= 5m)")
    print("================================================================================")
    tot_pass_a, tot_count_a = 0, 0
    all_errs_a = []
    for s in sessions:
        res = d['scenario_a_c6'].get(s, {})
        c = res.get('qualifying_count', 0)
        p = res.get('pass_count', 0)
        tot_count_a += c
        tot_pass_a += p
        errs = [e['final_error_m'] for e in res.get('evaluations', [])]
        all_errs_a.extend(errs)
        mean_e = np.mean(errs) if errs else 0.0
        min_e = np.min(errs) if errs else 0.0
        max_e = np.max(errs) if errs else 0.0
        p_pct = (p / c * 100.0) if c > 0 else 0.0
        print(f"  {s:4s} | Qual: {c:2d} | Pass: {p:2d} ({p_pct:5.1f}%) | Mean Err: {mean_e:6.2f}m | Min: {min_e:5.2f}m | Max: {max_e:6.2f}m")
    pct_a = (tot_pass_a / tot_count_a * 100.0) if tot_count_a > 0 else 0.0
    print(f"  --> SCENARIO A TOTAL: {tot_pass_a}/{tot_count_a} passed ({pct_a:.2f}%) | Global Mean Err: {np.mean(all_errs_a):.2f}m")

    print("\n================================================================================")
    print("4. SIH SCENARIO B EVALUATION (C6) (Complete Outage ~60s, Pass <= 100m)")
    print("================================================================================")
    tot_pass_b, tot_count_b = 0, 0
    all_errs_b = []
    all_drifts_b = []
    for s in sessions:
        res = d['scenario_b_c6'].get(s, {})
        c = res.get('qualifying_count', 0)
        p = res.get('pass_count', 0)
        tot_count_b += c
        tot_pass_b += p
        errs = [e['final_error_m'] for e in res.get('evaluations', [])]
        drifts = [e['drift_pct'] for e in res.get('evaluations', [])]
        all_errs_b.extend(errs)
        all_drifts_b.extend(drifts)
        mean_e = np.mean(errs) if errs else 0.0
        mean_d = np.mean(drifts) if drifts else 0.0
        p_pct = (p / c * 100.0) if c > 0 else 0.0
        print(f"  {s:4s} | Qual: {c:2d} | Pass: {p:2d} ({p_pct:5.1f}%) | Mean Err: {mean_e:7.2f}m | Mean Drift: {mean_d:6.2f}%")
    pct_b = (tot_pass_b / tot_count_b * 100.0) if tot_count_b > 0 else 0.0
    print(f"  --> SCENARIO B TOTAL: {tot_pass_b}/{tot_count_b} passed ({pct_b:.2f}%) | Global Mean Err: {np.mean(all_errs_b):.2f}m | Global Mean Drift: {np.mean(all_drifts_b):.2f}%")

if __name__ == '__main__':
    main()
