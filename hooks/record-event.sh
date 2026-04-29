#!/usr/bin/env bash
# Nova record-event.sh — JSONL 이벤트 기록 (Sprint 1)
#
# 사용법:
#   bash hooks/record-event.sh <event_type> [<extra_json>]
#
# extra payload 권장 nullable 필드 (schema v2, v5.20.0+):
#   - tool         : 도구 이름 (예: "Bash", "Read"). PostToolUse 훅(v5.21.0+)에서 채움
#   - duration_ms  : 도구 실행 시간 (밀리초). PostToolUse stdin payload에서 추출
#   - pattern_id   : 패턴 식별자 (8자 hex). evolve_decision 이벤트에만 명시 기록
#   - decision     : "accept" 또는 "reject" (evolve_decision 이벤트일 때만)
# confidence는 events.jsonl에 기록하지 않는다 — analyze-observations.sh가 산출 시점에 in-memory 계산.
#
# 환경변수:
#   NOVA_DISABLE_EVENTS=1      → 즉시 exit 0 (옵트아웃)
#   NOVA_EVENTS_PATH=<path>    → 기본 .nova/events.jsonl 대신 지정 경로
#   CI=true                    → ${CI_ARTIFACTS:-.}/nova-events/events.jsonl로 자동 치환
#   NOVA_EVENTS_MAX_SIZE=<bytes>  → rotation 크기 (기본 10MB)
#   NOVA_EVENTS_MAX_FILES=<int>   → rotation 보관 파일 수 (기본 5)
#
# Safe-default: 모든 에러 → stderr WARN + exit 0
# 관찰성 실패가 상위 skill을 마비시키지 않는다.

set -u

# ── 옵트아웃 ──
if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

EVENT_TYPE="${1:-}"
EXTRA_JSON="${2:-{\}}"

if [[ -z "$EVENT_TYPE" ]]; then
  echo "[nova:event] WARN: event_type 누락 — skip" >&2
  exit 0
fi

# jq 필수
if ! command -v jq >/dev/null 2>&1; then
  echo "[nova:event] WARN: jq 미설치 — 이벤트 기록 skip" >&2
  exit 0
fi

# ── 경로 결정 ──
if [[ -n "${NOVA_EVENTS_PATH:-}" ]]; then
  EVENTS_FILE="$NOVA_EVENTS_PATH"
elif [[ -n "${CI:-}" ]]; then
  EVENTS_FILE="${CI_ARTIFACTS:-.}/nova-events/events.jsonl"
else
  EVENTS_FILE=".nova/events.jsonl"
fi

EVENTS_DIR="$(dirname "$EVENTS_FILE")"
LOCK_FILE="${EVENTS_DIR}/.lock"
SESSION_ID_FILE="${EVENTS_DIR}/session.id"

mkdir -p "$EVENTS_DIR" 2>/dev/null || {
  echo "[nova:event] WARN: mkdir $EVENTS_DIR 실패 — skip" >&2
  exit 0
}

# ── Session ID (프로젝트/세션 격리, privacy-safe, race-safe atomic 발급) ──
SESSION_ID=""
if [[ -f "$SESSION_ID_FILE" ]]; then
  SESSION_ID=$(tr -d '\r\n' < "$SESSION_ID_FILE" 2>/dev/null || true)
fi
if [[ -z "$SESSION_ID" ]]; then
  RAND=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 16)
  [[ -z "$RAND" ]] && RAND="$(date +%s%N | tail -c 16)"
  CANDIDATE=$(printf '%s%s%s' "$PWD" "$$" "$RAND" | shasum -a 256 2>/dev/null | head -c 12)
  [[ -z "$CANDIDATE" ]] && CANDIDATE="unknown"
  # Race-safe: noclobber(-C)로 먼저 쓴 프로세스만 승자. 나머지는 기존 파일 읽기.
  if ( set -C; echo "$CANDIDATE" > "$SESSION_ID_FILE" ) 2>/dev/null; then
    SESSION_ID="$CANDIDATE"
  else
    SESSION_ID=$(tr -d '\r\n' < "$SESSION_ID_FILE" 2>/dev/null || true)
    [[ -z "$SESSION_ID" ]] && SESSION_ID="$CANDIDATE"  # fallback
  fi
fi

# CWD hash (경로 평문 저장 회피)
CWD_HASH=$(printf '%s' "$PWD" | shasum -a 256 2>/dev/null | head -c 8)
[[ -z "$CWD_HASH" ]] && CWD_HASH="unknown"

