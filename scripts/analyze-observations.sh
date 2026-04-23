#!/usr/bin/env bash
# Nova — analyze-observations.sh
# .nova/events.jsonl에서 행동 패턴을 분석해 상위 N개 빈도 패턴을 stdout으로 출력.
# 자동 승격 금지 — 결과는 사용자 승인 후에만 CPS Problem 초안으로 승격한다.
#
# Usage:
#   bash scripts/analyze-observations.sh [--top N] [--pattern tool-frequency|sequence|failures] [JSONL_FILE]
#
# Options:
#   --top N          상위 N개 출력 (기본: 10)
#   --pattern TYPE   분석 패턴 유형 (기본: tool-frequency)
#                    tool-frequency : 도구별 호출 빈도
#                    sequence       : 도구 시퀀스 (Read→Grep→Edit 등 N번 반복)
#                    failures       : 반복 실패 패턴 (evaluator FAIL/CONDITIONAL)
#   JSONL_FILE       이벤트 파일 경로 (기본: .nova/events.jsonl)

set -euo pipefail

# ── 기본값 ──
TOP_N=10
PATTERN="tool-frequency"
EVENTS_FILE=".nova/events.jsonl"

# ── 인수 파싱 ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)
      if [[ -z "${2:-}" || ! "${2}" =~ ^[0-9]+$ ]]; then
        echo "오류: --top 다음에 숫자를 지정하세요. 예: --top 5" >&2
        exit 1
      fi
      TOP_N="$2"
      shift 2
      ;;
    --top=*)
      TOP_N="${1#--top=}"
      shift
      ;;
    --pattern)
      if [[ -z "${2:-}" ]]; then
        echo "오류: --pattern 다음에 유형을 지정하세요 (tool-frequency|sequence|failures)" >&2
        exit 1
      fi
      PATTERN="$2"
      shift 2
      ;;
    --pattern=*)
      PATTERN="${1#--pattern=}"
      shift
      ;;
    -*)
      echo "알 수 없는 옵션: $1" >&2
      echo "Usage: bash $0 [--top N] [--pattern tool-frequency|sequence|failures] [JSONL_FILE]" >&2
      exit 1
      ;;
    *)
      EVENTS_FILE="$1"
      shift
      ;;
  esac
done

# ── 패턴 유효성 검사 ──
case "$PATTERN" in
  tool-frequency|sequence|failures)
    ;;
  *)
    echo "오류: 지원하지 않는 패턴: '$PATTERN'" >&2
    echo "지원 패턴: tool-frequency | sequence | failures" >&2
    exit 1
    ;;
esac

# ── 파일 존재 확인 ──
if [[ ! -f "$EVENTS_FILE" ]]; then
  echo "━━━ Nova Behavior Analysis ━━━━━━━━━━━━━━━━━━━━━"
  echo "  No observations — events.jsonl 없음: $EVENTS_FILE"
  echo "  관찰 데이터를 수집하려면 세션을 실행하세요."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# ── jq 의존성 확인 ──
if ! command -v jq >/dev/null 2>&1; then
  echo "오류: jq가 필요합니다. brew install jq 또는 apt-get install jq로 설치하세요." >&2
  exit 1
fi

# ── 이벤트 수 확인 ──
TOTAL_LINES=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
if [[ "$TOTAL_LINES" -eq 0 ]]; then
  echo "━━━ Nova Behavior Analysis ━━━━━━━━━━━━━━━━━━━━━"
  echo "  No observations — events.jsonl이 비어 있습니다: $EVENTS_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

echo "━━━ Nova Behavior Analysis ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  파일: $EVENTS_FILE"
echo "  이벤트 수: $TOTAL_LINES"
echo "  패턴: $PATTERN  |  상위: $TOP_N"
echo "  ⚠️  자동 승격 금지 — 결과는 사용자 승인 후 CPS Problem 초안으로 활용"
echo ""

# ──────────────────────────────────────────────────────────
# 패턴별 분석
# ──────────────────────────────────────────────────────────

