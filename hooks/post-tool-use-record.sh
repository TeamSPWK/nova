#!/usr/bin/env bash
# Nova PostToolUse Hook — tool_use_post 이벤트 기록 (v5.30.0)
#
# Claude Code v2.1.119+ PostToolUse stdin payload:
#   { "tool_name": "Bash", "tool_input": {...}, "tool_response": {...},
#     "duration_ms": 123, ... }
#
# 본 훅은 도구별 실행 시간(duration_ms)과 성공/실패만 기록한다.
# tool_input/tool_response 본문은 privacy 위험으로 절대 기록하지 않는다.
# Safe-default: exit 0 (관찰성 실패가 도구 호출을 실패시키지 않는다)

if [[ -n "${NOVA_DISABLE_EVENTS:-}" || "${NOVA_COEXIST:-0}" = "1" ]]; then
  exit 0
fi

TOOL="unknown"
DURATION=0
OK=true

if [[ ! -t 0 ]] && command -v jq >/dev/null 2>&1; then
  INPUT=$(cat 2>/dev/null || true)
  if [[ -n "$INPUT" ]]; then
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
    # floor로 float→int 안전 변환 (CC가 소수점 ms를 보낼 가능성 대비)
    DURATION=$(echo "$INPUT" | jq -r '(.duration_ms // 0) | floor' 2>/dev/null || echo 0)
    # tool_response.error 또는 tool_response.is_error → 실패로 표시
    ERR=$(echo "$INPUT" | jq -r '.tool_response.error // .tool_response.is_error // empty' 2>/dev/null || true)
    if [[ -n "$ERR" && "$ERR" != "false" && "$ERR" != "null" ]]; then
      OK=false
    fi
  fi
fi

# 정수 음성 검증 (jq가 비정상 값 리턴 시 기본 0). 음수도 거부.
case "$DURATION" in
  ''|-*|*[!0-9]*) DURATION=0 ;;
esac

NOVA_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

EXTRA=$(jq -cn \
  --arg t "$TOOL" \
  --argjson d "$DURATION" \
  --argjson ok "$OK" \
  '{tool: $t, duration_ms: $d, ok: $ok}' 2>/dev/null || echo '{}')

bash "${NOVA_ROOT}/hooks/record-event.sh" tool_use_post "$EXTRA" 2>/dev/null &

# ── §16 impl-tracker (v5.32.0+) ─────────────────────────────────────────
# Edit/Write/MultiEdit 성공 시 *코드 파일* 변경 누적 → .nova/impl-tracker.json.
# 임계(3파일+) 도달하면 threshold_hit=true. 1시간 자동 만료(새 카운트 시작).
# Reset: release.sh 성공 시. session-start가 미해소 시 advisory 노출.
if command -v jq >/dev/null 2>&1 && [[ "$OK" = "true" ]]; then
  case "$TOOL" in
    Edit|Write|MultiEdit)
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
      if [[ -n "$FILE_PATH" ]]; then
        # 코드 파일 휴리스틱: 보편 소스 확장자만, 자동/문서 영역 제외.
        case "$FILE_PATH" in
          *.sh|*.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.rb|*.swift|*.kt|*.java|*.c|*.cpp|*.h|*.hpp)
            case "$FILE_PATH" in
              */NOVA-STATE.md|*/.nova/*|*/docs/*) : ;;
              *)
                mkdir -p .nova 2>/dev/null
                TRACKER=".nova/impl-tracker.json"
                NOW=$(date +%s)
                CUR_COUNT=0
                CUR_FIRST=$NOW
                if [[ -f "$TRACKER" ]]; then
                  CUR_COUNT=$(jq -r '.count // 0' "$TRACKER" 2>/dev/null || echo 0)
                  CUR_FIRST=$(jq -r '.first_set_epoch // 0' "$TRACKER" 2>/dev/null || echo 0)
                  AGE=$((NOW - CUR_FIRST))
                  if (( AGE > 3600 )); then
                    CUR_COUNT=0
                    CUR_FIRST=$NOW
                  fi
                fi
                NEW_COUNT=$((CUR_COUNT + 1))
                HIT="false"
                (( NEW_COUNT >= 3 )) && HIT="true"
                jq -cn \
                  --argjson c "$NEW_COUNT" \
                  --argjson f "$CUR_FIRST" \
                  --argjson n "$NOW" \
                  --argjson h "$HIT" \
                  '{count:$c, first_set_epoch:$f, last_set_epoch:$n, threshold_hit:$h}' \
                  > "$TRACKER" 2>/dev/null || true
                ;;
            esac
            ;;
        esac
      fi
      ;;
  esac
fi

exit 0
