#!/bin/bash
# Nova State Drift Check — L3 검증 (Evaluator 단계)
# Spec: docs/specs/nova-state-schema-v2.md §10 — 코드 변경 vs NOVA-STATE.md 갱신 일치
#
# 사용법:
#   bash scripts/check-state-drift.sh              # warn 모드 (기본): WARN 출력, exit 0
#   bash scripts/check-state-drift.sh --strict     # strict: drift 발견 시 exit 1
#   bash scripts/check-state-drift.sh -h           # 도움말
#
# 검증 항목:
#   1. working tree에 코드 변경 있는데 NOVA-STATE.md mtime이 HEAD commit 시점 이전 → drift
#   2. NOVA-STATE.md 없음 → MISSING (Hard Gate가 별도 처리, 여기서는 skip)
#   3. v2 frontmatter handoff.outputs에 명시된 파일이 git diff에 없음 → handoff drift WARN

set -euo pipefail

MODE="warn"
GUIDE_HINT="docs/specs/nova-state-schema-v2.md §10"

usage() {
  cat <<EOF
Nova State Drift Check — L3 검증

USAGE:
  bash scripts/check-state-drift.sh [--strict] [-h]

MODES:
  warn (기본)    — drift 발견 시 stderr WARN, exit 0 (advisory)
  --strict      — drift 발견 시 exit 1 (Hard Gate 통합용)

검증:
  1. 코드 변경 있는데 STATE.md mtime이 HEAD commit 시점 이전 → drift
  2. v2 handoff.outputs 명시 파일이 git working tree에 없음 → handoff drift

Spec: $GUIDE_HINT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)  MODE="strict"; shift ;;
    --warn)    MODE="warn"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ 알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
  esac
done

# git 저장소 확인
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ℹ️  git 저장소 아님 — drift 검증 skip" >&2
  exit 0
fi

# NOVA-STATE.md 존재 확인
if [ ! -f "NOVA-STATE.md" ]; then
  echo "ℹ️  NOVA-STATE.md 없음 — drift 검증 skip (Hard Gate가 별도 처리)" >&2
  exit 0
fi

# ─────────────────────────────────────────────
# 검증 1: 코드 변경 vs STATE mtime
# ─────────────────────────────────────────────
HEAD_EPOCH=$(git log -1 --format=%ct 2>/dev/null || echo 0)
STATE_MTIME=$(stat -f %m NOVA-STATE.md 2>/dev/null || stat -c %Y NOVA-STATE.md 2>/dev/null || echo 0)

# working tree 코드 변경 (NOVA-STATE.md 자체 제외, 빈 파일 무시)
# set -o pipefail 환경에서 grep 매칭 0건 시 exit 1 방지: { ... || true; }
CODE_CHANGES=$(git diff --name-only HEAD 2>/dev/null \
  | { grep -vE '^NOVA-STATE\.md$|\.md\.bak$|^\.nova/' || true; } \
  | wc -l | tr -d ' ')

DRIFT=0

if [ "$CODE_CHANGES" -gt 0 ] && [ "$STATE_MTIME" -le "$HEAD_EPOCH" ]; then
  echo "❌ State Drift 의심: 코드 ${CODE_CHANGES}개 변경되었으나 NOVA-STATE.md가 HEAD commit 이전 시점" >&2
  echo "   - HEAD commit time: $(date -r "$HEAD_EPOCH" +%Y-%m-%d\ %H:%M:%S 2>/dev/null || echo "$HEAD_EPOCH")" >&2
  echo "   - STATE.md mtime:   $(date -r "$STATE_MTIME" +%Y-%m-%d\ %H:%M:%S 2>/dev/null || echo "$STATE_MTIME")" >&2
  echo "   해소: NOVA-STATE.md Recent Activity에 이번 작업 1줄 추가 + Goal/Active Tree 갱신" >&2
  DRIFT=1
fi

# ─────────────────────────────────────────────
# 검증 2: v2 handoff.outputs 일치 (선택, python3 + PyYAML 있을 때만)
# ─────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  HANDOFF_DRIFT=$(python3 - <<'PYEOF' 2>/dev/null || echo ""
import re, subprocess, yaml
try:
    text = open('NOVA-STATE.md', encoding='utf-8').read()
    m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
    if not m:
        exit(0)
    fm = yaml.safe_load(m.group(1)) or {}
    if fm.get('schema_version') != 2:
        exit(0)
    handoff = fm.get('handoff')
    if not handoff or not isinstance(handoff, dict):
        exit(0)
    outputs = handoff.get('outputs') or []
    if not outputs:
        exit(0)
    # git working tree에 변경된 파일
    result = subprocess.run(['git', 'diff', '--name-only', 'HEAD'],
                            capture_output=True, text=True, timeout=5)
    changed = set(result.stdout.strip().split('\n')) if result.stdout.strip() else set()
    missing = [o for o in outputs if o not in changed and not subprocess.run(
        ['git', 'log', '-1', '--format=%H', '--', o],
        capture_output=True, text=True, timeout=5).stdout.strip()]
    if missing:
        print(f"⚠️  handoff.outputs에 명시된 파일 {len(missing)}개가 git에 없음: {', '.join(missing[:3])}")
except Exception:
    pass
PYEOF
)
  if [ -n "$HANDOFF_DRIFT" ]; then
    echo "$HANDOFF_DRIFT" >&2
    DRIFT=1
  fi
fi

# ─────────────────────────────────────────────
# 결과
# ─────────────────────────────────────────────
if [ "$DRIFT" -eq 0 ]; then
  echo "✅ State Drift 없음 (코드: ${CODE_CHANGES} 변경, STATE 신선)" >&2
  exit 0
fi

# drift 발견
if [ "$MODE" = "strict" ]; then
  echo "" >&2
  echo "🛑 State Drift Hard Gate (--strict) — exit 1" >&2
  exit 1
fi

echo "" >&2
echo "ℹ️  warn 모드 (기본) — exit 0. strict 모드는 --strict 또는 Evaluator 단계에서 사용" >&2
exit 0
