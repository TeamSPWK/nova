#!/bin/bash
# AXIS Engineering — X-Verification v2 (멀티 AI 교차검증 + 합의율 자동 산출)
# Usage: ./scripts/x-verify.sh "질문 내용"
#        ./scripts/x-verify.sh -f question.txt
#        ./scripts/x-verify.sh --no-save "질문"  (결과 저장 안 함)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
VERIFY_DIR="$ROOT_DIR/docs/verifications"

source "${SCRIPT_DIR}/lib/common.sh"
check_update

# .env 로드 (필수)
if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}ERROR: ${CYAN}$ENV_FILE${NC}${RED} 파일을 찾을 수 없습니다.${NC}"
  exit 1
fi
load_env "$ENV_FILE"

require_commands jq curl

# API 키 확인
AVAILABLE_AIS=()
MISSING_KEYS=()

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  AVAILABLE_AIS+=("claude")
else
  MISSING_KEYS+=("ANTHROPIC_API_KEY")
  echo -e "${YELLOW}⚠️  WARNING: ${BOLD}ANTHROPIC_API_KEY${NC}${YELLOW}가 .env에 설정되지 않았습니다. Claude를 건너뜁니다.${NC}"
fi

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  AVAILABLE_AIS+=("gpt")
else
  MISSING_KEYS+=("OPENAI_API_KEY")
  echo -e "${YELLOW}⚠️  WARNING: ${BOLD}OPENAI_API_KEY${NC}${YELLOW}가 .env에 설정되지 않았습니다. GPT를 건너뜁니다.${NC}"
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  AVAILABLE_AIS+=("gemini")
else
  MISSING_KEYS+=("GEMINI_API_KEY")
  echo -e "${YELLOW}⚠️  WARNING: ${BOLD}GEMINI_API_KEY${NC}${YELLOW}가 .env에 설정되지 않았습니다. Gemini를 건너뜁니다.${NC}"
fi

if [[ ${#AVAILABLE_AIS[@]} -eq 0 ]]; then
  echo -e "${RED}ERROR: 사용 가능한 AI가 없습니다. .env에 최소 1개 API 키를 설정하세요.${NC}"
  exit 1
fi

if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
  echo ""
fi

# 옵션 처리
SAVE_RESULT=true
CLAUDE_MODEL="claude-sonnet-4-20250514"
SELECTED_AIS=()
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --no-save)
      SAVE_RESULT=false
      shift
      ;;
    --model)
      case "${2:-}" in
        opus)  CLAUDE_MODEL="claude-opus-4-20250514" ;;
        haiku) CLAUDE_MODEL="claude-haiku-4-5-20251001" ;;
        sonnet) CLAUDE_MODEL="claude-sonnet-4-20250514" ;;
        *) echo -e "${RED}ERROR: 알 수 없는 모델: ${2:-}. (opus, sonnet, haiku 중 선택)${NC}"; exit 1 ;;
      esac
      shift 2
      ;;
    --claude)  SELECTED_AIS+=("claude"); shift ;;
    --gpt)     SELECTED_AIS+=("gpt"); shift ;;
    --gemini)  SELECTED_AIS+=("gemini"); shift ;;
    *)
      echo -e "${RED}ERROR: 알 수 없는 옵션: $1${NC}"; exit 1
      ;;
  esac
done

