#!/bin/bash
# Nova SessionStart Hook — NOVA-STATE.md 자동 생성
# 세션 시작 시 NOVA-STATE.md가 없으면 프로젝트 상태를 스캔하여 자동 생성한다.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || true)

# cwd 폴백
if [ -z "$CWD" ] || [ "$CWD" = "null" ] || [ "$CWD" = "." ]; then
  CWD="$(pwd)"
fi

# CWD 경로 검증: 절대경로 확인 + 디렉토리 존재 확인
case "$CWD" in
  /*) ;;
  *) exit 0 ;;
esac

if [ ! -d "$CWD" ]; then
  exit 0
fi

# 프로젝트 정보 수집 (set +e로 find 실패 허용 — docs/ 없는 프로젝트 대응)
set +e
PLAN_COUNT=$(find "$CWD/docs/plans" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
DESIGN_COUNT=$(find "$CWD/docs/designs" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
VERIFY_COUNT=$(find "$CWD/docs/verifications" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
set -e

PLAN_REF="none"
DESIGN_REF="none"
VERIFY_REF="none"

if [ "${PLAN_COUNT:-0}" -gt 0 ]; then
  PLAN_REF=$(find "$CWD/docs/plans" -maxdepth 1 -name "*.md" 2>/dev/null | head -1 | sed "s|$CWD/||")
fi
if [ "${DESIGN_COUNT:-0}" -gt 0 ]; then
  DESIGN_REF=$(find "$CWD/docs/designs" -maxdepth 1 -name "*.md" 2>/dev/null | head -1 | sed "s|$CWD/||")
fi
if [ "${VERIFY_COUNT:-0}" -gt 0 ]; then
  VERIFY_REF=$(find "$CWD/docs/verifications" -maxdepth 1 -name "*.md" 2>/dev/null | sort | tail -1 | sed "s|$CWD/||")
fi

# NOVA-STATE.md 원자적 생성 (noclobber로 TOCTOU 경쟁 조건 해소)
# 이미 존재하면 자동 실패 → exit 0
set -C
{
printf '# Nova State\n'
printf '\n'
printf '## Current\n'
printf -- '- **Goal**: (CLAUDE.md 기반으로 초기화 필요 — /nova:next 실행 또는 직접 수정)\n'
printf -- '- **Phase**: building\n'
printf -- '- **Blocker**: none\n'
printf '\n'
printf '## Tasks\n'
printf '| Task | Status | Verdict | Note |\n'
printf '|------|--------|---------|------|\n'
printf '| /nova:next로 프로젝트 상태 확인 | todo | - | - |\n'
printf '\n'
printf '## Recently Done (최근 3개만)\n'
printf '| Task | Completed | Verdict | Ref |\n'
printf '|------|-----------|---------|-----|\n'
printf '\n'
printf '## Known Risks\n'
printf '| 위험 | 심각도 | 상태 |\n'
printf '|------|--------|------|\n'
printf '\n'
printf '## Known Gaps (미커버 영역)\n'
printf '| 영역 | 미커버 내용 | 우선순위 |\n'
printf '|------|-----------|----------|\n'
printf '\n'
printf '## 규칙 우회 이력 (감사 추적)\n'
printf '| 날짜 | 커맨드 | 우회 이유 | 사후 조치 |\n'
printf '|------|--------|----------|----------|\n'
printf '| — | — | — | — |\n'
printf '\n'
printf '> --emergency 플래그 사용 또는 Evaluator 건너뛸 때 반드시 기록. 미기록 = Hard-Block.\n'
printf '\n'
printf '## Last Activity\n'
printf -- '- (자동 생성) | -\n'
printf '\n'
printf '## Refs\n'
printf -- '- Plan: %s\n' "$PLAN_REF"
printf -- '- Design: %s\n' "$DESIGN_REF"
printf -- '- Last Verification: %s\n' "$VERIFY_REF"
} > "$CWD/NOVA-STATE.md" 2>/dev/null || exit 0

exit 0