analyze_tool_frequency() {
  echo "  ── 도구별 호출 빈도 ──"
  echo ""

  # tool_call 이벤트의 extra.tool 필드 집계 (v5.18.0 PreToolUse 훅)
  local tool_result
  tool_result=$(jq -r '
    select(.event_type == "tool_call") |
    (.extra.tool // .extra.tool_name // "unknown")
  ' "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")

  echo "  [도구 호출 빈도 (tool_call 이벤트)]"
  if [[ -z "$tool_result" ]]; then
    echo "  아직 관측 데이터 없음 — v5.18.0 PreToolUse 훅 활성 후 7일 대기 권장"
  else
    echo "$tool_result" | awk '{printf "  %3d  %s\n", $1, $2}'
  fi

  echo ""

  # 메타 이벤트 빈도 (session_start/end 등)
  local meta_result
  meta_result=$(jq -r '
    select(.event_type != null) |
    if .event_type == "session_start" or
       .event_type == "session_end" or
       .event_type == "evaluator_verdict" or
       .event_type == "sprint_started" or
       .event_type == "sprint_completed" or
       .event_type == "blocker_raised" or
       .event_type == "blocker_resolved" or
       .event_type == "plan_created" or
       .event_type == "jury_verdict" or
       .event_type == "tool_constraint_violation" or
       .event_type == "tool_constraint_bypass" or
       .event_type == "phase_transition" or
       .event_type == "orchestration_missing" then
      .event_type
    else
      empty
    end
  ' "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")

  echo "  [메타 이벤트]"
  if [[ -n "$meta_result" ]]; then
    echo "$meta_result" | awk '{printf "  %3d  %s\n", $1, $2}'
  else
    echo "  데이터 없음"
  fi
}

analyze_sequence() {
  echo "  ── 도구 시퀀스 패턴 (슬라이딩 윈도우 2~3연속) ──"
  echo ""

  # 타임스탬프 순으로 이벤트 타입 나열 후 2-gram, 3-gram 추출
  # session_start는 같은 session_id 내 첫 번째 항목만 유지 (debounce 후에도 중복 제거)
  local events_sorted
  events_sorted=$(jq -r '
    [.timestamp, (.session_id // ""), (.event_type // "unknown")] | @tsv
  ' "$EVENTS_FILE" 2>/dev/null | sort -k1 | awk -F'\t' '
    {
      etype = $3
      sid   = $2
      key   = sid "_session_start"
      if (etype == "session_start") {
        if (!seen[key]++) { print etype }
      } else {
        print etype
      }
    }
  ')

  if [[ -z "$events_sorted" ]]; then
    echo "  시퀀스 분석 불가 — 타임스탬프 필드가 없거나 이벤트가 비어 있습니다."
    exit 0
  fi

  local event_array=()
  while IFS= read -r line; do
    event_array+=("$line")
  done <<< "$events_sorted"

  local count=${#event_array[@]}

  echo "  [2-gram 시퀀스 (상위 $TOP_N)]"
  if [[ $count -ge 2 ]]; then
    for ((i=0; i<count-1; i++)); do
      echo "${event_array[$i]} → ${event_array[$((i+1))]}"
    done | sort | uniq -c | sort -rn | head -"$TOP_N" | \
      awk '{count=$1; $1=""; seq=substr($0,2); printf "  %3d  %s\n", count, seq}'
  else
    echo "  데이터 부족 (이벤트 2개 이상 필요)"
  fi

  echo ""
  echo "  [3-gram 시퀀스 (상위 $TOP_N)]"
  if [[ $count -ge 3 ]]; then
    for ((i=0; i<count-2; i++)); do
      echo "${event_array[$i]} → ${event_array[$((i+1))]} → ${event_array[$((i+2))]}"
    done | sort | uniq -c | sort -rn | head -"$TOP_N" | \
      awk '{count=$1; $1=""; seq=substr($0,2); printf "  %3d  %s\n", count, seq}'
  else
    echo "  데이터 부족 (이벤트 3개 이상 필요)"
  fi
}

analyze_failures() {
  echo "  ── 반복 실패 패턴 ──"
  echo ""

  # evaluator_verdict FAIL/CONDITIONAL 집계
  local fail_count conditional_count pass_count
  fail_count=$(jq -r 'select(.event_type == "evaluator_verdict" and .extra.verdict == "FAIL") | .extra.target // "unknown"' \
    "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")
  conditional_count=$(jq -r 'select(.event_type == "evaluator_verdict" and .extra.verdict == "CONDITIONAL") | .extra.target // "unknown"' \
    "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")
  pass_count=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "PASS")] | length' \
    "$EVENTS_FILE" 2>/dev/null || echo 0)

  local total_fail
  total_fail=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "FAIL")] | length' \
    "$EVENTS_FILE" 2>/dev/null || echo 0)
  local total_cond
  total_cond=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "CONDITIONAL")] | length' \
    "$EVENTS_FILE" 2>/dev/null || echo 0)

  echo "  [Evaluator 판정 요약]"
  echo "  PASS: $pass_count  |  CONDITIONAL: $total_cond  |  FAIL: $total_fail"
  echo ""

  if [[ -n "$fail_count" ]]; then
    echo "  [FAIL 타겟별 빈도 (상위 $TOP_N)]"
    echo "$fail_count" | awk '{printf "  %3d  FAIL  target=%s\n", $1, $2}'
    echo ""
  fi

  if [[ -n "$conditional_count" ]]; then
    echo "  [CONDITIONAL 타겟별 빈도 (상위 $TOP_N)]"
    echo "$conditional_count" | awk '{printf "  %3d  CONDITIONAL  target=%s\n", $1, $2}'
    echo ""
  fi

  # blocker 패턴
  local blocker_count
  blocker_count=$(jq -r 'select(.event_type == "blocker_raised") | .extra.blocker_type // "unknown"' \
    "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")
  if [[ -n "$blocker_count" ]]; then
    echo "  [블로커 타입별 빈도 (상위 $TOP_N)]"
    echo "$blocker_count" | awk '{printf "  %3d  %s\n", $1, $2}'
    echo ""
  fi

  # tool_constraint_violation 패턴
  local violation_count
  violation_count=$(jq -r 'select(.event_type == "tool_constraint_violation") | .extra.matched_pattern // "unknown"' \
    "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -"$TOP_N")
  if [[ -n "$violation_count" ]]; then
    echo "  [도구 제약 위반 패턴 (상위 $TOP_N)]"
    echo "$violation_count" | awk '{printf "  %3d  %s\n", $1, $2}'
  fi

  # orchestration_missing 집계
  local orch_missing_count
  orch_missing_count=$(jq -s '[.[] | select(.event_type == "orchestration_missing")] | length' \
    "$EVENTS_FILE" 2>/dev/null || echo 0)
  if [[ "$orch_missing_count" -gt 0 ]]; then
    local orch_avg_dur
    orch_avg_dur=$(jq -s '[.[] | select(.event_type == "orchestration_missing") | .extra.duration_sec // 0] | if length > 0 then add/length else 0 end | floor' \
      "$EVENTS_FILE" 2>/dev/null || echo 0)
    echo "  [Phase 0 orchestration 누락]"
    echo "  누락 횟수: $orch_missing_count  |  평균 세션 시간: ${orch_avg_dur}초"
    echo ""
  fi

  if [[ -z "$fail_count" && -z "$conditional_count" && -z "$blocker_count" && -z "$violation_count" && "$orch_missing_count" -eq 0 ]]; then
    echo "  실패 패턴 없음 — 기록된 FAIL/CONDITIONAL/blocker/violation/orchestration_missing 이벤트가 없습니다."
  fi
}

# ── 패턴 실행 ──
case "$PATTERN" in
  tool-frequency)
    analyze_tool_frequency
    ;;
  sequence)
    analyze_sequence
    ;;
  failures)
    analyze_failures
    ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  /nova:evolve --from-observations 로 CPS Problem 초안 생성 가능"
echo "  (자동 승격 금지 — 사용자 승인 필수)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
