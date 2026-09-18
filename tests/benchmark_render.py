#!/usr/bin/env python3
"""Compare the production TXT renderer with a git baseline (no host probes).

Usage: python3 tests/benchmark_render.py BASE_REVISION [ROWS]
Timing is informational; CI uses deterministic subprocess-count budgets instead.
"""
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

root = Path(__file__).resolve().parent.parent
revision = sys.argv[1] if len(sys.argv) > 1 else "5ccfd36c449ae4c37b60e7db9787bb3c911b4478"
rows = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
if not 1 <= rows <= 100000:
    raise SystemExit("ROWS must be between 1 and 100000")
baseline = subprocess.check_output(
    ["git", "show", f"{revision}:arm_info.sh"], cwd=root, text=True
)
reference = None
for label, source in (("baseline", baseline), ("working", (root / "arm_info.sh").read_text())):
    functions = source[source.index("report_width() {"):source.index("command_description() {")]
    code = functions + '''
REPORT_WIDTH=$(report_width)
for ((i=0;i<ROWS;i++)); do
    print_check_row "Параметр $i" '[INFO]' "Типовое значение ресурса $i"
done
'''
    durations = []
    for _ in range(3):
        start = time.monotonic()
        result = subprocess.run(
            ["bash", "-c", code], capture_output=True, check=True, timeout=120,
            env={**os.environ, "ROWS": str(rows), "COLUMNS": "110", "LC_ALL": "C.utf8"},
        )
        durations.append(time.monotonic() - start)
        if reference is None:
            reference = result.stdout
        elif result.stdout != reference:
            raise SystemExit("FAIL: rendered output differs from baseline")
    print(f"{label}: {rows} rows, median {statistics.median(durations):.3f}s, "
          f"runs {[round(t, 3) for t in durations]}", flush=True)
print("Output matches baseline byte for byte")
