#!/usr/bin/env bash
# Nova migrate-state-v3.sh — NOVA-STATE.md v2 → v3 work-item registry 변환 (Sprint 3)
#
# 입력: NOVA-STATE.md (v1 또는 v2)
# 출력: .nova/work-items/WI-NNNN-slug.json + index.json
#       NOVA-STATE.md.v2.bak (자동 백업)
#       NOVA-STATE.md에 marker 영역 추가 (--apply 시)
#
# PoC 5 규칙 (D 단계 PoC 결과 흡수):
#   1. priority 추론: 모두 medium 기본 (active/🔄만 high 선택)
#   2. blocked_reason 추출: 🚫 항목 줄 + 직후 줄에서 자유 텍스트
#   3. depends_on 추론 금지: 모두 빈 배열
#   4. source_docs 자동 추가 금지: 모두 빈 배열
#   5. commit_sha 부재 시 → status=proposed 강등 (done 추론 금지 — Codex)
#
# idempotency 가드:
#   이미 v3 registry(.nova/work-items/index.json 에 work_items 존재)를 보유한
#   프로젝트에서 실행하면 STATE 본문 재파싱을 생략하고 v3 marker 삽입만 수행한다.
#   → 활동 로그·Active Tree 행이 가짜 work-item 으로 둔갑해 registry 를
#      오염시키던 동작을 차단 (v1/v2 부트스트랩과 재실행을 안전하게 분리).
#
# 사용:
#   bash scripts/migrate-state-v3.sh                       # dry-run
#   bash scripts/migrate-state-v3.sh --apply               # 실제 적용
#   bash scripts/migrate-state-v3.sh --input PATH          # 다른 STATE
#   bash scripts/migrate-state-v3.sh --project PATH        # 다른 프로젝트 루트

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-${NOVA_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}}"

INPUT="NOVA-STATE.md"
PROJECT_ROOT="$PWD"
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)        APPLY=1 ;;
    --dry-run)      APPLY=0 ;;
    --input=*)      INPUT="${1#*=}" ;;
    --input)        INPUT="${2:-}"; shift ;;
    --project=*)    PROJECT_ROOT="${1#*=}" ;;
    --project)      PROJECT_ROOT="${2:-}"; shift ;;
    -h|--help)
      cat <<'USAGE'
Nova migrate-state-v3 — NOVA-STATE.md v2 → v3 work-item registry

사용:
  bash scripts/migrate-state-v3.sh                      dry-run (기본)
  bash scripts/migrate-state-v3.sh --apply              실제 적용 + 백업
  bash scripts/migrate-state-v3.sh --input PATH         대체 STATE 경로
  bash scripts/migrate-state-v3.sh --project PATH       대체 프로젝트 루트

출력:
  - .nova/work-items/WI-NNNN-slug.json (work-item 1개씩)
  - .nova/work-items/index.json (매니페스트)
  - NOVA-STATE.md.v2.bak (자동 백업, --apply 시)
  - 보존율 보고서 (stdout)

PoC 5 규칙 적용:
  priority=medium 기본 · blocked_reason 자유 텍스트 추출 · depends_on=[] · source_docs=[] · commit_sha 부재→proposed
USAGE
      exit 0
      ;;
    *) echo "[migrate-v3] ERR: 알 수 없는 옵션 '$1'" >&2; exit 2 ;;
  esac
  shift
done

STATE_FILE="$PROJECT_ROOT/$INPUT"
if [ "${INPUT:0:1}" = "/" ]; then STATE_FILE="$INPUT"; fi  # 절대경로 입력

WI_DIR="$PROJECT_ROOT/.nova/work-items"
INDEX_FILE="$WI_DIR/index.json"
BACKUP_FILE="${STATE_FILE}.v2.bak"

log()  { echo "[migrate-v3] $*"; }
warn() { echo "[migrate-v3] WARN: $*" >&2; }
err()  { echo "[migrate-v3] ERR: $*" >&2; }

