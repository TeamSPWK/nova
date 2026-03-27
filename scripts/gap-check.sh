#!/bin/bash
# AXIS Engineering — Gap Check (역방향 검증: 설계 → 구현 갭 탐지)
# Usage: ./scripts/gap-check.sh <design-doc.md> <code-dir>
# Example: ./scripts/gap-check.sh docs/designs/feature-x.md src/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/lib/common.sh"
check_update
load_env "$ROOT_DIR/.env"

# 입력 확인 (Usage를 먼저 — API 키 없어도 도움말은 보여줘야 함)
if [[ $# -lt 2 ]]; then
  echo -e "${BOLD}Usage:${NC}"
  echo -e "  ${YELLOW}\$ $0 <design-doc.md> <code-dir>${NC}"
  echo ""
  echo -e "  설계 문서와 구현 코드를 비교하여 갭을 탐지합니다."
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo -e "  ${YELLOW}\$ $0 docs/designs/auth.md src/${NC}"
  echo -e "  ${YELLOW}\$ $0 docs/designs/api.md apps/backend/${NC}"
  exit 1
fi

require_commands jq curl

# API 키 확인 (Gemini > GPT > Claude 우선순위로 fallback)
SELECTED_AI=""
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  SELECTED_AI="gemini"
elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
  SELECTED_AI="gpt"
elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  SELECTED_AI="claude"
else
  echo -e "${RED}ERROR: 사용 가능한 API 키가 없습니다.${NC}"
  echo -e "  ${CYAN}.env${NC} 파일에 다음 중 하나를 추가하세요:"
  echo -e "  ${BOLD}GEMINI_API_KEY${NC}, ${BOLD}OPENAI_API_KEY${NC}, 또는 ${BOLD}ANTHROPIC_API_KEY${NC}"
  exit 1
fi
echo -e "  ${BLUE}🤖 분석 AI:${NC} ${BOLD}${SELECTED_AI}${NC}"

DESIGN_DOC="$1"
CODE_DIR="$2"

if [[ ! -f "$DESIGN_DOC" ]]; then
  echo -e "${RED}ERROR: 설계 문서를 찾을 수 없습니다: ${CYAN}$DESIGN_DOC${NC}"
  exit 1
fi

if [[ ! -d "$CODE_DIR" ]]; then
  echo -e "${RED}ERROR: 코드 디렉토리를 찾을 수 없습니다: ${CYAN}$CODE_DIR${NC}"
  exit 1
fi

banner "AXIS Gap Check — 역방향 검증 (설계 ↔ 구현)"
echo ""
echo -e "  ${BOLD}📄 설계 문서:${NC} ${CYAN}$DESIGN_DOC${NC}"
echo -e "  ${BOLD}📂 코드 경로:${NC} ${CYAN}$CODE_DIR${NC}"
echo ""

DESIGN_CONTENT=$(cat "$DESIGN_DOC")

# 코드 파일 목록 수집 (주요 확장자만)
CODE_FILES=$(find "$CODE_DIR" -type f \( \
  -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
  -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
  -o -name "*.sh" -o -name "*.sql" \
  \) ! -path "*/node_modules/*" ! -path "*/.next/*" ! -path "*/dist/*" 2>/dev/null | head -100)

# 빈 디렉토리 확인
if [[ -z "$CODE_FILES" ]]; then
  echo -e "${RED}ERROR: '$CODE_DIR' 에서 분석 가능한 코드 파일을 찾을 수 없습니다.${NC}"
  echo -e "  지원 확장자: .ts .tsx .js .jsx .py .go .rs .java .sh .sql"
  echo -e "  디렉토리 경로를 확인하거나, 코드 파일이 존재하는지 확인하세요."
  exit 1
fi

# 파일 수 및 총 줄 수 계산
FILE_COUNT=0
TOTAL_LINES=0
for f in $CODE_FILES; do
  ((FILE_COUNT++)) || true
  lines=$(wc -l < "$f" 2>/dev/null || echo "0")
  TOTAL_LINES=$((TOTAL_LINES + lines))
done
echo -e "  ${BLUE}🔍 분석 대상: ${BOLD}${FILE_COUNT}개${NC}${BLUE} 파일 (총 ${BOLD}${TOTAL_LINES}줄${NC}${BLUE})${NC}"
echo ""

CODE_SUMMARY=""
for f in $CODE_FILES; do
  LINES=$(wc -l < "$f" 2>/dev/null || echo "0")
  CODE_SUMMARY+="### $f ($LINES lines)"$'\n'
  # 파일 상위 200줄 + 시그니처 추출 (200줄 이후 함수/클래스 정의)
  CODE_SUMMARY+=$(head -200 "$f" 2>/dev/null || echo "(읽기 실패)")
  if [[ "$LINES" -gt 200 ]]; then
    SIGS=$(tail -n +"201" "$f" 2>/dev/null | grep -n -E '^\s*(export |function |class |def |func |pub fn |public |private |protected |async function )' 2>/dev/null | head -30)
    if [[ -n "$SIGS" ]]; then
      CODE_SUMMARY+=$'\n# --- signatures after line 200 ---\n'
      CODE_SUMMARY+="$SIGS"
    fi
  fi
  CODE_SUMMARY+=$'\n\n'
done

CODE_SUMMARY="${CODE_SUMMARY:0:20000}"

echo -e "${BLUE}⏳ AI에게 갭 분석 요청 중...${NC}"
echo ""

ANALYSIS_PROMPT="당신은 소프트웨어 품질 검증 전문가입니다.

아래 설계 문서와 구현 코드를 비교하여 갭을 분석하세요.

## 설계 문서
$DESIGN_CONTENT

## 구현 코드 (주요 파일 상위 200줄 + 시그니처)
$CODE_SUMMARY

다음 JSON 형식으로만 응답하세요:
{
  \"match_rate\": (0-100 정수. 설계 요구사항이 구현에 반영된 비율),
  \"implemented\": [\"구현된 항목1\", \"구현된 항목2\"],
  \"missing\": [\"미구현 항목1\", \"미구현 항목2\"],
  \"extra\": [\"설계에 없지만 구현에 있는 항목1\"],
  \"risks\": [\"품질 위험 사항1\"],
  \"summary\": \"한줄 요약\"
}"

# AI별 API 호출
call_gemini_gap() {
  curl -s --max-time 30 "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg p "$ANALYSIS_PROMPT" '{
      contents: [{parts: [{text: $p}]}],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            match_rate: {type: "integer"},
            implemented: {type: "array", items: {type: "string"}},
            missing: {type: "array", items: {type: "string"}},
            extra: {type: "array", items: {type: "string"}},
            risks: {type: "array", items: {type: "string"}},
            summary: {type: "string"}
          },
          required: ["match_rate", "implemented", "missing", "extra", "risks", "summary"]
        }
      }
    }')" | jq -r '.candidates[0].content.parts[0].text // "ERROR"'
}

