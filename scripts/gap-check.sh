#!/bin/bash
# AXIS Engineering — Gap Check (역방향 검증: 설계 → 구현 갭 탐지)
# Usage: ./scripts/gap-check.sh <design-doc.md> <code-dir>
# Example: ./scripts/gap-check.sh docs/designs/feature-x.md src/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# .env 로드
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# 입력 확인
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <design-doc.md> <code-dir>"
  echo ""
  echo "설계 문서와 구현 코드를 비교하여 갭을 탐지합니다."
  echo ""
  echo "Examples:"
  echo "  $0 docs/designs/auth.md src/"
  echo "  $0 docs/designs/api.md apps/backend/"
  exit 1
fi

DESIGN_DOC="$1"
CODE_DIR="$2"

if [[ ! -f "$DESIGN_DOC" ]]; then
  echo -e "${RED}ERROR: 설계 문서를 찾을 수 없습니다: $DESIGN_DOC${NC}"
  exit 1
fi

if [[ ! -d "$CODE_DIR" ]]; then
  echo -e "${RED}ERROR: 코드 디렉토리를 찾을 수 없습니다: $CODE_DIR${NC}"
  exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  AXIS Gap Check — 역방향 검증 (설계 ↔ 구현)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}설계 문서:${NC} $DESIGN_DOC"
echo -e "${YELLOW}코드 경로:${NC} $CODE_DIR"
echo ""

DESIGN_CONTENT=$(cat "$DESIGN_DOC")

# 코드 파일 목록 수집 (주요 확장자만)
CODE_FILES=$(find "$CODE_DIR" -type f \( \
  -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
  -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
  -o -name "*.sh" -o -name "*.sql" \
  \) ! -path "*/node_modules/*" ! -path "*/.next/*" ! -path "*/dist/*" 2>/dev/null | head -100)

CODE_SUMMARY=""
for f in $CODE_FILES; do
  LINES=$(wc -l < "$f" 2>/dev/null || echo "0")
  CODE_SUMMARY+="### $f ($LINES lines)"$'\n'
  # 파일 내용 직접 포함 (상위 80줄)
  CODE_SUMMARY+=$(head -80 "$f" 2>/dev/null || echo "(읽기 실패)")
  CODE_SUMMARY+=$'\n\n'
done

CODE_SUMMARY="${CODE_SUMMARY:0:12000}"

echo -e "${BLUE}⏳ AI에게 갭 분석 요청 중...${NC}"
echo ""

ANALYSIS_PROMPT="당신은 소프트웨어 품질 검증 전문가입니다.

아래 설계 문서와 구현 코드를 비교하여 갭을 분석하세요.

## 설계 문서
$DESIGN_CONTENT

## 구현 코드 (주요 파일 상위 50줄)
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

RESULT=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
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
  }')" | jq -r '.candidates[0].content.parts[0].text // "ERROR"')

# JSON 정리
CLEAN_JSON=$(echo "$RESULT" | jq '.' 2>/dev/null || echo "{}")

# match_rate 키가 없으면 응답 구조가 다른 것 — 직접 추출 시도
if ! echo "$CLEAN_JSON" | jq -e '.match_rate' > /dev/null 2>&1; then
  # Gemini가 다른 구조로 응답했을 수 있음 — 요약 재시도
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

echo -e "${CYAN}━━━ 📊 갭 분석 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  매칭률:  ${RATE_COLOR}${MATCH_RATE}%${NC}"
echo -e "  판정:    ${VERDICT}"
echo -e "  요약:    ${SUMMARY}"
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

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