# ── Timestamps (GNU/BSD 호환) ──
TS_EPOCH=$(date -u +%s)
TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null | grep -E '\.[0-9]{3}Z$' || true)
if [[ -z "$TS_ISO" ]]; then
  TS_ISO=$(python3 -c '
import datetime, time
ms = int((time.time() % 1) * 1000)
print(datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.") + f"{ms:03d}Z")
' 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
fi

MONOTONIC_NS=$(python3 -c 'import time; print(time.monotonic_ns())' 2>/dev/null || echo "$((TS_EPOCH * 1000000000))")

# ── Nova version ──
VERSION_FILE="${BASH_SOURCE%/*}/../scripts/.nova-version"
NOVA_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || echo "unknown")

# ── Privacy 필터 ──
PRIVACY_FILTER="${BASH_SOURCE%/*}/_privacy-filter.py"
FILTERED=""
if [[ -f "$PRIVACY_FILTER" ]] && command -v python3 >/dev/null 2>&1; then
  FILTERED=$(printf '%s' "$EXTRA_JSON" | python3 "$PRIVACY_FILTER" 2>/dev/null || true)
fi
if [[ -z "$FILTERED" ]] || ! echo "$FILTERED" | jq -e '._extra' >/dev/null 2>&1; then
  # 필터 실패 시 보수적으로 extra 전체를 redacted로 마킹 (원본 노출 방지)
  REDACTED=true
  REASONS='["filter_unavailable"]'
  EXTRA_CLEAN='{}'
else
  REDACTED=$(echo "$FILTERED" | jq -r '._redacted')
  REASONS=$(echo "$FILTERED" | jq -c '._reasons')
  EXTRA_CLEAN=$(echo "$FILTERED" | jq -c '._extra')
fi

# ── JSON 라인 조립 ──
LINE=$(jq -cn \
  --arg ts "$TS_ISO" \
  --argjson ts_epoch "$TS_EPOCH" \
  --argjson mono "$MONOTONIC_NS" \
  --arg sid "$SESSION_ID" \
  --arg etype "$EVENT_TYPE" \
  --arg nv "$NOVA_VERSION" \
  --argjson red "$REDACTED" \
  --argjson reasons "$REASONS" \
  --argjson extra "$EXTRA_CLEAN" \
  --arg cwdh "$CWD_HASH" \
  '{
    schema_version: 2,
    timestamp: $ts,
    timestamp_epoch: $ts_epoch,
    monotonic_ns: $mono,
    session_id: $sid,
    event_type: $etype,
    nova_version: $nv,
    redacted: $red,
    redaction_reasons: $reasons,
    cwd_hash: $cwdh,
    extra: $extra
  }' 2>/dev/null || true)

if [[ -z "$LINE" ]]; then
  echo "[nova:event] WARN: JSON 조립 실패 — skip" >&2
  exit 0
fi

# ── Lock 획득 (flock 우선, mkdir fallback) ──
MAX_SIZE=${NOVA_EVENTS_MAX_SIZE:-10485760}
MAX_FILES=${NOVA_EVENTS_MAX_FILES:-5}
USE_FLOCK=0

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    USE_FLOCK=1
    exec 9>"$LOCK_FILE" 2>/dev/null || return 1
    flock -x -w 3 9 || return 1
    return 0
  fi
  local tries=30
  while (( tries > 0 )); do
    if mkdir "$LOCK_FILE" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    (( tries-- ))
  done
  return 1
}

release_lock() {
  if (( USE_FLOCK == 1 )); then
    exec 9>&- 2>/dev/null || true
  else
    rmdir "$LOCK_FILE" 2>/dev/null || true
  fi
}

if ! acquire_lock; then
  echo "[nova:event] WARN: lock 획득 실패(3초) — skip" >&2
  exit 0
fi

# ── Rotation 체크 ──
file_size() {
  local f="$1"
  stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0
}

if [[ -f "$EVENTS_FILE" ]]; then
  SIZE=$(file_size "$EVENTS_FILE")
  LINE_LEN=$(printf '%s\n' "$LINE" | wc -c | tr -d ' ')
  if (( SIZE + LINE_LEN > MAX_SIZE )); then
    for (( i=MAX_FILES-1; i>=1; i-- )); do
      if [[ -f "${EVENTS_FILE}.${i}" ]]; then
        mv "${EVENTS_FILE}.${i}" "${EVENTS_FILE}.$((i+1))" 2>/dev/null || true
      fi
    done
    mv "$EVENTS_FILE" "${EVENTS_FILE}.1" 2>/dev/null || true
    for (( i=MAX_FILES+1; i<=MAX_FILES+5; i++ )); do
      rm -f "${EVENTS_FILE}.${i}" 2>/dev/null || true
    done
    # 새 파일 + rotation_from 마커
    ROT_LINE=$(jq -cn --arg from "${EVENTS_FILE}.1" --arg ts "$TS_ISO" \
      '{schema_version:1, event_type:"rotation_marker", rotation_from:$from, timestamp:$ts}')
    printf '%s\n' "$ROT_LINE" > "$EVENTS_FILE"
    chmod 600 "$EVENTS_FILE" 2>/dev/null || true
  fi
fi

# ── Append ──
printf '%s\n' "$LINE" >> "$EVENTS_FILE" 2>/dev/null || {
  echo "[nova:event] WARN: append 실패 — skip" >&2
  release_lock
  exit 0
}
chmod 600 "$EVENTS_FILE" 2>/dev/null || true

release_lock
exit 0
