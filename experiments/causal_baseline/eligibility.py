"""Evaluator-only fixed-grid window eligibility report."""
from collections import Counter
from .replay import initialize_before, replay_outage
def report(session,start_s,end_s,window_s,step_s):
    rows=[]; t=start_s
    while t+window_s<=end_s:
        try:
            init=initialize_before(session,t); replay_outage(session,init,t,t+window_s,'constant_velocity'); rows.append({'t0_s':t,'t1_s':t+window_s,'eligible':True,'initial_interval_s':[init.interval_start_s,init.interval_end_s]})
        except ValueError as e: rows.append({'t0_s':t,'t1_s':t+window_s,'eligible':False,'reason':str(e)})
        t+=step_s
    return {'status':'OK' if any(r['eligible'] for r in rows) else 'NOT_EVALUABLE','windows':rows,'counts':dict(Counter('eligible' if r['eligible'] else r['reason'] for r in rows)),'coordinate_change_interval_is_proxy_not_fix_freshness':True}
