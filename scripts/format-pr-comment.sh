#!/usr/bin/env bash
# nova-ci JSON 판정 결과 → GitHub PR 코멘트 마크다운 변환
# Usage: echo '{"verdict":"PASS",...}' | bash scripts/format-pr-comment.sh
#
# 입력 JSON 스키마:
#   verdict:     "PASS" | "CONDITIONAL" | "FAIL"
#   intensity:   "Lite" | "Standard" | "Full"
#   summary:     string (선택)
#   counts:      { critical: int, high: int, warning: int }
#   issues:      [{ severity, location, issue, action }]
#   known_gaps:  string[]  (CONDITIONAL 시 미커버 영역)

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq가 설치되어 있지 않습니다." >&2
  exit 1
fi

INPUT=$(cat)

# ── 필드 파싱 ──
VERDICT=$(echo "$INPUT" | jq -r '.verdict // "UNKNOWN"')
INTENSITY=$(echo "$INPUT" | jq -r '.intensity // "Lite"')
SUMMARY=$(echo "$INPUT" | jq -r '.summary // ""')

CRITICAL=$(echo "$INPUT" | jq -r '.counts.critical // 0')
HIGH=$(echo "$INPUT" | jq -r '.counts.high // 0')
WARNING=$(echo "$INPUT" | jq -r '.counts.warning // 0')

# ── 판정 배지 ──
case "$VERDICT" in
  PASS)        BADGE="🟢 PASS" ;;
  CONDITIONAL) BADGE="🟡 CONDITIONAL" ;;
  FAIL)        BADGE="🔴 FAIL" ;;
  *)           BADGE="⚪ $VERDICT" ;;
esac

# ══════════════════════════════════════════════════
# 출력 — 첫 줄은 반드시 코멘트 식별자 마커
# ══════════════════════════════════════════════════

echo "<!-- nova-ci-verdict -->"
echo ""
echo "## Nova CI — ${BADGE}"
echo ""
echo "> **검증 강도**: ${INTENSITY} &nbsp;|&nbsp; Critical **${CRITICAL}** / High **${HIGH}** / Warning **${WARNING}**"
echo ""

if [[ -n "$SUMMARY" ]]; then
  echo "${SUMMARY}"
  echo ""
fi

# ── 이슈 테이블 ──
ISSUE_COUNT=$(echo "$INPUT" | jq '.issues | length')

if [[ "$ISSUE_COUNT" -gt 0 ]]; then
  echo "<details>"
  echo "<summary>이슈 목록 (${ISSUE_COUNT}건)</summary>"
  echo ""
  echo "| # | 심각도 | 파일:라인 | 이슈 | 권장 조치 |"
  echo "|---|--------|-----------|------|-----------|"

  echo "$INPUT" | jq -r '
    [ .issues[] ] | to_entries[] |
    "| \(.key + 1) | \(.value.severity // "-") | `\(.value.location // "-")` | \(.value.issue // "-") | \(.value.action // "-") |"
  '

  echo ""
  echo "</details>"
  echo ""
fi

# ── Known Gaps (CONDITIONAL 전용) ──
if [[ "$VERDICT" == "CONDITIONAL" ]]; then
  GAP_COUNT=$(echo "$INPUT" | jq '.known_gaps | length')
  if [[ "$GAP_COUNT" -gt 0 ]]; then
    echo "### Known Gaps (미커버 영역)"
    echo ""
    echo "$INPUT" | jq -r '.known_gaps[]' | while IFS= read -r gap; do
      echo "- ${gap}"
    done
    echo ""
  fi
fi

echo "---"
echo "_by Nova CI_"
