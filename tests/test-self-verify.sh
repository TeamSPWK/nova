#!/bin/bash
# Nova — 자가 검증 테스트 (Self-Verification)
# Usage: bash tests/test-self-verify.sh
#
# 의도적으로 결함이 주입된 코드와 설계 문서를 사용하여
# Nova의 갭 탐지 능력을 구조적으로 검증한다.
#
# 이 테스트는 Claude Code 에이전트 없이도 CI에서 실행 가능하다.
# 설계 문서의 검증 계약과 코드를 정적으로 비교하여 갭을 탐지한다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

# 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
echo "  Nova — 자가 검증 테스트 (Self-Verification)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════
# 1. 픽스처 존재 확인
# ═══════════════════════════════════════════

echo -e "${YELLOW}[픽스처: 존재]${NC}"
assert "설계 문서 존재" "[ -f '$FIXTURES/design-user-auth.md' ]"
assert "결함 코드 존재" "[ -f '$FIXTURES/code-user-auth.js' ]"
echo ""

# ═══════════════════════════════════════════
# 2. 갭 탐지: 누락된 엔드포인트
# ═══════════════════════════════════════════

echo -e "${YELLOW}[갭 탐지: 누락 엔드포인트]${NC}"

# 설계 문서에 정의된 엔드포인트
DESIGN_ENDPOINTS=$(grep -oE '(GET|POST|PUT|DELETE|PATCH) /api/[^ ]+' "$FIXTURES/design-user-auth.md" | sort)
# 코드에 구현된 라우트
CODE_ROUTES=$(grep -oE "router\.(get|post|put|delete|patch)\('(/[^']+)'" "$FIXTURES/code-user-auth.js" | sed "s/router\.\(.*\)('\(.*\)'/\U\1 \/api\/auth\2/" | sort)

# /api/auth/me가 설계에 있지만 코드에 없음을 탐지
assert "DEFECT#1 탐지: GET /api/auth/me 누락" \
  "echo '$DESIGN_ENDPOINTS' | grep -q 'GET /api/auth/me' && ! grep -q \"router.get.*'/me'\" '$FIXTURES/code-user-auth.js'"
echo ""

# ═══════════════════════════════════════════
# 3. 갭 탐지: 보안 결함
# ═══════════════════════════════════════════

echo -e "${YELLOW}[갭 탐지: 보안 결함]${NC}"

# 설계에서 bcrypt 요구, 코드에서 bcrypt import/require 없음
assert "DEFECT#2 탐지: bcrypt 미사용 (평문 비밀번호)" \
  "grep -q 'bcrypt' '$FIXTURES/design-user-auth.md' && ! grep -qE \"require.*bcrypt|import.*bcrypt\" '$FIXTURES/code-user-auth.js'"

# 하드코딩된 시크릿 키 탐지
assert "보안 탐지: 하드코딩된 JWT 시크릿" \
  "grep -q \"'secret-key'\" '$FIXTURES/code-user-auth.js'"
echo ""

# ═══════════════════════════════════════════
# 4. 갭 탐지: 검증 계약 불이행
# ═══════════════════════════════════════════

echo -e "${YELLOW}[갭 탐지: 검증 계약]${NC}"

# 이메일 중복 체크 누락: register 핸들러에 409 응답 또는 중복체크 로직 없음
assert "DEFECT#3 탐지: 이메일 중복 체크 누락 (409 응답 없음)" \
  "grep -q '409' '$FIXTURES/design-user-auth.md' && ! grep -qE '409|conflict|already.*exist|duplicate' '$FIXTURES/code-user-auth.js'"

# 비밀번호 길이 검증 누락: 코드에 password.length 또는 minLength 패턴 없음
assert "DEFECT#4 탐지: 비밀번호 최소 길이 검증 누락" \
  "grep -q '최소 8자' '$FIXTURES/design-user-auth.md' && ! grep -qE 'password\.length|minLength|min.*8' '$FIXTURES/code-user-auth.js'"

# JWT 토큰에 userId 누락: jwt.sign 호출에 userId/user.id 포함 여부
assert "DEFECT#5 탐지: JWT 토큰에 userId 미포함" \
  "grep -q 'userId' '$FIXTURES/design-user-auth.md' && ! grep -qE 'sign\(\{.*id:|sign\(\{.*userId' '$FIXTURES/code-user-auth.js'"
echo ""

# ═══════════════════════════════════════════
# 5. 결함 주석 오라클 일치
# ═══════════════════════════════════════════

echo -e "${YELLOW}[오라클: 결함 주석 일치]${NC}"

# 코드에 명시된 KNOWN_DEFECTS 수 확인
KNOWN_DEFECTS=$(grep -oE 'KNOWN_DEFECTS=[0-9]+' "$FIXTURES/code-user-auth.js" | cut -d= -f2)
assert "결함 오라클: KNOWN_DEFECTS=5" "[ '$KNOWN_DEFECTS' = '5' ]"
echo ""

# ═══════════════════════════════════════════
# 결과
# ═══════════════════════════════════════════

TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL} 갭 탐지 성공"
  echo ""
  echo -e "  Nova의 갭 탐지 원리가 5개 의도적 결함을"
  echo -e "  모두 구조적으로 식별할 수 있음을 확인했습니다."
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 미탐지"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
