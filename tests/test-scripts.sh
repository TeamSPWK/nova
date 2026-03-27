#!/bin/bash
# AXIS Kit — 스크립트 기본 테스트
# Usage: bash tests/test-scripts.sh

set -uo pipefail  # -e 제외: assert 함수에서 eval 실패를 허용해야 함

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "${ROOT_DIR}/scripts/lib/common.sh"

PASS=0
FAIL=0

# 테스트 함수
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
echo "  AXIS Kit — 스크립트 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- 파일 존재 테스트 ---
echo -e "${YELLOW}[파일 존재]${NC}"
assert "x-verify.sh 존재" "[ -f '$ROOT_DIR/scripts/x-verify.sh' ]"
assert "gap-check.sh 존재" "[ -f '$ROOT_DIR/scripts/gap-check.sh' ]"
assert "init.sh 존재" "[ -f '$ROOT_DIR/scripts/init.sh' ]"
assert "install.sh 존재" "[ -f '$ROOT_DIR/install.sh' ]"
echo ""

# --- 실행 권한 테스트 ---
echo -e "${YELLOW}[실행 권한]${NC}"
assert "x-verify.sh 실행 가능" "[ -x '$ROOT_DIR/scripts/x-verify.sh' ]"
assert "gap-check.sh 실행 가능" "[ -x '$ROOT_DIR/scripts/gap-check.sh' ]"
assert "init.sh 실행 가능" "[ -x '$ROOT_DIR/scripts/init.sh' ]"
assert "install.sh 실행 가능" "[ -x '$ROOT_DIR/install.sh' ]"
echo ""

# --- 커맨드 파일 테스트 ---
echo -e "${YELLOW}[커맨드 파일]${NC}"
COMMANDS=(next init plan xv design gap review propose metrics)
for cmd in "${COMMANDS[@]}"; do
  assert "/$(echo $cmd) 커맨드 존재" "[ -f '$ROOT_DIR/.claude/commands/${cmd}.md' ]"
done
echo ""

# --- 템플릿 파일 테스트 ---
echo -e "${YELLOW}[템플릿 파일]${NC}"
TEMPLATES=(cps-plan cps-design claude-md decision-record rule-proposal)
for tmpl in "${TEMPLATES[@]}"; do
  assert "${tmpl}.md 존재" "[ -f '$ROOT_DIR/docs/templates/${tmpl}.md' ]"
done
echo ""

# --- 문서 파일 테스트 ---
echo -e "${YELLOW}[문서 파일]${NC}"
assert "axis-engineering.md 존재" "[ -f '$ROOT_DIR/docs/axis-engineering.md' ]"
assert "context-chain.md 존재" "[ -f '$ROOT_DIR/docs/context-chain.md' ]"
assert "eval-checklist.md 존재" "[ -f '$ROOT_DIR/docs/eval-checklist.md' ]"
assert "rules-changelog.md 존재" "[ -f '$ROOT_DIR/docs/rules-changelog.md' ]"
assert "adoption-guide.md 존재" "[ -f '$ROOT_DIR/docs/adoption-guide.md' ]"
echo ""

# --- init.sh 기능 테스트 ---
echo -e "${YELLOW}[init.sh 기능]${NC}"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# 신규 프로젝트 모드
(cd "$TEST_DIR" && bash "$ROOT_DIR/scripts/init.sh" test-project "React" "한국어" > /dev/null 2>&1)
assert "init: docs/plans/ 생성" "[ -d '$TEST_DIR/docs/plans' ]"
assert "init: docs/designs/ 생성" "[ -d '$TEST_DIR/docs/designs' ]"
assert "init: CLAUDE.md 생성" "[ -f '$TEST_DIR/CLAUDE.md' ]"
assert "init: CLAUDE.md에 프로젝트명 포함" "grep -q 'test-project' '$TEST_DIR/CLAUDE.md'"
assert "init: CLAUDE.md에 AXIS 섹션 포함" "grep -q 'AXIS Engineering' '$TEST_DIR/CLAUDE.md'"

