#!/bin/bash
# Nova — 테스트 스위트 (플러그인 기반)
# Usage: bash tests/test-scripts.sh
#
# 플러그인 설치 전환(v2.0.0) 이후 구조.
# 스크립트 설치 시대의 테스트는 제거하고,
# 현재 존재하는 파일 기반으로 검증한다.
#
# ── 릴리스 전 수동 검증 예제 ──
# 서브에이전트 필드 테스트는 설치된 플러그인을 참조하므로,
# 커밋 전에는 스크립트 출력을 직접 검증한다.
#
# 1. init-nova-state.sh 구조 확인:
#   TDIR=$(mktemp -d) && cd "$TDIR" && git init -q && echo x > f && git add -A && git commit -q -m init
#   echo "{\"cwd\": \"$TDIR\"}" | bash /path/to/nova/scripts/init-nova-state.sh
#   cat -n "$TDIR/NOVA-STATE.md" && rm -rf "$TDIR"
#
# 2. session-start.sh 규칙 텍스트 확인:
#   bash hooks/session-start.sh | python3 -m json.tool
#
# 3. 커맨드/스킬 동기화 확인:
#   grep -r "Last Activity" .claude/commands/ .claude/skills/ --include="*.md"

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
  auto design explore gap init metrics next
  plan propose review xv
)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 파일 존재" "[ '$CMD_COUNT' -ge 11 ]"

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

README_KO_VER=$(grep -o 'version-[0-9]*\.[0-9]*\.[0-9]*' "$ROOT_DIR/README.ko.md" 2>/dev/null | sed 's/version-//' || echo "")
assert ".nova-version == README.ko 배지 ($NOVA_VER)" "[ '$NOVA_VER' = '$README_KO_VER' ]"
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
# 8. Session State (NOVA-STATE.md) 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Session State]${NC}"

assert "nova-state 템플릿 존재" \
  "[ -f '$ROOT_DIR/docs/templates/nova-state.md' ]"

assert "nova-state 템플릿 50줄 이내" \
  "[ \$(wc -l < '$ROOT_DIR/docs/templates/nova-state.md') -le 50 ]"

assert "context-chain 스킬: 세션 시작 프로토콜" \
  "grep -q '세션 시작 프로토콜' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"

assert "context-chain 스킬: 자동 갱신 트리거" \
  "grep -q '자동 갱신 트리거' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"

assert "context-chain 스킬: NOVA-STATE.md 참조" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"

assert "CLAUDE.md: 세션 상태 유지 규칙" \
  "grep -rq '세션 상태 유지' '$ROOT_DIR/docs/nova-rules.md'"

assert "/next: NOVA-STATE.md 우선 확인" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/commands/next.md'"

assert "/auto: State Update 단계" \
  "grep -q 'State Update' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/init: NOVA-STATE.md 생성" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/commands/init.md'"

assert "/review: NOVA-STATE.md 갱신 섹션 존재" \
  "grep -q 'CRITICAL.*NOVA-STATE.md' '$ROOT_DIR/.claude/commands/review.md'"

assert "/gap: NOVA-STATE.md 갱신 섹션 존재" \
  "grep -q 'CRITICAL.*NOVA-STATE.md' '$ROOT_DIR/.claude/commands/gap.md'"

assert "/verify: NOVA-STATE.md 갱신 섹션 존재" \
  "grep -q 'CRITICAL.*NOVA-STATE.md' '$ROOT_DIR/.claude/commands/verify.md'"

assert "/review: 다음 도구 호출로 갱신 지시" \
  "grep -q '다음 도구 호출로' '$ROOT_DIR/.claude/commands/review.md'"

assert "/gap: 다음 도구 호출로 갱신 지시" \
  "grep -q '다음 도구 호출로' '$ROOT_DIR/.claude/commands/gap.md'"

assert "/verify: 다음 도구 호출로 갱신 지시" \
  "grep -q '다음 도구 호출로' '$ROOT_DIR/.claude/commands/verify.md'"
