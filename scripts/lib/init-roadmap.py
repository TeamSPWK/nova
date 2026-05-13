#!/usr/bin/env python3
"""
init-roadmap.py — ROADMAP.md init wizard (3 모드)

Contract: docs/designs/status-dashboard.md §15
- blank: 빈 frontmatter + 본문 placeholder (1초, 외부 의존 0)
- scan:  docs/plans/*.md parent_phase 추출 (5초, 결정론)
- llm:   NOVA-STATE + git log + plans 수집 → .nova/init-input.json (Claude Agent가 후속 처리)

원칙:
- 자동 commit 0건 (§15.7)
- LLM 호출 0회 (메모리 feedback_api_key_optional_principle — Claude Agent subagent 패턴)
- ⚠️ unsure 마커로 추정 항목 명시 (§15.4)
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

ALLOWED_STATUS = {"done", "in_progress", "pending", "blocked"}
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)

# ---------------------------------------------------------------- args
def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True, choices=["blank", "scan", "llm"])
    p.add_argument("--out", default="ROADMAP.md")
    p.add_argument("--force", action="store_true")
    return p.parse_args()

# ---------------------------------------------------------------- common helpers
def today_iso():
    return dt.date.today().isoformat()

def repo_root():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return os.getcwd()

def extract_frontmatter(path):
    try:
        text = Path(path).read_text(encoding="utf-8")
    except Exception:
        return None
    m = FRONTMATTER_RE.match(text)
    if not m: return {}
    try:
        return yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return None

def assert_not_exists(out_path, force):
    if os.path.exists(out_path) and not force:
        print(f"[init-roadmap] {out_path} 이미 존재 — --force 없으면 거부.", file=sys.stderr)
        sys.exit(4)

def emit_file(out_path, content):
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(content, encoding="utf-8")

def commit_guidance(out_path):
    print(f"\n✓ {out_path} 생성 완료.")
    print(f"\n  검토 후 commit:")
    print(f"    git add {out_path}")
    print(f"    git commit -m \"feat: ROADMAP.md initial (status-dashboard SOT)\"")
    print(f"\n  검증:")
    print(f"    ./scripts/build-status.sh --quiet | jq '.roadmap'")

# ---------------------------------------------------------------- mode: blank
BLANK_TEMPLATE = """---
roadmap_id: # ⚠️ unsure — URL-safe slug 입력
title: # ⚠️ unsure — 프로젝트 한 줄 설명
created: {today}
current_phase: # ⚠️ unsure — phases[].id 중 하나
phases:
  - {{id: P1, title: # ⚠️ unsure, status: in_progress, summary: ""}}
external_pending: []
---

# Roadmap

> ROADMAP.md initial — `⚠️ unsure` 마커를 모두 채우세요.
> 가이드: docs/guides/status-dashboard.md
> Spec:  docs/designs/status-dashboard.md §12

## 📍 지금 어디?

(현재 phase 진행 상황 한 단락)

## 🚀 가까운 미래

(다음 phase 또는 sprint)

## 🔓 외부 승인 대기

(blocker가 있는 항목 — frontmatter `external_pending`에도 추가)
"""

def mode_blank(out_path, force):
    assert_not_exists(out_path, force)
    content = BLANK_TEMPLATE.format(today=today_iso())
    emit_file(out_path, content)
    commit_guidance(out_path)

# ---------------------------------------------------------------- mode: scan
def scan_plans(root):
    """docs/plans/*.md 중 parent_phase 있는 plan."""
    plans = []
    for path in sorted(glob_mod.glob(os.path.join(root, "docs/plans/*.md"))):
        fm = extract_frontmatter(path)
        if not fm or not isinstance(fm, dict): continue
        if not fm.get("parent_phase"): continue
        plan_id = fm.get("plan_id") or os.path.basename(path).replace(".md", "")
        status = fm.get("status", "pending")
        if status not in ALLOWED_STATUS:
            status = "pending"
        plans.append({
            "plan_id": plan_id,
            "parent_phase": fm["parent_phase"],
            "sprint_id": fm.get("sprint_id") or plan_id,
            "title": fm.get("title", plan_id),
            "status": status,
        })
    return plans

def mode_scan(out_path, force):
    assert_not_exists(out_path, force)
    root = repo_root()
    plans = scan_plans(root)
    if not plans:
        print("[init-roadmap] docs/plans/*.md 중 parent_phase 있는 plan 0건.", file=sys.stderr)
        print("  scan 모드는 frontmatter에 parent_phase 명시된 plan이 필요합니다.", file=sys.stderr)
        print("  대안: --blank (빈 템플릿) 또는 --llm (LLM 초안)", file=sys.stderr)
        sys.exit(5)

    # parent_phase 별 분류
    phase_map = {}
    for p in plans:
        phase_map.setdefault(p["parent_phase"], []).append(p)

    phases = []
    for phase_id, items in phase_map.items():
        has_in_progress = any(it["status"] == "in_progress" for it in items)
        all_done = all(it["status"] == "done" for it in items)
        if all_done:
            status = "done"
        elif has_in_progress:
            status = "in_progress"
        else:
            status = "pending"
        phases.append({
            "id": phase_id,
            "title": f"{phase_id} — ⚠️ unsure: title을 직접 채우세요",
            "status": status,
            "summary": f"sprints {len(items)}개 ({', '.join(it['sprint_id'] for it in items[:4])}{'...' if len(items)>4 else ''})",
        })

    # current_phase: 첫 in_progress
    current = next((p["id"] for p in phases if p["status"] == "in_progress"), phases[0]["id"])

    fm = {
        "roadmap_id": "# ⚠️ unsure — slug",
        "title": "# ⚠️ unsure — title",
        "created": today_iso(),
        "current_phase": current,
        "phases": phases,
        "external_pending": [],
    }

    yaml_str = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)
    content = (
        "---\n" + yaml_str + "---\n\n"
        f"# Roadmap (scan auto-draft from docs/plans/)\n\n"
        f"> Auto-generated by `init-roadmap.sh --scan` ({today_iso()}).\n"
        f"> `⚠️ unsure` 항목은 직접 채우세요.\n"
        f"> 감지된 plan: {len(plans)}개 / phases: {len(phases)}개.\n\n"
        f"## 📍 지금 어디?\n\n(현재 phase 진행 상황 한 단락)\n\n"
        f"## 🔓 외부 승인 대기\n\n(있다면 frontmatter `external_pending`에도 추가)\n"
    )
    emit_file(out_path, content)
    print(f"\n✓ scan 완료: {len(plans)} plan → {len(phases)} phases.")
    commit_guidance(out_path)

# ---------------------------------------------------------------- mode: llm (자료 수집)
def collect_git_log(repo_root_path, since="30 days ago", limit=50):
    try:
        out = subprocess.check_output(
            ["git", "log", f"--since={since}", "--oneline", f"-n{limit}"],
            cwd=repo_root_path, text=True, stderr=subprocess.DEVNULL,
        )
        return out.strip().splitlines()
    except Exception:
        return []

def collect_nova_state(repo_root_path):
    for cand in ("NOVA-STATE.md", "docs/NOVA-STATE.md"):
        p = os.path.join(repo_root_path, cand)
        if os.path.exists(p):
            try:
                return Path(p).read_text(encoding="utf-8")[:8000]  # cap to 8KB
            except Exception:
                pass
    return None

def collect_existing_docs(repo_root_path):
    """레거시 docs 노이즈 방지 위해 archived/ 제외 (§15.2 P2-R2)."""
    docs = []
    for path in sorted(glob_mod.glob(os.path.join(repo_root_path, "docs/*.md")))[:20]:
        rel = os.path.relpath(path, repo_root_path)
        if "archived" in rel or ".archive" in rel or "deprecated" in rel:
            continue
        docs.append(rel)
    return docs

LLM_PROMPT_TEMPLATE = """\
You are creating a ROADMAP.md draft for a software project.

# Contract
- frontmatter v1.0 schema: docs/designs/status-dashboard.md §12
- Required fields: roadmap_id, title, current_phase, phases[]
- Optional: external_pending[], links[]

# Inputs
(see init-input.json — NOVA-STATE.md + git log 30d + plans frontmatter + non-archived docs list)

# ⚠️ unsure rule (§15.4)
- If you cannot infer a field with high confidence, leave the value empty and add `# ⚠️ unsure: <reason>` comment.
- Do NOT guess. Empty + unsure is better than wrong.

# Output
Write the draft to: ROADMAP.md.draft
After review, the user will run: mv ROADMAP.md.draft ROADMAP.md && git add ROADMAP.md && git commit
DO NOT commit yourself.
"""

def mode_llm(out_path, force):
    root = repo_root()
    nova_dir = os.path.join(root, ".nova")
    Path(nova_dir).mkdir(parents=True, exist_ok=True)
    input_path = os.path.join(nova_dir, "init-input.json")

    inputs = {
        "$schema": "https://nova/init-roadmap-input/v1.0",
        "version": "1.0",
        "generated_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "target_out": out_path,
        "nova_state_md": collect_nova_state(root),
        "git_log_30d": collect_git_log(root),
        "plans_with_parent_phase": scan_plans(root),
        "existing_docs_non_archived": collect_existing_docs(root),
    }

    Path(input_path).write_text(
        json.dumps(inputs, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n✓ 자료 수집 완료: {input_path}")
    print(f"  - NOVA-STATE.md: {'있음 (' + str(len(inputs['nova_state_md'])) + ' chars)' if inputs['nova_state_md'] else '없음'}")
    print(f"  - git log 30d: {len(inputs['git_log_30d'])} commits")
    print(f"  - plans with parent_phase: {len(inputs['plans_with_parent_phase'])}")
    print(f"  - existing docs (non-archived): {len(inputs['existing_docs_non_archived'])}")
    print(f"\n  다음 단계 — Claude(메인)에게 위임:")
    print(f"    1) /nova:status 호출 (init-llm 흐름 안내)")
    print(f"    2) 또는 직접 Agent subagent에게:")
    print(f"       'docs/designs/status-dashboard.md §12 + .nova/init-input.json 기반으로 ROADMAP.md.draft 작성. ⚠️ unsure rule 준수.'")
    print(f"\n  Agent가 ROADMAP.md.draft 작성 후:")
    print(f"    review → mv ROADMAP.md.draft {out_path} && git add {out_path} && git commit")
    print(f"\n  ※ 외부 API 호출 0건 (Claude Code 세션 모델 사용)")

# ---------------------------------------------------------------- main
def main():
    args = parse_args()
    if args.mode == "blank":
        mode_blank(args.out, args.force)
    elif args.mode == "scan":
        mode_scan(args.out, args.force)
    elif args.mode == "llm":
        mode_llm(args.out, args.force)

if __name__ == "__main__":
    main()
