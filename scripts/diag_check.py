import os, sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.preprocessing.data_loader import IOVNBDLoader

def main():
    loader = IOVNBDLoader()
    test_sessions = loader.get_session_names('test')
    print(f"Discovered test sessions ({len(test_sessions)}): {test_sessions}")
    
    for s in test_sessions:
        info = loader.sessions[s]
        sess = loader.load_session(s, preprocess_imu=False)
        N = len(sess['enu_coords'])
        dist = float(sess['enu_coords'][-1, 0]**2 + sess['enu_coords'][-1, 1]**2)**0.5
        v_spd = sess['vehicle']['speed_mps']
        if v_spd is None:
            v_spd = sess['gps']['speed_mps']
        mean_v = float(v_spd.mean()) if v_spd is not None else 0.0
        max_v = float(v_spd.max()) if v_spd is not None else 0.0
        print(f"Session {s:5s} | Points: {N:6d} ({N*0.1:6.1f}s) | Mean Speed: {mean_v:5.2f} m/s | Max Speed: {max_v:5.2f} m/s")

if __name__ == '__main__':
    main()