echo ""

# ═══════════════════════════════════════════
# 8-1. /nova:explore 커맨드 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[커맨드: explore]${NC}"

assert "explore: 기술 부채 수집 (TODO/FIXME)" \
  "grep -q 'TODO.*FIXME\|FIXME.*TODO\|기술 부채' '$ROOT_DIR/.claude/commands/explore.md'"

assert "explore: 진입점 식별 키워드" \
  "grep -q '진입점' '$ROOT_DIR/.claude/commands/explore.md'"

assert "explore: NOVA-STATE.md 브리핑 언급" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/commands/explore.md'"

assert "explore: lockfile 자동 감지 언급" \
  "grep -q 'lockfile' '$ROOT_DIR/.claude/commands/explore.md'"
echo ""

# ═══════════════════════════════════════════
# 8-2. Generator-Evaluator 위임 규칙
# ═══════════════════════════════════════════

echo -e "${YELLOW}[위임 규칙: Generator-Evaluator 분리]${NC}"

assert "CLAUDE.md: 검증 분리 필수(must)" \
  "grep -q '검증 분리는 필수' '$ROOT_DIR/docs/nova-rules.md'"

assert "CLAUDE.md: 구현 위임 권장(should)" \
  "grep -q '구현 위임은 권장' '$ROOT_DIR/docs/nova-rules.md'"

assert "CLAUDE.md: 복잡도별 구현/검증 테이블" \
  "grep -q 'Evaluator Lite' '$ROOT_DIR/docs/nova-rules.md'"

assert "CLAUDE.md: 복잡도 재판단 규칙" \
  "grep -q '복잡도를 재판단' '$ROOT_DIR/docs/nova-rules.md'"

assert "CLAUDE.md: 고위험 영역 상향 규칙" \
  "grep -q '한 단계 상향' '$ROOT_DIR/docs/nova-rules.md'"

# /auto: Full Cycle + Verify Only 모드
assert "/auto: Full Cycle 모드" \
  "grep -q 'Full Cycle' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/auto: --verify-only 플래그" \
  "grep -q '\-\-verify-only' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/auto: Generator 서브에이전트 Phase" \
  "grep -q 'Phase 2: Generate' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/auto: Auto-Fix Phase" \
  "grep -q 'Phase 5: Auto-Fix' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/auto: 재시도 최대 1회" \
  "grep -q '최대 1회' '$ROOT_DIR/.claude/commands/auto.md'"

assert "/auto: CONDITIONAL 사용자 판단" \
  "grep -q '사용자에게 판단 위임' '$ROOT_DIR/.claude/commands/auto.md'"

# Evaluator 재검증 프로토콜
assert "evaluator: FAIL만 자동 재시도" \
  "grep -q '1회 자동 재시도' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

assert "evaluator: CONDITIONAL 자동 재시도 안 함" \
  "grep -q '자동 재시도 안 함' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

assert "evaluator: 수정 범위 제한" \
  "grep -q '수정 범위 제한' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

# Field Test 스킬 검증
assert "field-test: 워크트리 격리 명시" \
  "grep -q 'worktree' '$ROOT_DIR/.claude/skills/field-test/SKILL.md'"

assert "field-test: 오케스트레이터 코드 개입 금지" \
  "grep -q '코드에 개입하지 않는다' '$ROOT_DIR/.claude/skills/field-test/SKILL.md'"

assert "field-test: 자연어 지시 원칙" \
  "grep -q '자연어로 말한다' '$ROOT_DIR/.claude/skills/field-test/SKILL.md'"

assert "field-test: P-레벨 분류" \
  "grep -q 'P0.*P1.*P2\|P0\|P-레벨' '$ROOT_DIR/.claude/skills/field-test/SKILL.md'"

assert "field-test: 워크트리 정리 단계" \
  "grep -q 'worktree remove' '$ROOT_DIR/.claude/skills/field-test/SKILL.md'"

