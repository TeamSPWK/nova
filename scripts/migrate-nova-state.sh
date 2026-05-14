#!/bin/bash
# Nova State Migration — v1 → v2 변환 (NOVA-STATE.md schema v2.0)
# Spec: docs/specs/nova-state-schema-v2.md §9
#
# 사용법:
#   bash scripts/migrate-nova-state.sh                          # dry-run (기본)
#   bash scripts/migrate-nova-state.sh --apply                  # 실제 변환 + 백업
#   bash scripts/migrate-nova-state.sh --input path/to/STATE.md # 다른 파일 지정
#   bash scripts/migrate-nova-state.sh -h                       # 도움말
#
# 동작:
#   1. v2 frontmatter 감지 시 → no-op (이미 v2)
#   2. v1 파싱: Goal/Phase/Tasks/Recently Done/Last Activity/Refs
#   3. v2 렌더링: YAML frontmatter + 본문 마크다운 트리
#   4. dry-run: stdout 출력 (기본)
#   5. apply: 백업(*.v1.bak) 후 덮어쓰기
#   6. 추론 실패 graceful: stderr WARN + 원본 보존

set -euo pipefail

# ─────────────────────────────────────────────
# 옵션 파싱
# ─────────────────────────────────────────────
INPUT="NOVA-STATE.md"
APPLY=0
GUIDE_PATH="docs/guides/migrate-nova-state.md"

usage() {
  cat <<EOF
Nova State Migration — v1 → v2 (schema v2.0)

USAGE:
  bash scripts/migrate-nova-state.sh [OPTIONS]

OPTIONS:
  --input PATH    입력 STATE 파일 (기본: NOVA-STATE.md)
  --apply         실제 변환 + 백업 (기본은 dry-run)
  --dry-run       모의 실행, stdout 출력 (기본값)
  -h, --help      도움말

가이드: $GUIDE_PATH (TBD)
스펙:   docs/specs/nova-state-schema-v2.md §9
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    --input)   INPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ 알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
  esac
done

# ─────────────────────────────────────────────
# 입력 검증
# ─────────────────────────────────────────────
if [ ! -f "$INPUT" ]; then
  echo "❌ 입력 파일 없음: $INPUT" >&2
  exit 1
fi

# 이미 v2면 no-op
if head -10 "$INPUT" | grep -q "^schema_version: *2"; then
  echo "ℹ️  $INPUT 은(는) 이미 v2입니다. 변환 생략." >&2
  exit 0
fi

# python3 + PyYAML 의존성 확인 (다른 nova 스크립트와 동일)
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 필요 (다른 nova 스크립트와 동일 의존성)" >&2
  exit 1
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "❌ PyYAML 필요: pip3 install PyYAML" >&2
  exit 1
fi

# ─────────────────────────────────────────────
# v1 → v2 변환 (python3 임베드)
# ─────────────────────────────────────────────
OUTPUT=$(python3 - "$INPUT" <<'PYEOF'
import sys, re, yaml
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding='utf-8')

# ─── 헬퍼: CJK 친화 자연 자르기 ────────────
def truncate_smart(text, max_chars=80, seps=('. ', ' — ', ' (', ', ')):
    """문장 경계에서 자연스럽게 자름. 경계 없으면 max_chars + …"""
    text = text.strip()
    for sep in seps:
        idx = text.find(sep)
        if 10 < idx < max_chars:
            return text[:idx].rstrip().rstrip('.,—(')
    if len(text) > max_chars:
        return text[:max_chars].rstrip() + '…'
    return text

# ─── v1 섹션 추출 ────────────────────────────
def extract_section(text, heading_pat, end_pat=r'^##\s'):
    """## Heading 부터 다음 ## 까지 추출"""
    pat = re.compile(rf'^{heading_pat}.*?(?=^{end_pat}|\Z)',
                     re.MULTILINE | re.DOTALL)
    m = pat.search(text)
    return m.group(0).strip() if m else ''

def first_line_value(text, label):
    """- **Goal**: xxx 패턴에서 값 추출"""
    m = re.search(rf'-\s*\*\*{re.escape(label)}\*\*:\s*(.+)', text)
    return m.group(1).strip() if m else None

# Goal/Phase/Blocker — v1은 최상단 또는 ## Current 안에 있음
goal_raw = first_line_value(src, 'Goal') or '(legacy migration — goal 추론 실패, 수동 갱신 필요)'
goal     = truncate_smart(goal_raw, max_chars=80)
phase    = first_line_value(src, 'Phase')    or None
blocker  = first_line_value(src, 'Blocker')  or None
next_pt  = first_line_value(src, '다음 세션 진입점') or None

