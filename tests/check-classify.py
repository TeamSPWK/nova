#!/usr/bin/env python3
"""Status Dashboard — drift classify() 6-bucket regression guard.
Called from tests/test-scripts.sh (R31o). Exit 0 on PASS, non-0 on FAIL.
Spec: docs/designs/status-dashboard.md §6 (5 drift buckets + tag_missing).
"""
import importlib.util, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("b", os.path.join(ROOT, "scripts/lib/build-status.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

goals = [{"id": "G1", "paths": ["src/auth/**"]}]
cases = [
    ("tag_missing",  {"subject": "fix",  "body": "",                       "files": ["src/auth/x.ts"]}),
    ("tag_missing",  {"subject": "feat", "body": "Plan: other",            "files": ["src/auth/x.ts"]}),
    ("aligned",      {"subject": "feat", "body": "Plan: demo\nGoal: G1",   "files": ["src/auth/x.ts"]}),
    ("aligned",      {"subject": "fix",  "body": "Plan: demo",             "files": ["src/auth/y.ts"]}),
    ("drifted",      {"subject": "feat", "body": "Plan: demo\nGoal: G1",   "files": ["src/payment/x.ts"]}),
    ("unspecced",    {"subject": "feat", "body": "Plan: demo",             "files": ["src/misc/x.ts"]}),
    ("conflict",     {"subject": "feat", "body": "Plan: demo\nGoal: G99",  "files": ["src/auth/x.ts"]}),
    ("unverifiable", {"subject": "docs", "body": "Plan: demo\nGoal: G1",   "files": ["docs/x.md", "README.md"]}),
]

fails = 0
for expected, c in cases:
    c["sha"] = "abc"
    got, _, _ = mod.classify(c, "demo", goals)
    if got != expected:
        print(f"FAIL: expected={expected} got={got} files={c['files']}", file=sys.stderr)
        fails += 1

sys.exit(0 if fails == 0 else 1)