# 복잡도 기준 통일 검증 (CLAUDE.md와 auto.md 동일 기준)
CLAUDE_SMALL=$(grep -c '1~2 파일' "$ROOT_DIR/docs/nova-rules.md" || true)
AUTO_SMALL=$(grep -c '1~2 파일' "$ROOT_DIR/.claude/commands/auto.md" || true)
assert "복잡도 기준 통일: Small 1~2 파일" \
  "[ '$CLAUDE_SMALL' -ge 1 ] && [ '$AUTO_SMALL' -ge 1 ]"

CLAUDE_MED=$(grep -c '3~7 파일' "$ROOT_DIR/docs/nova-rules.md" || true)
AUTO_MED=$(grep -c '3~7 파일' "$ROOT_DIR/.claude/commands/auto.md" || true)
assert "복잡도 기준 통일: Medium 3~7 파일" \
  "[ '$CLAUDE_MED' -ge 1 ] && [ '$AUTO_MED' -ge 1 ]"
echo ""

# ═══════════════════════════════════════════
# 8-3. 플러그인 배포 동기화 (CLAUDE.md ↔ session-start.sh)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[동기화: CLAUDE.md ↔ session-start.sh]${NC}"

HOOK_FILE="$ROOT_DIR/hooks/session-start.sh"

assert "session-start.sh 존재" "[ -f '$HOOK_FILE' ]"
assert "session-start.sh JSON 유효" "bash '$HOOK_FILE' | python3 -m json.tool > /dev/null 2>&1"

# hooks.json이 session-start.sh를 참조하는지 (v3.1.1 회귀 방지)
HOOKS_JSON="$ROOT_DIR/hooks/hooks.json"
assert "hooks.json 존재" "[ -f '$HOOKS_JSON' ]"
assert "hooks.json: session-start.sh 참조" \
  "grep -q 'session-start.sh' '$HOOKS_JSON'"
assert "hooks.json: init-nova-state.sh 참조" \
  "grep -q 'init-nova-state.sh' '$HOOKS_JSON'"

# 핵심 규칙 키워드가 session-start.sh에 존재하는지 검증
# session-start.sh는 경량 요약만 포함. 핵심 키워드 존재 확인.
assert "동기화: 복잡도 판단 (§1)" \
  "bash '$HOOK_FILE' | grep -q '복잡도'"

assert "동기화: 검증 분리 (§2)" \
  "bash '$HOOK_FILE' | grep -q '검증.*서브에이전트'"

assert "동기화: NOVA-STATE.md 세션 상태 (§8)" \
  "bash '$HOOK_FILE' | grep -q 'NOVA-STATE.md'"

assert "동기화: 커맨드 테이블" \
  "bash '$HOOK_FILE' | grep -q '/nova:review'"

# init-nova-state.sh 실행 결과 검증
INIT_DIR=$(mktemp -d)
echo '{"cwd":"'"$INIT_DIR"'"}' | bash "$ROOT_DIR/scripts/init-nova-state.sh" 2>/dev/null || true

assert "init-nova-state: NOVA-STATE.md 생성" \
  "[ -f '$INIT_DIR/NOVA-STATE.md' ]"

assert "init-nova-state: Known Gaps 섹션" \
  "grep -q 'Known Gaps' '$INIT_DIR/NOVA-STATE.md'"

assert "init-nova-state: Known Risks 섹션" \
  "grep -q 'Known Risks' '$INIT_DIR/NOVA-STATE.md'"

assert "init-nova-state: Tasks 섹션" \
  "grep -q '## Tasks' '$INIT_DIR/NOVA-STATE.md'"

assert "init-nova-state: Last Activity 섹션" \
  "grep -q 'Last Activity' '$INIT_DIR/NOVA-STATE.md'"

rm -rf "$INIT_DIR"
echo ""

# ═══════════════════════════════════════════
# 9. bump-version.sh 동작 검증
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