if [ "$APPLY" = "1" ]; then log "APPLY 모드 — 실제 변환 진행"; else log "DRY-RUN — 변환 결과만 출력"; fi

# ── pre-flight ──
if [ ! -f "$STATE_FILE" ]; then
  err "STATE 파일 부재: $STATE_FILE"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  err "jq 미설치"
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 미설치"
  exit 2
fi

# .nova/ 디렉토리 미초기화면 안내
if [ ! -d "$PROJECT_ROOT/.nova" ] && [ "$APPLY" = "1" ]; then
  log "registry 미초기화 — 'bash scripts/setup.sh' 자동 호출"
  NOVA_REGISTRY_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/setup.sh" > /dev/null
fi

# ── idempotency 가드: 이미 v3 registry 를 보유한 프로젝트 보호 ──
# 이 스크립트는 v1/v2 → v3 일회성 부트스트랩 전용이다. STATE 본문의 마크다운 표
# (Tasks/Recent Activity/Known Gaps/Active Tree)를 work-item 으로 파싱하는데,
# 이미 v3 인 프로젝트에서 그대로 실행하면 활동 로그·Active Tree 행이 가짜
# work-item 으로 둔갑하고 index.json 에 누적 append(`.work_items += $items`)되어
# registry 가 오염된다. → index.json 에 work_items 가 이미 있으면 본문 재파싱을
# 통째로 생략하고, STATE 포맷 정합화(v3 marker 삽입/갱신)만 수행한다.
EXISTING_WI=0
if [ -f "$INDEX_FILE" ]; then
  EXISTING_WI=$(jq -r '(.work_items | length) // 0' "$INDEX_FILE" 2>/dev/null || echo 0)
  case "$EXISTING_WI" in ''|*[!0-9]*) EXISTING_WI=0 ;; esac
fi

if [ "$EXISTING_WI" -gt 0 ]; then
  log "registry 이미 v3 — work-item ${EXISTING_WI}개 보유. STATE 본문 재파싱 생략 (registry 무손상)."

  if grep -qF "<!-- nova:registry-rendered:start -->" "$STATE_FILE"; then
    # registry + marker 모두 존재 = 완전한 v3. 변환할 것 없음.
    if [ "$APPLY" = "1" ]; then
      NOVA_REGISTRY_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/registry-render-state.sh" \
        --state-file="$STATE_FILE" > /dev/null 2>&1 || true
      log "✅ 이미 완전한 v3 (registry ${EXISTING_WI} WI + marker) — render 갱신만 수행, 변환 없음"
    else
      log "DRY-RUN: 이미 완전한 v3 — 변환 불필요 (--apply 해도 registry·work-item 변경 없음)"
    fi
    exit 0
  fi

  # hybrid: registry 는 v3 완비, NOVA-STATE.md 에 marker 만 부재 → marker 삽입만.
  if [ "$APPLY" != "1" ]; then
    log "DRY-RUN: registry 는 v3 완비 — NOVA-STATE.md 에 v3 marker 만 삽입 예정."
    log "  registry work-item ${EXISTING_WI}개는 그대로 보존 (재생성·강등·append 없음)."
    log "  실제 적용: bash scripts/migrate-state-v3.sh --apply"
    exit 0
  fi

  [ -f "$BACKUP_FILE" ] || { cp "$STATE_FILE" "$BACKUP_FILE"; log "백업 생성: $(basename "$BACKUP_FILE")"; }
  NOVA_REGISTRY_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/registry-render-state.sh" \
    --state-file="$STATE_FILE" --force > /dev/null 2>&1 || true
  if grep -qF "<!-- nova:registry-rendered:start -->" "$STATE_FILE"; then
    log "✅ STATE 포맷 v3 정합화 완료 — v3 marker 삽입 + render (registry ${EXISTING_WI} WI 무손상)"
    exit 0
  fi
  err "marker 삽입 실패 — registry-render-state.sh 출력 수동 확인 필요"
  exit 2
