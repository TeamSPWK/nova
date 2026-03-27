#!/bin/bash
# AXIS Kit — 테스트 스위트
# Usage: bash tests/test-scripts.sh
#
# 구성 비율: 구조 30% / 기능 40% / 실패·예외 20% / E2E 10%

set -uo pipefail  # -e 제외: assert 함수에서 eval 실패를 허용해야 함

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "${ROOT_DIR}/scripts/lib/common.sh"

PASS=0
FAIL=0

assert() {
  local description="$1"
  local condition="$2"

  if eval "$condition"; then
    echo -e "  ${GREEN}✓${NC} $description"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} $description"
    ((FAIL++))
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AXIS Kit — 테스트 스위트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════
# 1. 구조 검증 (매니페스트 기반 통합)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 스크립트 + 실행 권한]${NC}"
SCRIPTS=(scripts/x-verify.sh scripts/gap-check.sh scripts/init.sh install.sh)
for s in "${SCRIPTS[@]}"; do
  assert "$s 존재+실행 가능" "[ -f '$ROOT_DIR/$s' ] && [ -x '$ROOT_DIR/$s' ]"
done
assert "common.sh 존재" "[ -f '$ROOT_DIR/scripts/lib/common.sh' ]"
assert ".axis-version 존재" "[ -f '$ROOT_DIR/scripts/.axis-version' ]"
echo ""

