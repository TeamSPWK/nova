#!/usr/bin/env bash
# Nova PreToolUse Hook — tool_call 이벤트 기록 (v5.18.0)
#
# Claude Code가 $TOOL_NAME 환경변수로 도구명을 제공한다.
# 도구 인자(경로/코드 등)는 privacy 위험으로 절대 기록하지 않는다.
#
# Safe-default: exit 0

if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

TOOL="${TOOL_NAME:-${hook_event_name:-unknown}}"
NOVA_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

bash "${NOVA_ROOT}/hooks/record-event.sh" tool_call "{\"tool\":\"${TOOL}\"}" 2>/dev/null &

exit 0
