"""Create a portable source ZIP without altering the checkout."""
import argparse, shutil, tempfile
from pathlib import Path
def main():
    p = argparse.ArgumentParser(); p.add_argument("--output", required=True); a = p.parse_args()
    root = Path(__file__).resolve().parents[2]; target = Path(a.output).with_suffix("")
    # Include only maintained Python/config inputs needed by the runner, never raw data or .git.
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / "NavDrishti"
        for item in ("experiments", "src", "configs"):
            shutil.copytree(root / item, stage / item, ignore=shutil.ignore_patterns("__pycache__", "*.zip"))
        shutil.make_archive(str(target), "zip", stage)
    print(str(target) + ".zip")
if __name__ == "__main__": main()