# AI 선택 필터링: --claude/--gpt/--gemini 지정 시 해당 AI만 사용
if [[ ${#SELECTED_AIS[@]} -gt 0 ]]; then
  FILTERED_AIS=()
  for ai in "${SELECTED_AIS[@]}"; do
    if [[ " ${AVAILABLE_AIS[*]} " =~ " $ai " ]]; then
      FILTERED_AIS+=("$ai")
    else
      echo -e "${RED}ERROR: ${BOLD}$ai${NC}${RED} API 키가 .env에 없습니다.${NC}"
      exit 1
    fi
  done
  AVAILABLE_AIS=("${FILTERED_AIS[@]}")
fi

# 입력 처리
if [[ "${1:-}" == "-f" && -n "${2:-}" ]]; then
  QUESTION=$(cat "$2")
elif [[ -n "${1:-}" ]]; then
  QUESTION="$1"
else
  echo -e "${BOLD}Usage:${NC}"
  echo -e "  ${YELLOW}\$ $0 [옵션] \"질문 내용\"${NC}"
  echo -e "  ${YELLOW}\$ $0 [옵션] -f question.txt${NC}"
  echo ""
  echo -e "${BOLD}옵션:${NC}"
  echo -e "  ${YELLOW}--claude${NC}              Claude만 호출"
  echo -e "  ${YELLOW}--gpt${NC}                 GPT만 호출"
  echo -e "  ${YELLOW}--gemini${NC}              Gemini만 호출"
  echo -e "  ${YELLOW}--gpt --gemini${NC}        조합 가능"
  echo -e "  ${YELLOW}--model opus|sonnet|haiku${NC}  Claude 모델 선택"
  echo -e "  ${YELLOW}--no-save${NC}             결과 저장 안 함"
  exit 1
fi

SYSTEM_PROMPT="당신은 소프트웨어 아키텍처 전문가입니다. 질문에 대해 명확하고 구조화된 의견을 한국어로 제시하세요. 답변은 500자 이내로 핵심만 간결하게."

divider
echo -e "${CYAN}  AXIS X-Verification v2 — 멀티 AI 교차검증${NC}"
echo -e "${CYAN}  Claude 모델: ${CLAUDE_MODEL}${NC}"
divider
echo ""
echo -e "  ${BOLD}❓ 질문:${NC} $QUESTION"
echo ""

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# ── Phase 1: 3개 AI 병렬 호출 ──

# API 응답에서 텍스트 추출
extract_text() {
  local name="$1" response="$2"
  case "$name" in
    claude) echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null ;;
    gpt)    echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null ;;
    gemini) echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null ;;
  esac
}

# 범용 API 호출 (재시도 + 파일 저장)
call_api() {
  local name="$1"
  local outfile="$TMPDIR/${name}.txt"
  shift
  local attempt
  for attempt in 1 2; do
    local response text
    response=$(curl -s --max-time 30 "$@" 2>/dev/null)
    text=$(extract_text "$name" "$response")
    if [[ -n "$text" ]]; then
      echo "$text" > "$outfile"
      return 0
    fi
    [[ $attempt -eq 1 ]] && sleep 2
  done
  echo "ERROR: ${name} API 호출 실패 (2회 시도 후 실패)" > "$outfile"
  return 1
}

call_claude() {
  call_api claude https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n --arg q "$QUESTION" --arg s "$SYSTEM_PROMPT" --arg m "$CLAUDE_MODEL" '{
      model: $m,
      max_tokens: 1024,
      system: $s,
      messages: [{role: "user", content: $q}]
    }')"
}

call_gpt() {
  call_api gpt https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$QUESTION" --arg s "$SYSTEM_PROMPT" '{
      model: "gpt-4o",
      messages: [{role: "system", content: $s}, {role: "user", content: $q}],
      temperature: 0.7
    }')"
}

call_gemini() {
  call_api gemini "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$SYSTEM_PROMPT\n\n$QUESTION" '{
      contents: [{parts: [{text: $q}]}]
    }')"
}

AI_COUNT=${#AVAILABLE_AIS[@]}
echo -e "${BLUE}⏳ Phase 1: ${AI_COUNT}개 AI에 동시 질의 중...${NC}"
echo ""

# 사용 가능한 AI만 호출
for ai in "${AVAILABLE_AIS[@]}"; do
  case "$ai" in
    claude) call_claude & ;;
    gpt)    call_gpt & ;;
    gemini) call_gemini & ;;
  esac
done
wait

# 결과 출력 (호출한 AI만)
SUCCESS_COUNT=0

if [[ " ${AVAILABLE_AIS[*]} " =~ " claude " ]]; then
  echo -e "${GREEN}━━━ 🟣 Claude (Anthropic) ━━━━━━━━━━━━━━━━━━━━━━${NC}"
  cat "$TMPDIR/claude.txt"
  grep -q "^ERROR:" "$TMPDIR/claude.txt" 2>/dev/null || ((SUCCESS_COUNT++)) || true
  echo ""
else
  echo -e "${YELLOW}━━━ 🟣 Claude (Anthropic) ━━━ [건너뜀: API 키 없음] ━━━${NC}"
  echo ""
fi