# ─── Tasks 테이블 파싱 ──────────────────────
tasks_section = extract_section(src, r'## Tasks')
task_rows = []
for line in tasks_section.splitlines():
    m = re.match(r'^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|$', line)
    if m and '---' not in m.group(2) and m.group(1).strip() != 'Task':
        task, status, verdict, note = (s.strip() for s in m.groups())
        task_rows.append({'task': task, 'status': status, 'verdict': verdict, 'note': note})

# ─── Recently Done 파싱 ─────────────────────
recent_section = extract_section(src, r'## Recently Done')
recent_rows = []
for line in recent_section.splitlines():
    m = re.match(r'^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|$', line)
    if m and '---' not in m.group(2) and m.group(1).strip() != 'Task':
        recent_rows.append({
            'task': m.group(1).strip(),
            'completed': m.group(2).strip(),
            'verdict': m.group(3).strip(),
            'ref': m.group(4).strip()
        })

# ─── Last Activity 파싱 (최근 5개, CJK 친화 컷) ─────────
activity_section = extract_section(src, r'## Last Activity')
activity_rows = []
for line in activity_section.splitlines():
    m = re.match(r'^-\s+(.+?)\s*\|\s*([0-9T:+\-Z\. ]+)\s*$', line)
    if m:
        msg, ts = m.group(1).strip(), m.group(2).strip()
        date = ts[:10] if len(ts) >= 10 else ts
        msg_short = truncate_smart(msg, max_chars=60, seps=('. ', '→ ', ' — ', ' ('))
        activity_rows.append({'date': date, 'msg': msg_short})
activity_rows = activity_rows[:5]

# ─── Known Risks / Gaps (분리 파싱 — 컬럼 의미 다름) ──
def parse_table_rows(section, skip_headers=()):
    """| col1 | col2 | col3 | 형식 표를 dict 리스트로"""
    rows = []
    for line in section.splitlines():
        m = re.match(r'^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|$', line)
        if m and '---' not in m.group(2) and m.group(1).strip() not in skip_headers:
            rows.append([m.group(i).strip() for i in (1, 2, 3)])
    return rows

risks_section = extract_section(src, r'## Known Risks')
gaps_section  = extract_section(src, r'## Known Gaps')

# Known Risks: 위험 / 심각도 / 상태
risk_rows = []
for cols in parse_table_rows(risks_section, skip_headers=('위험',)):
    risk_rows.append({'item': cols[0], 'severity': cols[1], 'state': cols[2]})

# Known Gaps: 영역 / 미커버 내용 / 우선순위 → v2 통합 시 의미 재매핑
for cols in parse_table_rows(gaps_section, skip_headers=('영역',)):
    area, content, priority = cols
    risk_rows.append({
        'item': f"[Gap] {area} — {content}",
        'severity': priority,
        'state': 'Known Gap',
    })

# ─── Refs ──────────────────────────────────
refs_section = extract_section(src, r'## Refs')

# ─── 활성 작업 분류 ─────────────────────────
done_tasks   = [t for t in task_rows if t['status'].lower() in ('done', 'completed')]
active_tasks = [t for t in task_rows if t['status'].lower() in ('in-progress', 'todo', 'doing')]
deferred     = [t for t in task_rows if t['status'].lower() in ('deferred', 'paused')]

# active_ao 추론 (heuristic): in-progress task 첫 번째에서 추출
active_ao = None
if active_tasks:
    # "status-dashboard Phase 2 (S5~S8)" 같은 패턴 → "status-dashboard"
    m = re.match(r'^([\w\-]+)', active_tasks[0]['task'])
    active_ao = f"AO-1 ({m.group(1)})" if m else "AO-1 (legacy)"

# ─── 상태 이모지 매핑 ──────────────────────
SEVERITY_EMOJI = {
    'resolved': '🟢', 'mitigated': '🟡',
    'high': '🔴', 'medium': '🟡', 'med': '🟡', 'low': '🟢',
}

def sev_emoji(sev):
    return SEVERITY_EMOJI.get(sev.lower(), '🟡')

# ─── v2 출력 렌더링 ─────────────────────────
out = []

# Frontmatter
fm = {
    'schema_version': 2,
    'goal': goal,
    'active_ao': active_ao,
    'handoff': None,  # 자동 추론 불가 — 다음 에이전트 갱신 시 채움
}
out.append('---')
out.append(yaml.dump(fm, allow_unicode=True, default_flow_style=False, sort_keys=False).rstrip())
out.append('---')
out.append('')

# 헤더
out.append('# 🚀 Nova State')
out.append('')

# Current
out.append('## 🎯 Current')
out.append(f'**{goal}**')
out.append('')
if next_pt:
    out.append('> [!NOTE]')
    out.append(f'> **다음 세션 진입점**: {next_pt}')
    out.append('')

