#!/usr/bin/env bash
# Nova — reconcile-state.sh
# NOVA-STATE.md prose ↔ git log ↔ registry 3-way 대조 엔진
#
# 사용법:
#   bash scripts/reconcile-state.sh [--jsonl] [--since=<N>d] [-h|--help]
#
# Exit code:
#   0 = clean (🟢만)
#   1 = drift (⚠️/❓ 1건+)
#   2 = 엔진 오류 (STATE 없음, git 미설치 등)
#
# 불변식: 이 스크립트는 어떤 파일도 쓰지 않는다 (read-only).
# 가이드: docs/guides/state-drift-reconciliation.md

set -euo pipefail

GUIDE_HINT="docs/guides/state-drift-reconciliation.md"
SINCE="90d"
JSONL=0

# tmpfile 누수 방지 — 조기 set -e 종료 시에도 정리 (read-only 불변식: /tmp만 건드림)
trap 'rm -f "${_PROSE_SCRIPT:-}" "${_ENGINE_SCRIPT:-}"' EXIT

usage() {
  cat <<'EOF'
Nova State Reconcile — prose ↔ git log ↔ registry 3-way 대조 엔진

USAGE:
  bash scripts/reconcile-state.sh [--jsonl] [--since=<N>d] [-h|--help]

OPTIONS:
  --jsonl         기계 판독 단일 JSON object 출력
  --since=<N>d    git log 조회 윈도우 (기본: 90d)
  -h, --help      이 도움말 출력

EXIT CODE:
  0 = clean (🟢 정상만)
  1 = drift (⚠️ 또는 ❓ 1건 이상)
  2 = 엔진 오류 (STATE 없음, git 미설치, jq 미설치 등)

EOF
  echo "가이드: $GUIDE_HINT"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jsonl)     JSONL=1; shift ;;
    --since=*)   SINCE="${1#*=}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── 의존성 확인 ──────────────────────────────────────────────────────────────

for _dep in git jq python3; do
  if ! command -v "$_dep" >/dev/null 2>&1; then
    echo "ERROR: $_dep 미설치 — reconcile 실행 불가. 가이드: $GUIDE_HINT" >&2
    exit 2
  fi
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: git 레포가 아님 — reconcile 실행 불가." >&2
  exit 2
fi

if [ ! -f "NOVA-STATE.md" ]; then
  echo "ERROR: NOVA-STATE.md 없음 — reconcile 실행 불가. 가이드: $GUIDE_HINT" >&2
  exit 2
fi

# ── STEP 1: STATE 클래스 판정 ─────────────────────────────────────────────────

INDEX_FILE=".nova/work-items/index.json"

has_registry=0
if [ -f "$INDEX_FILE" ]; then
  _WI_COUNT=$(jq '.work_items | length' "$INDEX_FILE" 2>/dev/null || echo 0)
  [ "$_WI_COUNT" -gt 0 ] && has_registry=1
fi