if [[ " ${AVAILABLE_AIS[*]} " =~ " gpt " ]]; then
  echo -e "${GREEN}━━━ 🟢 GPT-4o (OpenAI) ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  cat "$TMPDIR/gpt.txt"
  grep -q "^ERROR:" "$TMPDIR/gpt.txt" 2>/dev/null || ((SUCCESS_COUNT++)) || true
  echo ""
else
  echo -e "${YELLOW}━━━ 🟢 GPT-4o (OpenAI) ━━━ [건너뜀: API 키 없음] ━━━${NC}"
  echo ""
fi

if [[ " ${AVAILABLE_AIS[*]} " =~ " gemini " ]]; then
  echo -e "${GREEN}━━━ 🔵 Gemini (Google) ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  cat "$TMPDIR/gemini.txt"
  grep -q "^ERROR:" "$TMPDIR/gemini.txt" 2>/dev/null || ((SUCCESS_COUNT++)) || true
  echo ""
else
  echo -e "${YELLOW}━━━ 🔵 Gemini (Google) ━━━ [건너뜀: API 키 없음] ━━━${NC}"
  echo ""
fi

if [[ $SUCCESS_COUNT -eq 0 ]]; then
  echo -e "${RED}ERROR: 모든 AI 호출이 실패했습니다. 네트워크 및 API 키를 확인하세요.${NC}"
  exit 1
fi

# ── Phase 2: 합의율 자동 산출 ──

# 호출된 AI 응답 수집
RESPONSES=""
for ai in claude gpt gemini; do
  if [[ -f "$TMPDIR/${ai}.txt" ]] && ! grep -q "^ERROR:" "$TMPDIR/${ai}.txt" 2>/dev/null; then
    RESP=$(cat "$TMPDIR/${ai}.txt")
    RESPONSES+="## ${ai} 응답"$'\n'"${RESP}"$'\n\n'
  fi
done

if [[ $SUCCESS_COUNT -eq 1 ]]; then
  echo -e "${BLUE}💡 AI 1개 + 현재 에이전트 = 교차검증 (합의 분석 건너뜀)${NC}"
  echo ""
  # 1개일 때는 합의 분석 없이 바로 결과 저장으로
  RATE="N/A"
  VERDICT="agent_review"
  SUMMARY="단일 AI 응답 — 현재 에이전트와 교차검증하세요"
  CLEAN_JSON="{}"
  COMMON=""
  DIFFS=""
else
  echo -e "${BLUE}⏳ Phase 2: ${SUCCESS_COUNT}개 AI 합의율 분석 중...${NC}"
  echo ""

  ANALYSIS_PROMPT="다음은 같은 질문에 대한 ${SUCCESS_COUNT}개 AI의 응답입니다. 합의 수준을 분석하세요.

## 원래 질문
$QUESTION

$RESPONSES
반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트 없이 JSON만:
{
  \"consensus_rate\": (0-100 정수. 핵심 결론의 방향성이 일치하는 정도),
  \"common_points\": [\"공통 의견1\", \"공통 의견2\"],
  \"differences\": [\"차이점1\", \"차이점2\"],
  \"verdict\": \"auto_approve 또는 human_review 또는 redefine\",
  \"summary\": \"한줄 요약\"
}"

# Gemini flash로 합의 분석 (비용 최소화)
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo -e "${YELLOW}WARNING: GEMINI_API_KEY가 없어 합의 분석을 건너뜁니다.${NC}"
  ANALYSIS="ERROR"
