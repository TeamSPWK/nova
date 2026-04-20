#!/usr/bin/env bash
# Nova Stop Hook — session_end 이벤트 기록 (Sprint 1)
# Safe-default: 실패는 stderr WARN + exit 0

set -u

if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

START_FILE=".nova/session.start_epoch"
DURATION_MS=0

if [[ -f "$START_FILE" ]]; then
  START_EPOCH=$(tr -d '[:space:]' < "$START_FILE" 2>/dev/null || echo 0)
  NOW=$(date -u +%s)
  if [[ -n "$START_EPOCH" && "$START_EPOCH" =~ ^[0-9]+$ ]]; then
    DURATION_MS=$(( (NOW - START_EPOCH) * 1000 ))
    [[ $DURATION_MS -lt 0 ]] && DURATION_MS=0  # 시계 skew 방어
  fi
fi

if command -v jq >/dev/null 2>&1; then
  EXTRA=$(jq -cn --argjson dur "$DURATION_MS" --arg reason "stop_hook" \
    '{duration_ms: $dur, exit_reason: $reason}')
else
  EXTRA='{"duration_ms":0,"exit_reason":"stop_hook"}'
fi

bash "${BASH_SOURCE%/*}/record-event.sh" session_end "$EXTRA" 2>/dev/null || true

# Orchestration 추적 누락 감사 (Phase 0 계약 준수 검사)
bash "${BASH_SOURCE%/*}/audit-orchestration.sh" 2>/dev/null || true

rm -f "$START_FILE" 2>/dev/null || true
exit 0
