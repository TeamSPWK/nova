#!/usr/bin/env python3
"""
build-status.py — Plan frontmatter + git log → StatusData JSON v1.0

Contract:
- Input:  docs/designs/status-dashboard.md §4 (Plan frontmatter v1.0)
- Output: docs/designs/status-dashboard.md §5 (StatusData JSON v1.0)
- Drift:  docs/designs/status-dashboard.md §6 (5-bucket classification)
- Degradation: docs/designs/status-dashboard.md §8 (graceful)

이 스크립트는 build-status.sh를 통해 호출된다. 직접 실행도 가능.
"""
import argparse
import datetime as dt
import glob as glob_mod
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML required. Install: pip3 install PyYAML", file=sys.stderr)
    sys.exit(3)

SCHEMA_URL = "https://nova/status-data/v1.0"
VERSION = "1.0"
ALLOWED_STATUS = {"done", "in_progress", "pending", "blocked"}

ROADMAP_CANDIDATES = ["ROADMAP.md", "docs/ROADMAP.md", "docs/roadmap.md"]
DEFAULT_STALE_THRESHOLD_DAYS = 7

# ---------------------------------------------------------------- args
def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--plan", help="Plan markdown file path (for goals/groups/drift)")
    p.add_argument("--roadmap", help="ROADMAP.md path (default: auto-discover)")
    p.add_argument("--since", default="7 days ago", help='git log --since')
    p.add_argument("--stale-threshold", type=int, default=DEFAULT_STALE_THRESHOLD_DAYS,
                   help="ROADMAP stale 임계 (일). Default 7.")
    p.add_argument("--no-roadmap", action="store_true",
                   help="ROADMAP 발견 시도 X — Phase 1 동작 강제")
    p.add_argument("--out", help="Output JSON path (default stdout)")
    p.add_argument("--quiet", action="store_true")
    return p.parse_args()

# ---------------------------------------------------------------- plan discovery
def find_default_plan():
    """docs/plans/*.md 중 첫 frontmatter 발견 파일."""
    for path in sorted(glob_mod.glob("docs/plans/*.md")):
        try:
            fm, _ = extract_frontmatter(path)
            if fm:
                return path
        except Exception:
            continue
    return None

# ---------------------------------------------------------------- frontmatter
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)

def extract_frontmatter(path):
    """Return (dict|None, body). dict={} if no frontmatter. None if parse error."""
    text = Path(path).read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(text)
    if not m:
        return ({}, text)
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return (None, text)
    return (fm, text[m.end():])

