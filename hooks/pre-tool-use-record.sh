#!/usr/bin/env bash
# Nova PreToolUse Hook — tool_call 이벤트 기록 (v5.18.2)
#
# Claude Code hooks 공식 스펙: stdin으로 JSON 전달 — {"tool_name": "Bash", ...}
# v5.18.0~v5.18.1은 환경변수 가정이 오류였음. stdin JSON 파싱으로 수정.
#
# 도구 인자(경로/코드 등)는 privacy 위험으로 절대 기록하지 않는다. tool 이름만.
# Safe-default: exit 0

if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

TOOL="unknown"
if [[ ! -t 0 ]]; then
  # stdin 비-tty — Claude Code hooks 표준 또는 inherited fd
  # v5.38.1 hotfix: cat blocking → read -t (nonblocking) 으로 변경.
  # 이유: inherited 빈 stdin은 EOF가 안 오므로 cat이 무한 대기 (1시간+ hang 사고 발생, v5.38.0 release).
  # read -t 1: 1초 내에 첫 라인 없으면 fallback.
  INPUT=""
  if IFS= read -r -t 1 INPUT 2>/dev/null; then
    # 추가 라인 nonblocking 흡수 (multi-line JSON 대비)
    while IFS= read -r -t 0.1 _next 2>/dev/null; do
      INPUT="${INPUT}${_next}"
    done
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
  else
    # stdin 비어있음 또는 timeout — 환경변수 fallback (CI/테스트 호환)
    TOOL="${TOOL_NAME:-unknown}"
  fi
else
  # tty 수동 실행
  TOOL="${TOOL_NAME:-manual}"
fi

NOVA_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

bash "${NOVA_ROOT}/hooks/record-event.sh" tool_call "{\"tool\":\"${TOOL}\"}" 2>/dev/null &

exit 0