schema_v=$(python3 -c "
import re
text = open('NOVA-STATE.md', encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
if m:
    sv = re.search(r'schema_version:\s*(\d+)', m.group(1))
    if sv:
        print(sv.group(1)); exit()
print('0')
" 2>/dev/null || echo "0")

if [ "$has_registry" -eq 1 ] && [ "$schema_v" = "3" ]; then
  state_class="v3"
elif [ "$has_registry" -eq 1 ]; then
  state_class="hybrid"
else
  state_class="v2-only"
fi

# ── STEP 2: 소스 수집 ─────────────────────────────────────────────────────────

# prose 항목 수집 (tmpfile로 heredoc 변수 보간 문제 회피)
_PROSE_SCRIPT=$(mktemp /tmp/nova-reconcile-prose.XXXXXX.py)
cat > "$_PROSE_SCRIPT" << 'PROSE_EOF'
import re, sys

STATUS_KW = re.compile(r'진행\s*중|작업\s*중|WIP|in progress|TODO', re.IGNORECASE)
SKIP_SECTION = re.compile(r'^##\s+(📊\s*)?Recent Activity|^##\s+Recently Done', re.IGNORECASE)
MARKER_START = "<!-- nova:registry-rendered:start -->"
MARKER_END   = "<!-- nova:registry-rendered:end -->"

try:
    text = open('NOVA-STATE.md', encoding='utf-8').read()
except Exception:
    sys.exit(0)

lines = text.splitlines()
in_marker = False
in_skip_section = False
in_details = False
current_section = "Unknown"

for i, line in enumerate(lines, 1):
    if MARKER_START in line:
        in_marker = True; continue
    if MARKER_END in line:
        in_marker = False; continue
    if in_marker:
        continue
    if re.match(r'<details', line, re.IGNORECASE):
        in_details = True; continue
    if re.match(r'</details', line, re.IGNORECASE):
        in_details = False; continue
    if in_details:
        continue
    m_sec = re.match(r'^(#{1,4})\s+(.+)', line)
    if m_sec:
        current_section = m_sec.group(2).strip()
        in_skip_section = bool(SKIP_SECTION.match(line))
        continue
    if in_skip_section:
        continue
    # 리스트 항목
    m_list = re.match(r'^[\s]*[-*]\s+(.+)', line)
    if m_list:
        content = m_list.group(1).strip()
        if re.match(r'\[x\]', content, re.IGNORECASE):
            continue
        has_checkbox = bool(re.match(r'\[\s\]', content))
        has_status = bool(STATUS_KW.search(content))
        if has_checkbox or has_status:
            clean = re.sub(r'^\[\s?\]\s*', '', content)
            print(f"{i}\x1f{current_section}\x1f{clean}")
        continue
    # 표 row
    if '|' in line and STATUS_KW.search(line):
        if re.match(r'^[\s]*\|[\s\-:]+\|', line):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        combined = ' '.join(cells)
        if STATUS_KW.search(combined):
            print(f"{i}\x1f{current_section}\x1f{combined}")
PROSE_EOF
PROSE_ITEMS=$(python3 "$_PROSE_SCRIPT" 2>/dev/null || true)
rm -f "$_PROSE_SCRIPT"

# git log 수집 (%b 제거: body 개행이 %x1f 구분자를 깨뜨려 trailer 파싱 누락)
# SINCE 정규화: git이 "Nd ago"를 일부 환경에서 0커밋으로 오파싱(macOS git "30d ago"→0) → "N days ago"
_SINCE_NUM="${SINCE//[!0-9]/}"
[[ -z "$_SINCE_NUM" ]] && _SINCE_NUM=90
GIT_COMMITS=$(git log --since="${_SINCE_NUM} days ago" \
  --pretty=format:"COMMIT%x1f%H%x1f%ai%x1f%s%x1f%(trailers:key=Nova-WI,valueonly,separator=%x2C)" \
  2>/dev/null || true)

# ── STEP 3 & 4: 분류 엔진 (Python tmpfile) ────────────────────────────────────

_ENGINE_SCRIPT=$(mktemp /tmp/nova-reconcile-engine.XXXXXX.py)
cat > "$_ENGINE_SCRIPT" << 'ENGINE_EOF'
import re, subprocess, sys, os, json

SINCE        = os.environ.get("_R_SINCE", "90d")
HAS_REGISTRY = os.environ.get("_R_HAS_REGISTRY", "0") == "1"
STATE_CLASS  = os.environ.get("_R_STATE_CLASS", "v2-only")
INDEX_FILE   = os.environ.get("_R_INDEX_FILE", ".nova/work-items/index.json")
JSONL_MODE   = os.environ.get("_R_JSONL", "0") == "1"
PROSE_RAW    = os.environ.get("_R_PROSE", "")
GIT_RAW      = os.environ.get("_R_GIT", "")

SEP = "\x1f"

TOKEN_PATTERNS = [
    re.compile(r'[a-z][a-z0-9]*(?:-[a-z0-9]+)+'),   # kebab-id
    re.compile(r'--[a-z][a-z-]+'),                    # --flag
    re.compile(r'[^\s"\']*[/\.][^\s"\']{2,}'),        # path
    re.compile(r'v?\d+\.\d+\.\d+'),                   # vX.Y.Z
    re.compile(r'WI-\d+'),                             # WI-NNN
    re.compile(r'"([^"]{3,})"'),                      # "quoted"
]
NOTES_DONE_KW = re.compile(r'done|완료|done이었음|이전 STATE', re.IGNORECASE)
GIT_PREFIX = re.compile(
    r'^(feat|fix|chore|docs|refactor|update|security|axis)(\([^)]*\))?:\s*',
    re.IGNORECASE
)

def extract_tokens(text):
    tokens = set()
    text = GIT_PREFIX.sub('', str(text))
    for pat in TOKEN_PATTERNS:
        for m in pat.finditer(text):
            tok = m.group(1).lower() if m.lastindex else m.group(0).lower()
            if len(tok) >= 3:
                tokens.add(tok)
    return tokens

def check_sha(sha):
    if not sha:
        return False
    try:
        r = subprocess.run(["git", "cat-file", "-e", sha],
                           capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False

# git 커밋 파싱 (format: COMMIT SEP sha SEP date SEP subject SEP trailers)
commits = []
for line in GIT_RAW.splitlines():
    if not line.startswith(f"COMMIT{SEP}"):
        continue
    parts = (line.split(SEP) + [""] * 6)[:6]
    _, sha, date_iso, subject, trailers, *_ = parts
    nova_wi_ids = [t.strip() for t in trailers.split(",")
                   if re.match(r'WI-\d+', t.strip())]
    commits.append({
        "sha": sha[:7], "full_sha": sha, "date_iso": date_iso,
        "subject": subject,
        "tokens": extract_tokens(subject),
        "nova_wi_ids": nova_wi_ids,
    })

# prose 항목 파싱
prose_items = []
for line in PROSE_RAW.splitlines():
    if not line.strip():
        continue
    parts = line.split(SEP, 2)
    if len(parts) < 3:
        continue
    line_no, section, text = parts
    prose_items.append({"line_no": int(line_no), "section": section, "text": text})

# registry WI 로드
wi_list = []
wi_details = {}
if HAS_REGISTRY and os.path.isfile(INDEX_FILE):
    try:
        idx = json.load(open(INDEX_FILE))
        wi_list = idx.get("work_items", [])
        wi_dir = os.path.dirname(INDEX_FILE)
        for wi in wi_list:
            wid = wi["id"]
            wp = os.path.join(wi_dir, f"{wid}.json")
            if os.path.isfile(wp):
                try:
                    wi_details[wid] = json.load(open(wp))
                except Exception:
                    wi_details[wid] = wi
            else:
                wi_details[wid] = wi
    except Exception:
        pass

items = []

# WI 분류
if STATE_CLASS in ("v3", "hybrid"):
    for wi in wi_list:
        wid = wi["id"]
        status = wi.get("status", "")
        title = wi.get("title", "") or ""
        detail = wi_details.get(wid, wi)
        ev = detail.get("evidence") or {}
        ev_sha = (ev.get("commit_sha", "") if isinstance(ev, dict) else "") or \
                  detail.get("evidence_commit", "") or detail.get("evidence_sha", "") or ""

        if status == "done":
            if ev_sha and check_sha(ev_sha):
                items.append({"category": "verified", "source": "wi", "wi_id": wid,
                              "evidence": ev_sha, "text": f"{wid} {title} (done, SHA verified)"})
            else:
                items.append({"category": "suspect_explicit", "source": "wi", "wi_id": wid,
                              "evidence": ev_sha or None, "text": f"{wid} {title}",
                              "reason": "done but evidence_sha 부재/unreachable",
                              "suggestion": f"bash scripts/registry-write.sh transition {wid} done --evidence-commit=<SHA>"})
        elif status in ("active", "proposed"):
            notes = (detail.get("notes") or "").strip()
            trailer_c = next((c for c in commits if wid in c["nova_wi_ids"]), None)
            if trailer_c:
                items.append({"category": "suspect_explicit", "source": "wi", "wi_id": wid,
                              "evidence": trailer_c["sha"], "text": f"{wid} {title}",
                              "reason": f"registry={status} ↔ 커밋 {trailer_c['sha']} Nova-WI:{wid}",
                              "suggestion": f"bash scripts/registry-write.sh transition {wid} done --evidence-commit={trailer_c['full_sha']}"})
            elif notes and NOTES_DONE_KW.search(notes):
                # notes에 완료 흔적 키워드 → explicit suspect 승격 (결정적 신호)
                items.append({"category": "suspect_explicit", "source": "wi", "wi_id": wid,
                              "evidence": None, "text": f"{wid} {title}",
                              "reason": f"registry={status} ↔ notes가 이전 완료를 시사: {notes[:80]}",
                              "suggestion": f"bash scripts/registry-write.sh transition {wid} done --evidence-commit=<SHA>"})
            else:
                wi_tok = extract_tokens(f"{wid} {title} {notes}")
                scored = sorted(commits, key=lambda c: len(wi_tok & c["tokens"]), reverse=True)
                best = scored[0] if scored else None
                if best and len(wi_tok & best["tokens"]) >= 1:
                    shared = wi_tok & best["tokens"]
                    items.append({"category": "suspect_fuzzy", "source": "wi", "wi_id": wid,
                                  "evidence": f"{best['sha']} (shared: {', '.join(sorted(shared))})",
                                  "text": f"{wid} {title}",
                                  "reason": f"registry={status}, 커밋 {best['sha']}와 유사",
                                  "suggestion": f"bash scripts/registry-write.sh transition {wid} done --evidence-commit={best['full_sha']}"})
                else:
                    items.append({"category": "normal", "source": "wi", "wi_id": wid,
                                  "evidence": None, "text": f"{wid} {title} (정당하게 진행 중)"})
        else:
            items.append({"category": "normal", "source": "wi", "wi_id": wid,
                          "evidence": None, "text": f"{wid} {title} (status={status})"})

# suspect WI set (흡수 대상: suspect로 분류된 WI만)
suspect_wi_ids = {i["wi_id"] for i in items
                  if i.get("category") in ("suspect_explicit", "suspect_fuzzy")
                  and i.get("wi_id")}

# prose 분류
for prose in prose_items:
    text = prose["text"]
    ptok = extract_tokens(text)
    # suspect WI token 흡수 (normal/verified WI는 흡수 안 함)
    absorbed = any(
        bool(extract_tokens(f"{wi['id']} {wi.get('title','')}") & ptok)
        for wi in wi_list
        if wi["id"] in suspect_wi_ids
    )
    if absorbed:
        continue
    scored = sorted(commits, key=lambda c: len(ptok & c["tokens"]), reverse=True)
    best = scored[0] if scored else None
    if best and len(ptok & best["tokens"]) >= 1:
        shared = ptok & best["tokens"]
        items.append({"category": "suspect_fuzzy", "source": "prose",
                      "line_no": prose["line_no"], "wi_id": None,
                      "evidence": f"{best['sha']} (공유 토큰: {', '.join(sorted(shared))})",
                      "text": text,
                      "reason": f'prose "{text}" ↔ 커밋 {best["sha"]}'})
    else:
        items.append({"category": "untracked", "source": "prose",
                      "line_no": prose["line_no"], "wi_id": None,
                      "evidence": None, "text": text})

counts = {k: sum(1 for i in items if i["category"] == k)
          for k in ("verified","suspect_explicit","suspect_fuzzy","untracked","normal")}

result = {
    "state_class": STATE_CLASS, "window": SINCE,
    "mode": "3-way" if STATE_CLASS in ("v3","hybrid") else "2-way",
    "counts": counts, "items": items,
}
if STATE_CLASS == "hybrid":
    result["banner"] = "⚠️ hybrid: STATE 본문이 v2 형식 — /nova:migrate-state로 완전 v3 권고"
elif STATE_CLASS == "v2-only":
    result["banner"] = "⚠️ v2-only: registry 없음 — 2-way 모드 (prose↔git). /nova:migrate-state로 v3 권고"

if JSONL_MODE:
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

# 사람용 출력
total_wi = sum(1 for i in items if i.get("source") == "wi")
wi_str = f" · registry {total_wi} WI" if STATE_CLASS in ("v3","hybrid") else ""
print(f"Nova State Reconcile — {STATE_CLASS} STATE{wi_str} · git {SINCE}")
if result.get("banner"):
    print(result["banner"])
print()

verified = [i for i in items if i["category"] == "verified"]
if verified:
    print(f"✅ 완료검증 ({len(verified)})")
    for i in verified:
        print(f"  {i.get('wi_id','')} {i['text']}")
    print()

suspects = [i for i in items if i["category"] in ("suspect_explicit","suspect_fuzzy")]
if suspects:
    print(f"⚠️ 완료의심 — 확인 필요 ({len(suspects)})")
    for i in suspects:
        kind = "[explicit]" if i["category"] == "suspect_explicit" else "[fuzzy]  "
        si = f" L{i.get('line_no','?')}" if i.get("source") == "prose" else ""
        label = i.get("wi_id") or f"prose{si}"
        print(f"  {kind} {label}  {i['text']}")
        if i.get("reason"):
            print(f"             → {i['reason']}")
        if i.get("suggestion"):
            print(f"             → {i['suggestion']}")
    print()

untracked = [i for i in items if i["category"] == "untracked"]
if untracked:
    print(f"❓ 추적불가 — Nova가 상태를 알 수 없음 ({len(untracked)})")
    for i in untracked:
        si = f" L{i.get('line_no','?')}" if i.get("source") == "prose" else ""
        print(f"  prose{si}: {i['text']}")
    print()

normal = [i for i in items if i["category"] == "normal"]
print(f"🟢 정상: {len(normal)}")

# exit code 계산용 JSON을 두 번째 JSON 출력으로 추가
print(f"\n__JSON__{json.dumps(result, ensure_ascii=False)}")
ENGINE_EOF

export _R_SINCE="$SINCE"
export _R_HAS_REGISTRY="$has_registry"
export _R_STATE_CLASS="$state_class"
export _R_INDEX_FILE="$INDEX_FILE"
export _R_JSONL="$JSONL"
export _R_PROSE="$PROSE_ITEMS"
export _R_GIT="$GIT_COMMITS"

ENGINE_OUT=$(python3 "$_ENGINE_SCRIPT" 2>/dev/null || true)
rm -f "$_ENGINE_SCRIPT"

if [ -z "$ENGINE_OUT" ]; then
  echo "ERROR: 분류 엔진 실패. 가이드: $GUIDE_HINT" >&2
  exit 2
fi

if [ "$JSONL" -eq 1 ]; then
  echo "$ENGINE_OUT"
  JSON_DATA="$ENGINE_OUT"
else
  # 사람용 출력에서 __JSON__ 구분자 이후 부분 추출
  HUMAN_OUT=$(echo "$ENGINE_OUT" | python3 -c "
import sys
lines = sys.stdin.read().splitlines()
for l in lines:
    if l.startswith('__JSON__'):
        break
    print(l)
")
  JSON_DATA=$(echo "$ENGINE_OUT" | python3 -c "
import sys
for l in sys.stdin.read().splitlines():
    if l.startswith('__JSON__'):
        print(l[8:])
        break
")
  echo "$HUMAN_OUT"
fi

# exit code 결정
SUSPECT_COUNT=$(echo "$JSON_DATA" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    c=d.get('counts',{})
    print(c.get('suspect_explicit',0)+c.get('suspect_fuzzy',0)+c.get('untracked',0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

if [ "$SUSPECT_COUNT" -gt 0 ]; then
  exit 1
else
  exit 0
fi