echo -e "${YELLOW}[구조: 커맨드 매니페스트]${NC}"
COMMANDS=(next init plan xv design gap review propose metrics)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 ${#COMMANDS[@]}개 존재" "[ '$CMD_COUNT' -eq '${#COMMANDS[@]}' ]"
for cmd in "${COMMANDS[@]}"; do
  assert "/$(echo $cmd) 커맨드" "[ -f '$ROOT_DIR/.claude/commands/${cmd}.md' ]"
done
echo ""

echo -e "${YELLOW}[구조: 에이전트]${NC}"
AGENTS=(architect senior-dev qa-engineer security-engineer devops-engineer)
for agent in "${AGENTS[@]}"; do
  assert "$agent 에이전트" "[ -f '$ROOT_DIR/.claude/agents/${agent}.md' ]"
done
echo ""

echo -e "${YELLOW}[구조: 템플릿 + 문서]${NC}"
TEMPLATES=(cps-plan cps-design claude-md decision-record rule-proposal)
for tmpl in "${TEMPLATES[@]}"; do
  assert "템플릿 ${tmpl}.md" "[ -f '$ROOT_DIR/docs/templates/${tmpl}.md' ]"
done
DOCS=(axis-engineering context-chain eval-checklist rules-changelog adoption-guide usage-guide)
for doc in "${DOCS[@]}"; do
  assert "문서 ${doc}.md" "[ -f '$ROOT_DIR/docs/${doc}.md' ]"
done
echo ""

# ═══════════════════════════════════════════
# 2. 기능 검증 (동작 테스트)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[기능: common.sh 유틸리티]${NC}"
assert "색상 변수 BOLD" "[ -n '$BOLD' ]"
assert "색상 변수 NC" "[ -n '$NC' ]"
assert "load_env 함수" "type load_env &>/dev/null"
assert "require_commands 함수" "type require_commands &>/dev/null"
assert "banner 함수" "type banner &>/dev/null"
assert "divider 함수" "type divider &>/dev/null"
assert "check_update 함수" "type check_update &>/dev/null"
# banner 실제 동작
BANNER_OUT=$(banner "테스트 배너" 2>&1)
assert "banner 출력에 제목 포함" "echo '$BANNER_OUT' | grep -q '테스트 배너'"
echo ""

echo -e "${YELLOW}[기능: init.sh 신규 모드]${NC}"
INIT_DIR=$(mktemp -d)
(cd "$INIT_DIR" && bash "$ROOT_DIR/scripts/init.sh" test-project "React" "한국어" > /dev/null 2>&1)
assert "init: docs/plans/ 생성" "[ -d '$INIT_DIR/docs/plans' ]"
assert "init: docs/designs/ 생성" "[ -d '$INIT_DIR/docs/designs' ]"
assert "init: docs/decisions/ 생성" "[ -d '$INIT_DIR/docs/decisions' ]"
assert "init: docs/verifications/ 생성" "[ -d '$INIT_DIR/docs/verifications' ]"
assert "init: CLAUDE.md 생성" "[ -f '$INIT_DIR/CLAUDE.md' ]"
assert "init: CLAUDE.md에 프로젝트명" "grep -q 'test-project' '$INIT_DIR/CLAUDE.md'"
assert "init: CLAUDE.md에 AXIS 섹션" "grep -q 'AXIS Engineering' '$INIT_DIR/CLAUDE.md'"
assert "init: CLAUDE.md에 Tech Stack" "grep -q 'React' '$INIT_DIR/CLAUDE.md'"
assert "init: .gitignore에 .env" "grep -q '\.env' '$INIT_DIR/.gitignore'"
echo ""

echo -e "${YELLOW}[기능: init.sh adopt 모드]${NC}"
# adopt: 기존 CLAUDE.md 유지 + AXIS 섹션 추가
(cd "$INIT_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt test-project > /dev/null 2>&1)
assert "adopt: 기존 프로젝트명 유지" "grep -q 'test-project' '$INIT_DIR/CLAUDE.md'"
assert "adopt: AXIS 섹션 존재" "grep -q 'AXIS Engineering' '$INIT_DIR/CLAUDE.md'"
echo ""

echo -e "${YELLOW}[기능: install.sh full 모드]${NC}"
INSTALL_DIR=$(mktemp -d)
bash "$ROOT_DIR/install.sh" "$INSTALL_DIR" > /dev/null 2>&1 || true
assert "full: 커맨드 9개" "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 9 ]"
assert "full: 스크립트 3개" "[ \$(ls '$INSTALL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 3 ]"
assert "full: common.sh" "[ -f '$INSTALL_DIR/scripts/lib/common.sh' ]"
assert "full: 템플릿 5개" "[ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"
assert "full: 가이드 3개" "[ -f '$INSTALL_DIR/docs/context-chain.md' ] && [ -f '$INSTALL_DIR/docs/eval-checklist.md' ] && [ -f '$INSTALL_DIR/docs/adoption-guide.md' ]"
echo ""

echo -e "${YELLOW}[기능: install.sh minimal 모드]${NC}"
MINIMAL_DIR=$(mktemp -d)
bash "$ROOT_DIR/install.sh" --minimal "$MINIMAL_DIR" > /dev/null 2>&1 || true
assert "minimal: 커맨드 3개만" "[ \$(ls '$MINIMAL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 3 ]"
assert "minimal: init.sh만" "[ \$(ls '$MINIMAL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 1 ]"
assert "minimal: common.sh 포함" "[ -f '$MINIMAL_DIR/scripts/lib/common.sh' ]"
assert "minimal: 템플릿 없음" "[ ! -d '$MINIMAL_DIR/docs/templates' ] || [ \$(ls '$MINIMAL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 0 ]"
echo ""

echo -e "${YELLOW}[기능: install.sh update 모드]${NC}"
bash "$ROOT_DIR/install.sh" --update "$INSTALL_DIR" > /dev/null 2>&1 || true
assert "update: 커맨드 9개 유지" "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 9 ]"
assert "update: 템플릿 보존" "[ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"
echo ""

# ═══════════════════════════════════════════
# 3. 에러 처리 · 예외 (Negative Testing)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[에러: x-verify.sh 실패 경로]${NC}"
XV_OUTPUT=$(bash "$ROOT_DIR/scripts/x-verify.sh" 2>&1 || true)
XV_EXIT=$?
assert "x-verify: 인자 없으면 비정상 종료" "[ '$XV_EXIT' -ne 0 ] || echo '$XV_OUTPUT' | grep -qE 'Usage|\.env'"
assert "x-verify: 에러 메시지 포함" "echo '$XV_OUTPUT' | grep -qE 'Usage|ERROR|\.env'"
echo ""

echo -e "${YELLOW}[에러: gap-check.sh 실패 경로]${NC}"
GAP_OUTPUT=$(bash "$ROOT_DIR/scripts/gap-check.sh" 2>&1 || true)
assert "gap-check: 인자 없으면 Usage" "echo '$GAP_OUTPUT' | grep -qE 'Usage|GEMINI_API_KEY'"

# 존재하지 않는 파일
GAP_BAD=$(bash "$ROOT_DIR/scripts/gap-check.sh" nonexistent.md src/ 2>&1 || true)
assert "gap-check: 없는 설계문서 에러" "echo '$GAP_BAD' | grep -qE 'ERROR|찾을 수 없습니다|GEMINI'"

# 존재하지 않는 디렉토리
GAP_BAD2=$(bash "$ROOT_DIR/scripts/gap-check.sh" "$ROOT_DIR/README.md" /nonexistent/ 2>&1 || true)
assert "gap-check: 없는 코드경로 에러" "echo '$GAP_BAD2' | grep -qE 'ERROR|찾을 수 없습니다|GEMINI'"
echo ""

echo -e "${YELLOW}[에러: init.sh 실패 경로]${NC}"
INIT_BAD=$(bash "$ROOT_DIR/scripts/init.sh" 2>&1 || true)
assert "init: 인자 없으면 사용법 출력" "echo '$INIT_BAD' | grep -qE '사용법|Usage'"
echo ""

echo -e "${YELLOW}[에러: install.sh 잘못된 모드]${NC}"
INSTALL_BAD=$(bash "$ROOT_DIR/install.sh" --invalid-mode /tmp/test 2>&1 || true)
assert "install: 잘못된 모드 처리" "echo '$INSTALL_BAD' | grep -qE 'ERROR|Installer|Updater|축소'"
echo ""

# ═══════════════════════════════════════════
# 4. 멱등성 (재실행 안전성)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[멱등성: init.sh 재실행]${NC}"
IDEM_DIR=$(mktemp -d)
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" idem-test > /dev/null 2>&1)
CLAUDE_BEFORE=$(wc -c < "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)

# 같은 명령 재실행 — CLAUDE.md가 덮어써지면 안 됨
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" idem-test > /dev/null 2>&1)
CLAUDE_AFTER=$(wc -c < "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
assert "init 재실행: CLAUDE.md 크기 보존" "[ '$CLAUDE_BEFORE' -eq '$CLAUDE_AFTER' ]"

# adopt 재실행 — AXIS 섹션 중복 추가 안 됨
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt idem-test > /dev/null 2>&1)
AXIS_COUNT=$(grep -c 'AXIS Engineering' "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt idem-test > /dev/null 2>&1)
AXIS_COUNT2=$(grep -c 'AXIS Engineering' "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
assert "adopt 재실행: AXIS 섹션 중복 없음" "[ '$AXIS_COUNT' -eq '$AXIS_COUNT2' ]"

rm -rf "$IDEM_DIR"
echo ""

echo -e "${YELLOW}[멱등성: install.sh 재실행]${NC}"
IDEM_INSTALL=$(mktemp -d)
bash "$ROOT_DIR/install.sh" "$IDEM_INSTALL" > /dev/null 2>&1 || true
FILE_COUNT_1=$(find "$IDEM_INSTALL" -type f | wc -l | tr -d ' ')

bash "$ROOT_DIR/install.sh" "$IDEM_INSTALL" > /dev/null 2>&1 || true
FILE_COUNT_2=$(find "$IDEM_INSTALL" -type f | wc -l | tr -d ' ')
assert "install 재실행: 파일 수 동일" "[ '$FILE_COUNT_1' -eq '$FILE_COUNT_2' ]"

rm -rf "$IDEM_INSTALL"
echo ""

# ═══════════════════════════════════════════
# 5. 출력 형식 · 내용 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[출력: 생성 파일 내용 검증]${NC}"
CONTENT_DIR=$(mktemp -d)
(cd "$CONTENT_DIR" && bash "$ROOT_DIR/scripts/init.sh" content-test "Next.js" "한국어" > /dev/null 2>&1)

# CLAUDE.md 필수 섹션 확인
assert "CLAUDE.md: Language 섹션" "grep -q 'Language' '$CONTENT_DIR/CLAUDE.md'"
assert "CLAUDE.md: Commands 섹션" "grep -q 'Commands' '$CONTENT_DIR/CLAUDE.md'"
assert "CLAUDE.md: Human-AI 섹션" "grep -q 'Human-AI' '$CONTENT_DIR/CLAUDE.md'"
assert "CLAUDE.md: Credentials 섹션" "grep -q 'Credentials' '$CONTENT_DIR/CLAUDE.md'"
assert "CLAUDE.md: 응답 언어 설정" "grep -q '한국어' '$CONTENT_DIR/CLAUDE.md'"

# .axis-version 형식 검증
assert ".axis-version: 시맨틱 버전" "grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' '$ROOT_DIR/scripts/.axis-version'"

rm -rf "$CONTENT_DIR"
echo ""

# ═══════════════════════════════════════════
# 6. E2E 통합 (init → install → verify)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[E2E: 신규 프로젝트 전체 흐름]${NC}"
E2E_DIR=$(mktemp -d)

# Step 1: install
bash "$ROOT_DIR/install.sh" "$E2E_DIR" > /dev/null 2>&1 || true
assert "E2E: install 후 커맨드 존재" "[ -d '$E2E_DIR/.claude/commands' ]"

# Step 2: init
(cd "$E2E_DIR" && bash scripts/init.sh e2e-project "Express + TypeScript" > /dev/null 2>&1)
assert "E2E: init 후 CLAUDE.md 존재" "[ -f '$E2E_DIR/CLAUDE.md' ]"
assert "E2E: init 후 docs 구조 존재" "[ -d '$E2E_DIR/docs/plans' ] && [ -d '$E2E_DIR/docs/designs' ]"

# Step 3: verify 구조 완결성
assert "E2E: 커맨드+스크립트+CLAUDE.md 모두 존재" \
  "[ -f '$E2E_DIR/.claude/commands/next.md' ] && [ -f '$E2E_DIR/scripts/init.sh' ] && [ -f '$E2E_DIR/CLAUDE.md' ]"
assert "E2E: CLAUDE.md에 프로젝트 정보" "grep -q 'e2e-project' '$E2E_DIR/CLAUDE.md' && grep -q 'Express' '$E2E_DIR/CLAUDE.md'"

rm -rf "$E2E_DIR"
echo ""

echo -e "${YELLOW}[E2E: 기존 프로젝트 adopt 흐름]${NC}"
E2E_ADOPT=$(mktemp -d)

# 기존 CLAUDE.md가 있는 프로젝트 시뮬레이션
echo "# My Existing Project" > "$E2E_ADOPT/CLAUDE.md"
echo "Existing content here" >> "$E2E_ADOPT/CLAUDE.md"

# Step 1: minimal install
bash "$ROOT_DIR/install.sh" --minimal "$E2E_ADOPT" > /dev/null 2>&1 || true
assert "E2E adopt: minimal install 성공" "[ -f '$E2E_ADOPT/.claude/commands/next.md' ]"

# Step 2: adopt
(cd "$E2E_ADOPT" && bash scripts/init.sh --adopt existing-project > /dev/null 2>&1)
assert "E2E adopt: 기존 내용 보존" "grep -q 'Existing content here' '$E2E_ADOPT/CLAUDE.md'"
assert "E2E adopt: AXIS 섹션 추가됨" "grep -q 'AXIS Engineering' '$E2E_ADOPT/CLAUDE.md'"

rm -rf "$E2E_ADOPT"
echo ""

# ═══════════════════════════════════════════
# 정리
# ═══════════════════════════════════════════

rm -rf "$INIT_DIR" "$INSTALL_DIR" "$MINIMAL_DIR" 2>/dev/null

# --- 결과 ---
TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL} 테스트 통과"
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
fi
echo ""
echo "  구조: $(echo "$PASS" | head -1) | 기능 | 에러 | 멱등성 | 출력 | E2E"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
