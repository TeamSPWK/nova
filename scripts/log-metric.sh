#!/usr/bin/env bash
# Nova — 메트릭 로그 append + 회전
# Usage: bash scripts/log-metric.sh --event <name> [--key val ...]
# Example:
#   bash scripts/log-metric.sh --event ui_audit_triggered --files 5 --loc 42
#   bash scripts/log-metric.sh --event ui_audit_opt_out --reason flag

set -euo pipefail

NOVA_DIR=".nova"
METRICS_FILE="$NOVA_DIR/metrics.jsonl"
ROTATE_THRESHOLD=1000

# 인자 파싱: key-value 쌍을 JSON 객체로 조립
EVENT=""
EXTRA_JSON="{}"

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    --*)
      KEY="${1#--}"
      VAL="$2"
      # 숫자면 number, 아니면 string으로
      if echo "$VAL" | grep -qE '^-?[0-9]+$'; then
        EXTRA_JSON=$(echo "$EXTRA_JSON" | jq --arg k "$KEY" --argjson v "$VAL" '. + {($k): $v}' 2>/dev/null || echo "$EXTRA_JSON")
      else
        EXTRA_JSON=$(echo "$EXTRA_JSON" | jq --arg k "$KEY" --arg v "$VAL" '. + {($k): $v}' 2>/dev/null || echo "$EXTRA_JSON")
      fi
      shift 2
      ;;
    *) shift ;;
  esac
done

if [ -z "$EVENT" ]; then
  echo "[Nova] log-metric: --event 필수" >&2
  exit 0
fi

# .nova/ 디렉토리 생성
if ! mkdir -p "$NOVA_DIR" 2>/dev/null; then
  echo "[Nova] log-metric: .nova/ 디렉토리 생성 실패 — 메트릭 스킵" >&2
  exit 0
fi

# 타임스탬프 (KST)
TS=$(date '+%Y-%m-%dT%H:%M:%S+09:00' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')

# JSON 1줄 생성
LINE=$(echo "$EXTRA_JSON" | jq -c --arg ts "$TS" --arg ev "$EVENT" \
  '{ts: $ts, event: $ev} + .' 2>/dev/null || echo "{\"ts\":\"$TS\",\"event\":\"$EVENT\"}")

# 회전 체크 (기존 파일이 1000줄 초과 시)
if [ -f "$METRICS_FILE" ]; then
  LINE_COUNT=$(wc -l < "$METRICS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "$LINE_COUNT" -ge "$ROTATE_THRESHOLD" ]; then
    YYYYMM=$(date '+%Y%m' 2>/dev/null || echo "000000")
    ROTATE_TARGET="$NOVA_DIR/metrics.${YYYYMM}.jsonl"
    # 이미 같은 이름이 있으면 숫자 suffix 추가
    if [ -f "$ROTATE_TARGET" ]; then
      ROTATE_TARGET="$NOVA_DIR/metrics.${YYYYMM}.$(date '+%H%M%S').jsonl"
    fi
    if mv "$METRICS_FILE" "$ROTATE_TARGET" 2>/dev/null; then
      : # 성공
    else
      echo "[Nova] log-metric: 메트릭 회전 실패 — 계속 진행" >&2
    fi
  fi
fi

# append
if ! echo "$LINE" >> "$METRICS_FILE" 2>/dev/null; then
  echo "[Nova] log-metric: metrics.jsonl 쓰기 실패 — 메트릭 스킵" >&2
  exit 0
fi