# ---------------------------------------------------------------- schema validation (§4.3)
def validate(fm):
    """Return (normalized_data, warnings). Never crash on bad input."""
    w = []
    if not isinstance(fm, dict):
        return ({}, ["frontmatter가 dict 형식이 아닙니다."])

    d = {
        "plan_id": fm.get("plan_id"),
        "title": fm.get("title"),
        "current_phase": fm.get("current_phase"),
        "current_sprint": fm.get("current_sprint"),
        "phases": [], "sprints": {}, "groups": [], "goals": [],
    }
    if not d["plan_id"]:
        w.append("plan_id 누락 — minimal mode 진행.")

    # phases
    seen = set()
    for ph in (fm.get("phases") or []):
        if not isinstance(ph, dict): continue
        pid = ph.get("id")
        if not pid:
            w.append("phases[]에 id 없는 항목 — skip.")
            continue
        if pid in seen:
            w.append(f"phases id 중복 ({pid}) — 첫 항목만 사용.")
            continue
        seen.add(pid)
        status = ph.get("status", "pending")
        if status not in ALLOWED_STATUS:
            w.append(f"phases[{pid}].status 비정상 ({status}) → pending.")
            status = "pending"
        d["phases"].append({
            "id": pid,
            "title": str(ph.get("title") or "").strip(),
            "status": status,
            "summary": str(ph.get("summary") or ""),
        })

    # sprints (map of phase_id → array)
    sprints = fm.get("sprints") or {}
    if isinstance(sprints, dict):
        for phase_id, sp_list in sprints.items():
            if not isinstance(sp_list, list): continue
            normalized = []
            for s in sp_list:
                if not isinstance(s, dict): continue
                sid = s.get("id")
                if not sid: continue
                status = s.get("status", "pending")
                if status not in ALLOWED_STATUS:
                    w.append(f"sprints[{phase_id}][{sid}].status 비정상 ({status}) → pending.")
                    status = "pending"
                normalized.append({"id": sid, "title": s.get("title", sid), "status": status})
            d["sprints"][phase_id] = normalized

    # groups
    seen_g = set()
    for g in (fm.get("groups") or []):
        if not isinstance(g, dict): continue
        gid = g.get("id")
        if not gid: continue
        if gid in seen_g:
            w.append(f"groups id 중복 ({gid}) — 첫 항목만 사용.")
            continue
        seen_g.add(gid)
        target = g.get("target", 0)
        paths = g.get("paths") or []
        if not isinstance(target, int) or target <= 0:
            w.append(f"groups[{gid}].target ≤ 0 — 표시 X.")
            continue
        if not isinstance(paths, list) or not paths:
            w.append(f"groups[{gid}].paths 비어있음 — 표시 X.")
            continue
        d["groups"].append({
            "id": gid,
            "title": g.get("title", gid),
            "target": target,
            "paths": [str(p) for p in paths],
            "count_strategy": g.get("count_strategy", "files"),
        })

    # goals
    seen_goal = set()
    for go in (fm.get("goals") or []):
        if not isinstance(go, dict): continue
        gid = go.get("id")
        if not gid: continue
        if gid in seen_goal: continue
        seen_goal.add(gid)
        status = go.get("status", "pending")
        if status not in ALLOWED_STATUS:
            status = "pending"
        d["goals"].append({
            "id": gid,
            "title": go.get("title", gid),
            "paths": go.get("paths") or [],
            "status": status,
            "needs_approval": bool(go.get("needs_approval", False)),
        })

    # cursor: in_progress phase 자동 선택
    if not d["current_phase"]:
        for ph in d["phases"]:
            if ph["status"] == "in_progress":
                d["current_phase"] = ph["id"]
                break

    return (d, w)

# ---------------------------------------------------------------- glob matching (fast-glob style)
_GLOB_CACHE = {}

def glob_to_regex(pattern):
    parts = []
    i = 0
    while i < len(pattern):
        if pattern[i:i+3] == "**/":
            parts.append("(?:.*/)?")
            i += 3
        elif pattern[i:i+2] == "**":
            parts.append(".*?")
            i += 2
        elif pattern[i] == "*":
            parts.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            parts.append("[^/]")
            i += 1
        elif pattern[i] in ".+(){}|^$\\":
            parts.append(re.escape(pattern[i]))
            i += 1
        else:
            parts.append(pattern[i])
            i += 1
    return "^" + "".join(parts) + "$"

def match_globs(path, patterns):
    """Negation('!prefix') 지원. last-match-wins."""
    matched = False
    for p in patterns:
        is_neg = p.startswith("!")
        clean = p[1:] if is_neg else p
        if clean not in _GLOB_CACHE:
            _GLOB_CACHE[clean] = re.compile(glob_to_regex(clean))
        if _GLOB_CACHE[clean].match(path):
            matched = not is_neg
    return matched

# ---------------------------------------------------------------- groups count (filesystem)
def count_groups(groups, repo_root):
    enriched, total_done, total_target = [], 0, 0
    for g in groups:
        files = set()
        for p in g["paths"]:
            if p.startswith("!"): continue
            pattern = os.path.join(repo_root, p)
            for fs_path in glob_mod.glob(pattern, recursive=True):
                if not os.path.isfile(fs_path): continue
                rel = os.path.relpath(fs_path, repo_root)
                if match_globs(rel, g["paths"]):
                    files.add(rel)
        count = len(files)
        target = g["target"]
        percent = min(int(round(count / target * 100)), 100) if target else 0
        enriched.append({
            "id": g["id"], "title": g["title"],
            "target": target, "count": count, "percent": percent,
        })
        total_done += min(count, target)
        total_target += target
    return enriched, {"done": total_done, "total": total_target}

# ---------------------------------------------------------------- phase progress (§5.4)
def compute_phase_progress(phases, sprints):
    for ph in phases:
        s = ph["status"]
        if s == "done":          ph["progress"] = 100
        elif s == "pending":     ph["progress"] = 0
        elif s == "blocked":     ph["progress"] = 50
        elif s == "in_progress":
            sp = sprints.get(ph["id"]) or []
            if sp:
                done_n = sum(1 for x in sp if x["status"] == "done")
                ph["progress"] = int(round(done_n / len(sp) * 100))
            else:
                ph["progress"] = 0
    return phases

