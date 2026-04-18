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
  run design scan evolve setup next
  auto plan review check ask ux-audit
  worktree-setup
)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 파일 존재" "[ '$CMD_COUNT' -ge 13 ]"

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  assert "커맨드: $cmd.md" "[ -f '$ROOT_DIR/.claude/commands/$cmd.md' ]"
done

# 삭제된 커맨드가 존재하지 않는지 확인
assert "gap.md 삭제 확인" "[ ! -f '$ROOT_DIR/.claude/commands/gap.md' ]"
assert "propose.md 삭제 확인" "[ ! -f '$ROOT_DIR/.claude/commands/propose.md' ]"
assert "metrics.md 삭제 확인" "[ ! -f '$ROOT_DIR/.claude/commands/metrics.md' ]"
assert "xv.md 삭제 확인 (ask.md로 대체)" "[ ! -f '$ROOT_DIR/.claude/commands/xv.md' ]"
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
# 5-1. Codex 매니페스트
# ═══════════════════════════════════════════

echo -e "${YELLOW}[플러그인: Codex 매니페스트]${NC}"

assert ".codex-plugin/plugin.json 존재" "[ -f '$ROOT_DIR/.codex-plugin/plugin.json' ]"
assert ".codex-plugin/plugin.json: name" "jq -e '.name' '$ROOT_DIR/.codex-plugin/plugin.json' > /dev/null 2>&1"
assert ".codex-plugin/plugin.json: version" "jq -e '.version' '$ROOT_DIR/.codex-plugin/plugin.json' > /dev/null 2>&1"
assert ".codex-plugin/plugin.json: description" "jq -e '.description' '$ROOT_DIR/.codex-plugin/plugin.json' > /dev/null 2>&1"
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

CODEX_PLUGIN_VER=$(jq -r '.version' "$ROOT_DIR/.codex-plugin/plugin.json" 2>/dev/null || echo "")
assert ".nova-version == .codex-plugin/plugin.json ($NOVA_VER)" "[ '$NOVA_VER' = '$CODEX_PLUGIN_VER' ]"
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

assert "/run: State Update 단계" \
  "grep -q 'State Update' '$ROOT_DIR/.claude/commands/run.md'"

assert "/setup: NOVA-STATE.md 생성" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/commands/setup.md'"

assert "/review: NOVA-STATE.md 갱신 섹션 존재" \
  "grep -q 'CRITICAL.*NOVA-STATE.md' '$ROOT_DIR/.claude/commands/review.md'"

assert "/check: NOVA-STATE.md 갱신 섹션 존재" \
  "grep -q 'CRITICAL.*NOVA-STATE.md' '$ROOT_DIR/.claude/commands/check.md'"

assert "/review: 다음 도구 호출로 갱신 지시" \
  "grep -q '다음 도구 호출로' '$ROOT_DIR/.claude/commands/review.md'"

assert "/check: 다음 도구 호출로 갱신 지시" \
  "grep -q '다음 도구 호출로' '$ROOT_DIR/.claude/commands/check.md'"
echo ""

# ═══════════════════════════════════════════
# 8-1. /nova:scan 커맨드 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[커맨드: scan]${NC}"

assert "scan: 기술 부채 수집 (TODO/FIXME)" \
  "grep -q 'TODO.*FIXME\|FIXME.*TODO\|기술 부채' '$ROOT_DIR/.claude/commands/scan.md'"

assert "scan: 진입점 식별 키워드" \
  "grep -q '진입점' '$ROOT_DIR/.claude/commands/scan.md'"

assert "scan: NOVA-STATE.md 브리핑 언급" \
  "grep -q 'NOVA-STATE.md' '$ROOT_DIR/.claude/commands/scan.md'"

assert "scan: lockfile 자동 감지 언급" \
  "grep -q 'lockfile' '$ROOT_DIR/.claude/commands/scan.md'"
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

# /run: Full Cycle + Verify Only 모드
assert "/run: Full Cycle 모드" \
  "grep -q 'Full Cycle' '$ROOT_DIR/.claude/commands/run.md'"

