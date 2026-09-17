"""
scripts/parse_revalidation_v4.py
Parses results/phase_revalidation_v4/revalidation_v4_results.json
"""
import json
import numpy as np

def main():
    json_path = 'results/phase_revalidation_v4/revalidation_v4_results.json'
    try:
        with open(json_path) as f:
            d = json.load(f)
    except Exception as e:
        print(f"Error opening {json_path}: {e}")
        return

    print("=" * 80)
    print("1. CONTROLLED KINEMATIC ABLATION (Session S1 Window [1500..1800], 30s Outage)")
    print("=" * 80)
    ablation = d.get('controlled_ablation_s1_30s', {})
    for k in ['A1_C6_Baseline', 'A2_Plus_ZUPT', 'A3_Plus_Bias_Comp', 'A4_Plus_Speed_Observer', 'A5_C7_Full_Enhanced']:
        v = ablation.get(k)
        if v:
            print(f"{k:24s} | Final Err: {v['final_error_m']:7.2f}m | Drift: {v['drift_pct']:6.2f}% | RMSE: {v['rmse_m']:6.2f}m | Max Err: {v['max_error_m']:7.2f}m | Jump: {v['recovery_jump_m']:.3f}m | Cornering: {v['cornering_count']}")

    print("\n" + "=" * 80)
    print("2. FULL BENCHMARK C7 (NAV-SHIELD v4: ZUPT+Bias+SpeedObs+AdaptNHC) BY SESSION & DURATION")
    print("=" * 80)
    sessions = ['S1', 'S2', 'S3a', 'S3b', 'S3c', 'S4']
    full_bench = d.get('full_benchmark_c7', {})
    for dur in ['10s', '30s', '60s']:
        print(f"\n--- Duration {dur} ---")
        d_drifts, d_errs, d_rmses, d_jumps = [], [], [], []
        for s in sessions:
            stat = full_bench.get(s, {}).get(dur, {}).get('summary', {})
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

    print("\n" + "=" * 80)
    print("3. SIH SCENARIO A EVALUATION (Short Outages 3-5s, 40-60m, Pass <= 5m)")
    print("=" * 80)
    scen_a = d.get('scenario_a', {})
    tot_pass_a, tot_count_a = 0, 0
    tot_pass_ar, tot_count_ar = 0, 0
    all_errs_a = []
    all_errs_ar = []
    for s in sessions:
        res = scen_a.get(s, {})
        c = res.get('qualifying_count', 0)
        p = res.get('pass_count_nio', 0)
        pr = res.get('pass_count_ref', 0)
        tot_count_a += c
        tot_pass_a += p
        tot_count_ar += c
        tot_pass_ar += pr
        errs = [e['final_error_m'] for e in res.get('evaluations_nio', [])]
        errs_r = [e['final_error_m'] for e in res.get('evaluations_ref', [])]
        all_errs_a.extend(errs)
        all_errs_ar.extend(errs_r)
        mean_e = np.mean(errs) if errs else 0.0
        min_e = np.min(errs) if errs else 0.0
        max_e = np.max(errs) if errs else 0.0
        p_pct = (p / c * 100.0) if c > 0 else 0.0
        print(f"  {s:4s} | Qual: {c:2d} | C7 Pass: {p:2d} ({p_pct:5.1f}%) | Mean Err: {mean_e:6.2f}m | Min: {min_e:5.2f}m | Max: {max_e:6.2f}m")
    pct_a = (tot_pass_a / tot_count_a * 100.0) if tot_count_a > 0 else 0.0
    print(f"  --> SCENARIO A (C7 Pipeline): {tot_pass_a}/{tot_count_a} passed ({pct_a:.2f}%) | Global Mean Err: {np.mean(all_errs_a):.2f}m" if all_errs_a else "  --> No qualifying Scenario A windows.")

    print("\n--- Scenario A with Reference Speed (Wheel Odometer / Perfect Speed Bound) ---")
    for s in sessions:
        res = scen_a.get(s, {})
        c = res.get('qualifying_count', 0)
        pr = res.get('pass_count_ref', 0)
        errs_r = [e['final_error_m'] for e in res.get('evaluations_ref', [])]
        p_pct = (pr / c * 100.0) if c > 0 else 0.0
        mean_er = np.mean(errs_r) if errs_r else 0.0
        min_er = np.min(errs_r) if errs_r else 0.0
        max_er = np.max(errs_r) if errs_r else 0.0
        print(f"  {s:4s} | Qual: {c:2d} | Ref Pass: {pr:2d} ({p_pct:5.1f}%) | Mean Err: {mean_er:6.2f}m | Min: {min_er:5.2f}m | Max: {max_er:6.2f}m")
    pct_ar = (tot_pass_ar / tot_count_ar * 100.0) if tot_count_ar > 0 else 0.0
    print(f"  --> REF SPEED TOTAL: {tot_pass_ar}/{tot_count_ar} passed ({pct_ar:.2f}%) | Global Mean Err: {np.mean(all_errs_ar):.2f}m")

    print("\n" + "=" * 80)
    print("4. SIH SCENARIO B EVALUATION (C7 Pipeline) (Complete Outage ~60s, ~1km, Pass <= 100m)")
    print("=" * 80)
    scen_b = d.get('scenario_b', {})
    tot_pass_b, tot_count_b = 0, 0
    all_errs_b = []
    all_drifts_b = []
    for s in sessions:
        res = scen_b.get(s, {})
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
    print(f"  --> SCENARIO B TOTAL: {tot_pass_b}/{tot_count_b} passed ({pct_b:.2f}%) | Global Mean Err: {np.mean(all_errs_b):.2f}m | Global Mean Drift: {np.mean(all_drifts_b):.2f}%" if all_errs_b else "  --> No qualifying Scenario B windows.")

if __name__ == '__main__':
    main()