fi

# ── python 파서: v2 STATE → work-item JSON 배열 + 보존율 ──
# stdout: JSON {work_items: [...], stats: {tasks, recent, gaps, active_tree, total}}
python3 - "$STATE_FILE" <<'PYEOF' > /tmp/.nova-migrate-$$.json
import sys, re, json, os
from datetime import datetime, timezone

state_path = sys.argv[1]
with open(state_path, encoding='utf-8') as f:
    raw = f.read()

# 1) frontmatter 분리
fm = {}
body = raw
if raw.startswith('---\n'):
    end = raw.find('\n---\n', 4)
    if end > 0:
        body = raw[end+5:]

# 2) 섹션별 파싱 — 마크다운 헤더 기반
def find_section(text, header_pattern):
    """## Tasks 같은 섹션 본문(다음 ## 헤더까지) 반환.
    이모지 prefix 허용: ## 🌳 Active Tree, ## 📊 Recent Activity 등."""
    # 이모지/유니코드 심볼 prefix (0~3 문자) 허용
    m = re.search(rf'^##\s+(?:\S{{1,3}}\s+)?{header_pattern}\s*$', text, re.MULTILINE)
    if not m:
        return None
    start = m.end()
    next_header = re.search(r'^##\s+', text[start:], re.MULTILINE)
    end = start + next_header.start() if next_header else len(text)
    return text[start:end]

def parse_table(section):
    """| col | col | ... | 패턴 본문 행만 추출 (헤더+구분선 제외)"""
    if not section:
        return []
    rows = []
    for line in section.split('\n'):
        line = line.strip()
        # 표 행: | 로 시작 + | 로 끝, 구분선(---)이 아닌
        if line.startswith('|') and line.endswith('|') and '---' not in line:
            cols = [c.strip() for c in line.strip('|').split('|')]
            # 헤더(첫 행에 '---' 없는 헤더) 또한 자동 인식 — 추정상 첫 매칭 헤더 스킵
            rows.append(cols)
    # 첫 행은 헤더 — 스킵
    if rows and not any(c.startswith('-') for c in rows[0]):
        rows = rows[1:]
    return rows

def parse_active_tree(section):
    """- ✅/⬜/🔄/🚫 [link or title] — note 형식. tuple 반환"""
    if not section:
        return []
    items = []
    lines = section.split('\n')
    for i, line in enumerate(lines):
        m = re.match(r'^\s*-\s+(✅|⬜|🔄|🚫)\s+(.+?)\s*$', line)
        if m:
            emoji, content = m.groups()
            # blocked_reason: 🚫 다음 줄에서 추출
            blocked_reason = None
            if emoji == '🚫':
                next_line = lines[i+1].strip() if i+1 < len(lines) else ''
                if next_line.startswith('-') or not next_line:
                    blocked_reason = "미정의 — 사용자 입력 필요"
                else:
                    blocked_reason = next_line.lstrip('- ').strip()
            items.append({'emoji': emoji, 'content': content, 'blocked_reason': blocked_reason})
    return items

def slugify(t):
    t = t.strip().lower()
    t = re.sub(r'[\s_/\\]+', '-', t)
    t = re.sub(r'[^a-z0-9가-힣\-]+', '', t)
    t = re.sub(r'-+', '-', t).strip('-')
    return (t or 'untitled')[:60]

def extract_commit_sha(text):
    """텍스트에서 commit SHA 패턴 추출 (7~40자 hex)"""
    m = re.search(r'\b([a-f0-9]{7,40})\b', text or '')
    return m.group(1) if m else None

# 3) 섹션별 → work-items 변환
work_items = []
stats = {'tasks': 0, 'recent': 0, 'gaps': 0, 'active_tree': 0, 'done_with_sha': 0, 'proposed_demoted': 0}
ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

