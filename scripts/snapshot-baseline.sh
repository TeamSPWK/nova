#!/usr/bin/env bash
# Nova — snapshot-baseline.sh
# v{version} baseline 스냅샷을 docs/baselines/{version}-baseline.md에 생성.
# ECC 흡수(P0-2/P0-3/P1-1) 이전 측정 기준선 — v5.22.0+ 후험 비교용.
#
# Usage:
#   bash scripts/snapshot-baseline.sh v5.20.0
#
# 출력: docs/baselines/{version}-baseline.md (5 섹션 markdown)

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"  # 예: v5.20.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="docs/baselines/${VERSION}-baseline.md"
EVENTS_FILE=".nova/events.jsonl"

mkdir -p docs/baselines

# ── 데이터 수집 (기본값으로 안전 처리) ──
LINES=0
SIZE_BYTES=0
V1_COUNT=0
V2_COUNT=0
ANALYZE_OUTPUT="(no data)"

if [[ -f "$EVENTS_FILE" ]]; then
  LINES=$(wc -l < "$EVENTS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  SIZE_BYTES=$(wc -c < "$EVENTS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  if command -v jq >/dev/null 2>&1; then
    V1_COUNT=$(jq -r 'select(.schema_version == 1)' "$EVENTS_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    V2_COUNT=$(jq -r 'select(.schema_version == 2)' "$EVENTS_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  fi

  # analyze-observations.sh 출력
  if [[ -x scripts/analyze-observations.sh ]] || [[ -f scripts/analyze-observations.sh ]]; then
    ANALYZE_OUTPUT=$(bash scripts/analyze-observations.sh 2>&1 || echo "(analyze 실행 실패)")
  fi
fi

# ── Evaluator FAIL률 (events.jsonl evaluator_verdict 집계) ──
EVAL_FAIL=0
EVAL_PASS=0
EVAL_COND=0
EVAL_TOTAL=0
if [[ -f "$EVENTS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  EVAL_FAIL=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "FAIL")] | length' "$EVENTS_FILE" 2>/dev/null || echo 0)
  EVAL_PASS=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "PASS")] | length' "$EVENTS_FILE" 2>/dev/null || echo 0)
  EVAL_COND=$(jq -s '[.[] | select(.event_type == "evaluator_verdict" and .extra.verdict == "CONDITIONAL")] | length' "$EVENTS_FILE" 2>/dev/null || echo 0)
  EVAL_TOTAL=$((EVAL_FAIL + EVAL_PASS + EVAL_COND))
fi

# ── tools 호출 빈도 Top 10 (tool_call 이벤트) ──
TOOLS_TOP10=""
if [[ -f "$EVENTS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  TOOLS_TOP10=$(jq -r '
    select(.event_type == "tool_call") |
    (.extra.tool // .extra.tool_name // "unknown")
  ' "$EVENTS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | awk '{printf "  %s: %s\n", $2, $1}' || echo "  (no data)")
  [[ -z "$TOOLS_TOP10" ]] && TOOLS_TOP10="  (no tool_call events)"
fi

# ── 메타 ──
JQ_VERSION=$(jq --version 2>/dev/null || echo "n/a")
OS_NAME=$(uname -s)
TS=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

# ── markdown 작성 ──
{
  echo "# Nova ${VERSION} Baseline Snapshot"
  echo ""
  echo "> 생성: ${TS}"
  echo "> 목적: ECC 흡수(P0-2 비용 가이드 / P0-3 Strategic Compact / P1-1 audit-self) 이전 측정 기준선. v5.22.0+ 후험 비교."
  echo ""
  echo "## 1. events.jsonl 통계"
  echo ""
  echo "- 라인 수: ${LINES}"
  echo "- 파일 크기: ${SIZE_BYTES} bytes"
  echo "- schema_version=1 record: ${V1_COUNT}"
  echo "- schema_version=2 record: ${V2_COUNT}"
  echo ""
  echo "## 2. analyze-observations 출력"
  echo ""
  echo '```'
  echo "$ANALYZE_OUTPUT"
  echo '```'
  echo ""
  echo "## 3. Evaluator FAIL률"
  echo ""
  echo "- 총 evaluator_verdict 이벤트: ${EVAL_TOTAL}"
  echo "- PASS: ${EVAL_PASS}"
  echo "- CONDITIONAL: ${EVAL_COND}"
  echo "- FAIL: ${EVAL_FAIL}"
  if [[ "$EVAL_TOTAL" -gt 0 ]]; then
    FAIL_PCT=$(python3 -c "print(f'{${EVAL_FAIL}/${EVAL_TOTAL}*100:.1f}')" 2>/dev/null || echo "n/a")
    echo "- FAIL 비율: ${FAIL_PCT}%"
  else
    echo "- FAIL 비율: n/a (이벤트 없음)"
  fi
  echo ""
  echo "## 4. tools 호출 빈도 Top 10"
  echo ""
  echo '```'
  echo "$TOOLS_TOP10"
  echo '```'
  echo ""
  echo "## 5. 측정 메타"
  echo ""
  echo "- Nova 버전: ${VERSION}"
  echo "- 측정 일시: ${TS}"
  echo "- jq 버전: ${JQ_VERSION}"
  echo "- OS: ${OS_NAME}"
  echo "- 측정 명령: \`bash scripts/snapshot-baseline.sh ${VERSION}\`"
} > "$OUT"

echo "✅ baseline 스냅샷 저장: $OUT"
