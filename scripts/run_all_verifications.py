"""
scripts/run_all_verifications.py
Executes the verification suite across all navigation pipeline phases.
"""
import sys
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

VERIFICATION_SCRIPTS = [
    "scripts/verify_phase1.py",
    "scripts/verify_phase2.py",
    "scripts/verify_phase4.py",
    "scripts/verify_phase5.py",
    "scripts/verify_phase6.py",
    "scripts/verify_phase7.py",
    "scripts/verify_phase8.py",
    "scripts/verify_phase9.py",
]

def main():
    print("=" * 75)
    print("  NAV-SHIELD FULL VERIFICATION SUITE")
    print("=" * 75)
    
    all_passed = True
    for script in VERIFICATION_SCRIPTS:
        script_path = PROJECT_ROOT / script
        if not script_path.exists():
            continue
        print(f"\n>>> Running: {script} ...")
        res = subprocess.run([sys.executable, str(script_path)], cwd=str(PROJECT_ROOT))
        if res.returncode != 0:
            print(f"FAILED: {script} (exit code {res.returncode})")
            all_passed = False
        else:
            print(f"PASSED: {script} [OK]")

    print("\n" + "=" * 75)
    if all_passed:
        print("  ALL VERIFICATION PHASES PASSED (100% COMPLIANCE)")
    else:
        print("  SOME VERIFICATIONS FAILED")
    print("=" * 75)
    return 0 if all_passed else 1

if __name__ == '__main__':
    sys.exit(main())