# Active Tree
out.append('## 🌳 Active Tree')
out.append('')
if active_tasks:
    for t in active_tasks:
        out.append(f"- 🔄 **{t['task']}** — `{t['status']}`")
        if t['note'] and t['note'] != '-':
            out.append(f"  - 📝 {t['note']}")
    out.append('')
else:
    out.append('> 진행 중인 AO 없음. 다음 AO 선택 대기.')
    out.append('')

# Handoff — null이면 섹션 생략
# (자동 추론 불가, 다음 에이전트가 채움)

# Recent Activity
out.append('## 📊 Recent Activity')
out.append('')
out.append('| 시각 | 작업 | 결과 |')
out.append('|------|------|:----:|')
for r in activity_rows:
    msg_short = r['msg'][:80] + ('…' if len(r['msg']) > 80 else '')
    out.append(f"| {r['date']} | {msg_short} | ✅ |")
out.append('')

# Risks & Gaps
if risk_rows:
    out.append('## ⚠️ Risks & Gaps')
    out.append('')
    out.append('| 항목 | 심각도 | 상태 |')
    out.append('|------|:------:|------|')
    for r in risk_rows:
        out.append(f"| {r['item']} | {sev_emoji(r['severity'])} {r['severity']} | {r['state']} |")
    out.append('')

# Archive
all_done = done_tasks + deferred
if all_done or recent_rows:
    out.append(f'<details>')
    out.append(f'<summary>📦 <b>Archive</b> — 완료된 AO ({len(all_done) + len(recent_rows)}개)</summary>')
    out.append('')
    out.append('| AO | 결과 | 핵심 산출물 |')
    out.append('|----|:----:|------------|')
    NOTE_SEPS = ('. ', ' + ', ' — ', ' (')
    for t in done_tasks:
        emoji = '✅' if t['verdict'].upper() == 'PASS' else '☑️'
        note_s = truncate_smart(t['note'], max_chars=100, seps=NOTE_SEPS)
        out.append(f"| {t['task']} | {emoji} {t['verdict']} | {note_s} |")
    for t in deferred:
        note_s = truncate_smart(t['note'], max_chars=100, seps=NOTE_SEPS)
        out.append(f"| {t['task']} | ⏸️ Deferred | {note_s} |")
    for r in recent_rows:
        emoji = '✅' if r['verdict'].upper() == 'PASS' else '☑️'
        note_s = truncate_smart(r['ref'], max_chars=100, seps=NOTE_SEPS)
        out.append(f"| {r['task']} | {emoji} {r['verdict']} | {note_s} |")
    out.append('')
    out.append('</details>')
    out.append('')

# Refs (원본 그대로 유지 — 추론 위험 회피)
if refs_section:
    out.append('## 🔗 Refs')
    out.append('')
    for line in refs_section.splitlines()[1:]:  # 헤더 라인 스킵
        if line.strip():
            out.append(line)
    out.append('')

# 푸터
out.append('---')
out.append('')
out.append('<sub>📐 schema_version: 2 · 🔧 v1→v2 migration via `scripts/migrate-nova-state.sh`</sub>')

print('\n'.join(out))

# 추론 신뢰도 stderr 보고
warnings = []
if not active_tasks and not done_tasks:
    warnings.append('Tasks 테이블 파싱 0건 — 원본 포맷 확인 필요')
if not activity_rows:
    warnings.append('Last Activity 파싱 0건')
if goal.startswith('(legacy'):
    warnings.append('Goal 추론 실패 — frontmatter 수동 갱신 필요')

if warnings:
    print('', file=sys.stderr)
    print('⚠️  추론 경고:', file=sys.stderr)
    for w in warnings:
        print(f'   - {w}', file=sys.stderr)

PYEOF
)

# ─────────────────────────────────────────────
# 출력 / 적용
# ─────────────────────────────────────────────
if [ "$APPLY" -eq 1 ]; then
  BACKUP="${INPUT}.v1.bak"
  cp "$INPUT" "$BACKUP"
  printf '%s\n' "$OUTPUT" > "$INPUT"
  echo "✅ 변환 완료" >&2
  echo "   원본 백업: $BACKUP" >&2
  echo "   변환 결과: $INPUT" >&2
  echo "" >&2
  echo "다음 단계:" >&2
  echo "   1. $INPUT 을 마크다운 뷰어로 열어 결과 확인" >&2
  echo "   2. frontmatter handoff 필드는 다음 에이전트 작업 시 자동 채워짐" >&2
  echo "   3. 문제 발생 시: cp $BACKUP $INPUT (복원)" >&2
else
  echo "=== DRY-RUN 결과 ($INPUT) ===" >&2
  echo "" >&2
  printf '%s\n' "$OUTPUT"
  echo "" >&2
  echo "=== DRY-RUN 끝 ===" >&2
  echo "" >&2
  echo "ℹ️  실제 적용: bash scripts/migrate-nova-state.sh --apply --input $INPUT" >&2
fi
