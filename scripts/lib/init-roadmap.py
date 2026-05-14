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
    p.add_argument("--mode", required=True, choices=["blank", "scan", "llm", "heuristic", "api"])
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
# status 4값 의미:
#   done        — Exit criteria 통과 완료
#   in_progress — 현재 작업 phase
#   pending     — 선행 phase 미완료 대기 (dependency-blocked는 전부 여기)
#   blocked     — 외부 trigger(승인·사고·사람) 필요 — 진짜 위험만 표기
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
# v5.36.0 (W2): 시크릿 패턴 — init-input.json에 NOVA-STATE 본문이 통째로 들어가므로
# 사용자가 부주의하게 .nova/를 git에 커밋·공유 시 노출 방지. 기본 redaction.
SECRET_PATTERNS = [
    # AWS
    (re.compile(r'AKIA[0-9A-Z]{16}'), 'AWS_ACCESS_KEY_ID'),
    (re.compile(r'aws_secret_access_key\s*[=:]\s*["\']?([A-Za-z0-9/+=]{40})["\']?', re.I), 'AWS_SECRET'),
    # GitHub
    (re.compile(r'gh[pousr]_[A-Za-z0-9_]{36,}'), 'GITHUB_TOKEN'),
    # OpenAI / Anthropic
    (re.compile(r'sk-[A-Za-z0-9]{20,}'), 'OPENAI_KEY'),
    (re.compile(r'sk-ant-[A-Za-z0-9_\-]{20,}'), 'ANTHROPIC_KEY'),
    # Generic high-entropy assignments
    (re.compile(r'(?i)(api[_-]?key|secret|password|token|bearer)\s*[=:]\s*["\']?([A-Za-z0-9_/+=\-]{20,})["\']?'), 'GENERIC_SECRET'),
    # JWT
    (re.compile(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'), 'JWT'),
]

def redact_secrets(text):
    if not text:
        return text
    out = text
    for pat, label in SECRET_PATTERNS:
        out = pat.sub(f'[REDACTED:{label}]', out)
    return out

def collect_git_log(repo_root_path, since="30 days ago", limit=50):
    try:
        out = subprocess.check_output(
            ["git", "log", f"--since={since}", "--oneline", f"-n{limit}"],
            cwd=repo_root_path, text=True, stderr=subprocess.DEVNULL,
        )
        return redact_secrets(out.strip()).splitlines()
    except Exception:
        return []

def collect_nova_state(repo_root_path):
    for cand in ("NOVA-STATE.md", "docs/NOVA-STATE.md"):
        p = os.path.join(repo_root_path, cand)
        if os.path.exists(p):
            try:
                return redact_secrets(Path(p).read_text(encoding="utf-8")[:8000])  # cap to 8KB + redact
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

def ensure_nova_gitignored(root):
    """v5.36.0 (W2): .nova/ 디렉토리에 secret을 포함할 수 있는 init-input.json이 들어가므로
    프로젝트 .gitignore에 .nova/ 등록을 권고/자동 추가. 이미 무시 중이면 skip.
    """
    gi_path = os.path.join(root, ".gitignore")
    nova_entry = ".nova/"
    try:
        if os.path.exists(gi_path):
            content = Path(gi_path).read_text(encoding="utf-8")
            # 정확 또는 broader 패턴 검사
            for line in content.splitlines():
                stripped = line.strip()
                if stripped in (".nova", ".nova/", "/.nova", "/.nova/"):
                    return False  # 이미 무시 중
            # 미등록 — append
            sep = "" if content.endswith("\n") else "\n"
            Path(gi_path).write_text(content + sep + nova_entry + "\n", encoding="utf-8")
            return True
        else:
            Path(gi_path).write_text(nova_entry + "\n", encoding="utf-8")
            return True
    except Exception:
        return False

def mode_llm(out_path, force):
    root = repo_root()
    nova_dir = os.path.join(root, ".nova")
    Path(nova_dir).mkdir(parents=True, exist_ok=True)
    input_path = os.path.join(nova_dir, "init-input.json")

    # v5.36.0 (W2): .nova/ gitignore 자동 등록 (시크릿 누출 방지)
    added = ensure_nova_gitignored(root)
    if added:
        print(f"  · .gitignore에 .nova/ 추가 (init-input.json은 redacted secret이지만 안전 권고)")

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

# ---------------------------------------------------------------- mode: heuristic (v5.37.0)
# 결정론적 phase 추출 — LLM 없이 frontmatter 없는 plan에서도 정보 추출
# 우선순위: ROADMAP frontmatter > plan frontmatter > plan markdown header > NOVA-STATE 파싱

PLAN_HEADER_RE = re.compile(r'^>\s*(Status|Owner|Goal|Created|Updated|Mode|Iteration|Phase)\s*:\s*(.+?)\s*$', re.M | re.I)
NOVA_PHASE_RE = re.compile(r'^\s*[-*]\s*\*\*Phase\*\*\s*:\s*(.+?)\s*$', re.M | re.I)
TASKS_TABLE_ROW_RE = re.compile(r'^\|\s*([^|]+?)\s*\|\s*(done|todo|in_progress|pending|blocked|PASS|FAIL|wip|진행|완료|대기|차단)\s*\|', re.M | re.I)

# Status 텍스트 → enum normalize
STATUS_NORMALIZE = {
    "done": "done", "pass": "done", "완료": "done",
    "todo": "pending", "pending": "pending", "대기": "pending",
    "in_progress": "in_progress", "in progress": "in_progress", "wip": "in_progress", "진행": "in_progress",
    "blocked": "blocked", "fail": "blocked", "차단": "blocked",
}

def normalize_status(s):
    if not s: return "pending"
    return STATUS_NORMALIZE.get(s.strip().lower(), "pending")

def heuristic_extract_plan(path):
    """frontmatter 없는 plan에서 markdown header에서 metadata 추출.
    Returns dict with id/title/status/summary or None if 추출 실패."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except Exception:
        return None
    basename = os.path.basename(path).replace(".md", "")
    # title — first # heading or filename
    title_match = re.search(r'^#\s+(.+?)\s*$', text, re.M)
    title = title_match.group(1).strip() if title_match else basename
    # status from `> Status:` line
    status = "pending"
    for m in PLAN_HEADER_RE.finditer(text[:2000]):
        key, val = m.group(1).lower(), m.group(2)
        if key == "status":
            status = normalize_status(val)
            break
    # summary — first paragraph after title (max 120 chars)
    body = text[title_match.end():] if title_match else text
    body = re.sub(r'^>\s*.+$', '', body, flags=re.M)  # remove blockquote metadata
    para_match = re.search(r'^([^\n#>].{10,200}?)(?:\n\n|\n#|\Z)', body.strip(), re.S | re.M)
    summary = para_match.group(1).strip()[:120] if para_match else ""
    return {"id": basename, "title": title[:80], "status": status, "summary": summary}

def heuristic_extract_nova_state_phase(root):
    """NOVA-STATE.md에서 current_phase 추출 (`**Phase**:` 라인)."""
    state = collect_nova_state(root)
    if not state:
        return None
    m = NOVA_PHASE_RE.search(state)
    if m:
        # "M1 Done — ...", "Phase 1 in progress", etc → 첫 토큰만
        raw = m.group(1).strip()
        first_token = re.split(r'[\s\—\-:]+', raw, maxsplit=1)[0].rstrip(',.;')
        return first_token if first_token else None
    return None

def mode_heuristic(out_path, force):
    root = repo_root()
    plan_paths = sorted(glob_mod.glob(os.path.join(root, "docs/plans/*.md")))
    # archived plan 제외
    plan_paths = [p for p in plan_paths if "archived" not in p.lower()]

    if not plan_paths:
        print(f"[heuristic] docs/plans/*.md 0개 — heuristic 추출 불가", file=sys.stderr)
        sys.exit(2)

    phases = []
    for p in plan_paths:
        info = heuristic_extract_plan(p)
        if info:
            phases.append(info)

    if not phases:
        print(f"[heuristic] plan {len(plan_paths)}개 발견했으나 markdown header 추출 실패", file=sys.stderr)
        sys.exit(3)

    # current_phase: NOVA-STATE에서 추론 → 매칭되는 id 또는 첫 in_progress
    state_phase = heuristic_extract_nova_state_phase(root)
    current = None
    if state_phase:
        for ph in phases:
            if state_phase.lower() in ph["id"].lower() or state_phase.lower() in ph["title"].lower():
                current = ph["id"]
                ph["status"] = "in_progress"
                break
    if not current:
        in_progress = next((ph for ph in phases if ph["status"] == "in_progress"), None)
        if in_progress:
            current = in_progress["id"]
        else:
            current = phases[0]["id"]
            phases[0]["status"] = "in_progress"

    slug = os.path.basename(root) or "project"
    slug_safe = re.sub(r'[^A-Za-z0-9._-]', '_', slug).strip('_') or "project"

    fm = {
        "roadmap_id": slug_safe,
        "title": f"{slug_safe} (auto-heuristic)",
        "created": today_iso(),
        "current_phase": current,
        "phases": phases,
        "external_pending": [],
        "_mode": "heuristic",  # dashboard 배지용
    }
    yaml_str = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)
    content = (
        "---\n" + yaml_str + "---\n\n"
        f"# Roadmap (auto-heuristic from docs/plans/)\n\n"
        f"> Auto-generated by `init-roadmap.sh --heuristic` ({today_iso()}).\n"
        f"> 결정론적 추출 — frontmatter 없는 plan에서 markdown header + 파일명 기반.\n"
        f"> ⚠️ 정확도 낮을 수 있음 — 사용자 검수 권장.\n"
        f"> 더 정확한 결과: Claude Code session에서 `/nova:status` 호출 → Agent LLM 추론.\n\n"
        f"## 📍 발견된 phases\n\n{len(phases)}개 ({', '.join(p['id'] for p in phases[:5])}{'...' if len(phases)>5 else ''})\n"
    )
    Path(out_path).write_text(content, encoding="utf-8")
    print(f"\n✓ heuristic 추출 완료: {out_path}", file=sys.stderr)
    print(f"  - plans: {len(plan_paths)}개 → phases: {len(phases)}개", file=sys.stderr)
    print(f"  - current_phase: {current}", file=sys.stderr)
    print(f"  - ⚠️ 정확도 낮을 수 있음 — 사용자 검수 권장", file=sys.stderr)

# ---------------------------------------------------------------- mode: api (v5.37.0)
# ANTHROPIC_API_KEY 있으면 curl로 Claude API 직접 호출 — 옵션 (메모리 'API 키 의존성 0 원칙' 준수: 필수 강제 X)
def mode_api(out_path, force):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(f"[api] ANTHROPIC_API_KEY 환경변수 없음 — skip (heuristic 또는 마커로 fallback)", file=sys.stderr)
        sys.exit(2)
    root = repo_root()

    # 자료 수집 — mode_llm과 동일하지만 .nova/init-input.json은 안 만듦 (API 직접 호출)
    nova_state = collect_nova_state(root) or ""
    git_log = collect_git_log(root)
    plans_meta = scan_plans(root)
    docs_list = collect_existing_docs(root)

    prompt = f"""다음 입력을 분석해 ROADMAP.md frontmatter(YAML)를 작성하라. 본문 markdown은 작성 금지. frontmatter만 출력. 자동 commit 금지.

## 입력
NOVA-STATE.md:
{nova_state[:3000]}

git log 30d (max 30 commits):
{chr(10).join(git_log[:30])}

docs/plans (with parent_phase):
{json.dumps(plans_meta, ensure_ascii=False, indent=2)[:2000]}

existing docs:
{json.dumps(docs_list, ensure_ascii=False)[:500]}

## 출력 스키마
```yaml
roadmap_id: <slug>
title: <한 줄 프로젝트 설명>
created: {today_iso()}
current_phase: <phases[].id 중 in_progress인 것>
phases:
  - id: <slug-safe>
    title: <phase 명, id와 다른 값>
    status: <done|in_progress|pending|blocked>
    summary: <한 줄>
external_pending: []
```

## 규칙
- phase status 의미: done=완료/in_progress=현재/pending=선행 phase 대기/blocked=외부 trigger 필요
- "blocked by phase X" 의존성은 blocked가 아닌 pending
- 추측 영역은 title에 "⚠️ unsure" 표기
- YAML만 출력 (```yaml ... ``` 블록), 다른 설명 X
"""

    import urllib.request, urllib.error
    payload = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": prompt}],
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"[api] Anthropic API HTTP {e.code}: {e.reason}", file=sys.stderr)
        sys.exit(4)
    except Exception as e:
        print(f"[api] Anthropic API 호출 실패: {e}", file=sys.stderr)
        sys.exit(4)

    text = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
    yaml_match = re.search(r'```ya?ml\s*\n(.*?)\n```', text, re.S)
    yaml_body = yaml_match.group(1) if yaml_match else text.strip()
    try:
        fm = yaml.safe_load(yaml_body) or {}
    except yaml.YAMLError as e:
        print(f"[api] LLM 응답 YAML 파싱 실패: {e}", file=sys.stderr)
        sys.exit(5)
    if not isinstance(fm, dict) or "phases" not in fm:
        print(f"[api] LLM 응답에 phases 키 없음 — skip", file=sys.stderr)
        sys.exit(5)

    fm["_mode"] = "api"  # dashboard 배지용
    yaml_str = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)
    content = (
        "---\n" + yaml_str + "---\n\n"
        f"# Roadmap (auto-api LLM)\n\n"
        f"> Auto-generated by `init-roadmap.sh --api` ({today_iso()}) via Anthropic API.\n"
        f"> 사용자 검수 후 채택: `mv {out_path} ROADMAP.md`.\n"
    )
    Path(out_path).write_text(content, encoding="utf-8")
    print(f"\n✓ api 추출 완료: {out_path}", file=sys.stderr)
    print(f"  - phases: {len(fm.get('phases', []))}개", file=sys.stderr)
    print(f"  - current_phase: {fm.get('current_phase', '-')}", file=sys.stderr)

# ---------------------------------------------------------------- main
def main():
    args = parse_args()
    if args.mode == "blank":
        mode_blank(args.out, args.force)
    elif args.mode == "scan":
        mode_scan(args.out, args.force)
    elif args.mode == "llm":
        mode_llm(args.out, args.force)
    elif args.mode == "heuristic":
        mode_heuristic(args.out, args.force)
    elif args.mode == "api":
        mode_api(args.out, args.force)

if __name__ == "__main__":
    main()
