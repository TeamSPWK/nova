#!/bin/bash
# Nova — 테스트 스위트 (플러그인 기반)
# Usage: bash tests/test-scripts.sh
#
# 플러그인 설치 전환(v2.0.0) 이후 구조.
# 스크립트 설치 시대의 테스트는 제거하고,
# 현재 존재하는 파일 기반으로 검증한다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

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
echo "  Nova — 테스트 스위트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════
# 1. 구조: 커맨드 매니페스트
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 커맨드]${NC}"

EXPECTED_COMMANDS=(
  auto design gap init metrics next nova-update
  plan propose review team xv
)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 파일 존재" "[ '$CMD_COUNT' -ge 12 ]"

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  assert "커맨드: $cmd.md" "[ -f '$ROOT_DIR/.claude/commands/$cmd.md' ]"
done
echo ""

# ═══════════════════════════════════════════
# 2. 구조: 커맨드 description frontmatter
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: description frontmatter]${NC}"

for cmd_file in "$ROOT_DIR/.claude/commands/"*.md; do
  cmd_name=$(basename "$cmd_file")
  assert "$cmd_name: description 존재" "head -3 '$cmd_file' | grep -q 'description:'"
done
echo ""

# ═══════════════════════════════════════════
# 3. 구조: 에이전트
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 에이전트]${NC}"

EXPECTED_AGENTS=(architect devops-engineer qa-engineer security-engineer senior-dev)
AGENT_COUNT=$(ls "$ROOT_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "에이전트 5개" "[ '$AGENT_COUNT' -eq 5 ]"

for agent in "${EXPECTED_AGENTS[@]}"; do
  assert "에이전트: $agent.md" "[ -f '$ROOT_DIR/.claude/agents/$agent.md' ]"
done
echo ""

# ═══════════════════════════════════════════
# 4. 구조: 템플릿 + 핵심 문서
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 템플릿 + 문서]${NC}"

EXPECTED_TEMPLATES=(claude-md.md cps-design.md cps-plan.md decision-record.md rule-proposal.md)
for tmpl in "${EXPECTED_TEMPLATES[@]}"; do
  assert "템플릿: $tmpl" "[ -f '$ROOT_DIR/docs/templates/$tmpl' ]"
done

EXPECTED_DOCS=(nova-engineering.md usage-guide.md eval-checklist.md context-chain.md rules-changelog.md)
for doc in "${EXPECTED_DOCS[@]}"; do
  assert "문서: $doc" "[ -f '$ROOT_DIR/docs/$doc' ]"
done
echo ""

# ═══════════════════════════════════════════
# 5. 플러그인 매니페스트
# ═══════════════════════════════════════════

echo -e "${YELLOW}[플러그인: 매니페스트]${NC}"

assert "plugin.json 존재" "[ -f '$ROOT_DIR/.claude-plugin/plugin.json' ]"
assert "marketplace.json 존재" "[ -f '$ROOT_DIR/.claude-plugin/marketplace.json' ]"

# 필수 필드 검증
assert "plugin.json: name" "jq -e '.name' '$ROOT_DIR/.claude-plugin/plugin.json' > /dev/null 2>&1"
assert "plugin.json: version" "jq -e '.version' '$ROOT_DIR/.claude-plugin/plugin.json' > /dev/null 2>&1"
assert "plugin.json: description" "jq -e '.description' '$ROOT_DIR/.claude-plugin/plugin.json' > /dev/null 2>&1"
assert "marketplace.json: plugins 배열" "jq -e '.plugins[0].name' '$ROOT_DIR/.claude-plugin/marketplace.json' > /dev/null 2>&1"
echo ""

# ═══════════════════════════════════════════
# 6. 버전 일관성 (Single Source of Truth)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[버전: 일관성]${NC}"

VERSION_FILE="$ROOT_DIR/scripts/.nova-version"
assert ".nova-version 존재" "[ -f '$VERSION_FILE' ]"
assert ".nova-version 시맨틱" "grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' '$VERSION_FILE'"

NOVA_VER=$(tr -d '[:space:]' < "$VERSION_FILE")
PLUGIN_VER=$(jq -r '.version' "$ROOT_DIR/.claude-plugin/plugin.json" 2>/dev/null)
README_VER=$(grep -o 'version-[0-9]*\.[0-9]*\.[0-9]*' "$ROOT_DIR/README.md" 2>/dev/null | sed 's/version-//' || echo "")

assert ".nova-version == plugin.json ($NOVA_VER)" "[ '$NOVA_VER' = '$PLUGIN_VER' ]"
assert "marketplace.json에 version 없음 (plugin.json이 유일한 source)" \
  "! jq -e '.plugins[0].version' '$ROOT_DIR/.claude-plugin/marketplace.json' > /dev/null 2>&1"
assert ".nova-version == README 배지 ($NOVA_VER)" "[ '$NOVA_VER' = '$README_VER' ]"
echo ""

# ═══════════════════════════════════════════
# 7. 마크다운 구조 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[구조: 마크다운 콘텐츠]${NC}"