# Tasks 표 (Task / Status / Verdict / Note)
tasks_sec = find_section(body, r'Tasks')
for row in parse_table(tasks_sec):
    if len(row) < 1 or not row[0]:
        continue
    title = row[0]
    status_raw = row[1].lower() if len(row) > 1 else 'todo'
    note = row[3] if len(row) > 3 else ''
    # PoC #5: status 추론 금지 — 모두 proposed (done 추론 절대 X)
    work_items.append({
        'title': title,
        'status': 'proposed',
        'priority': 'medium',
        'notes': f"v2 Tasks: {note}" if note else "",
        'origin': 'Tasks',
        'commit_sha': None,
        'blocked_reason': None,
    })
    stats['tasks'] += 1

# Recently Done 표 (commit_sha 추출 시 status=done)
recent_sec = find_section(body, r'(Recently Done|Recent Activity)(\s*\(.+\))?')
for row in parse_table(recent_sec):
    if len(row) < 1 or not row[0]:
        continue
    title = row[0]
    ref = row[3] if len(row) > 3 else ''
    sha = extract_commit_sha(ref) or extract_commit_sha(row[2] if len(row) > 2 else '')
    if sha:
        work_items.append({
            'title': title,
            'status': 'done',
            'priority': 'medium',
            'notes': '',
            'origin': 'Recently Done',
            'commit_sha': sha,
            'blocked_reason': None,
        })
        stats['done_with_sha'] += 1
    else:
        work_items.append({
            'title': title,
            'status': 'proposed',  # PoC #5: 강등
            'priority': 'medium',
            'notes': '이전 STATE에서 done이었음 — evidence 확인 필요',
            'origin': 'Recently Done',
            'commit_sha': None,
            'blocked_reason': None,
        })
        stats['proposed_demoted'] += 1
    stats['recent'] += 1

# Known Gaps 표 (priority=low)
gaps_sec = find_section(body, r'Known Gaps.*')
for row in parse_table(gaps_sec):
    if len(row) < 1 or not row[0]:
        continue
    title = row[0]
    note = row[1] if len(row) > 1 else ''
    work_items.append({
        'title': title,
        'status': 'proposed',
        'priority': 'low',
        'notes': f"v2 Known Gaps: {note}" if note else "",
        'origin': 'Known Gaps',
        'commit_sha': None,
        'blocked_reason': None,
    })
    stats['gaps'] += 1

# Active Tree (v2.5+, swk-ground-control 형식)
at_sec = find_section(body, r'Active Tree.*')
for it in parse_active_tree(at_sec):
    emoji = it['emoji']
    title = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', it['content'])  # markdown link 제거
    if emoji == '✅':
        sha = extract_commit_sha(title)
        if sha:
            status, priority, blocked = 'done', 'medium', None
            stats['done_with_sha'] += 1
        else:
            status, priority, blocked = 'proposed', 'medium', None
            stats['proposed_demoted'] += 1
    elif emoji == '🔄':
        status, priority, blocked = 'active', 'high', None
    elif emoji == '🚫':
        status, priority, blocked = 'blocked', 'medium', it['blocked_reason']
    else:  # ⬜
        status, priority, blocked = 'proposed', 'medium', None

    work_items.append({
        'title': title,
        'status': status,
        'priority': priority,
        'notes': f"v2 Active Tree: {emoji}",
        'origin': 'Active Tree',
        'commit_sha': sha if emoji == '✅' else None,
        'blocked_reason': blocked,
    })
    stats['active_tree'] += 1

stats['total_v2_items'] = stats['tasks'] + stats['recent'] + stats['gaps'] + stats['active_tree']

print(json.dumps({
    'work_items': work_items,
    'stats': stats,
    'ts': ts,
}, ensure_ascii=False, indent=2))
PYEOF

PARSED="/tmp/.nova-migrate-$$.json"
if ! jq empty "$PARSED" 2>/dev/null; then
  err "STATE 파싱 실패 — Python 파서 출력 invalid"
  cat "$PARSED" | head -20 >&2
  rm -f "$PARSED"
  exit 2
