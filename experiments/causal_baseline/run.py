"""Phone-only diagnostic CLI. Runtime faults are exported, then exit nonzero."""
import argparse, csv, json, traceback
from pathlib import Path
import numpy as np
from .phone_csv import load_phone_csv
from .replay import initialize_before, replay_outage
from .export import safe_export
from .provenance import manifest
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--config',required=True); ap.add_argument('--output',required=True); a=ap.parse_args(); out=Path(a.output); out.mkdir(parents=True,exist_ok=True)
    for name in ('trajectory.csv','status.json','manifest.json','diagnostic.log'): (out/name).unlink(missing_ok=True)
    cfg={}; inputs=[]; loaded=False
    try:
        cfg=json.loads(Path(a.config).read_text()); inputs=[Path(a.config)]
        if 'phone_csv' not in cfg: raise ValueError('phone_csv is required; legacy vehicle-sensitive loader is not used')
        phone=Path(cfg['phone_csv']); inputs.append(phone); s=load_phone_csv(phone,cfg.get('timestamp_gap_s',2.)); loaded=True
        initial=initialize_before(s,float(cfg['t0_s']),cfg.get('history_min_span_s',1.),cfg.get('history_max_span_s',5.),cfg.get('max_extrapolation_s',2.))
        r=replay_outage(s,initial,float(cfg['t0_s']),float(cfg['t1_s']),cfg['mode'],np.asarray(cfg['phone_to_vehicle_rotation']) if cfg.get('mode')=='gyro_heading_speed' and cfg.get('phone_to_vehicle_rotation') is not None else None,cfg.get('max_gyro_age_s'))
        with (out/'trajectory.csv').open('w',newline='') as f:
            w=csv.writer(f); w.writerow(['time_s','east_m','north_m']); w.writerows(r.trajectory)
        status={'status':r.status,'reason':r.reason,'endpoint_error_m':r.endpoint_error_m,'session':cfg.get('session'),'mode':cfg['mode'],'initial_source_time_s':initial.source_time_s,'initial_interval_s':[initial.interval_start_s,initial.interval_end_s],'initial_source_type':initial.source_type,'metrics_computable':r.endpoint_error_m is not None}; code=0
    except ValueError as e:
        status={'status':'NOT_EVALUABLE' if loaded else 'RUNTIME_ERROR','reason':str(e),'metrics_computable':False}; (out/'diagnostic.log').write_text(traceback.format_exc()); code=0 if loaded else 2
    except (KeyError,FileNotFoundError,UnicodeDecodeError) as e:
        status={'status':'RUNTIME_ERROR','reason':str(e),'metrics_computable':False}; (out/'diagnostic.log').write_text(traceback.format_exc()); code=2
    except Exception as e:
        status={'status':'RUNTIME_ERROR','reason':f'unexpected: {e}','metrics_computable':False}; (out/'diagnostic.log').write_text(traceback.format_exc()); code=3
    try: (out/'manifest.json').write_text(json.dumps(manifest(Path.cwd(),cfg,inputs),indent=2))
    except Exception as e: status['export_warning']=f'manifest failure: {e}'
    safe_export(out,status); return code
if __name__=='__main__': raise SystemExit(main())
