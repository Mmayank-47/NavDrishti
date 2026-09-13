#!/usr/bin/env python3
"""
scripts/run_notebooks.py
─────────────────────────────────────────────────────────────────────────────
Executes all cells of a specified notebook sequentially in-process,
supporting both local and remote environments.
─────────────────────────────────────────────────────────────────────────────
"""

import sys
import os
import io
import json
import traceback
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

# Ensure UTF-8 output encoding on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

class TeeOutput:
    """Tee output to both real stream and an in-memory buffer."""
    def __init__(self, real_stream, buffer):
        self.real_stream = real_stream
        self.buffer = buffer

    def write(self, s):
        self.real_stream.write(s)
        self.buffer.write(s)

    def flush(self):
        self.real_stream.flush()
        self.buffer.flush()

    def fileno(self):
        return self.real_stream.fileno()

def run_notebook(nb_path, save_in_place=True):
    p = Path(nb_path).resolve()
    print(f"\n============================================================")
    print(f"  Executing Notebook: {p.name}")
    print(f"============================================================")
    
    with open(p, 'r', encoding='utf-8') as f:
        nb = json.load(f)

    # Execution namespace
    ns = {
        '__file__': str(p),
        '__name__': '__main__',
    }

    code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
    print(f"Total code cells to execute: {len(code_cells)}")

    exec_count = 0
    for idx, cell in enumerate(nb.get('cells', []), 1):
        if cell.get('cell_type') != 'code':
            continue
        
        code = ''.join(cell.get('source', []))
        if not code.strip():
            cell['execution_count'] = None
            cell['outputs'] = []
            continue

        exec_count += 1
        cell['execution_count'] = exec_count
        cell['outputs'] = []

        stdout_buf = io.StringIO()
        stderr_buf = io.StringIO()

        tee_out = TeeOutput(sys.stdout, stdout_buf)
        tee_err = TeeOutput(sys.stderr, stderr_buf)

        error_occurred = False
        with redirect_stdout(tee_out), redirect_stderr(tee_err):
            try:
                exec(code, ns)
            except Exception as e:
                error_occurred = True
                err_msg = traceback.format_exc()
                print(f"\n[ERROR] in cell {exec_count}: {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
                cell['outputs'].append({
                    'output_type': 'error',
                    'ename': type(e).__name__,
                    'evalue': str(e),
                    'traceback': err_msg.splitlines(keepends=True)
                })

        out_text = stdout_buf.getvalue()
        if out_text:
            cell['outputs'].insert(0, {
                'output_type': 'stream',
                'name': 'stdout',
                'text': out_text.splitlines(keepends=True)
            })

        err_text = stderr_buf.getvalue()
        if err_text and not error_occurred:
            cell['outputs'].append({
                'output_type': 'stream',
                'name': 'stderr',
                'text': err_text.splitlines(keepends=True)
            })

        if error_occurred:
            if save_in_place:
                with open(p, 'w', encoding='utf-8') as f:
                    json.dump(nb, f, indent=1, ensure_ascii=False)
            sys.exit(1)

    if save_in_place:
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(nb, f, indent=1, ensure_ascii=False)
        print(f"Persisted execution outputs back to {p.name}")

    print(f"\n[SUCCESS] Completed notebook: {p.name} successfully!")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python scripts/run_notebooks.py <notebook_path>")
        sys.exit(1)
    run_notebook(sys.argv[1])

