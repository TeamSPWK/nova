#!/usr/bin/env bash
# nova-ci.sh — Nova CI PR 코드 리뷰 실행
# Usage: nova-ci.sh --level <level> --changed-files <file> --diff <file> [--design-doc <file>]
# Output: verdict JSON (stdout)
#
# 출력 JSON 스키마:
#   verdict:    "PASS" | "CONDITIONAL" | "FAIL"
#   intensity:  "Lite" | "Standard" | "Full"
#   summary:    string
#   counts:     { critical: int, high: int, warning: int }
#   issues:     [{ severity, location, issue, action }]
#   known_gaps: string[]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# ── 인자 파싱 ──
LEVEL="auto"
CHANGED_FILES=""
DIFF_FILE=""
DESIGN_DOC=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --level)         LEVEL="$2";         shift 2 ;;
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --diff)          DIFF_FILE="$2";     shift 2 ;;
    --design-doc)    DESIGN_DOC="$2";    shift 2 ;;
    *) echo "::error::알 수 없는 인수: $1" >&2; exit 1 ;;
  esac
done

# ── 필수 인수 검증 ──
if [[ -z "$CHANGED_FILES" || -z "$DIFF_FILE" ]]; then
  echo "::error::--changed-files와 --diff는 필수 인수입니다." >&2
  exit 1
fi

if [[ ! -f "$CHANGED_FILES" ]]; then
  echo "::error::changed-files 파일을 찾을 수 없습니다: $CHANGED_FILES" >&2
  exit 1
fi

if [[ ! -f "$DIFF_FILE" ]]; then
  echo "::error::diff 파일을 찾을 수 없습니다: $DIFF_FILE" >&2
  exit 1
fi

# ── API 키 확인 ──
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "::error::ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다. GitHub Secret에 ANTHROPIC_API_KEY를 추가하세요." >&2
  exit 1
fi

require_commands jq curl

# ── 변경 파일 수 계산 ──
FILE_COUNT=$(grep -c '.' "$CHANGED_FILES" 2>/dev/null || echo 0)

# ── review-level: auto 해석 ──
# 소규모(≤2파일) → Lite, 중규모(3~7파일) → Standard, 대규모(8+파일) → Full
if [[ "$LEVEL" == "auto" ]]; then
  if [[ "$FILE_COUNT" -le 2 ]]; then
    INTENSITY="Lite"
  elif [[ "$FILE_COUNT" -le 7 ]]; then
    INTENSITY="Standard"
  else
    INTENSITY="Full"
  fi
else
  case "$LEVEL" in
    lite)     INTENSITY="Lite" ;;
    standard) INTENSITY="Standard" ;;
    full)     INTENSITY="Full" ;;
    *)
      echo "::error::유효하지 않은 review-level: ${LEVEL}. (auto|lite|standard|full) 중 하나를 사용하세요." >&2
      exit 1
      ;;
  esac
fi

# ── 컨텍스트 구성 ──
DIFF_CONTENT=$(cat "$DIFF_FILE")
FILE_LIST=$(cat "$CHANGED_FILES")

DESIGN_SECTION=""
if [[ -n "$DESIGN_DOC" && -f "$DESIGN_DOC" ]]; then
  DESIGN_CONTENT=$(cat "$DESIGN_DOC")
  DESIGN_SECTION=$(printf "## 설계 문서\n%s\n\n" "$DESIGN_CONTENT")
fi

# ── 강도별 리뷰 초점 ──
case "$INTENSITY" in
  Lite)
    FOCUS="런타임 크래시와 보안 취약점(Critical)에 집중. Warning은 최소화."
    ;;
  Standard)
    FOCUS="Critical + High 이슈 탐지. 설계 정합성, 에러 핸들링, 데이터 무결성 검토."
    ;;
  Full)
    FOCUS="전수 검증. Critical + High + Warning. 경계값, 동시성, 타입 안전성, 알려진 갭 포함."
    ;;
esac

REVIEW_PROMPT="당신은 Nova CI 코드 리뷰어입니다. PR 변경사항을 분석하고 verdict JSON만 출력하세요.

## 검증 강도: ${INTENSITY} — ${FOCUS}

## 변경 파일 목록 (${FILE_COUNT}개)
${FILE_LIST}

${DESIGN_SECTION}## PR Diff
\`\`\`diff
${DIFF_CONTENT}
\`\`\`

## 판정 기준
- **PASS**: Critical/High 이슈 없음
- **CONDITIONAL**: Critical 없지만 High 이슈 존재
- **FAIL**: Critical 이슈 1개 이상

## 이슈 심각도 정의
- **Critical**: 런타임 크래시 유발, 보안 취약점, 데이터 손상/무결성 위반, 사용자 오판단 유발
- **High**: 기능 미동작(dead code), 잘못된 로직, 누락된 에러 핸들링
- **Warning**: 코드 품질, 가독성, 성능 개선 권장

반드시 아래 JSON 형식으로만 응답하세요. 마크다운, 설명 없이 순수 JSON만:
{
  \"verdict\": \"PASS\",
  \"intensity\": \"${INTENSITY}\",
  \"summary\": \"한줄 리뷰 요약\",
  \"counts\": { \"critical\": 0, \"high\": 0, \"warning\": 0 },
  \"issues\": [
    { \"severity\": \"Critical\", \"location\": \"파일:라인\", \"issue\": \"이슈 설명\", \"action\": \"권장 조치\" }
  ],
  \"known_gaps\": [\"미커버 영역 설명\"]
}"

# ── Claude API 호출 ──
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-4-6}"

RESPONSE=$(curl -s --max-time 120 https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n \
    --arg prompt "$REVIEW_PROMPT" \
    --arg model "$CLAUDE_MODEL" \
    '{
      model: $model,
      max_tokens: 2048,
      messages: [{role: "user", content: $prompt}]
    }')" 2>/dev/null)

# ── API 응답 파싱 ──
TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)

if [[ -z "$TEXT" ]]; then
  ERROR_TYPE=$(echo "$RESPONSE" | jq -r '.error.type // empty' 2>/dev/null)
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)
  if [[ -n "$ERROR_TYPE" ]]; then
    echo "::error::Claude API 오류 [${ERROR_TYPE}]: ${ERROR_MSG}" >&2
  else
    echo "::error::Claude API 호출 실패. ANTHROPIC_API_KEY를 확인하세요." >&2
  fi
  exit 1
fi

# ── JSON 추출 (마크다운 코드블록 제거) ──
CLEAN_JSON=$(echo "$TEXT" \
  | sed 's/```json//g' \
  | sed 's/```//g' \
  | tr -d '\r' \
  | jq '.' 2>/dev/null || true)

if [[ -z "$CLEAN_JSON" ]]; then
  echo "::error::Claude 응답이 유효한 JSON이 아닙니다. 응답: ${TEXT:0:200}" >&2
  exit 1
fi

# ── intensity 필드 강제 동기화 (auto 해석 결과 반영) ──
CLEAN_JSON=$(echo "$CLEAN_JSON" | jq --arg intensity "$INTENSITY" '.intensity = $intensity')

# ── 출력 ──
echo "$CLEAN_JSON"
