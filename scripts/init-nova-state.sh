#!/bin/bash
# Nova SessionStart Hook — NOVA-STATE.md 자동 생성
# 세션 시작 시 NOVA-STATE.md가 없으면 프로젝트 상태를 스캔하여 자동 생성한다.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)

# cwd 폴백
if [ -z "$CWD" ] || [ "$CWD" = "null" ] || [ "$CWD" = "." ]; then
  CWD="$(pwd)"
fi

# 이미 존재하면 스킵
if [ -f "$CWD/NOVA-STATE.md" ]; then
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

# NOVA-STATE.md 생성
cat > "$CWD/NOVA-STATE.md" << NOVA_EOF
# Nova State

## Current
- **Goal**: (자동 생성됨 — /nova:next로 갱신하세요)
- **Phase**: building
- **Blocker**: none

## In Progress
| Task | Owner | Started | Status |
|------|-------|---------|--------|

## Recently Done (최근 3개만)
| Task | Completed | Verdict | Ref |
|------|-----------|---------|-----|

## Next Actions (최대 3개)
1. [ ] /nova:next로 프로젝트 상태 확인

## Refs
- Plan: $PLAN_REF
- Design: $DESIGN_REF
- Last Verification: $VERIFY_REF
NOVA_EOF

exit 0