else
  ANALYSIS=""
  for _attempt in 1 2; do
    _response=$(curl -s --max-time 30 "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg p "$ANALYSIS_PROMPT" '{
        contents: [{parts: [{text: $p}]}],
        generationConfig: {temperature: 0.1}
      }')" 2>/dev/null)
    ANALYSIS=$(echo "$_response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    if [[ -n "$ANALYSIS" ]]; then
      break
    fi
    if [[ $_attempt -eq 1 ]]; then
      sleep 2
    fi
  done
  if [[ -z "$ANALYSIS" ]]; then
    ANALYSIS="ERROR"
    echo -e "${YELLOW}WARNING: 합의 분석 API 호출 실패 (2회 시도 후 실패)${NC}"
  fi
fi

# JSON 추출 (마크다운 코드블록 제거)
CLEAN_JSON=$(echo "$ANALYSIS" | sed 's/```json//g' | sed 's/```//g' | tr -d '\n' | jq '.' 2>/dev/null || echo "$ANALYSIS")

# 파싱
RATE=$(echo "$CLEAN_JSON" | jq -r '.consensus_rate // "?"' 2>/dev/null || echo "?")
VERDICT=$(echo "$CLEAN_JSON" | jq -r '.verdict // "unknown"' 2>/dev/null || echo "unknown")
SUMMARY=$(echo "$CLEAN_JSON" | jq -r '.summary // "분석 실패"' 2>/dev/null || echo "분석 실패")

# 공통점/차이점 출력
COMMON=$(echo "$CLEAN_JSON" | jq -r '.common_points[]? // empty' 2>/dev/null)
DIFFS=$(echo "$CLEAN_JSON" | jq -r '.differences[]? // empty' 2>/dev/null)

fi  # SUCCESS_COUNT == 1 분기 종료

# 판정 색상
case "$VERDICT" in
  auto_approve)  VERDICT_COLOR="${GREEN}✅ AUTO APPROVE${NC}" ;;
  human_review)  VERDICT_COLOR="${YELLOW}⚠️  HUMAN REVIEW${NC}" ;;
  agent_review)  VERDICT_COLOR="${CYAN}🤖 AGENT REVIEW${NC}" ;;
  redefine)      VERDICT_COLOR="${RED}🔄 REDEFINE${NC}" ;;
  *)             VERDICT_COLOR="${RED}❓ UNKNOWN${NC}" ;;
esac

echo -e "${MAGENTA}━━━ 📊 합의 분석 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}합의율:${NC}  ${CYAN}${BOLD}${RATE}${NC}$( [[ "$RATE" != "N/A" ]] && echo "%" || true )"
echo -e "  ${BOLD}판정:${NC}    ${VERDICT_COLOR}"
echo -e "  ${BOLD}요약:${NC}    ${SUMMARY}"
echo ""

if [[ -n "$COMMON" ]]; then
  echo -e "  ${GREEN}공통점:${NC}"
  echo "$COMMON" | while read -r line; do echo "    • $line"; done
  echo ""
fi

if [[ -n "$DIFFS" ]]; then
  echo -e "  ${YELLOW}차이점:${NC}"
  echo "$DIFFS" | while read -r line; do echo "    • $line"; done
  echo ""
fi

divider

# ── Phase 3: 결과 저장 ──

if [[ "$SAVE_RESULT" == true ]]; then
  mkdir -p "$VERIFY_DIR"
  DATE=$(date +%Y-%m-%d)
  SLUG=$(echo "$QUESTION" | head -c 40 | sed 's/[^a-zA-Z0-9가-힣]/-/g' | sed 's/-\+/-/g' | sed 's/-$//')
  FILENAME="${DATE}-${SLUG}.md"
  FILEPATH="$VERIFY_DIR/$FILENAME"

  # 호출된 AI 응답만 수집
  AI_SECTIONS=""
  for ai in claude gpt gemini; do
    if [[ -f "$TMPDIR/${ai}.txt" ]]; then
      AI_SECTIONS+="## ${ai}"$'\n'
      AI_SECTIONS+="$(cat "$TMPDIR/${ai}.txt")"$'\n\n'
    fi
  done

  cat > "$FILEPATH" << MDEOF
# X-Verification: ${QUESTION:0:80}

> 날짜: $DATE
> 합의율: ${RATE}$( [[ "$RATE" != "N/A" ]] && echo "%" || true )
> 판정: $VERDICT
> AI: ${AVAILABLE_AIS[*]}

## 질문
$QUESTION

$AI_SECTIONS
## 합의 분석
- **합의율**: ${RATE}$( [[ "$RATE" != "N/A" ]] && echo "%" || true )
- **판정**: $VERDICT
- **요약**: $SUMMARY

### 공통점
$(echo "$COMMON" | while read -r line; do echo "- $line"; done)

### 차이점
$(echo "$DIFFS" | while read -r line; do echo "- $line"; done)
MDEOF

  echo ""
echo -e "${GREEN}📁 결과 저장: ${CYAN}$FILEPATH${NC}"
fi
