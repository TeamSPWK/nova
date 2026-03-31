#!/bin/bash
# Nova SessionStart Hook — NOVA-STATE.md 자동 생성
# 세션 시작 시 NOVA-STATE.md가 없으면 프로젝트 상태를 스캔하여 자동 생성한다.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || true)
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || true)

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

# 프로젝트 정보 수집
PLAN_COUNT=$(ls "$CWD"/docs/plans/*.md 2>/dev/null | wc -l | tr -d ' ')
DESIGN_COUNT=$(ls "$CWD"/docs/designs/*.md 2>/dev/null | wc -l | tr -d ' ')
VERIFY_COUNT=$(ls "$CWD"/docs/verifications/*.md 2>/dev/null | wc -l | tr -d ' ')

PLAN_REF="none"
DESIGN_REF="none"
VERIFY_REF="none"

if [ "$PLAN_COUNT" -gt 0 ]; then
  PLAN_REF=$(ls "$CWD"/docs/plans/*.md 2>/dev/null | head -1 | sed "s|$CWD/||")
fi
if [ "$DESIGN_COUNT" -gt 0 ]; then
  DESIGN_REF=$(ls "$CWD"/docs/designs/*.md 2>/dev/null | head -1 | sed "s|$CWD/||")
fi
if [ "$VERIFY_COUNT" -gt 0 ]; then
  VERIFY_REF=$(ls -t "$CWD"/docs/verifications/*.md 2>/dev/null | head -1 | sed "s|$CWD/||")
fi

# NOVA-STATE.md 원자적 생성 (noclobber로 TOCTOU 경쟁 조건 해소)
# 이미 존재하면 자동 실패 → exit 0
set -C
{
printf '# Nova State\n'
printf '\n'
printf '## Current\n'
printf -- '- **Goal**: (자동 생성됨 — /nova:next로 갱신하세요)\n'
printf -- '- **Phase**: building\n'
printf -- '- **Blocker**: none\n'
printf '\n'
printf '## In Progress\n'
printf '| Task | Owner | Started | Status |\n'
printf '|------|-------|---------|--------|\n'
printf '\n'
printf '## Recently Done (최근 3개만)\n'
printf '| Task | Completed | Verdict | Ref |\n'
printf '|------|-----------|---------|-----|\n'
printf '\n'
printf '## Next Actions (최대 3개)\n'
printf '1. [ ] /nova:next로 프로젝트 상태 확인\n'
printf '\n'
printf '## Refs\n'
printf -- '- Plan: %s\n' "$PLAN_REF"
printf -- '- Design: %s\n' "$DESIGN_REF"
printf -- '- Last Verification: %s\n' "$VERIFY_REF"
} > "$CWD/NOVA-STATE.md" 2>/dev/null || exit 0

exit 0