fi

TOTAL_V2=$(jq -r '.stats.total_v2_items' "$PARSED")
TASKS=$(jq -r '.stats.tasks' "$PARSED")
RECENT=$(jq -r '.stats.recent' "$PARSED")
GAPS=$(jq -r '.stats.gaps' "$PARSED")
ACTIVE_TREE=$(jq -r '.stats.active_tree' "$PARSED")
DONE_WITH_SHA=$(jq -r '.stats.done_with_sha' "$PARSED")
PROPOSED_DEMOTED=$(jq -r '.stats.proposed_demoted' "$PARSED")

log "v2 STATE 파싱 완료:"
log "  Tasks: $TASKS, Recently Done: $RECENT, Known Gaps: $GAPS, Active Tree: $ACTIVE_TREE"
log "  → 변환 대상 work-item: ${TOTAL_V2}개 (done w/ sha: ${DONE_WITH_SHA}, proposed 강등: ${PROPOSED_DEMOTED})"

if [ "$TOTAL_V2" -eq 0 ]; then
  log "변환 대상 0건 — 추가 작업 없음 (이미 v3 또는 빈 STATE)"
  rm -f "$PARSED"
  exit 0
fi

# ── dry-run: 변환 미리보기만 ──
if [ "$APPLY" != "1" ]; then
  log ""
  log "변환 미리보기 (5건 샘플):"
  jq -r '.work_items[0:5] | .[] | "  - [\(.origin)] \(.title) → status=\(.status), priority=\(.priority)"' "$PARSED"
  log ""
  log "전체 보고서: $PARSED (jq -r '.work_items[]' 로 확인)"
  log "실제 적용: bash scripts/migrate-state-v3.sh --apply"
  exit 0
fi

# ── apply: 실제 변환 ──
# 1) 백업
if [ ! -f "$BACKUP_FILE" ]; then
  cp "$STATE_FILE" "$BACKUP_FILE"
  log "백업 생성: $(basename "$BACKUP_FILE")"
fi

# 2) registry 초기화 (필요 시)
[ -f "$INDEX_FILE" ] || NOVA_REGISTRY_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/setup.sh" > /dev/null

NEXT_SEQ=$(jq -r '.next_seq' "$INDEX_FILE")
TS=$(date -u +%FT%TZ)

# 3) work-item JSON 일괄 생성 + index 갱신
NEW_INDEX_ITEMS="["
FIRST=1
WI_COUNT=$(jq '.work_items | length' "$PARSED")
for i in $(seq 0 $((WI_COUNT - 1))); do
  title=$(jq -r ".work_items[$i].title" "$PARSED")
  status=$(jq -r ".work_items[$i].status" "$PARSED")
  priority=$(jq -r ".work_items[$i].priority" "$PARSED")
  notes=$(jq -r ".work_items[$i].notes // \"\"" "$PARSED")
  commit_sha=$(jq -r ".work_items[$i].commit_sha // \"\"" "$PARSED")
  blocked_reason=$(jq -r ".work_items[$i].blocked_reason // \"\"" "$PARSED")

  slug=$(python3 -c "
import sys, re
t = sys.argv[1].strip().lower()
t = re.sub(r'[\\s_/\\\\]+', '-', t)
t = re.sub(r'[^a-z0-9가-힣\\-]+', '', t)
t = re.sub(r'-+', '-', t).strip('-')
print((t or 'untitled')[:60])
" "$title")
  id=$(printf "WI-%04d-%s" "$NEXT_SEQ" "$slug")
  NEXT_SEQ=$((NEXT_SEQ + 1))

  # evidence 구성
  ev_sha="[]"
  [ -n "$commit_sha" ] && ev_sha="[\"$commit_sha\"]"
  ar_at="null"
  bl_reason_json="null"
  [ -n "$blocked_reason" ] && bl_reason_json=$(jq -n --arg s "$blocked_reason" '$s')

  wi_file="$WI_DIR/$id.json"
  jq -n \
    --arg id "$id" --arg title "$title" --arg status "$status" \
    --arg priority "$priority" --arg notes "$notes" --arg ts "$TS" \
    --argjson commits "$ev_sha" --argjson bl "$bl_reason_json" \
    '{
      schema_version: "3.0", id: $id, title: $title, status: $status,
      review_required: false, archived_at: null, priority: $priority,
      depends_on: [], source_docs: [],
      evidence: { commit_sha: $commits, test_output: null, files_changed: null, pr_url: null },
      created_at: $ts, updated_at: $ts,
      owner: null, notes: $notes,
      superseded_by: null, blocked_reason: $bl,
      last_verified_at: null
    }' > "$wi_file"

  # index 항목
  [ $FIRST -eq 0 ] && NEW_INDEX_ITEMS+=","
  NEW_INDEX_ITEMS+=$(jq -cn --arg id "$id" --arg s "$status" --arg p "$priority" --arg t "$TS" \
    '{id:$id, status:$s, review_required:false, priority:$p, updated_at:$t}')
  FIRST=0