call_gpt_gap() {
  local response
  response=$(curl -s --max-time 30 "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg p "$ANALYSIS_PROMPT" '{
      model: "gpt-4o",
      messages: [{role: "user", content: $p}],
      temperature: 0.1,
      response_format: {type: "json_object"}
    }')")
  echo "$response" | jq -r '.choices[0].message.content // "ERROR"'
}

call_claude_gap() {
  local response
  response=$(curl -s --max-time 30 "https://api.anthropic.com/v1/messages" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n --arg p "$ANALYSIS_PROMPT" '{
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      messages: [{role: "user", content: $p}]
    }')")
  echo "$response" | jq -r '.content[0].text // "ERROR"'
}

case "$SELECTED_AI" in
  gemini) RESULT=$(call_gemini_gap) ;;
  gpt)    RESULT=$(call_gpt_gap) ;;
  claude) RESULT=$(call_claude_gap) ;;
esac

# JSON 정리 (GPT/Claude가 마크다운 코드블록으로 감쌀 수 있음)
CLEAN_JSON=$(echo "$RESULT" | sed 's/```json//g' | sed 's/```//g' | jq '.' 2>/dev/null || echo "{}")

# match_rate 키가 없으면 응답 구조가 다른 것 — 직접 추출 시도
if ! echo "$CLEAN_JSON" | jq -e '.match_rate' > /dev/null 2>&1; then
  # AI가 다른 구조로 응답했을 수 있음 — 요약 재시도
  CLEAN_JSON='{"match_rate": 0, "implemented": [], "missing": ["JSON 파싱 실패 - 원시 응답을 확인하세요"], "extra": [], "risks": [], "summary": "응답 구조 불일치"}'
  echo -e "${YELLOW}[INFO] AI 응답이 예상 형식과 다릅니다. 원시 응답:${NC}"
  echo "$RESULT" | head -40
  echo ""
