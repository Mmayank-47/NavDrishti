import json, math
from pathlib import Path
def _clean(x):
    if isinstance(x, float) and not math.isfinite(x): return "NON_FINITE"
    if isinstance(x, dict): return {k:_clean(v) for k,v in x.items()}
    if isinstance(x, (list, tuple)): return [_clean(v) for v in x]
    return x
def safe_export(directory, payload):
    p = Path(directory); p.mkdir(parents=True, exist_ok=True); out = p / "status.json"
    out.write_text(json.dumps(_clean(payload), indent=2, allow_nan=False)); return out
