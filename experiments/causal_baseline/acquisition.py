"""Offline-first, content-verified IO-VNBD phone-file resolver."""
import hashlib, json
from pathlib import Path
ROOT=Path(__file__).parent
def _why(p):
    if not p.exists(): return 'absent'
    b=p.read_bytes()
    if not b: return 'empty'
    if b.startswith(b'version https://git-lfs.github.com'): return 'lfs_pointer'
    if b.lstrip().lower().startswith((b'<html',b'<!doctype html')): return 'html_error'
    return None
def resolve(session, *, local_dir=None, drive_dir=None, archive_dir=None, explicit_file=None, allow_unverified=False):
    expected=json.loads((ROOT/'expected_hashes.json').read_text())['files'].get(f'S-{session}.csv')
    sources=(('explicit_file',Path(explicit_file).parent) if explicit_file else None,('local',local_dir),('drive',drive_dir),('archive',archive_dir))
    for item in sources:
        if item is None: continue
        source,d=item
        if d:
            p=Path(explicit_file) if explicit_file else Path(d)/f'S-{session}.csv'; reason=_why(p)
            if reason: raise ValueError(reason) if explicit_file else FileNotFoundError(reason)
            size=p.stat().st_size; digest=hashlib.sha256(p.read_bytes()).hexdigest()
            verified=bool(expected and expected['size']==size and expected['sha256']==digest)
            if expected and not verified: raise ValueError('wrong_hash_or_truncated')
            if not verified and not allow_unverified: raise ValueError('unverified_file')
            return {'path':str(p),'source':source,'verified':verified,'sha256':digest,'size':size,'expected':expected}
    raise FileNotFoundError('dataset file absent from supplied local/drive/archive sources; network LFS retrieval is unavailable')