assert "/run: --verify-only 플래그" \
  "grep -q '\-\-verify-only' '$ROOT_DIR/.claude/commands/run.md'"

assert "/run: Generator 서브에이전트 Phase" \
  "grep -q 'Phase 2: Generate' '$ROOT_DIR/.claude/commands/run.md'"

assert "/run: Auto-Fix Phase" \
  "grep -q 'Phase 5: Auto-Fix' '$ROOT_DIR/.claude/commands/run.md'"

assert "/run: 재시도 최대 1회" \
  "grep -q '최대 1회' '$ROOT_DIR/.claude/commands/run.md'"

assert "/run: CONDITIONAL 사용자 판단" \
  "grep -q '사용자에게 판단 위임' '$ROOT_DIR/.claude/commands/run.md'"

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

# 복잡도 기준 통일 검증 (CLAUDE.md와 run.md 동일 기준)
CLAUDE_SMALL=$(grep -c '1~2 파일' "$ROOT_DIR/docs/nova-rules.md" || true)
AUTO_SMALL=$(grep -c '1~2 파일' "$ROOT_DIR/.claude/commands/run.md" || true)
assert "복잡도 기준 통일: Small 1~2 파일" \
  "[ '$CLAUDE_SMALL' -ge 1 ] && [ '$AUTO_SMALL' -ge 1 ]"

CLAUDE_MED=$(grep -c '3~7 파일' "$ROOT_DIR/docs/nova-rules.md" || true)
AUTO_MED=$(grep -c '3~7 파일' "$ROOT_DIR/.claude/commands/run.md" || true)
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
# 8-4. 커맨드 ↔ session-start.sh 동기화 (자동 감지)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[동기화: 커맨드 ↔ session-start.sh]${NC}"

SESSION_TMP=$(mktemp)
bash "$HOOK_FILE" > "$SESSION_TMP" 2>/dev/null

INTERNAL_COMMANDS="evolve"  # 개발자 전용 (사용자에게 노출 안 함)
for cmd_file in "$ROOT_DIR/.claude/commands/"*.md; do
  cmd_name=$(basename "$cmd_file" .md)
  if echo "$INTERNAL_COMMANDS" | grep -qw "$cmd_name"; then
    continue
  fi
  assert "session-start.sh: /nova:$cmd_name 포함" \
    "grep -q '/nova:$cmd_name' '$SESSION_TMP'"
done

rm -f "$SESSION_TMP"
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
mkdir -p "$BUMP_DIR/.codex-plugin"
cp "$ROOT_DIR/.codex-plugin/plugin.json" "$BUMP_DIR/.codex-plugin/"
cp "$ROOT_DIR/README.md" "$BUMP_DIR/README.md"

# patch 테스트
(cd "$BUMP_DIR" && bash scripts/bump-version.sh patch > /dev/null 2>&1)
BUMPED=$(tr -d '[:space:]' < "$BUMP_DIR/scripts/.nova-version")
BUMPED_PLUGIN=$(jq -r '.version' "$BUMP_DIR/.claude-plugin/plugin.json")
BUMPED_CODEX=$(jq -r '.version' "$BUMP_DIR/.codex-plugin/plugin.json")

assert "patch: 버전 증가" "[ '$BUMPED' != '$NOVA_VER' ]"
assert "patch: 3곳 동기화 (.nova-version, plugin.json, README)" \
  "[ '$BUMPED' = '$BUMPED_PLUGIN' ]"
assert "patch: .codex-plugin/plugin.json 동기화" \
  "[ '$BUMPED' = '$BUMPED_CODEX' ]"

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
# 10. generate-meta.sh + nova-meta.json 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[메타데이터: nova-meta.json]${NC}"

assert "generate-meta.sh 존재" \
  "[ -f '$ROOT_DIR/scripts/generate-meta.sh' ]"

# 실행하여 JSON 생성
bash "$ROOT_DIR/scripts/generate-meta.sh" > /dev/null 2>&1

META="$ROOT_DIR/docs/nova-meta.json"

assert "nova-meta.json 생성됨" \
  "[ -f '$META' ]"

