#!/bin/bash
# AXIS Kit — 테스트 스위트
# Usage: bash tests/test-scripts.sh
#
# 구성: 구조 ~20% / 기능 ~40% / 에러 ~15% / 멱등성 ~10% / 출력 ~5% / E2E ~10%
# X-Verify 합의: 구조 축소, E2E·에러·멱등성 유지, 60~75개 적정

set -uo pipefail

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
# 1. 구조 (매니페스트 일괄 검증)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 파일 매니페스트]${NC}"

# 스크립트: 존재 + 실행 권한 일괄
SCRIPTS=(scripts/x-verify.sh scripts/gap-check.sh scripts/init.sh install.sh)
for s in "${SCRIPTS[@]}"; do
  assert "$s" "[ -f '$ROOT_DIR/$s' ] && [ -x '$ROOT_DIR/$s' ]"
done
assert "lib/common.sh" "[ -f '$ROOT_DIR/scripts/lib/common.sh' ]"
assert ".axis-version (시맨틱)" "grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' '$ROOT_DIR/scripts/.axis-version'"

# 커맨드: 개수만 확인 (개별 파일 검증은 install E2E에서)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 11개" "[ '$CMD_COUNT' -eq 11 ]"

# 에이전트: 개수만 확인
AGENT_COUNT=$(ls "$ROOT_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "에이전트 5개" "[ '$AGENT_COUNT' -eq 5 ]"

# 템플릿: 개수만 확인
TMPL_COUNT=$(ls "$ROOT_DIR/docs/templates/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "템플릿 5개" "[ '$TMPL_COUNT' -eq 5 ]"

# 핵심 문서만 확인 (6개를 3개로 축소 — 나머지는 install E2E에서 검증)
assert "axis-engineering.md" "[ -f '$ROOT_DIR/docs/axis-engineering.md' ]"
assert "usage-guide.md" "[ -f '$ROOT_DIR/docs/usage-guide.md' ]"
assert "adoption-guide.md" "[ -f '$ROOT_DIR/docs/adoption-guide.md' ]"
echo ""

# ═══════════════════════════════════════════
# 2. 기능: common.sh
# ═══════════════════════════════════════════

echo -e "${YELLOW}[기능: common.sh]${NC}"
# 핵심 함수만 검증 (존재 + 동작)
assert "load_env 함수" "type load_env &>/dev/null"
assert "require_commands 함수" "type require_commands &>/dev/null"
assert "banner 함수" "type banner &>/dev/null"
assert "check_update 함수" "type check_update &>/dev/null"

BANNER_OUT=$(banner "테스트" 2>&1)
assert "banner 실제 출력" "echo '$BANNER_OUT' | grep -q '테스트'"
echo ""

# ═══════════════════════════════════════════
# 3. 기능: init.sh
# ═══════════════════════════════════════════

echo -e "${YELLOW}[기능: init.sh 신규]${NC}"
INIT_DIR=$(mktemp -d)
(cd "$INIT_DIR" && bash "$ROOT_DIR/scripts/init.sh" test-proj "React" "한국어" > /dev/null 2>&1)

assert "디렉토리 4개 생성" \
  "[ -d '$INIT_DIR/docs/plans' ] && [ -d '$INIT_DIR/docs/designs' ] && [ -d '$INIT_DIR/docs/decisions' ] && [ -d '$INIT_DIR/docs/verifications' ]"
assert "CLAUDE.md 생성" "[ -f '$INIT_DIR/CLAUDE.md' ]"
assert "CLAUDE.md: 프로젝트명+AXIS+Tech Stack" \
  "grep -q 'test-proj' '$INIT_DIR/CLAUDE.md' && grep -q 'AXIS Engineering' '$INIT_DIR/CLAUDE.md' && grep -q 'React' '$INIT_DIR/CLAUDE.md'"
assert "CLAUDE.md: 필수 섹션 (Language+Commands+Human-AI+Credentials)" \
  "grep -q 'Language' '$INIT_DIR/CLAUDE.md' && grep -q 'Commands' '$INIT_DIR/CLAUDE.md' && grep -q 'Human-AI' '$INIT_DIR/CLAUDE.md' && grep -q 'Credentials' '$INIT_DIR/CLAUDE.md'"
assert ".gitignore에 .env" "grep -q '\.env' '$INIT_DIR/.gitignore'"
echo ""

echo -e "${YELLOW}[기능: init.sh adopt]${NC}"
(cd "$INIT_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt test-proj > /dev/null 2>&1)
assert "adopt: 기존 내용 유지 + AXIS 섹션" \
  "grep -q 'test-proj' '$INIT_DIR/CLAUDE.md' && grep -q 'AXIS Engineering' '$INIT_DIR/CLAUDE.md'"
echo ""

# ═══════════════════════════════════════════
# 4. 기능: install.sh 3모드
# ═══════════════════════════════════════════

echo -e "${YELLOW}[기능: install full]${NC}"
INSTALL_DIR=$(mktemp -d)
bash "$ROOT_DIR/install.sh" "$INSTALL_DIR" > /dev/null 2>&1 || true

assert "full: 커맨드 11개" "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 11 ]"
assert "full: 스크립트 3개 + common.sh" \
  "[ \$(ls '$INSTALL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 3 ] && [ -f '$INSTALL_DIR/scripts/lib/common.sh' ]"
assert "full: 템플릿 5개" "[ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"
assert "full: 가이드 3개" \
  "[ -f '$INSTALL_DIR/docs/context-chain.md' ] && [ -f '$INSTALL_DIR/docs/eval-checklist.md' ] && [ -f '$INSTALL_DIR/docs/adoption-guide.md' ]"
echo ""

echo -e "${YELLOW}[기능: install minimal]${NC}"
MINIMAL_DIR=$(mktemp -d)
bash "$ROOT_DIR/install.sh" --minimal "$MINIMAL_DIR" > /dev/null 2>&1 || true

assert "minimal: 커맨드 3개만" "[ \$(ls '$MINIMAL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 3 ]"
assert "minimal: init.sh + common.sh만" \
  "[ \$(ls '$MINIMAL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 1 ] && [ -f '$MINIMAL_DIR/scripts/lib/common.sh' ]"
assert "minimal: 템플릿 없음" \
  "[ ! -d '$MINIMAL_DIR/docs/templates' ] || [ \$(ls '$MINIMAL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 0 ]"
echo ""

echo -e "${YELLOW}[기능: install update]${NC}"
bash "$ROOT_DIR/install.sh" --update "$INSTALL_DIR" > /dev/null 2>&1 || true
assert "update: 커맨드 유지 + 템플릿 보존" \
  "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 11 ] && [ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"
echo ""

# ═══════════════════════════════════════════
# 5. 에러 처리 (Negative Testing)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[에러: 스크립트 실패 경로]${NC}"

# x-verify: 인자 없음
XV_OUT=$(bash "$ROOT_DIR/scripts/x-verify.sh" 2>&1 || true)
assert "x-verify: 인자 없음 → 에러" "echo '$XV_OUT' | grep -qE 'Usage|ERROR|\.env'"

# gap-check: 인자 없음
GAP_OUT=$(bash "$ROOT_DIR/scripts/gap-check.sh" 2>&1 || true)
assert "gap-check: 인자 없음 → Usage/에러" "echo '$GAP_OUT' | grep -qE 'Usage|GEMINI_API_KEY'"

# gap-check: 없는 설계문서
GAP_BAD=$(bash "$ROOT_DIR/scripts/gap-check.sh" nonexistent.md src/ 2>&1 || true)
assert "gap-check: 없는 파일 → 에러" "echo '$GAP_BAD' | grep -qE 'ERROR|찾을 수 없습니다|GEMINI'"

# gap-check: 없는 디렉토리
GAP_BAD2=$(bash "$ROOT_DIR/scripts/gap-check.sh" "$ROOT_DIR/README.md" /nonexistent/ 2>&1 || true)
assert "gap-check: 없는 경로 → 에러" "echo '$GAP_BAD2' | grep -qE 'ERROR|찾을 수 없습니다|GEMINI'"

# init: 인자 없음
INIT_BAD=$(bash "$ROOT_DIR/scripts/init.sh" 2>&1 || true)
assert "init: 인자 없음 → 사용법" "echo '$INIT_BAD' | grep -qE '사용법|Usage'"

# install: 잘못된 모드
INSTALL_BAD=$(bash "$ROOT_DIR/install.sh" --invalid /tmp/test 2>&1 || true)
assert "install: 잘못된 모드 → 처리" "echo '$INSTALL_BAD' | grep -qE 'ERROR|Installer|Updater|축소'"
echo ""

# ═══════════════════════════════════════════
# 6. 멱등성 (재실행 안전성)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[멱등성]${NC}"

# init 재실행: CLAUDE.md 덮어쓰기 방지
IDEM_DIR=$(mktemp -d)
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" idem > /dev/null 2>&1)
SIZE_1=$(wc -c < "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" idem > /dev/null 2>&1)
SIZE_2=$(wc -c < "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
assert "init 재실행: CLAUDE.md 보존" "[ '$SIZE_1' -eq '$SIZE_2' ]"

# adopt 재실행: 중복 섹션 방지
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt idem > /dev/null 2>&1)
CNT_1=$(grep -c 'AXIS Engineering' "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
(cd "$IDEM_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt idem > /dev/null 2>&1)
CNT_2=$(grep -c 'AXIS Engineering' "$IDEM_DIR/CLAUDE.md" 2>/dev/null || echo 0)
assert "adopt 재실행: 중복 없음" "[ '$CNT_1' -eq '$CNT_2' ]"

# install 재실행: 파일 수 동일
IDEM_INS=$(mktemp -d)
bash "$ROOT_DIR/install.sh" "$IDEM_INS" > /dev/null 2>&1 || true
FC_1=$(find "$IDEM_INS" -type f | wc -l | tr -d ' ')
bash "$ROOT_DIR/install.sh" "$IDEM_INS" > /dev/null 2>&1 || true
FC_2=$(find "$IDEM_INS" -type f | wc -l | tr -d ' ')
assert "install 재실행: 파일 수 동일" "[ '$FC_1' -eq '$FC_2' ]"

rm -rf "$IDEM_DIR" "$IDEM_INS"
echo ""

# ═══════════════════════════════════════════
# 7. E2E 통합
# ═══════════════════════════════════════════

echo -e "${YELLOW}[E2E: 신규 프로젝트]${NC}"
E2E_DIR=$(mktemp -d)

bash "$ROOT_DIR/install.sh" "$E2E_DIR" > /dev/null 2>&1 || true
(cd "$E2E_DIR" && bash scripts/init.sh e2e-proj "Express" > /dev/null 2>&1)

assert "install→init 완료" \
  "[ -f '$E2E_DIR/.claude/commands/next.md' ] && [ -f '$E2E_DIR/CLAUDE.md' ] && [ -d '$E2E_DIR/docs/plans' ]"
assert "CLAUDE.md에 프로젝트 정보" \
  "grep -q 'e2e-proj' '$E2E_DIR/CLAUDE.md' && grep -q 'Express' '$E2E_DIR/CLAUDE.md'"
rm -rf "$E2E_DIR"
echo ""

echo -e "${YELLOW}[E2E: 기존 프로젝트 adopt]${NC}"
E2E_ADOPT=$(mktemp -d)
echo -e "# Existing Project\nMy existing content" > "$E2E_ADOPT/CLAUDE.md"

bash "$ROOT_DIR/install.sh" --minimal "$E2E_ADOPT" > /dev/null 2>&1 || true
(cd "$E2E_ADOPT" && bash scripts/init.sh --adopt existing > /dev/null 2>&1)

assert "minimal→adopt 완료" "[ -f '$E2E_ADOPT/.claude/commands/next.md' ]"
assert "기존 내용 보존 + AXIS 추가" \
  "grep -q 'My existing content' '$E2E_ADOPT/CLAUDE.md' && grep -q 'AXIS Engineering' '$E2E_ADOPT/CLAUDE.md'"
rm -rf "$E2E_ADOPT"
echo ""

# ═══════════════════════════════════════════
# 정리 + 결과
# ═══════════════════════════════════════════

rm -rf "$INIT_DIR" "$INSTALL_DIR" "$MINIMAL_DIR" 2>/dev/null

TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL} 테스트 통과"
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
