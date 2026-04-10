#!/usr/bin/env bash

# Nova Engineering — PreToolUse Hook (Bash)
# git commit 명령 감지 시 verify 리마인더를 advisory로 주입.
# 강제 차단이 아닌 리마인더 방식 — AI가 최종 판단.

# $TOOL_INPUT 환경변수에 Bash 도구의 command가 전달됨
INPUT="${TOOL_INPUT:-}"

# git commit 패턴 감지 (git commit, git -c ... commit 등)
if echo "$INPUT" | grep -qE '^\s*git\s+(.*\s+)?commit(\s|$)'; then
  cat << 'NOVA_EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate 리마인더] git commit을 감지했습니다. 커밋 전 체크리스트:\n\n1. /nova:verify 또는 /nova:review를 실행했는가?\n2. 3파일 이상 변경 시 검증 결과가 PASS인가?\n3. NOVA-STATE.md가 갱신되었는가?\n\n위 항목을 확인하지 않았다면, 커밋 전에 /nova:verify --fast를 실행하세요.\n이 리마인더는 강제 차단이 아닌 권고입니다. 사소한 변경(README, 설정)은 건너뛸 수 있습니다."
  }
}
NOVA_EOF
fi

exit 0