fi

# 파싱
MATCH_RATE=$(echo "$CLEAN_JSON" | jq -r '.match_rate // "?"' 2>/dev/null || echo "?")
SUMMARY=$(echo "$CLEAN_JSON" | jq -r '.summary // "분석 실패"' 2>/dev/null || echo "분석 실패")

# 매칭률 색상
if [[ "$MATCH_RATE" =~ ^[0-9]+$ ]]; then
  if [[ "$MATCH_RATE" -ge 90 ]]; then
    RATE_COLOR="${GREEN}"
    VERDICT="✅ PASS"
  elif [[ "$MATCH_RATE" -ge 70 ]]; then
    RATE_COLOR="${YELLOW}"
    VERDICT="⚠️  REVIEW NEEDED"
  else
    RATE_COLOR="${RED}"
    VERDICT="❌ SIGNIFICANT GAPS"
  fi
else
  RATE_COLOR="${RED}"
  VERDICT="❓ PARSE ERROR"
fi

divider
echo ""
echo -e "  ${BOLD}매칭률:${NC}  ${RATE_COLOR}${BOLD}${MATCH_RATE}%${NC}"
echo -e "  ${BOLD}판정:${NC}    ${VERDICT}"
echo -e "  ${BOLD}요약:${NC}    ${SUMMARY}"
echo ""

# 구현된 항목
IMPLEMENTED=$(echo "$CLEAN_JSON" | jq -r '.implemented[]? // empty' 2>/dev/null)
if [[ -n "$IMPLEMENTED" ]]; then
  echo -e "  ${GREEN}✅ 구현 완료:${NC}"
  echo "$IMPLEMENTED" | while read -r line; do echo "    • $line"; done
  echo ""
fi

# 미구현 항목
MISSING=$(echo "$CLEAN_JSON" | jq -r '.missing[]? // empty' 2>/dev/null)
if [[ -n "$MISSING" ]]; then
  echo -e "  ${RED}❌ 미구현:${NC}"
  echo "$MISSING" | while read -r line; do echo "    • $line"; done
  echo ""
fi

# 설계 외 구현
EXTRA=$(echo "$CLEAN_JSON" | jq -r '.extra[]? // empty' 2>/dev/null)
if [[ -n "$EXTRA" ]]; then
  echo -e "  ${YELLOW}➕ 설계 외 구현:${NC}"
  echo "$EXTRA" | while read -r line; do echo "    • $line"; done
  echo ""
fi

# 위험 사항
RISKS=$(echo "$CLEAN_JSON" | jq -r '.risks[]? // empty' 2>/dev/null)
if [[ -n "$RISKS" ]]; then
  echo -e "  ${RED}⚠️  위험:${NC}"
  echo "$RISKS" | while read -r line; do echo "    • $line"; done
  echo ""
fi

divider
