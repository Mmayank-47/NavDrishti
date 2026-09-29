"""Evaluator-only fixed-grid window eligibility report."""
from collections import Counter
from .replay import initialize_before, replay_outage
import math
def report(session,start_s,end_s,window_s,step_s,*,mode='constant_velocity',phone_to_vehicle=None,history_min_span_s=1.,history_max_span_s=5.,max_extrapolation_s=2.,max_gyro_age_s=None):
    if not all(math.isfinite(x) for x in (start_s,end_s,window_s,step_s)) or window_s<=0 or step_s<=0 or end_s<=start_s: raise ValueError('invalid eligibility grid')
    rows=[]; t=start_s
    while t+window_s<=end_s:
        try:
            init=initialize_before(session,t,history_min_span_s,history_max_span_s,max_extrapolation_s)
            r=replay_outage(session,init,t,t+window_s,mode,phone_to_vehicle,max_gyro_age_s)
            eligible=r.status=='OK' and r.endpoint_error_m is not None and math.isfinite(r.endpoint_error_m)
            rows.append({'t0_s':t,'t1_s':t+window_s,'eligible':eligible,'reason':None if eligible else r.reason,'replay_status':r.status,'endpoint_error_m':r.endpoint_error_m,'initial_interval_s':[init.interval_start_s,init.interval_end_s]})
        except ValueError as e: rows.append({'t0_s':t,'t1_s':t+window_s,'eligible':False,'reason':str(e)})
        t+=step_s
    return {'status':'OK' if any(r['eligible'] for r in rows) else 'NOT_EVALUABLE','windows':rows,'counts':dict(Counter('eligible' if r['eligible'] else r['reason'] for r in rows)),'coordinate_change_interval_is_proxy_not_fix_freshness':True}
