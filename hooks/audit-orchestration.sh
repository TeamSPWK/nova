#!/usr/bin/env bash
# Nova Orchestration Audit — 세션 종료 시 MCP 추적 누락 감지
#
# Orchestrator 스킬(SKILL.md §Phase 0)이 반드시 호출하기로 약속한
# orchestration_start MCP 도구를 실제로 호출했는지 사후 검사한다.
#
# 판정 규칙:
#   - 세션 지속 시간 >= 180초 (3분) — simple 커맨드 제외
#   - .nova-orchestration.json에 현재 세션 이후 updatedAt 없음
#   → orchestration_missing 이벤트 기록
#
# Safe-default: 모든 에러 → stderr WARN + exit 0
# 감사 실패가 상위 파이프라인을 막지 않는다.

set -u

if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

THRESHOLD_SEC="${NOVA_ORCH_AUDIT_THRESHOLD:-180}"
START_FILE=".nova/session.start_epoch"
ORCH_FILE=".nova-orchestration.json"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "$START_FILE" ]]; then
  exit 0
fi

START_EPOCH=$(tr -d '[:space:]' < "$START_FILE" 2>/dev/null || echo 0)
NOW=$(date -u +%s)
if [[ -z "$START_EPOCH" || ! "$START_EPOCH" =~ ^[0-9]+$ ]]; then
  exit 0
fi

DURATION_SEC=$(( NOW - START_EPOCH ))
if [[ $DURATION_SEC -lt $THRESHOLD_SEC ]]; then
  # 짧은 세션은 단일 커맨드 가능성 — 감사 대상 아님
  exit 0
fi

# 세션 시작 시각 (ISO 8601 UTC)
SESSION_START_ISO=$(date -u -r "$START_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                    date -u -d "@$START_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

if [[ -z "$SESSION_START_ISO" ]]; then
  exit 0
fi

# .nova-orchestration.json에 현재 세션 이후 갱신된 항목이 있는가?
RECENT_ORCH_COUNT=0
if [[ -f "$ORCH_FILE" ]]; then
  RECENT_ORCH_COUNT=$(jq --arg since "$SESSION_START_ISO" \
    '[.[] | select(.updatedAt >= $since)] | length' \
    "$ORCH_FILE" 2>/dev/null || echo 0)
fi

if [[ "$RECENT_ORCH_COUNT" -eq 0 ]]; then
  # 누락 — orchestration_missing 이벤트 기록
  EXTRA=$(jq -cn \
    --argjson dur "$DURATION_SEC" \
    --arg threshold "$THRESHOLD_SEC" \
    --arg since "$SESSION_START_ISO" \
    '{
      duration_sec: $dur,
      threshold_sec: ($threshold | tonumber),
      session_start: $since,
      reason: "no_orchestration_updates_during_session"
    }')
  bash "${BASH_SOURCE%/*}/record-event.sh" orchestration_missing "$EXTRA" 2>/dev/null || true
fi

exit 0