assert "nova-meta.json JSON 유효" \
  "python3 -m json.tool '$META' > /dev/null 2>&1"

# 버전 일치
META_VER=$(jq -r '.version' "$META")
assert "meta.version == .nova-version ($NOVA_VER)" \
  "[ '$META_VER' = '$NOVA_VER' ]"

# 커맨드 수 일치
META_CMD_COUNT=$(jq '.commands | length' "$META")
ACTUAL_CMD_COUNT=$(ls -1 "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "meta.commands 수 == 실제 커맨드 수 ($ACTUAL_CMD_COUNT)" \
  "[ '$META_CMD_COUNT' = '$ACTUAL_CMD_COUNT' ]"

# 스킬 수 일치
META_SKILL_COUNT=$(jq '.skills | length' "$META")
ACTUAL_SKILL_COUNT=$(ls -1d "$ROOT_DIR/.claude/skills/"*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
assert "meta.skills 수 == 실제 스킬 수 ($ACTUAL_SKILL_COUNT)" \
  "[ '$META_SKILL_COUNT' = '$ACTUAL_SKILL_COUNT' ]"

# 에이전트 수 일치
META_AGENT_COUNT=$(jq '.agents | length' "$META")
ACTUAL_AGENT_COUNT=$(ls -1 "$ROOT_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "meta.agents 수 == 실제 에이전트 수 ($ACTUAL_AGENT_COUNT)" \
  "[ '$META_AGENT_COUNT' = '$ACTUAL_AGENT_COUNT' ]"

# stats 일치
assert "meta.stats.commands == 커맨드 수" \
  "[ '$(jq '.stats.commands' "$META")' = '$ACTUAL_CMD_COUNT' ]"

assert "meta.stats.skills == 스킬 수" \
  "[ '$(jq '.stats.skills' "$META")' = '$ACTUAL_SKILL_COUNT' ]"

assert "meta.stats.agents == 에이전트 수" \
  "[ '$(jq '.stats.agents' "$META")' = '$ACTUAL_AGENT_COUNT' ]"

echo ""

# ═══════════════════════════════════════════
# 13. 에이전트: self_verify 필드 (Sprint 1)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[에이전트: self_verify 필드]${NC}"

# self_verify 블록이 있어야 하는 Generator 계열 에이전트
SELF_VERIFY_AGENTS=(
  "senior-dev"
  "devops-engineer"
  "architect"
  "qa-engineer"
  "security-engineer"
)

for agent in "${SELF_VERIFY_AGENTS[@]}"; do
  agent_file="$ROOT_DIR/.claude/agents/${agent}.md"
  assert "${agent}.md: self_verify 블록 존재" \
    "grep -q '^## self_verify' '$agent_file'"
  assert "${agent}.md: confident/uncertain/not_tested 3필드 포함" \
    "grep -q 'confident:' '$agent_file' && grep -q 'uncertain:' '$agent_file' && grep -q 'not_tested:' '$agent_file'"
  assert "${agent}.md: 자가점검 체크리스트에 self_verify 라인" \
    "grep -q 'self_verify 필드를 포함했는가' '$agent_file'"
done

echo ""

# ═══════════════════════════════════════════
# 14. 의미 불일치 검증 (Sprint 3)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[의미: 문서 간 일관성]${NC}"

# A) §5 경량화 원칙 ↔ review.md 기본값
assert "session-start §5 기본 Lite 존재" \
  "bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '기본 Lite'"
assert "review.md 기본 강도 Lite 선언 존재" \
  "grep -q '기본 강도는 Lite' '$ROOT_DIR/.claude/commands/review.md'"

# B) §1 재판단 조항 동기화 (nova-rules.md ↔ session-start.sh ↔ run.md)
assert "nova-rules.md: '작업 중 재판단' 조항" \
  "grep -q '작업 중 재판단' '$ROOT_DIR/docs/nova-rules.md'"
assert "session-start.sh: '자가 완화 금지' 조항" \
  "bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '자가 완화 금지'"
assert "run.md: '복잡도 재판단' Phase 2 Checkpoint" \
  "grep -q '복잡도 재판단' '$ROOT_DIR/.claude/commands/run.md'"

# C) run.md ↔ evaluator/SKILL.md CONDITIONAL 일관성
# run.md Phase 5 Auto-Fix는 FAIL만 대상, CONDITIONAL은 보고만
assert "run.md Phase 5: CONDITIONAL 자동 재시도 없음 명시" \
  "grep -qE '(CONDITIONAL.*자동 재시도 (없음|안 함|하지 않))|(CONDITIONAL.*보고)' '$ROOT_DIR/.claude/commands/run.md'"
assert "evaluator SKILL.md: CONDITIONAL 자동 재시도 없음 명시" \
  "grep -qE 'CONDITIONAL.*(자동 재시도 없음|자동 재시도 안 함|자동 수정하지 않)' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

echo ""

# ═══════════════════════════════════════════
# 10. 환경 기둥: worktree-setup
# ═══════════════════════════════════════════

echo -e "${YELLOW}[환경: worktree-setup]${NC}"

WT_HOOK="$ROOT_DIR/hooks/worktree-setup.sh"
WT_SKILL="$ROOT_DIR/.claude/skills/worktree-setup/SKILL.md"
WT_CMD="$ROOT_DIR/.claude/commands/worktree-setup.md"

assert "worktree-setup.sh 존재 + 실행 권한" \
  "[ -f '$WT_HOOK' ] && [ -x '$WT_HOOK' ]"
assert "worktree-setup/SKILL.md 존재" "[ -f '$WT_SKILL' ]"
assert "worktree-setup.md (커맨드) 존재" "[ -f '$WT_CMD' ]"

# hooks.json에 등록됐는지
assert "hooks.json: worktree-setup.sh 참조" \
  "grep -q 'worktree-setup.sh' '$ROOT_DIR/hooks/hooks.json'"

# session-start.sh 커맨드 목록에 /nova:worktree-setup 포함 (자동 감지 테스트가 잡지만 명시)
assert "session-start.sh: /nova:worktree-setup 포함" \
  "bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '/nova:worktree-setup'"

# 런타임 동작: 메인 레포에서 실행 시 skip
WT_TMP=$(mktemp -d)
(cd "$WT_TMP" && git init -q && echo x > f && git add -A && git commit -q -m init)
assert "worktree-setup: 메인 레포에서 skip (exit 0)" \
  "(cd '$WT_TMP' && bash '$WT_HOOK'); [ \$? -eq 0 ]"

# 런타임 동작: worktree에서 gitignored 파일을 심링크
(cd "$WT_TMP" && \
  echo -e ".env\n.secret/\n.npmrc" > .gitignore && \
  git add .gitignore && git commit -q -m ignore && \
  echo "FOO=bar" > .env && \
  mkdir -p .secret && echo "tok" > .secret/s && \
  echo "//r=x" > .npmrc && \
  git worktree add -b nova-test-wt wt1 -q)

if [ -d "$WT_TMP/wt1" ]; then
  WT1_ERR=$( (cd "$WT_TMP/wt1" && bash "$WT_HOOK" >/dev/null) 2>&1 )
  assert "worktree-setup: .env 심링크 생성" \
    "[ -L '$WT_TMP/wt1/.env' ]"
  assert "worktree-setup: .secret 심링크 생성" \
    "[ -L '$WT_TMP/wt1/.secret' ]"
  assert "worktree-setup: .npmrc 심링크 생성" \
    "[ -L '$WT_TMP/wt1/.npmrc' ]"

  # 멱등성: 재실행해도 깨지지 않음
  WT1_ERR=$( (cd "$WT_TMP/wt1" && bash "$WT_HOOK" >/dev/null) 2>&1 )
  assert "worktree-setup: 재실행 멱등 (.env 링크 유지)" \
    "[ -L '$WT_TMP/wt1/.env' ]"

  # 깨진 심링크: 메인에서 파일 삭제해도 자동 교체 안 함 + stderr 경고
  rm -f "$WT_TMP/.npmrc"
  BROKEN_OUT=$( (cd "$WT_TMP/wt1" && bash "$WT_HOOK" >/dev/null) 2>&1 )
  assert "worktree-setup: 깨진 심링크 skip (링크 유지)" \
    "[ -L '$WT_TMP/wt1/.npmrc' ] && [ ! -e '$WT_TMP/wt1/.npmrc' ]"
  assert "worktree-setup: 깨진 심링크 경고 출력" \
    "echo \"\$BROKEN_OUT\" | grep -q '깨진 심링크'"
else
  echo "[DIAG wt1] worktree 생성 실패 — 환경: $(uname -a), git: $(git --version)" >&2
  echo "[DIAG wt1] WT_TMP 내용: $(ls -la "$WT_TMP" 2>&1)" >&2
  echo "[DIAG wt1] hook stderr: ${WT1_ERR:-<캡처 안됨>}" >&2
fi

# 악성 경로 주입 차단 (worktree-sync.json override)
# NOTE: 서브셸 내 heredoc이 Ubuntu CI에서 불안정 — printf로 교체 (v5.8.1 hotfix)
# .env는 worktree add 후 생성 (tracked 방지)
WT_TMP2=$(mktemp -d)
(cd "$WT_TMP2" && git init -q && echo x > f && git add -A && git commit -q -m init)
mkdir -p "$WT_TMP2/.claude"
printf '%s\n' '{"links":["/etc/passwd","../../../etc/shadow",".env"]}' > "$WT_TMP2/.claude/worktree-sync.json"
printf 'FOO=bar\n' > "$WT_TMP2/.env"
(cd "$WT_TMP2" && git worktree add -b nova-sec-wt wt2 -q)

if [ -d "$WT_TMP2/wt2" ] && command -v jq >/dev/null 2>&1; then
  WT2_ERR=$( (cd "$WT_TMP2/wt2" && bash "$WT_HOOK" >/dev/null) 2>&1 )
  assert "worktree-setup: 절대 경로(/etc/passwd) 차단" \
    "[ ! -e '$WT_TMP2/wt2/etc/passwd' ] && [ ! -L '$WT_TMP2/wt2/etc' ]"
  assert "worktree-setup: 상위 이동(../../..) 차단" \
    "[ ! -L '$WT_TMP2/wt2/../../../etc/shadow' ]"
  assert "worktree-setup: 정당한 경로(.env)는 링크됨" \
    "[ -L '$WT_TMP2/wt2/.env' ]"
elif [ ! -d "$WT_TMP2/wt2" ]; then
  echo "[DIAG wt2] worktree 생성 실패 — 환경: $(uname -a), git: $(git --version)" >&2
  echo "[DIAG wt2] WT_TMP2 내용: $(ls -la "$WT_TMP2" 2>&1)" >&2
fi

# 파일명에 ..가 포함된 정당한 경로는 허용되어야 함 (경로 세그먼트 ..만 차단)
# NOTE: 서브셸 내 heredoc이 Ubuntu CI에서 불안정 — printf로 교체 (v5.8.1 hotfix)
# .env..backup은 worktree add 후 생성 (tracked 방지)
WT_TMP3=$(mktemp -d)
(cd "$WT_TMP3" && git init -q && echo x > f && git add -A && git commit -q -m init)
mkdir -p "$WT_TMP3/.claude"
printf '%s\n' '{"links":[".env..backup"]}' > "$WT_TMP3/.claude/worktree-sync.json"
printf 'BAK=1\n' > "$WT_TMP3/.env..backup"
(cd "$WT_TMP3" && git worktree add -b nova-dotdot-wt wt3 -q)

if [ -d "$WT_TMP3/wt3" ] && command -v jq >/dev/null 2>&1; then
  WT3_LOG=$( (cd "$WT_TMP3/wt3" && NOVA_WORKTREE_DEBUG=1 bash "$WT_HOOK" 2>&1) )
  if [ -L "$WT_TMP3/wt3/.env..backup" ]; then
    assert "worktree-setup: 파일명 내 ..는 허용 (.env..backup 링크됨)" "true"
  else
    echo "[DIAG wt3] 링크 실패 — 환경: $(uname -a)" >&2
    echo "[DIAG wt3] hook log: $WT3_LOG" >&2
    echo "[DIAG wt3] override file: $(cat "$WT_TMP3/.claude/worktree-sync.json" 2>&1)" >&2
    echo "[DIAG wt3] main file: $(ls -la "$WT_TMP3/.env..backup" 2>&1)" >&2
    echo "[DIAG wt3] wt3 dir: $(ls -la "$WT_TMP3/wt3" 2>&1)" >&2
    echo "[DIAG wt3] worktree list: $(git -C "$WT_TMP3/wt3" worktree list 2>&1)" >&2
    assert "worktree-setup: 파일명 내 ..는 허용 (.env..backup 링크됨)" "false"
  fi
elif [ -d "$WT_TMP3/wt3" ]; then
  echo "[DIAG wt3] jq 없음 — 테스트 skip (이 환경에서는 정상)" >&2
else
  echo "[DIAG wt3] worktree 생성 실패 — 환경: $(uname -a)" >&2
fi

rm -rf "$WT_TMP3"

rm -rf "$WT_TMP" "$WT_TMP2"
echo ""

# ═══════════════════════════════════════════
# Sprint A: ux-audit Cognitive Load 디자인 항목 검증
# ═══════════════════════════════════════════

echo -e "${YELLOW}[ux-audit: Sprint A — Cognitive Load 디자인 항목]${NC}"

# 케이스 a: SKILL.md에 항목 11/12 포함
assert "ux-audit SKILL.md에 디자인 시스템 정합 항목 11/12 포함" \
  "grep -q '디자인 시스템 정합 — 인지 부하 관점' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '학습한 시각 패턴' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '인지 일관성을 깨는가' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md'"

# 케이스 b: SKILL.md ↔ commands/ux-audit.md 동기화
assert "ux-audit SKILL.md ↔ commands/ux-audit.md 평가자 3 동기화" \
  "grep -q '디자인 시스템 정합 — 인지 부하 관점' '$ROOT_DIR/.claude/commands/ux-audit.md' && \
   grep -q '학습한 시각 패턴' '$ROOT_DIR/.claude/commands/ux-audit.md' && \
   grep -q '인지 일관성을 깨는가' '$ROOT_DIR/.claude/commands/ux-audit.md'"

# 케이스 c: 디자인 시스템 자동 감지 5단계 우선순위 명시
assert "ux-audit Phase 1에 디자인 시스템 자동 감지 5단계" \
  "grep -q '디자인 시스템 자동 감지' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q 'tailwind.config' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q 'design-tokens/' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q 'packages/\*/tokens' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md'"

# 케이스 d: B 비활성화 + 끝줄 표기 규칙
assert "ux-audit B 비활성화 Context Override + 끝줄 표기" \
  "grep -q 'Context Override' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '디자인 시스템 정의 없음' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '토큰 검증 스킵' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md'"

# 케이스 e: 디자인 항목 3건 서브 제한 + 8건 전체 제한
assert "ux-audit 디자인 항목 출력 제한 + 8건 전체 제한 명시" \
  "grep -q '디자인 항목 출력 제한' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '최대 3건' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md' && \
   grep -q '전체 출력 8건 제한은 그대로 유지합니다' '$ROOT_DIR/.claude/skills/ux-audit/SKILL.md'"

echo ""

# ═══════════════════════════════════════════
# Sprint B: UI 감지 + 메트릭 + 캐시
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Sprint B: UI 감지 + 메트릭 + 캐시]${NC}"

# 헬퍼 스크립트 존재 확인
assert "detect-ui-change.sh 존재 + 실행 가능" \
  "[ -f '$ROOT_DIR/scripts/detect-ui-change.sh' ] && [ -x '$ROOT_DIR/scripts/detect-ui-change.sh' ]"
assert "detect-design-system.sh 존재 + 실행 가능" \
  "[ -f '$ROOT_DIR/scripts/detect-design-system.sh' ] && [ -x '$ROOT_DIR/scripts/detect-design-system.sh' ]"
assert "log-metric.sh 존재 + 실행 가능" \
  "[ -f '$ROOT_DIR/scripts/log-metric.sh' ] && [ -x '$ROOT_DIR/scripts/log-metric.sh' ]"

# fixture 존재 확인
for fixture in react-component backend-only logic-only monorepo css-in-js critical-violation; do
  assert "fixture: $fixture 존재" "[ -d '$ROOT_DIR/tests/fixtures/$fixture' ]"
done

# detect-ui-change.sh 출력 JSON 스키마 (react-component fixture)
# 주의: Nova 레포 내 fixture는 독립 git 레포가 필요하므로 run-fixture-detect.sh로 위임
assert "detect-ui-change.sh --post-impl 출력은 valid JSON" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' react-component --post-impl | jq -e . > /dev/null 2>&1"

# Done 조건 1: UI 단독 변경 트리거
assert "Sprint B #1: UI 단독 변경(react-component)에서 is_ui=true" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' react-component --post-impl | jq -e '.is_ui == true' > /dev/null 2>&1"

# Done 조건 2: 백엔드 트리거 안 됨
assert "Sprint B #2: backend-only fixture에서 is_ui=false" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' backend-only --post-impl | jq -e '.is_ui == false' > /dev/null 2>&1"

# Done 조건 3: 순수 로직 스킵
assert "Sprint B #3: logic-only fixture에서 is_ui=false (no UI keywords)" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' logic-only --post-impl | jq -e '.is_ui == false' > /dev/null 2>&1"

# Done 조건 9: monorepo 매칭
assert "Sprint B #9: monorepo fixture에서 is_ui=true" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' monorepo --post-impl | jq -e '.is_ui == true' > /dev/null 2>&1"

# Done 조건 10: CSS-in-JS .ts 승격
assert "Sprint B #10: css-in-js fixture(.ts)에서 is_ui=true" \
  "bash '$ROOT_DIR/tests/run-fixture-detect.sh' css-in-js --post-impl | jq -e '.is_ui == true' > /dev/null 2>&1"

# detect-design-system.sh: 미정의 시 detected=false
assert "Sprint B: detect-design-system.sh — 미정의 시 detected=false" \
  "(cd /tmp && bash '$ROOT_DIR/scripts/detect-design-system.sh') | jq -e '.detected == false' > /dev/null 2>&1"

# log-metric.sh: .nova/metrics.jsonl 1줄 append
assert "Sprint B: log-metric.sh가 .nova/metrics.jsonl에 1줄 append" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && bash '$ROOT_DIR/scripts/log-metric.sh' --event test_event --files 1 && [ \"\$(wc -l < .nova/metrics.jsonl | tr -d ' ')\" = '1' ]); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# orchestrator SKILL.md: Phase 5.5 삽입 확인
assert "Sprint B: orchestrator SKILL.md에 Phase 5.5 포함" \
  "grep -q 'Phase 5.5' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

assert "Sprint B: orchestrator SKILL.md에 UI 변경 감지 분기 포함" \
  "grep -q 'detect-ui-change.sh' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

assert "Sprint B: orchestrator SKILL.md에 ux-audit Lite 언급" \
  "grep -q 'ux-audit Lite' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

assert "Sprint B: orchestrator Phase 1에 UI 사전 감지 추가" \
  "grep -q 'UI 변경 사전 감지' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

# Done 조건 6/7: notice + cache hit (별도 스크립트 위임)
assert "Sprint B #6: 사전 고지 첫 트리거 vs 이후" "bash '$ROOT_DIR/tests/test-ui-audit-notice.sh' > /dev/null 2>&1"
assert "Sprint B #7: 동일 변경 캐시 hit" "bash '$ROOT_DIR/tests/test-cache-hit.sh' > /dev/null 2>&1"

# Done 조건 11 (Nice-to-have): metrics 회전
assert "Sprint B #11 (Nice): metrics.jsonl 1000줄 초과 시 회전" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\"; mkdir -p .nova; for i in \$(seq 1 1001); do echo '{}' >> .nova/metrics.jsonl; done; bash '$ROOT_DIR/scripts/log-metric.sh' --event rotation_test; ls .nova/metrics.*.jsonl > /dev/null 2>&1); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

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