# adopt 모드
(cd "$TEST_DIR" && bash "$ROOT_DIR/scripts/init.sh" --adopt test-project > /dev/null 2>&1)
assert "adopt: 기존 CLAUDE.md 유지" "grep -q 'test-project' '$TEST_DIR/CLAUDE.md'"
echo ""

# --- common.sh 테스트 ---
echo -e "${YELLOW}[common.sh 공통 유틸리티]${NC}"
assert "common.sh 존재" "[ -f '$ROOT_DIR/scripts/lib/common.sh' ]"
assert "common.sh: 색상 변수 로드됨" "[ -n '$BOLD' ] && [ -n '$NC' ]"
assert "common.sh: load_env 함수 존재" "type load_env &>/dev/null"
assert "common.sh: require_commands 함수 존재" "type require_commands &>/dev/null"
assert "common.sh: banner 함수 존재" "type banner &>/dev/null"
assert "common.sh: divider 함수 존재" "type divider &>/dev/null"
echo ""

# --- x-verify.sh 기본 테스트 (인자 없이, .env 필요) ---
echo -e "${YELLOW}[x-verify.sh 기본]${NC}"
XV_OUTPUT=$(bash "$ROOT_DIR/scripts/x-verify.sh" 2>&1 || true)
assert "x-verify: 인자 없으면 Usage 또는 .env 에러" "echo '$XV_OUTPUT' | grep -qE 'Usage|\.env'"
echo ""

# --- gap-check.sh 기본 테스트 (인자 없이) ---
echo -e "${YELLOW}[gap-check.sh 기본]${NC}"
GAP_OUTPUT=$(bash "$ROOT_DIR/scripts/gap-check.sh" 2>&1 || true)
assert "gap-check: 인자 없으면 Usage 또는 API 키 에러" "echo '$GAP_OUTPUT' | grep -qE 'Usage|GEMINI_API_KEY|design-doc'"
echo ""

# --- install.sh 모드별 테스트 ---
echo -e "${YELLOW}[install.sh 모드별]${NC}"
INSTALL_DIR=$(mktemp -d)

# full 모드
bash "$ROOT_DIR/install.sh" "$INSTALL_DIR" > /dev/null 2>&1 || true
assert "install full: 커맨드 9개 설치" "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 9 ]"
assert "install full: 스크립트 3개 설치" "[ \$(ls '$INSTALL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 3 ]"
assert "install full: common.sh 설치" "[ -f '$INSTALL_DIR/scripts/lib/common.sh' ]"
assert "install full: 템플릿 5개 설치" "[ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"
assert "install full: 가이드 3개 설치" "[ -f '$INSTALL_DIR/docs/context-chain.md' ] && [ -f '$INSTALL_DIR/docs/eval-checklist.md' ] && [ -f '$INSTALL_DIR/docs/adoption-guide.md' ]"

# minimal 모드 (새 디렉토리)
MINIMAL_DIR=$(mktemp -d)
bash "$ROOT_DIR/install.sh" --minimal "$MINIMAL_DIR" > /dev/null 2>&1 || true
assert "install minimal: 커맨드 3개만 설치" "[ \$(ls '$MINIMAL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 3 ]"
assert "install minimal: init.sh만 설치" "[ \$(ls '$MINIMAL_DIR/scripts/'*.sh 2>/dev/null | wc -l) -eq 1 ]"
assert "install minimal: common.sh 설치" "[ -f '$MINIMAL_DIR/scripts/lib/common.sh' ]"
assert "install minimal: 템플릿 없음" "[ ! -d '$MINIMAL_DIR/docs/templates' ] || [ \$(ls '$MINIMAL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 0 ]"

# update 모드 (full 위에 덮어쓰기)
bash "$ROOT_DIR/install.sh" --update "$INSTALL_DIR" > /dev/null 2>&1 || true
assert "install update: 커맨드 9개 유지" "[ \$(ls '$INSTALL_DIR/.claude/commands/'*.md 2>/dev/null | wc -l) -eq 9 ]"
assert "install update: 템플릿 보존" "[ \$(ls '$INSTALL_DIR/docs/templates/'*.md 2>/dev/null | wc -l) -eq 5 ]"

rm -rf "$INSTALL_DIR" "$MINIMAL_DIR"
echo ""

# --- 결과 ---
TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL} 테스트 통과"
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
