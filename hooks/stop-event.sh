#!/usr/bin/env bash
# Nova Stop Hook — session_end 이벤트 기록 (Sprint 1)
# Safe-default: 실패는 stderr WARN + exit 0

set -u

if [[ -n "${NOVA_DISABLE_EVENTS:-}" || "${NOVA_COEXIST:-0}" = "1" ]]; then
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
# stderr 리다이렉션 제거 — audit 경고가 사용자에게 전달되도록 함
bash "${BASH_SOURCE%/*}/audit-orchestration.sh" || true

# 미정리 teammate 팀 감사 (B7 antipattern — leader shutdown_request 누락 감지, v5.47.9+)
bash "${BASH_SOURCE%/*}/audit-teammates.sh" || true

# ── v3 marker 자동 렌더 (v5.44.0+) ──
# NOVA-STATE.md에 v3 marker가 있으면 registry-render-state.sh가 marker 영역을 자동 갱신.
# marker 부재(v2/v1 STATE)는 silent skip — 사용자 변경 없음. 실패해도 hook은 exit 0.
# AI 트림 의무 면제의 마지막 한 조각 — 시계열은 events.jsonl + 이 자동 렌더로 통합.
if [[ -f "NOVA-STATE.md" ]] && grep -qF "<!-- nova:registry-rendered:start -->" NOVA-STATE.md 2>/dev/null; then
  NOVA_ROOT_FOR_RENDER="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE%/*}/.." && pwd)}"
  if [[ -x "${NOVA_ROOT_FOR_RENDER}/scripts/registry-render-state.sh" ]]; then
    bash "${NOVA_ROOT_FOR_RENDER}/scripts/registry-render-state.sh" >/dev/null 2>&1 || true
  fi
fi

# ── Desktop notification (M-2, CC v2.1.141+ terminalSequence) ──
# NOVA_DESKTOP_NOTIFY=1일 때만 동작. 최근 5 이벤트에 commit_blocked 또는
# evaluator_verdict=FAIL이 있으면 bell + xterm/iTerm window title을 stdout JSON으로 emit.
# CC가 terminalSequence 필드를 읽어 controlling terminal 없이도 알림 전송.
# Escape 시퀀스: BEL(0x07) + ESC(0x1B)]0;<title>BEL  (xterm OSC 0)
if [[ "${NOVA_DESKTOP_NOTIFY:-0}" == "1" ]]; then
  EVENTS_FILE=".nova/events.jsonl"
  if [[ -f "$EVENTS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    TRIGGER=$(tail -n 5 "$EVENTS_FILE" 2>/dev/null \
      | jq -sr '[.[] | select(
          .event_type == "commit_blocked" or
          (.event_type == "evaluator_verdict" and (.extra.result // .extra.verdict // "") == "FAIL")
        )] | length' 2>/dev/null || echo 0)
    if [[ "$TRIGGER" =~ ^[0-9]+$ ]] && (( TRIGGER > 0 )); then
      # 명시적 byte 구성으로 견고성 확보 — 소스 파일에 control char 미포함
      NOTIFY_SEQ=$(printf '\007\033]0;Nova: BLOCKED\007')
      jq -cn --arg seq "$NOTIFY_SEQ" '{terminalSequence: $seq}' 2>/dev/null || true
    fi
  fi
fi

rm -f "$START_FILE" 2>/dev/null || true
exit 0