done
NEW_INDEX_ITEMS+="]"

jq --argjson items "$NEW_INDEX_ITEMS" --argjson n "$NEXT_SEQ" --arg ts "$TS" \
  '.next_seq = $n | .work_items += $items | .generated_at = $ts' "$INDEX_FILE" > "$INDEX_FILE.tmp" \
  && mv "$INDEX_FILE.tmp" "$INDEX_FILE"

# 4) NOVA-STATE.md에 marker 영역 추가 (없으면)
if ! grep -qF "<!-- nova:registry-rendered:start -->" "$STATE_FILE"; then
  # ## Tasks 섹션 뒤에 marker 영역 삽입
  python3 -c "
import sys, re
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    txt = f.read()
marker = '''

## Active Tree (Nova v3 registry 자동 렌더)

<!-- nova:registry-rendered:start -->
<!-- 이 marker 안쪽은 bash scripts/registry-render-state.sh가 자동 갱신. 손편집 금지. -->
<!-- nova:registry-rendered:end -->
'''
# ## Tasks 섹션 끝 (다음 ## 직전)에 삽입
m = re.search(r'^##\\s+Tasks', txt, re.MULTILINE)
if m:
    rest = txt[m.end():]
    next_h = re.search(r'\\n##\\s+', rest)
    if next_h:
        insert_at = m.end() + next_h.start()
        txt = txt[:insert_at] + marker + txt[insert_at:]
    else:
        txt = txt + marker
else:
    txt = txt + marker
with open(p, 'w', encoding='utf-8') as f:
    f.write(txt)
" "$STATE_FILE"
  log "marker 영역 NOVA-STATE.md에 추가"
fi

# 5) render-state 자동 호출
NOVA_REGISTRY_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/registry-render-state.sh" > /dev/null 2>&1 || true

# 6) 보존율 보고
NUM_CREATED=$(ls "$WI_DIR"/WI-*.json 2>/dev/null | wc -l | tr -d ' ')
PRESERVATION_A=$(python3 -c "print(round($NUM_CREATED / $TOTAL_V2 * 100, 1) if $TOTAL_V2 else 0)")
log ""
log "✅ v2→v3 마이그레이션 완료"
log "  변환된 work-item: ${NUM_CREATED}개"
log "  보존율 (a) 항목 수: ${PRESERVATION_A}% ($NUM_CREATED/$TOTAL_V2)"
log "  보존율 (b) 상태: done w/ sha=$DONE_WITH_SHA, proposed 강등=$PROPOSED_DEMOTED"
log ""
log "다음 단계:"
log "  bash scripts/registry-drift-check.sh         # 변환 결과 검증 (Sprint 4)"
log "  git diff $STATE_FILE                          # marker 영역 확인"
log "  사용자 후속 입력: source_docs, depends_on (post-migration 수동)"

rm -f "$PARSED"
exit 0