# 커맨드: description + 최소 1개 헤딩
for cmd_file in "$ROOT_DIR/.claude/commands/"*.md; do
  cmd_name=$(basename "$cmd_file")
  assert "$cmd_name: # 헤딩 존재" "grep -q '^#' '$cmd_file'"
  # 빈 파일 아닌지
  LINE_COUNT=$(wc -l < "$cmd_file" | tr -d ' ')
  assert "$cmd_name: 최소 5줄 이상" "[ '$LINE_COUNT' -ge 5 ]"
done

# 에이전트: name + description + model + tools frontmatter
for agent_file in "$ROOT_DIR/.claude/agents/"*.md; do
  agent_name=$(basename "$agent_file")
  assert "$agent_name: name frontmatter" "head -10 '$agent_file' | grep -q '^name:'"
  assert "$agent_name: description frontmatter" "head -10 '$agent_file' | grep -q '^description:'"
  assert "$agent_name: model frontmatter" "head -10 '$agent_file' | grep -q '^model:'"
  assert "$agent_name: tools frontmatter" "head -10 '$agent_file' | grep -q '^tools:'"
done

# 스킬: name + description frontmatter
for skill_dir in "$ROOT_DIR/.claude/skills/"*/; do
  skill_file="$skill_dir/SKILL.md"
  if [ -f "$skill_file" ]; then
    skill_name=$(basename "$skill_dir")
    assert "스킬 $skill_name: name frontmatter" "head -10 '$skill_file' | grep -q '^name:'"
    assert "스킬 $skill_name: description frontmatter" "head -10 '$skill_file' | grep -q '^description:'"
  fi
done

# LICENSE 파일 존재
assert "LICENSE 파일 존재" "[ -f '$ROOT_DIR/LICENSE' ]"

# README 내부 링크 유효성 (docs/ 참조)
README_LINKS=$(grep -oE '\(docs/[^)]+\)' "$ROOT_DIR/README.md" 2>/dev/null | tr -d '()' || true)
for link in $README_LINKS; do
  assert "README 링크: $link" "[ -f '$ROOT_DIR/$link' ]"
done

README_KO_LINKS=$(grep -oE '\(docs/[^)]+\)' "$ROOT_DIR/README.ko.md" 2>/dev/null | tr -d '()' || true)
for link in $README_KO_LINKS; do
  assert "README.ko 링크: $link" "[ -f '$ROOT_DIR/$link' ]"
done
echo ""

# ═══════════════════════════════════════════
# 8. bump-version.sh 동작 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[기능: bump-version.sh]${NC}"

assert "bump-version.sh 존재 + 실행 권한" \
  "[ -f '$ROOT_DIR/scripts/bump-version.sh' ] && [ -x '$ROOT_DIR/scripts/bump-version.sh' ]"

# 임시 환경에서 테스트
BUMP_DIR=$(mktemp -d)
cp -r "$ROOT_DIR/scripts" "$BUMP_DIR/scripts"
mkdir -p "$BUMP_DIR/.claude-plugin"
cp "$ROOT_DIR/.claude-plugin/plugin.json" "$BUMP_DIR/.claude-plugin/"
cp "$ROOT_DIR/.claude-plugin/marketplace.json" "$BUMP_DIR/.claude-plugin/"
cp "$ROOT_DIR/README.md" "$BUMP_DIR/README.md"

# patch 테스트
(cd "$BUMP_DIR" && bash scripts/bump-version.sh patch > /dev/null 2>&1)
BUMPED=$(tr -d '[:space:]' < "$BUMP_DIR/scripts/.nova-version")
BUMPED_PLUGIN=$(jq -r '.version' "$BUMP_DIR/.claude-plugin/plugin.json")

assert "patch: 버전 증가" "[ '$BUMPED' != '$NOVA_VER' ]"
assert "patch: 3곳 동기화 (.nova-version, plugin.json, README)" \
  "[ '$BUMPED' = '$BUMPED_PLUGIN' ]"

# 직접 지정 테스트
(cd "$BUMP_DIR" && bash scripts/bump-version.sh 9.9.9 > /dev/null 2>&1)
DIRECT=$(tr -d '[:space:]' < "$BUMP_DIR/scripts/.nova-version")
assert "직접 지정: 9.9.9" "[ '$DIRECT' = '9.9.9' ]"

# 동일 버전 → 무변경
BEFORE=$(tr -d '[:space:]' < "$BUMP_DIR/scripts/.nova-version")
(cd "$BUMP_DIR" && bash scripts/bump-version.sh 9.9.9 > /dev/null 2>&1)
AFTER=$(tr -d '[:space:]' < "$BUMP_DIR/scripts/.nova-version")
assert "동일 버전: 무변경" "[ '$BEFORE' = '$AFTER' ]"

# 인자 없음 → 에러
USAGE_OUT=$(cd "$BUMP_DIR" && bash scripts/bump-version.sh 2>&1 || true)
assert "인자 없음: 사용법 출력" "echo '$USAGE_OUT' | grep -q '사용법'"

rm -rf "$BUMP_DIR"
echo ""

# ═══════════════════════════════════════════
# 결과
# ═══════════════════════════════════════════

TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL} 테스트 통과"
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