# ---------------------------------------------------------------- git log
COMMIT, BODY, FILES = "===COMMIT===", "===BODY===", "===FILES==="

def parse_git_log(since, repo_root):
    fmt = f"{COMMIT}%n%H%n%s%n{BODY}%n%b%n{FILES}"
    try:
        out = subprocess.check_output(
            ["git", "log", f"--since={since}", "--no-merges",
             "--name-only", f"--pretty=format:{fmt}"],
            cwd=repo_root, text=True, stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return []
    commits = []
    for chunk in out.split(COMMIT + "\n"):
        chunk = chunk.strip()
        if not chunk: continue
        m = re.match(rf"^([a-f0-9]+)\n(.*?)\n{BODY}\n(.*?)\n{FILES}(.*)$", chunk, re.S)
        if not m: continue
        sha, subject, body, files_raw = m.groups()
        files = [f for f in files_raw.strip().split("\n") if f]
        commits.append({"sha": sha[:7], "subject": subject, "body": body, "files": files})
    return commits

# ---------------------------------------------------------------- drift classification (§6.3)
PLAN_RE = re.compile(r"^Plan:\s*([A-Za-z0-9_\-]+)\s*$", re.M)
GOAL_RE = re.compile(r"^Goal:\s*([A-Za-z0-9_\-]+)\s*$", re.M)
NON_FUNCTIONAL = [
    re.compile(r"(^|/)tests?/"),
    re.compile(r"\.(test|spec)\.[jt]sx?$"),
    re.compile(r"(^|/)docs?/"),
    re.compile(r"\.md$"),
    re.compile(r"^README"),
    re.compile(r"\.gitignore$"),
    re.compile(r"(^|/)\.github/"),
]

def is_non_functional(path):
    return any(p.search(path) for p in NON_FUNCTIONAL)

def classify(commit, plan_id, goals):
    text = (commit.get("body") or "") + "\n" + (commit.get("subject") or "")
    pm = PLAN_RE.search(text)
    plan_tag = pm.group(1) if pm else None
    gm = GOAL_RE.search(text)
    goal_tag = gm.group(1) if gm else None

    if not plan_tag or plan_tag != plan_id:
        return "tag_missing", plan_tag, goal_tag

    goal_ids = {g["id"] for g in goals}
    if goal_tag and goal_tag not in goal_ids:
        return "conflict", plan_tag, goal_tag

    files = commit.get("files") or []
    matched = [g["id"] for g in goals if any(match_globs(f, g.get("paths") or []) for f in files)]

    if goal_tag is None:
        return ("aligned" if matched else "unspecced"), plan_tag, None

    if not matched:
        if files and all(is_non_functional(f) for f in files):
            return "unverifiable", plan_tag, goal_tag
        return "drifted", plan_tag, goal_tag

    if goal_tag in matched:
        return "aligned", plan_tag, goal_tag
    return "drifted", plan_tag, goal_tag

def compute_drift(commits, plan_id, goals, since_label):
    buckets = {"aligned": 0, "drifted": 0, "unspecced": 0,
               "unverifiable": 0, "conflict": 0, "tag_missing": 0}
    drifted_commits = []
    for c in commits:
        b, _pt, gt = classify(c, plan_id, goals)
        buckets[b] += 1
        if b == "drifted":
            drifted_commits.append({
                "sha": c["sha"], "subject": c["subject"],
                "goal_declared": gt, "paths_actual": c["files"][:5],
            })
    total = len(commits)
    countable = total - buckets["tag_missing"]
    drift_n = buckets["drifted"] + buckets["conflict"]
    if countable > 0:
        pct = int(round(drift_n / countable * 100))
        verdict = "green" if pct < 30 else ("amber" if pct < 70 else "red")
    else:
        pct, verdict = 0, "unknown"
    return {
        "since": since_label, "commits_total": total,
        "buckets": buckets, "drift_percent": pct, "verdict": verdict,
        "drifted_commits": drifted_commits,
    }

def resolve_since_label(since):
    m = re.match(r"^(\d+)\s+days?\s+ago$", since.strip())
    if m:
        d = dt.datetime.now() - dt.timedelta(days=int(m.group(1)))
        return d.strftime("%Y-%m-%d")
    return since

# ---------------------------------------------------------------- Phase 2: ROADMAP discovery
def find_roadmap(repo_root, override=None):
    """ROADMAP.md 3 후보 경로 시도. Return path or None."""
    if override:
        p = Path(override)
        return str(p) if p.exists() else None
    for cand in ROADMAP_CANDIDATES:
        full = os.path.join(repo_root, cand)
        if os.path.exists(full):
            return full
    return None

# ---------------------------------------------------------------- Phase 2: ROADMAP 검증 (§12.3)
def validate_roadmap(fm, path):
    """ROADMAP frontmatter 검증. Return (normalized|None, warnings)."""
    w = []
    if not isinstance(fm, dict):
        return (None, ["ROADMAP frontmatter dict 아님 — Phase 1 fallback."])
    if not fm.get("roadmap_id"):
        return (None, ["ROADMAP roadmap_id 누락 — Phase 1 fallback."])

    rm = {
        "roadmap_id": fm["roadmap_id"],
        "title": fm.get("title", fm["roadmap_id"]),
        "current_phase": fm.get("current_phase"),
        "phases": [],
        "external_pending": [],
        "links": fm.get("links") or [],
        "path": path,
    }

    seen = set()
    for p in (fm.get("phases") or []):
        if not isinstance(p, dict): continue
        pid = p.get("id")
        if not pid:
            w.append("ROADMAP phases[]에 id 없는 항목 — skip"); continue
        if pid in seen:
            w.append(f"ROADMAP phases id 중복 ({pid}) — 첫 항목만 사용"); continue
        seen.add(pid)
        status = p.get("status", "pending")
        if status not in ALLOWED_STATUS:
            w.append(f"ROADMAP phases[{pid}].status 비정상 ({status}) → pending"); status = "pending"
        rm["phases"].append({
            "id": pid, "title": str(p.get("title") or "").strip(), "status": status,
            "summary": str(p.get("summary") or ""),
            "range_months": p.get("range_months"),
        })

    if not rm["current_phase"]:
        for p in rm["phases"]:
            if p["status"] == "in_progress":
                rm["current_phase"] = p["id"]; break
        if not rm["current_phase"]:
            w.append("current_phase 미선언 + in_progress phase 없음 — Phase bar 첫 항목 시각만.")

    phase_ids = {p["id"] for p in rm["phases"]}
    for ext in (fm.get("external_pending") or []):
        if not isinstance(ext, dict): continue
        eid = ext.get("id") or ext.get("title", "")
        ext_phase = ext.get("phase")
        if ext_phase and ext_phase not in phase_ids:
            w.append(f"external_pending[{eid}].phase={ext_phase} not in ROADMAP — phase=null")
            ext_phase = None
        rm["external_pending"].append({
            "id": eid,
            "title": ext.get("title", eid),
            "blocker": ext.get("blocker", "") or "",
            "activation": ext.get("activation", "") or "",
            "phase": ext_phase,
        })

    return (rm, w)

# ---------------------------------------------------------------- Phase 2: 멀티 plan 스캔 (§13)
def scan_plans(repo_root):
    """docs/plans/*.md frontmatter 스캔. parent_phase 있는 것만 통합 대상."""
    plans = []
    plan_glob = os.path.join(repo_root, "docs/plans/*.md")
    for path in sorted(glob_mod.glob(plan_glob)):
        try:
            fm, _ = extract_frontmatter(path)
        except Exception:
            continue
        if not fm or not isinstance(fm, dict):
            continue
        if not fm.get("parent_phase"):
            continue
        plan_id = fm.get("plan_id") or os.path.basename(path).replace(".md", "")
        plans.append({
            "plan_id": plan_id,
            "parent_phase": fm.get("parent_phase"),
            "sprint_id": fm.get("sprint_id") or plan_id,
            "title": fm.get("title", plan_id),
            "status": fm.get("status", "pending"),
            "path": path,
        })
    return plans

# ---------------------------------------------------------------- Phase 2: 통합 (§13.2)
def integrate_roadmap_plans(roadmap, plans):
    """§13.2 algorithm. Return (sprints dict, warnings)."""
    sprints = {p["id"]: [] for p in roadmap["phases"]}
    seen_sprint_ids = set()
    warnings = []
    phase_ids = {p["id"] for p in roadmap["phases"]}

    for plan in plans:
        phase_id = plan["parent_phase"]
        if phase_id not in phase_ids:
            warnings.append(
                f"plan {plan['plan_id']} parent_phase={phase_id} not in ROADMAP — skip")
            continue
        sprint_id = plan["sprint_id"]
        if sprint_id in seen_sprint_ids:
            warnings.append(f"duplicate sprint_id {sprint_id} — first wins")
            continue
        seen_sprint_ids.add(sprint_id)
        status = plan["status"]
        if status not in ALLOWED_STATUS:
            warnings.append(f"plan {plan['plan_id']}.status 비정상 ({status}) → pending")
            status = "pending"
        sprints[phase_id].append({
            "id": sprint_id, "title": plan["title"], "status": status,
        })
    return sprints, warnings

# ---------------------------------------------------------------- Phase 2: stale 검증 (§14)
def check_stale(roadmap_path, repo_root, threshold_days):
    """git log -1 --format=%cI <roadmap>. Return info dict or None."""
    try:
        rel = os.path.relpath(roadmap_path, repo_root)
        out = subprocess.check_output(
            ["git", "log", "-1", "--format=%cI", "--", rel],
            cwd=repo_root, text=True, stderr=subprocess.DEVNULL,
        ).strip()
        if not out:
            return {
                "path": rel, "last_commit": None, "age_days": None,
                "stale": False, "stale_reason": "git history 없음 (uncommitted)",
            }
        last = dt.datetime.fromisoformat(out.replace("Z", "+00:00"))
        age = (dt.datetime.now(last.tzinfo) - last).days
        stale = age > threshold_days
        return {
            "path": rel, "last_commit": out, "age_days": age,
            "stale": stale,
            "stale_reason": (f"commit {age} days ago > threshold {threshold_days}"
                             if stale else None),
        }
    except Exception:
        return None

# ---------------------------------------------------------------- main
def now_iso():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")

def emit(data, out_path):
    s = json.dumps(data, ensure_ascii=False, indent=2)
    if out_path:
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        Path(out_path).write_text(s + "\n", encoding="utf-8")
    else:
        print(s)

def main():
    args = parse_args()
    base = {"$schema": SCHEMA_URL, "version": VERSION, "generated_at": now_iso()}

    try:
        repo_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        repo_root = os.getcwd()

    # ─── Phase 2: ROADMAP 시도 ─────────────────────────────────
    roadmap = None
    roadmap_warnings = []
    stale_info = None

    if not args.no_roadmap:
        roadmap_path = find_roadmap(repo_root, override=args.roadmap)
        if roadmap_path:
            try:
                rm_fm, _ = extract_frontmatter(roadmap_path)
            except Exception:
                rm_fm = None
            if rm_fm:
                roadmap, roadmap_warnings = validate_roadmap(rm_fm, roadmap_path)
                if roadmap:
                    stale_info = check_stale(roadmap_path, repo_root, args.stale_threshold)

    # ─── ROADMAP 통합 모드 ─────────────────────────────────────
    if roadmap:
        plans = scan_plans(repo_root)
        sprints, integ_warnings = integrate_roadmap_plans(roadmap, plans)
        phases = compute_phase_progress(list(roadmap["phases"]), sprints)

        # current_sprint: current_phase의 in_progress sprint 첫 항목
        cur_phase = roadmap["current_phase"]
        cur_sprint = None
        if cur_phase and cur_phase in sprints:
            for s in sprints[cur_phase]:
                if s["status"] == "in_progress":
                    cur_sprint = s["id"]; break

        # --plan 보조 흡수 (groups + goals + drift)
        # ROADMAP 모드: --plan은 명시된 경우만 사용 (자동 발견 X — ROADMAP title 우선)
        plan_path = args.plan
        plan_meta = {
            "plan_id": roadmap["roadmap_id"],
            "title": roadmap["title"],
            "plan_path": "(roadmap)",
        }
        groups, screens_total, goals = [], {"done": 0, "total": 0}, []
        plan_warnings = []
        if plan_path and os.path.exists(plan_path):
            try:
                p_fm, _ = extract_frontmatter(plan_path)
            except Exception:
                p_fm = None
            if p_fm:
                pd, plan_warnings = validate(p_fm)
                # --plan 명시 시 plan title을 헤더로 (ROADMAP title은 덮음)
                if pd.get("plan_id"):
                    plan_meta = {
                        "plan_id": pd["plan_id"],
                        "title": pd.get("title") or pd["plan_id"],
                        "plan_path": plan_path,
                    }
                if pd["groups"]:
                    groups, screens_total = count_groups(pd["groups"], repo_root)
                goals = pd["goals"]

        # drift
        drift = None
        if plan_meta.get("plan_id"):
            commits = parse_git_log(args.since, repo_root)
            drift = compute_drift(commits, plan_meta["plan_id"], goals,
                                  resolve_since_label(args.since))

        result = dict(base)
        result["mode"] = "roadmap"
        result["plan"] = plan_meta
        result["roadmap"] = {
            "roadmap_id": roadmap["roadmap_id"],
            "title": roadmap["title"],
            "path": stale_info["path"] if stale_info else os.path.relpath(roadmap["path"], repo_root),
            **(stale_info or {"stale": False, "stale_reason": None}),
        }
        result["cursor"] = {
            "current_phase": cur_phase,
            "current_sprint": cur_sprint,
        }
        result["phases"] = phases
        result["sprints"] = sprints
        result["groups"] = groups
        result["screens_total"] = screens_total
        result["goals"] = goals
        result["external_pending"] = roadmap["external_pending"]
        result["warnings"] = roadmap_warnings + integ_warnings + plan_warnings
        if drift:
            result["drift"] = drift

        if not args.quiet and result["warnings"]:
            for w in result["warnings"]:
                print(f"WARN: {w}", file=sys.stderr)
        emit(result, args.out)
        return

    # ─── Phase 1 모드 (호환성 100%) ────────────────────────────
    plan_path = args.plan or find_default_plan()

    if not plan_path or not os.path.exists(plan_path):
        emit({**base, "minimal": True, "mode": "phase1",
              "plan": {"plan_id": "(missing)",
                       "title": "Plan 파일을 찾을 수 없습니다.",
                       "plan_path": "(none)"},
              "warnings": ["docs/plans/*.md 발견 실패 + ROADMAP.md도 없음. --plan 인자 지정 필요."]
                          + roadmap_warnings},
             args.out)
        return

    fm, _body = extract_frontmatter(plan_path)
    if fm is None:
        emit({**base, "minimal": True, "mode": "phase1",
              "plan": {"plan_id": "(parse-error)",
                       "title": os.path.basename(plan_path),
                       "plan_path": plan_path},
              "warnings": ["frontmatter YAML 파싱 실패."] + roadmap_warnings},
             args.out)
        return

    data, warnings = validate(fm)
    phases = compute_phase_progress(data["phases"], data["sprints"])
    groups, screens_total = (count_groups(data["groups"], repo_root)
                              if data["groups"] else ([], {"done": 0, "total": 0}))

    minimal = not data["plan_id"]
    result = dict(base)
    result["mode"] = "phase1"

    if minimal:
        result["minimal"] = True
        result["plan"] = {
            "plan_id": "(missing)",
            "title": data.get("title") or os.path.basename(plan_path),
            "plan_path": plan_path,
        }
        result["warnings"] = warnings + roadmap_warnings
    else:
        result["plan"] = {
            "plan_id": data["plan_id"],
            "title": data.get("title") or data["plan_id"],
            "plan_path": plan_path,
        }
        result["cursor"] = {
            "current_phase": data.get("current_phase"),
            "current_sprint": data.get("current_sprint"),
        }
        result["phases"] = phases
        result["sprints"] = data["sprints"]
        result["groups"] = groups
        result["screens_total"] = screens_total
        result["goals"] = data["goals"]
        result["warnings"] = warnings + roadmap_warnings
        commits = parse_git_log(args.since, repo_root)
        result["drift"] = compute_drift(
            commits, data["plan_id"], data["goals"], resolve_since_label(args.since))

    if not args.quiet and result["warnings"]:
        for w in result["warnings"]:
            print(f"WARN: {w}", file=sys.stderr)

    emit(result, args.out)


if __name__ == "__main__":
    main()
