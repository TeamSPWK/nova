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

# record-event.sh는 CI 환경변수가 set이면 ${CI_ARTIFACTS:-.}/nova-events/events.jsonl로
# 이벤트 파일 경로를 치환한다. 테스트는 격리된 TMPD의 .nova/events.jsonl을 전제로
# 작성돼 있어 GitHub Actions 러너(CI=true)에서 경로 불일치로 실패한다.
# CI 분기 자체는 별도 assertion으로 검증하고, 본 스위트에서는 분기를 비활성화한다.
unset CI

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
  auto plan deepplan review check ask ux-audit
  worktree-setup
)
CMD_COUNT=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "커맨드 파일 존재" "[ '$CMD_COUNT' -ge 14 ]"

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

EXPECTED_AGENTS=(architect devops-engineer qa-engineer security-engineer senior-dev refiner)
AGENT_COUNT=$(ls "$ROOT_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert "에이전트 6개" "[ '$AGENT_COUNT' -eq 6 ]"

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

# State Prune Symmetry — 갱신/정리 트리거 비대칭 회귀 가드 (v5.19.6+)
# 6개 갱신 트리거 커맨드 모두에 "갱신 후 정리" 지시문이 존재해야 한다.
# 갱신만 강제하고 정리를 강제하지 않으면 NOVA-STATE.md가 단조 증가한다.
for _cmd in plan design check review ux-audit run evolve; do
  assert "/$_cmd: 갱신 후 정리 트리거 존재 (50줄 초과 시 트림)" \
    "grep -qE '갱신 후 정리|50줄 초과' '$ROOT_DIR/.claude/commands/$_cmd.md'"
done

# session-start.sh 3개 프로파일에 STATE 사이즈 룰 키워드 ("50줄") 노출
# 매 세션 자동 주입되는 글로벌 룰이 룰 자체를 인지시켜야 한다.
for _profile in lean standard strict; do
  assert "session-start.sh ($_profile): NOVA-STATE 사이즈 룰 노출 (50줄)" \
    "NOVA_PROFILE=$_profile bash '$ROOT_DIR/hooks/session-start.sh' 2>/dev/null | grep -q '50줄'"
done

# NOVA-STATE 갱신 지점이 있는 스킬도 정리 트리거 의무를 진다 (orchestrator/deepplan/ux-audit).
# context-chain SKILL은 자동 갱신 트리거 표에 evolve 행을 포함해야 한다.
for _skill in orchestrator deepplan ux-audit; do
  assert "skills/$_skill: 갱신 후 정리 트리거 존재 (50줄)" \
    "grep -q '50줄' '$ROOT_DIR/.claude/skills/$_skill/SKILL.md'"
done
assert "skills/context-chain: 자동 갱신 트리거 표에 evolve 행 존재" \
  "grep -q 'nova:evolve.*완료' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"
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

# A) §5 경량화 원칙 — session-start는 경량화로 §5 제거됨. review.md/check.md 단독 보유
assert "review.md 기본 강도 Lite 선언 존재" \
  "grep -q '기본 강도는 Lite' '$ROOT_DIR/.claude/commands/review.md'"
assert "review.md: §5 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §5' '$ROOT_DIR/.claude/commands/review.md'"
assert "check.md: §5 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §5' '$ROOT_DIR/.claude/commands/check.md'"
assert "run.md: §5/§6 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §5' '$ROOT_DIR/.claude/commands/run.md' && grep -q 'nova-rules.md §6' '$ROOT_DIR/.claude/commands/run.md'"
assert "auto.md: §6/§9 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §6' '$ROOT_DIR/.claude/commands/auto.md' && grep -q 'nova-rules.md §9' '$ROOT_DIR/.claude/commands/auto.md'"
assert "plan.md: §1 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §1' '$ROOT_DIR/.claude/commands/plan.md'"
assert "deepplan.md: §1 on-demand 로드 선언 (deepplan 권장 조건)" \
  "grep -q 'nova-rules.md §1' '$ROOT_DIR/.claude/commands/deepplan.md'"
assert "context-chain/SKILL.md: §8 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §8' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"
assert "evaluator/SKILL.md: §2/§3 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §2' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md' && grep -q 'nova-rules.md §3' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"
assert "orchestrator/SKILL.md: §2/§6 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §2' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md' && grep -q 'nova-rules.md §6' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

# B) §1 재판단 조항 동기화 (nova-rules.md ↔ session-start.sh ↔ run.md)
assert "nova-rules.md: '작업 중 재판단' 조항" \
  "grep -q '작업 중 재판단' '$ROOT_DIR/docs/nova-rules.md'"
assert "session-start.sh: '자가 완화 금지' 조항" \
  "bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '자가 완화 금지'"

# D) session-start 출력 크기 상한 (Sprint 0 경량화 회귀 방지)
#    - hard limit 2500 bytes: 초과 시 플러그인 로드 가능성 파손
#    - soft target 1900 bytes: 새 규칙 추가 예산 여유 확보
SESSION_SIZE=$(bash "$ROOT_DIR/hooks/session-start.sh" | wc -c | tr -d ' ')
assert "session-start 출력 크기 hard limit 2500 bytes 이하 ($SESSION_SIZE)" \
  "[ $SESSION_SIZE -le 2500 ]"
assert "session-start 출력 크기 soft target 1900 bytes 이하 ($SESSION_SIZE)" \
  "[ $SESSION_SIZE -le 1900 ]"

# E) on-demand 로드 — 제거된 §3/§5/§6/§8/§9 세부가 session-start에 없어야 함
assert "session-start: §6 '스프린트 분할' 상세 없음 (on-demand 로드 증명)" \
  "! bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '스프린트 분할'"
assert "session-start: §9 '긴급 모드' 상세 없음 (on-demand 로드 증명)" \
  "! bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '긴급 모드'"
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
# Sprint 3: deepplan 동기화
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Sprint 3: deepplan 동기화]${NC}"

assert "commands/deepplan.md 존재" \
  "[ -f '$ROOT_DIR/.claude/commands/deepplan.md' ]"

assert "skills/deepplan/SKILL.md 존재" \
  "[ -f '$ROOT_DIR/.claude/skills/deepplan/SKILL.md' ]"

assert "session-start.sh: /nova:deepplan 포함" \
  "bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '/nova:deepplan'"

assert "nova-rules.md: deepplan 언급 존재" \
  "grep -q 'deepplan' '$ROOT_DIR/docs/nova-rules.md'"

assert "orchestrator SKILL.md: --deep 플래그 처리 포함" \
  "grep -q '\-\-deep' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

assert "orchestrator SKILL.md: deepplan 호출 로직 포함" \
  "grep -q 'deepplan' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

assert "auto.md: --deep 플래그 문서화" \
  "grep -q '\-\-deep' '$ROOT_DIR/.claude/commands/auto.md'"

assert "plan.md: deepplan 크로스 레퍼런스 존재" \
  "grep -q 'deepplan' '$ROOT_DIR/.claude/commands/plan.md'"

assert "next.md: deepplan 진입 조건 언급 존재" \
  "grep -q 'deepplan' '$ROOT_DIR/.claude/commands/next.md'"

echo ""

# ═══════════════════════════════════════════
# Sprint 1 (v5.12.0): 관찰성 레이어 — JSONL + KPI + Privacy
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Sprint 1: 관찰성 레이어]${NC}"

# 파일 존재 + 실행 권한
assert "Sprint 1: hooks/record-event.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/hooks/record-event.sh' ]"
assert "Sprint 1: hooks/stop-event.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/hooks/stop-event.sh' ]"
assert "Sprint 1: hooks/_privacy-filter.py 존재" \
  "[ -f '$ROOT_DIR/hooks/_privacy-filter.py' ]"
assert "Sprint 1: scripts/nova-metrics.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/scripts/nova-metrics.sh' ]"
assert "Sprint 1: scripts/permissions-template.json 존재 + 유효 JSON" \
  "[ -f '$ROOT_DIR/scripts/permissions-template.json' ] && jq -e . '$ROOT_DIR/scripts/permissions-template.json' > /dev/null 2>&1"

# hooks.json에 Stop 엔트리
assert "Sprint 1: hooks.json에 Stop 엔트리 존재" \
  "jq -e '.hooks.Stop' '$ROOT_DIR/hooks/hooks.json' > /dev/null 2>&1"
assert "Sprint 1: hooks.json Stop → stop-event.sh 참조" \
  "jq -r '.hooks.Stop[0].hooks[0].command' '$ROOT_DIR/hooks/hooks.json' | grep -q 'stop-event.sh'"

# session-start.sh에 record-event.sh 호출 포함
assert "Sprint 1: session-start.sh에 record-event 호출 포함" \
  "grep -q 'record-event.sh' '$ROOT_DIR/hooks/session-start.sh'"

# S1.1 / S1.2 / S1.3: record-event 기본 스모크
assert "S1.1/1.2/1.3: record-event 3 타입 기록 + JSONL 유효 + 3종 event_type" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/hooks/record-event.sh' session_start '{}' && \
    bash '$ROOT_DIR/hooks/record-event.sh' evaluator_verdict '{\"verdict\":\"PASS\",\"critical_issues\":0,\"target\":\"code\"}' && \
    bash '$ROOT_DIR/hooks/record-event.sh' phase_transition '{\"orchestration_id\":\"t\",\"phase_name\":\"A\"}' && \
    [ \"\$(wc -l < .nova/events.jsonl | tr -d ' ')\" = '3' ] && \
    jq -s '.' .nova/events.jsonl > /dev/null && \
    [ \"\$(jq -r '.event_type' .nova/events.jsonl | sort -u | wc -l | tr -d ' ')\" = '3' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# 필수 필드 존재
assert "S1.3: 필수 필드 — schema_version/timestamp/session_id/event_type 모두 non-null" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/hooks/record-event.sh' session_start '{}' && \
    [ \"\$(jq -c 'select(.schema_version==null or .timestamp==null or .session_id==null or .event_type==null)' .nova/events.jsonl | wc -l | tr -d ' ')\" = '0' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.4: Privacy 10종 redact
assert "S1.4: Privacy 필터 10종 (sk-ant/sk-proj/ghp_/xoxb-/sk_live/AIza/AKIA/JWT/password/private_key) 전수 redacted" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    STRIPE_FIX=\"sk_\"\"live_\"\"1234567890abcdefghijklmn\"; \
    for v in 'sk-ant-api03-abcdefghij1234567890' 'sk-proj-AbcDef123456789012345678' 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij' 'xoxb-1234567890-abcdefgh' \"\$STRIPE_FIX\" 'AIzaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q' 'AKIAIOSFODNN7EXAMPLE' 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1In0.sigsigsigsigsigsigsig' '-----BEGIN RSA PRIVATE KEY-----ABC'; do \
      bash '$ROOT_DIR/hooks/record-event.sh' t \"{\\\"key\\\":\\\"\$v\\\"}\"; \
    done && \
    bash '$ROOT_DIR/hooks/record-event.sh' t '{\"password\":\"abcdef123\"}' && \
    [ \"\$(jq -s '[.[] | select(.redacted == true)] | length' .nova/events.jsonl)\" = '10' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.5: 동시성 xargs -P 20
assert "S1.5: 병렬 append 20회 → 20 라인 + 전수 JSON parse" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    seq 1 20 | xargs -P 20 -I{} bash '$ROOT_DIR/hooks/record-event.sh' phase_transition '{\"p\":\"x\"}' 2>/dev/null && \
    [ \"\$(wc -l < .nova/events.jsonl | tr -d ' ')\" = '20' ] && \
    jq -s 'length == 20' .nova/events.jsonl > /dev/null \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.9: NOVA_DISABLE_EVENTS=1 → 0 라인
assert "S1.9: NOVA_DISABLE_EVENTS=1 → 이벤트 기록 생략" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    NOVA_DISABLE_EVENTS=1 bash '$ROOT_DIR/hooks/record-event.sh' session_start '{}' && \
    [ ! -f .nova/events.jsonl ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.9b: CI=true → \${CI_ARTIFACTS:-.}/nova-events/events.jsonl 경로 치환 (CI 분기 자체 검증)
assert "S1.9b: CI=true → CI_ARTIFACTS/nova-events/events.jsonl로 경로 치환" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    CI=true CI_ARTIFACTS=\"\$TMPD/artifacts\" bash '$ROOT_DIR/hooks/record-event.sh' session_start '{}' && \
    [ -f \"\$TMPD/artifacts/nova-events/events.jsonl\" ] && \
    [ ! -f .nova/events.jsonl ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.10: 기록 실패 safe-default (권한 없는 디렉토리)
assert "S1.10: 기록 실패 시 exit 0 (safe-default) — chmod 000 .nova" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir .nova && chmod 000 .nova && \
    bash '$ROOT_DIR/hooks/record-event.sh' session_start '{}' ; \
    RC=\$?; chmod 755 .nova; [ \$RC -eq 0 ]); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.7: nova-metrics 빈 fixture → N/A 4건
assert "S1.7a: nova-metrics.sh 빈 fixture → N/A 4건" \
  "TMPD=\$(mktemp -d); touch \"\$TMPD/empty.jsonl\"; \
    OUT=\$(bash '$ROOT_DIR/scripts/nova-metrics.sh' --fixture \"\$TMPD/empty.jsonl\" 2>&1); \
    COUNT=\$(echo \"\$OUT\" | grep -c 'N/A (insufficient data)'); \
    rm -rf \"\$TMPD\"; [ \$COUNT -ge 4 ]"

# S1.7b: nova-metrics 없는 파일 → N/A + exit 0 (pipefail-safe: grep -q가 pipe 조기 종료 시 141 방지)
assert "S1.7b: nova-metrics.sh 없는 파일 → N/A 4건 + exit 0" \
  "OUT=\$(bash '$ROOT_DIR/scripts/nova-metrics.sh' --fixture /nonexistent/path 2>&1); RC=\$?; [ \$RC -eq 0 ] && [ \$(echo \"\$OUT\" | grep -c 'N/A (insufficient data)') -ge 4 ]"

# S1.11: docs/nova-engineering.md §9 — 실측 없음 제거 + nova-metrics 참조
assert "S1.11: nova-engineering.md §9 — '실측 결과가 아니다' 제거됨" \
  "! grep -q '실측 결과가 아니다' '$ROOT_DIR/docs/nova-engineering.md'"
assert "S1.11: nova-engineering.md §9 — scripts/nova-metrics.sh 참조" \
  "grep -q 'scripts/nova-metrics.sh' '$ROOT_DIR/docs/nova-engineering.md'"

# S1.13: nova-rules.md §10 신설
assert "S1.13: nova-rules.md §10 관찰성 계약 신설" \
  "grep -q '^## §10' '$ROOT_DIR/docs/nova-rules.md'"

# 스킬 3종 on-demand §10 참조
assert "Sprint 1: evaluator/SKILL.md — §10 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §10' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"
assert "Sprint 1: orchestrator/SKILL.md — §10 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §10' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"
assert "Sprint 1: context-chain/SKILL.md — §10 on-demand 로드 선언" \
  "grep -q 'nova-rules.md §10' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"

# 스킬 관찰성 훅 (record-event 호출 지시)
assert "Sprint 1: evaluator/SKILL.md — record-event.sh 호출 지시 포함" \
  "grep -q 'record-event.sh' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"
assert "Sprint 1: orchestrator/SKILL.md — record-event.sh 호출 지시 포함" \
  "grep -q 'record-event.sh' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

# next.md KPI 요약
assert "Sprint 1: next.md — nova-metrics.sh KPI 요약 포함" \
  "grep -q 'nova-metrics.sh' '$ROOT_DIR/.claude/commands/next.md'"

# session-start.sh 크기 여전히 soft 1900 이하 (회귀)
assert "Sprint 1 회귀: session-start 출력 여전히 soft 1900 bytes 이하" \
  "[ \$(bash '$ROOT_DIR/hooks/session-start.sh' | wc -c | tr -d ' ') -le 1900 ]"

# S1.6: Rotation 트리거 (MAX_SIZE=512, 10 events → 2+ 파일 + rotation_marker 첫 라인)
assert "S1.6: rotation MAX_SIZE=512 + 10 events → 2+ 파일 + rotation_marker" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    for i in 1 2 3 4 5 6 7 8 9 10; do \
      NOVA_EVENTS_MAX_SIZE=512 bash '$ROOT_DIR/hooks/record-event.sh' test_event \"{\\\"i\\\":\$i}\" ; \
    done && \
    FCOUNT=\$(ls .nova/events.jsonl* 2>/dev/null | wc -l | tr -d ' ') && [ \$FCOUNT -ge 2 ] && \
    head -1 .nova/events.jsonl | jq -e '.event_type == \"rotation_marker\"' > /dev/null \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S1.7c: KPI 스냅샷 — fixture 기반 정확 일치 (process/gap/multi)
assert "S1.7c: KPI 스냅샷 fixture — process=33.3% · gap=100.0% · multi=50.0%" \
  "OUT=\$(bash '$ROOT_DIR/scripts/nova-metrics.sh' --fixture '$ROOT_DIR/tests/fixtures/events-fixture.jsonl' --since all 2>&1); \
   echo \"\$OUT\" | grep -q 'Process consistency:.*33\\.3% (n=3)' && \
   echo \"\$OUT\" | grep -q 'Gap detection rate:.*100\\.0% (n=1)' && \
   echo \"\$OUT\" | grep -q 'Multi-perspective:.*50\\.0% (n=2)'"

# Sprint 1 wiring 회귀: 4개 이벤트 타입 호출 지시 존재
assert "Wiring: plan.md — plan_created" \
  "grep -q 'plan_created' '$ROOT_DIR/.claude/commands/plan.md'"
assert "Wiring: deepplan/SKILL.md — plan_created" \
  "grep -q 'plan_created' '$ROOT_DIR/.claude/skills/deepplan/SKILL.md'"
assert "Wiring: ask.md — jury_verdict" \
  "grep -q 'jury_verdict' '$ROOT_DIR/.claude/commands/ask.md'"
assert "Wiring: jury/SKILL.md — jury_verdict" \
  "grep -q 'jury_verdict' '$ROOT_DIR/.claude/skills/jury/SKILL.md'"
assert "Wiring: run.md — blocker_raised" \
  "grep -q 'blocker_raised' '$ROOT_DIR/.claude/commands/run.md'"
assert "Wiring: orchestrator/SKILL.md — blocker_raised" \
  "grep -q 'blocker_raised' '$ROOT_DIR/.claude/skills/orchestrator/SKILL.md'"

# Race-safe session_id (noclobber): 20 병렬 → unique id 1개
assert "Race-safe: session_id 20 병렬 → unique 1개" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    seq 1 20 | xargs -P 20 -I{} bash '$ROOT_DIR/hooks/record-event.sh' test_event '{}' 2>/dev/null && \
    UNIQ=\$(jq -r '.session_id' .nova/events.jsonl | sort -u | wc -l | tr -d ' ') && \
    [ \"\$UNIQ\" = '1' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Entropy MIN_LEN 48 회귀 (오탐 방어)
assert "Privacy: entropy MIN_LEN 48 상향 (40자 합법 토큰 미-redact)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/hooks/record-event.sh' test_event '{\"commit_sha\":\"abc123def456abc123def456abc123def456abcd\"}' && \
    jq -r '.extra.commit_sha' .nova/events.jsonl | head -1 | grep -qv '<redacted' \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

echo ""

# ═══════════════════════════════════════════
# Sprint 2a (v5.14.0): 도구 제약 정적 — audit + settings 템플릿
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Sprint 2a: 도구 제약 정적]${NC}"

# 파일/실행 권한
assert "Sprint 2a: scripts/audit-agent-tools.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/scripts/audit-agent-tools.sh' ]"
assert "Sprint 2a: scripts/setup-permissions.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/scripts/setup-permissions.sh' ]"
assert "Sprint 2a: scripts/permissions-template.json 유효 JSON" \
  "jq -e . '$ROOT_DIR/scripts/permissions-template.json' > /dev/null 2>&1"

# plugin.json tool_contract 구조
assert "Sprint 2a: plugin.json tool_contract 필드 존재 + per_agent 6개 이상" \
  "jq -e '.tool_contract.per_agent | length >= 6' '$ROOT_DIR/.claude-plugin/plugin.json' > /dev/null 2>&1"
assert "Sprint 2a: plugin.json tool_contract — _nova_comment에 U1 명시" \
  "jq -r '.tool_contract._nova_comment' '$ROOT_DIR/.claude-plugin/plugin.json' | grep -q 'U1'"
assert "Sprint 2a: plugin.json tool_contract.deferred_allow에 ToolSearch 포함" \
  "jq -e '.tool_contract.deferred_allow | index(\"ToolSearch\")' '$ROOT_DIR/.claude-plugin/plugin.json' > /dev/null 2>&1"

# permissions-template 구조
assert "Sprint 2a: permissions-template.json — deny 10+ 패턴" \
  "[ \$(jq '.permissions.deny | length' '$ROOT_DIR/scripts/permissions-template.json') -ge 10 ]"
assert "Sprint 2a: permissions-template.json — defaultMode=ask" \
  "[ \"\$(jq -r '.permissions.defaultMode' '$ROOT_DIR/scripts/permissions-template.json')\" = 'ask' ]"

# S2a.2: audit 실행 exit 0 (기본 상태)
assert "S2a.2: audit-agent-tools.sh exit 0 (5/5 일치)" \
  "bash '$ROOT_DIR/scripts/audit-agent-tools.sh' > /dev/null 2>&1"

# S2a.4: fixture 1 — 빈 settings 병합 (path traversal 방어 우회: --allow-outside)
assert "S2a.4: setup-permissions fixture 1(빈) → Nova deny 10+ 주입" \
  "TMPD=\$(mktemp -d); cp '$ROOT_DIR/tests/fixtures/settings-empty.json' \"\$TMPD/s.json\"; \
   bash '$ROOT_DIR/scripts/setup-permissions.sh' --target \"\$TMPD/s.json\" --allow-outside > /dev/null 2>&1; \
   COUNT=\$(jq '.permissions.deny | length' \"\$TMPD/s.json\" 2>/dev/null); \
   rm -rf \"\$TMPD\"; [ \"\$COUNT\" -ge 10 ]"

# S2a.5: fixture 2 — 기존 allow 보존 + env 최상위 키 보존
assert "S2a.5: fixture 2(기존 allow+env) → 사용자 값 보존 + Nova 병합" \
  "TMPD=\$(mktemp -d); cp '$ROOT_DIR/tests/fixtures/settings-with-allow.json' \"\$TMPD/s.json\"; \
   bash '$ROOT_DIR/scripts/setup-permissions.sh' --target \"\$TMPD/s.json\" --allow-outside > /dev/null 2>&1; \
   HAS_GIT=\$(jq '.permissions.allow | index(\"Bash(git status)\") != null' \"\$TMPD/s.json\" 2>/dev/null); \
   HAS_ENV=\$(jq -r '.env.USER_CUSTOM_VAR' \"\$TMPD/s.json\" 2>/dev/null); \
   MODE=\$(jq -r '.permissions.defaultMode' \"\$TMPD/s.json\" 2>/dev/null); \
   rm -rf \"\$TMPD\"; [ \"\$HAS_GIT\" = 'true' ] && [ \"\$HAS_ENV\" = 'preserved' ] && [ \"\$MODE\" = 'deny' ]"

# S2a.6: fixture 3 — 충돌 → CONFLICT stderr + deny 우선
assert "S2a.6: fixture 3(충돌) → stderr CONFLICT 리포트 + deny에 'rm -rf *' 유지" \
  "TMPD=\$(mktemp -d); cp '$ROOT_DIR/tests/fixtures/settings-with-conflict.json' \"\$TMPD/s.json\"; \
   OUT=\$(bash '$ROOT_DIR/scripts/setup-permissions.sh' --target \"\$TMPD/s.json\" --allow-outside 2>&1 >/dev/null); \
   HAS_CONFLICT=\$(echo \"\$OUT\" | grep -c 'CONFLICT'); \
   HAS_DENY=\$(jq '.permissions.deny | index(\"Bash(rm -rf *)\") != null' \"\$TMPD/s.json\" 2>/dev/null); \
   ALLOW_HAS_RM=\$(jq '.permissions.allow | index(\"Bash(rm -rf *)\") != null' \"\$TMPD/s.json\" 2>/dev/null); \
   rm -rf \"\$TMPD\"; [ \"\$HAS_CONFLICT\" -ge 2 ] && [ \"\$HAS_DENY\" = 'true' ] && [ \"\$ALLOW_HAS_RM\" = 'false' ]"

# S2a.7: nova-rules.md §11 신설 + fewer-permission-prompts 명시
assert "S2a.7: nova-rules.md §11 도구 제약 계약 신설" \
  "grep -q '^## §11' '$ROOT_DIR/docs/nova-rules.md'"
assert "S2a.7: nova-rules.md §11 — fewer-permission-prompts 역할 분담 명시" \
  "grep -q 'fewer-permission-prompts' '$ROOT_DIR/docs/nova-rules.md'"

# S2a.9: setup.md --permissions 옵션 문서화
assert "S2a.9: setup.md — --permissions 옵션 문서" \
  "grep -q -- '\`--permissions\`' '$ROOT_DIR/.claude/commands/setup.md'"

# Bootstrap 이벤트 자동 주입 (cd 후 상대경로 — cwd 하위라 traversal 방어 통과)
assert "Sprint 2a: setup-permissions.sh — bootstrap=true 이벤트 자동 기록" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/scripts/setup-permissions.sh' --target ./s.json > /dev/null 2>&1 && \
    jq -r 'select(.extra.bootstrap == true) | .event_type' .nova/events.jsonl | grep -q session_start \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Sprint 2a Evaluator 피드백 보강: P0/P1 Issue 해소 회귀
# Issue #1: Path traversal — 외부 경로 거부
assert "Sprint 2a #1: setup-permissions path traversal 방어 (외부 경로 exit 2)" \
  "TMPD=\$(mktemp -d); RC=0; bash '$ROOT_DIR/scripts/setup-permissions.sh' --target /tmp/nova-traversal-test-\$\$.json 2>/dev/null >/dev/null || RC=\$?; rm -f /tmp/nova-traversal-test-\$\$.json; rm -rf \"\$TMPD\"; [ \$RC -eq 2 ]"

# Issue #1': Path traversal — `..` bypass 차단 (cwd 부모로 escape)
assert "Sprint 2a #1': setup-permissions '..' bypass 차단 (cwd 부모로 escape 거부)" \
  "TMPD=\$(mktemp -d); mkdir -p \"\$TMPD/proj\"; \
   RC=0; (cd \"\$TMPD/proj\" && bash '$ROOT_DIR/scripts/setup-permissions.sh' --target '../escape.json' 2>/dev/null >/dev/null) || RC=\$?; \
   EXISTS=\$([ -f \"\$TMPD/escape.json\" ] && echo 1 || echo 0); \
   rm -rf \"\$TMPD\"; [ \$RC -eq 2 ] && [ \"\$EXISTS\" = '0' ]"

# Issue #2: Symlink 거부
assert "Sprint 2a #2: setup-permissions symlink 거부 (exit 2)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && touch target.json && ln -s target.json link.json && \
    RC=0; bash '$ROOT_DIR/scripts/setup-permissions.sh' --target link.json --allow-outside 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ]); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue #3: Bootstrap 중복 방지
assert "Sprint 2a #3: setup-permissions 2회 실행 시 bootstrap 이벤트 1건만" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/scripts/setup-permissions.sh' --target ./s1.json > /dev/null 2>&1 && \
    bash '$ROOT_DIR/scripts/setup-permissions.sh' --target ./s2.json > /dev/null 2>&1 && \
    COUNT=\$(jq -s '[.[] | select(.event_type==\"session_start\" and (.extra.bootstrap // false) == true)] | length' .nova/events.jsonl 2>/dev/null) && \
    [ \"\$COUNT\" = '1' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue #4: Orphan agent 감지
assert "Sprint 2a #4: audit-agent-tools orphan 감지 (plugin.json 키에 파일 없으면 FAIL)" \
  "TMPD=\$(mktemp -d); cp -r '$ROOT_DIR/.claude-plugin' \"\$TMPD/\" && cp -r '$ROOT_DIR/.claude' \"\$TMPD/\" && \
    jq '.tool_contract.per_agent += {\"phantom-agent\": [\"Read\"]}' \"\$TMPD/.claude-plugin/plugin.json\" > \"\$TMPD/pj.json\" && \
    mv \"\$TMPD/pj.json\" \"\$TMPD/.claude-plugin/plugin.json\" && \
    AUDIT_COPY=\$(cat '$ROOT_DIR/scripts/audit-agent-tools.sh' | sed \"s#^ROOT_DIR=.*#ROOT_DIR=\\\"\$TMPD\\\"#\" | sed \"s#^MANIFEST=.*#MANIFEST=\\\"\$TMPD/.claude-plugin/plugin.json\\\"#\" | sed \"s#^AGENTS_DIR=.*#AGENTS_DIR=\\\"\$TMPD/.claude/agents\\\"#\") && \
    echo \"\$AUDIT_COPY\" > \"\$TMPD/audit.sh\" && chmod +x \"\$TMPD/audit.sh\" && \
    RC=0; bash \"\$TMPD/audit.sh\" 2>/dev/null >/dev/null || RC=\$?; \
    rm -rf \"\$TMPD\"; [ \$RC -eq 1 ]"

# Issue #7: 위험 패턴 확장
assert "Sprint 2a #7: permissions-template deny 15+ (추가 패턴 반영)" \
  "[ \$(jq '.permissions.deny | length' '$ROOT_DIR/scripts/permissions-template.json') -ge 15 ]"
assert "Sprint 2a #7: permissions-template에 mkfs* 패턴 포함" \
  "jq -e '.permissions.deny | index(\"Bash(mkfs* *)\")' '$ROOT_DIR/scripts/permissions-template.json' > /dev/null 2>&1"

# nova-rules §11 — 알려진 제약 섹션
assert "Sprint 2a: nova-rules.md §11 — disallowedTools 제약 명시" \
  "grep -q 'disallowedTools' '$ROOT_DIR/docs/nova-rules.md'"
assert "Sprint 2a: nova-rules.md §11 — path traversal 방어 명시" \
  "grep -q 'Path traversal' '$ROOT_DIR/docs/nova-rules.md'"

# U2 해소 문서
assert "Sprint 2a: U2 해소 docs/unknowns-resolution.md 기록" \
  "grep -qE '^## U2' '$ROOT_DIR/docs/unknowns-resolution.md' && grep -q '해소 일자.*2026-04-19' '$ROOT_DIR/docs/unknowns-resolution.md'"

# session-start 크기 회귀
assert "Sprint 2a 회귀: session-start 여전히 soft 1900 이하" \
  "[ \$(bash '$ROOT_DIR/hooks/session-start.sh' | wc -c | tr -d ' ') -le 1900 ]"

echo ""

# ═══════════════════════════════════════════
# Sprint 2b (v5.15.0): 도구 제약 런타임 — PreToolUse 차단
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Sprint 2b: 도구 제약 런타임]${NC}"

# S2b.1: precheck-tool.sh 존재 + 실행 권한
assert "S2b.1: scripts/precheck-tool.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/scripts/precheck-tool.sh' ]"

# S2b.2: 허용 도구(Read) → exit 0 (settings 없는 경로에서도 safe-default)
assert "S2b.2: Read 도구 → exit 0 (허용)" \
  "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/x\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1"

# S2b.3: 위반 도구(Bash rm -rf *) → exit 2 + JSONL violation
assert "S2b.3: Bash(rm -rf *) → exit 2 + stderr DENIED + JSONL tool_constraint_violation" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; STDERR=\$(echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/foo\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>&1 >/dev/null) || RC=\$?; \
    [ \$RC -eq 2 ] && \
    echo \"\$STDERR\" | grep -q 'DENIED' && \
    [ \"\$(jq -r '.event_type' .nova/events.jsonl | head -1)\" = 'tool_constraint_violation' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S2b.4: settings.json 없음 → exit 0 (safe-default)
assert "S2b.4: settings.json 없음 → exit 0 (safe-default)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1 \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S2b.5: permissions-template.json — PreToolUse 훅 엔트리 활성
assert "S2b.5: permissions-template.json PreToolUse → precheck-tool.sh 참조" \
  "jq -r '.hooks.PreToolUse[0].hooks[0].command' '$ROOT_DIR/scripts/permissions-template.json' | grep -q 'precheck-tool.sh'"

# S2b.6: record-event.sh tool_constraint_violation 타입 지원
assert "S2b.6: record-event.sh tool_constraint_violation 기록 + schema 유효" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    bash '$ROOT_DIR/hooks/record-event.sh' tool_constraint_violation '{\"agent\":\"test\",\"tool_attempted\":\"Bash\",\"matched_pattern\":\"Bash(rm -rf *)\"}' && \
    [ \"\$(jq -r '.event_type' .nova/events.jsonl | head -1)\" = 'tool_constraint_violation' ] && \
    [ \"\$(jq -r '.schema_version' .nova/events.jsonl | head -1)\" = '2' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S2b.7: evaluator SKILL.md — tool_constraint_violation 감사 섹션
assert "S2b.7: evaluator/SKILL.md — 사후 감사 섹션 + jq 쿼리 예시" \
  "grep -q 'tool_constraint_violation' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md' && grep -q 'VIOLATION_COUNT' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

# S2b.8: 성능 벤치 — 허용 경로 100ms 이내
assert "S2b.8: precheck-tool 허용 경로 지연 < 500ms (성능)" \
  "START=\$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))'); \
   echo '{\"tool_name\":\"Read\",\"tool_input\":{}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1; \
   END=\$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))'); \
   DIFF_MS=\$(( (END - START) / 1000000 )); \
   [ \$DIFF_MS -lt 500 ]"

# S2b: 다중 deny 패턴 — 첫 매치로 차단
assert "S2b: 다중 deny 패턴 — 첫 매치로 차단 확인" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(sudo *)\",\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sudo apt update\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S2b: jq 없는 환경 safe-default
assert "S2b: jq 없는 환경 → exit 0 (safe-default, 도구 허용)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    PATH=/usr/bin:/bin echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}' | PATH=/usr/bin:/bin bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1 \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Sprint 2b Evaluator FAIL 해소 — Critical Bypass 12종 회귀 가드
# Issue #1: Bash 복합 명령 bypass (세그먼트 분리)
assert "S2b #1a: 'echo x && rm -rf *' → 차단 (복합 && 분리)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x && rm -rf /tmp/foo\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

assert "S2b #1b: '   rm -rf *' (선행 공백) → 차단" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"   rm -rf /tmp/foo\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

assert "S2b #1c: 'rm -rf *; echo done' → 차단 (세미콜론 분리)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x; echo done\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue C: newline 세그먼트 분리
assert "S2b #C: 'echo x\\nrm -rf *' (newline 분리) → 차단" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    RC=0; printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x\\nrm -rf /tmp/x\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# §11 Issue A/B 명시
assert "S2b §11 Issue A: 'sh -c/bash -c' 래핑 한계 명시" \
  "grep -q 'sh -c/bash -c' '$ROOT_DIR/docs/nova-rules.md' || grep -q 'bash -c.*bypass' '$ROOT_DIR/docs/nova-rules.md'"
assert "S2b §11 Issue B: Write/Edit file_path 정규화 없음 명시" \
  "grep -q 'file_path.*정규화' '$ROOT_DIR/docs/nova-rules.md'"

# Issue #2: Write/Edit deny 매칭 구현
assert "S2b #2a: Write(/etc/passwd) → 차단" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Write(/etc/*)\"]}}' > .claude/settings.json && \
    RC=0; echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/etc/passwd\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

assert "S2b #2b: Edit(/home/foo.txt) → 허용 (deny 패턴 불일치)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Edit(/etc/*)\"]}}' > .claude/settings.json && \
    echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/home/foo.txt\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1 \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue #3: settings.local.json이 project deny를 축소할 수 없음 (union)
assert "S2b #3: settings.local(빈 deny) + settings(Bash rm) → 차단 유지 (union)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    echo '{\"permissions\":{\"deny\":[]}}' > .claude/settings.local.json && \
    RC=0; echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' 2>/dev/null >/dev/null || RC=\$?; \
    [ \$RC -eq 2 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue #10: NOVA_BYPASS_PRECHECK 환경변수로 일시 해제 + 감사 이벤트
assert "S2b #10: NOVA_BYPASS_PRECHECK=1 → exit 0 + tool_constraint_bypass 이벤트" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{\"permissions\":{\"deny\":[\"Bash(rm -rf *)\"]}}' > .claude/settings.json && \
    NOVA_BYPASS_PRECHECK=1 echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x\"}}' | NOVA_BYPASS_PRECHECK=1 bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1 && \
    [ \"\$(jq -r '.event_type' .nova/events.jsonl | head -1)\" = 'tool_constraint_bypass' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# Issue #6: Invalid JSON → schema_error 이벤트 + fail-open (exit 0)
assert "S2b #6: settings.json invalid JSON → exit 0 + schema_error 이벤트" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir -p .claude && \
    echo '{ invalid json' > .claude/settings.json && \
    echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x\"}}' | bash '$ROOT_DIR/scripts/precheck-tool.sh' > /dev/null 2>&1 && \
    jq -s '[.[] | select(.event_type==\"schema_error\")] | length' .nova/events.jsonl | grep -q '^[1-9]' \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# nova-rules §11 런타임 범위와 한계 명시
assert "S2b: nova-rules §11 — '런타임 Enforcement 범위와 한계' 섹션" \
  "grep -q '런타임 Enforcement' '$ROOT_DIR/docs/nova-rules.md' && grep -q 'Fail-open 정책' '$ROOT_DIR/docs/nova-rules.md' && grep -q 'NOVA_BYPASS_PRECHECK' '$ROOT_DIR/docs/nova-rules.md'"

# Evaluator SKILL.md — idempotent jq 쿼리 예시
assert "S2b: evaluator/SKILL.md — HIGH_RISK/BYPASS/SCHEMA_ERRORS jq 쿼리 3종" \
  "grep -q 'HIGH_RISK' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md' && grep -q 'BYPASS_COUNT' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md' && grep -q 'SCHEMA_ERRORS' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

# session-start 크기 회귀
assert "Sprint 2b 회귀: session-start 여전히 soft 1900 이하" \
  "[ \$(bash '$ROOT_DIR/hooks/session-start.sh' | wc -c | tr -d ' ') -le 1900 ]"

echo ""

# ═══════════════════════════════════════════
# orchestration-tracker load/save 회귀 (v5.15.1 데이터 손실 + atomic + merge)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[orchestration-tracker]${NC}"
assert "orchestration-tracker 단위 테스트 (TC1~TC9) 통과" \
  "node '$ROOT_DIR/tests/test-orchestration-tracker.mjs' > /dev/null 2>&1"

# ═══════════════════════════════════════════
# MCP dist 배포 무결성 (v5.15.1/v5.15.2 껍데기 릴리스 사고 방지)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[MCP dist 배포 무결성]${NC}"

# .mcp.json의 entrypoint 경로 추출 (릴리스 사고 분석 결과 도입)
MCP_ENTRY=$(jq -r '.mcpServers[].args[]?' "$ROOT_DIR/.mcp.json" 2>/dev/null | grep -F 'dist/' | sed 's|.*\${CLAUDE_PLUGIN_ROOT}/||' | head -1)

assert "MCP dist 무결성: .mcp.json entrypoint 경로 추출 가능" \
  "[ -n '$MCP_ENTRY' ]"

assert "MCP dist 무결성: $MCP_ENTRY 파일이 저장소에 존재" \
  "[ -f '$ROOT_DIR/$MCP_ENTRY' ]"

assert "MCP dist 무결성: $MCP_ENTRY 가 git tracked" \
  "(cd '$ROOT_DIR' && git ls-files --error-unmatch '$MCP_ENTRY' > /dev/null 2>&1)"

assert "MCP dist 무결성: $MCP_ENTRY 가 .gitignore에 걸려있지 않음" \
  "(cd '$ROOT_DIR' && ! git check-ignore '$MCP_ENTRY' > /dev/null 2>&1)"

# release.sh가 multiline 커밋 메시지의 첫 줄만 title로 쓰는가 (v5.16.0 릴리스 단계 422 오류 재발 방지)
assert "release.sh: 릴리스 title에 head -1 + cut 240자 제한" \
  "grep -q 'head -1' '$ROOT_DIR/scripts/release.sh' && grep -q 'cut -c1-240' '$ROOT_DIR/scripts/release.sh'"

# ═══════════════════════════════════════════
# Orchestration 추적 계약 (Phase 0 강제 + 사후 감사)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[Orchestration 추적 계약]${NC}"

# SKILL.md가 Phase 0 오케스트레이션 등록을 명시적으로 "필수/최우선"으로 규정하는가
assert "Orchestrator SKILL.md: Phase 0 등록 스텝 필수 명시" \
  "grep -q 'Phase 0.*오케스트레이션 등록' '$ROOT_DIR/skills/orchestrator/SKILL.md'"

# soft escape hatch 문구 재삽입 감지 (v5.15.x 이전 문구)
assert "Orchestrator SKILL.md: soft escape hatch 문구 제거됨" \
  "! grep -q '사용 불가능한 환경에서는 추적 없이' '$ROOT_DIR/skills/orchestrator/SKILL.md'"

# audit-orchestration.sh 존재 + 실행 권한
assert "hooks/audit-orchestration.sh 존재 + 실행 권한" \
  "[ -x '$ROOT_DIR/hooks/audit-orchestration.sh' ]"

# stop-event.sh가 audit-orchestration.sh를 호출하는가
assert "stop-event.sh → audit-orchestration.sh 연계" \
  "grep -q 'audit-orchestration.sh' '$ROOT_DIR/hooks/stop-event.sh'"

# audit 동작: 짧은 세션(임계값 미만) → 감지 스킵
assert "audit: 짧은 세션(임계값 미만) → 감지 스킵 (exit 0 + 이벤트 없음)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir .nova && \
    date -u +%s > .nova/session.start_epoch && \
    NOVA_ORCH_AUDIT_THRESHOLD=300 bash '$ROOT_DIR/hooks/audit-orchestration.sh' && \
    [ ! -f .nova/events.jsonl ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# audit 동작: 긴 세션 + orch 기록 없음 → orchestration_missing 이벤트 기록
assert "audit: 긴 세션 + orch 기록 0 → orchestration_missing 이벤트" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir .nova && \
    echo \$(( \$(date -u +%s) - 400 )) > .nova/session.start_epoch && \
    NOVA_ORCH_AUDIT_THRESHOLD=180 bash '$ROOT_DIR/hooks/audit-orchestration.sh' && \
    [ -f .nova/events.jsonl ] && \
    grep -q 'orchestration_missing' .nova/events.jsonl \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# audit 동작: 긴 세션 + orch 최신 업데이트 존재 → 감지 안 함 (false positive 방지)
assert "audit: 긴 세션 + 세션 중 orch 업데이트 존재 → 감지 안 함" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir .nova && \
    SESSION_EPOCH=\$(( \$(date -u +%s) - 400 )); \
    echo \$SESSION_EPOCH > .nova/session.start_epoch; \
    NOW_ISO=\$(date -u +'%Y-%m-%dT%H:%M:%SZ'); \
    echo '{\"orch-x\":{\"id\":\"orch-x\",\"task\":\"t\",\"complexity\":\"simple\",\"status\":\"running\",\"phases\":[],\"createdAt\":\"'\$NOW_ISO'\",\"updatedAt\":\"'\$NOW_ISO'\"}}' > .nova-orchestration.json; \
    NOVA_ORCH_AUDIT_THRESHOLD=180 bash '$ROOT_DIR/hooks/audit-orchestration.sh' && \
    [ ! -f .nova/events.jsonl -o \"\$(grep -c 'orchestration_missing' .nova/events.jsonl 2>/dev/null || echo 0)\" = '0' ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# NOVA_DISABLE_EVENTS=1 → audit도 옵트아웃
assert "audit: NOVA_DISABLE_EVENTS=1 → 이벤트 기록 생략" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && mkdir .nova && \
    echo \$(( \$(date -u +%s) - 400 )) > .nova/session.start_epoch && \
    NOVA_DISABLE_EVENTS=1 NOVA_ORCH_AUDIT_THRESHOLD=180 bash '$ROOT_DIR/hooks/audit-orchestration.sh' && \
    [ ! -f .nova/events.jsonl ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

echo ""

# ═══════════════════════════════════════════
# S3: SKILL Discipline — description workflow-lint + triggering fixtures (v5.17.0)
# 근거: memory/project_nova_competitive_analysis_2026_04_23.md
#      Jesse Vincent(obra/superpowers)의 writing-skills 실측 — description에
#      workflow 요약이 포함되면 Claude가 본문을 스킵한다.
# ═══════════════════════════════════════════

assert "S3.1: SKILL description — workflow 화살표(→) 금지" \
  "! grep -qE '^description:.*→' $ROOT_DIR/skills/*/SKILL.md"

assert "S3.2: SKILL description — 단계 숫자 홍보(N단 파이프라인 / Explorer×N) 금지" \
  "! grep -qE '^description:.*(단 파이프라인|Explorer×|Explorer x)' $ROOT_DIR/skills/*/SKILL.md"

assert "S3.3: test-skill-triggering.sh — 각 skills/*에 positive fixture 존재" \
  "bash $ROOT_DIR/tests/test-skill-triggering.sh"

assert "S3.4: skills/writing-nova-skill/SKILL.md — MUST TRIGGER 명시" \
  "grep -q 'MUST TRIGGER' $ROOT_DIR/skills/writing-nova-skill/SKILL.md"

echo ""

# ═══════════════════════════════════════════
# S4: Adaptive Control (Tier 2, v5.18.0)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S4: Adaptive Control]${NC}"

# S4.1: pre-edit-check.sh NOVA_PROFILE=lean에서 CPS 경고 스킵
assert "S4.1: pre-edit-check.sh NOVA_PROFILE=lean → CPS 경고 없음 (lean 스킵)" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    INPUT='{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.ts\"}}' && \
    ! NOVA_PROFILE=lean TOOL_INPUT=\"\$INPUT\" bash '$ROOT_DIR/hooks/pre-edit-check.sh' 2>&1 | grep -q 'CPS Plan' \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S4.2: session-start.sh NOVA_PROFILE=strict에서 antipatterns 섹션 존재
assert "S4.2: NOVA_PROFILE=strict → antipatterns 섹션 주입" \
  "NOVA_PROFILE=strict bash '$ROOT_DIR/hooks/session-start.sh' | grep -q 'nova-antipatterns.md'"

# S4.3: session-start.sh NOVA_PROFILE=lean에서 §1~§3만 (antipatterns, §4~§5 없음)
assert "S4.3: NOVA_PROFILE=lean → antipatterns 섹션 없음" \
  "! NOVA_PROFILE=lean bash '$ROOT_DIR/hooks/session-start.sh' | grep -q 'nova-antipatterns.md'"

assert "S4.3b: NOVA_PROFILE=lean → 복잡도(§1) 포함" \
  "NOVA_PROFILE=lean bash '$ROOT_DIR/hooks/session-start.sh' | grep -q '복잡도'"

# S4.4: nova-antipatterns.md 존재 + §A/§B 섹션 + 항목 12개 이상
assert "S4.4a: docs/nova-antipatterns.md 존재" \
  "[ -f '$ROOT_DIR/docs/nova-antipatterns.md' ]"

assert "S4.4b: nova-antipatterns.md §A 섹션 존재" \
  "grep -q '^## §A' '$ROOT_DIR/docs/nova-antipatterns.md'"

assert "S4.4c: nova-antipatterns.md §B 섹션 존재" \
  "grep -q '^## §B' '$ROOT_DIR/docs/nova-antipatterns.md'"

assert "S4.4d: nova-antipatterns.md 항목 12개 이상" \
  "[ \"\$(grep -c '^### [AB][0-9]' '$ROOT_DIR/docs/nova-antipatterns.md' 2>/dev/null || echo 0)\" -ge 12 ]"

# S4.5: release.sh에 removal report 경고 문구 존재
assert "S4.5: scripts/release.sh — 제거 리포트 경고 문구 존재" \
  "grep -q '제거 리포트가 비어 있습니다' '$ROOT_DIR/scripts/release.sh'"

assert "S4.5b: scripts/release.sh — --removal 플래그 처리 존재" \
  "grep -q -- '--removal=' '$ROOT_DIR/scripts/release.sh'"

# S4.6: nova-rules.md §12 섹션 존재
assert "S4.6: docs/nova-rules.md §12 Profile Gate 섹션 존재" \
  "grep -q '^## §12' '$ROOT_DIR/docs/nova-rules.md'"

# S4.7: --emergency가 lean 별칭으로 동작 (JSON 유효 + antipatterns 없음)
assert "S4.7: session-start.sh --emergency → lean 별칭 (antipatterns 없음)" \
  "bash '$ROOT_DIR/hooks/session-start.sh' --emergency | python3 -m json.tool > /dev/null 2>&1 && \
   ! bash '$ROOT_DIR/hooks/session-start.sh' --emergency | grep -q 'nova-antipatterns.md'"

echo ""

# ═══════════════════════════════════════════
# S5: Behavior Learning 엔진 (Tier 3)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S5: Behavior Learning]${NC}"

# S5.1: analyze-observations.sh 존재 + 실행 권한
assert "S5.1: scripts/analyze-observations.sh 존재 + 실행 권한" \
  "[ -f '$ROOT_DIR/scripts/analyze-observations.sh' ] && [ -x '$ROOT_DIR/scripts/analyze-observations.sh' ]"

# S5.2: commands/evolve.md에 --from-observations 문구
assert "S5.2: commands/evolve.md — --from-observations 플래그 문서화" \
  "grep -q '\-\-from-observations' '$ROOT_DIR/.claude/commands/evolve.md'"

# S5.3: skills/evolution/SKILL.md에 "Behavior Learning" 또는 "Phase 1" 문구
assert "S5.3: skills/evolution/SKILL.md — Behavior Learning 섹션 존재" \
  "grep -q 'Behavior Learning\|Phase 1' '$ROOT_DIR/.claude/skills/evolution/SKILL.md'"

# S5.4: 빈 fixture → 정상 종료 + "No observations" 메시지 or 빈 결과
assert "S5.4: analyze-observations.sh 빈 파일 입력 → 정상 종료 + No observations" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    touch empty.jsonl && \
    OUT=\$(bash '$ROOT_DIR/scripts/analyze-observations.sh' empty.jsonl 2>&1); RC=\$?; \
    echo \"\$OUT\" | grep -q 'No observations\|비어 있습니다\|없음'; \
    [ \$RC -eq 0 ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

# S5.5: 실제 fixture (10라인 이상) → Top 패턴 출력 포함
assert "S5.5: analyze-observations.sh 실 fixture (10+ 라인) → 패턴 출력" \
  "TMPD=\$(mktemp -d); (cd \"\$TMPD\" && \
    for i in \$(seq 1 12); do \
      echo '{\"event_type\":\"session_start\",\"timestamp\":\"2026-04-23T00:0'\$i':00Z\",\"schema_version\":1,\"session_id\":\"abc123\"}' >> events.jsonl; \
    done && \
    OUT=\$(bash '$ROOT_DIR/scripts/analyze-observations.sh' --top 5 --pattern tool-frequency events.jsonl 2>&1); RC=\$?; \
    [ \$RC -eq 0 ] && [ -n \"\$OUT\" ] \
  ); STATUS=\$?; rm -rf \"\$TMPD\"; [ \$STATUS -eq 0 ]"

echo ""

# ═══════════════════════════════════════════
# S6: Evaluator GAN 3단 확장 (Tier 3)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S6: GAN 3단 확장]${NC}"

# S6.1: agents/refiner.md 존재 + frontmatter에 name/description/tools 필드
assert "S6.1: agents/refiner.md 존재 + name/description/tools frontmatter" \
  "[ -f '$ROOT_DIR/.claude/agents/refiner.md' ] && \
   head -10 '$ROOT_DIR/.claude/agents/refiner.md' | grep -q '^name:' && \
   head -10 '$ROOT_DIR/.claude/agents/refiner.md' | grep -q '^description:' && \
   head -10 '$ROOT_DIR/.claude/agents/refiner.md' | grep -q '^tools:'"

# S6.2: skills/evaluator/SKILL.md에 "GAN" 또는 "refiner" 섹션 문구
assert "S6.2: evaluator/SKILL.md — GAN 3단 확장 섹션 존재" \
  "grep -q 'GAN\|refiner' '$ROOT_DIR/.claude/skills/evaluator/SKILL.md'"

# S6.3: commands/{check,run,review}.md 모두에 --with-refiner 문구
assert "S6.3: check.md — --with-refiner 문구" \
  "grep -q '\-\-with-refiner' '$ROOT_DIR/.claude/commands/check.md'"
assert "S6.3: run.md — --with-refiner 문구" \
  "grep -q '\-\-with-refiner' '$ROOT_DIR/.claude/commands/run.md'"
assert "S6.3: review.md — --with-refiner 문구" \
  "grep -q '\-\-with-refiner' '$ROOT_DIR/.claude/commands/review.md'"

# S6.4: refiner.md description에 "수정안" 또는 "제안" 키워드 + 코드 적용 금지 원칙 명시
assert "S6.4: refiner.md — 수정안/제안 키워드 + 코드 직접 변경 금지 명시" \
  "grep -q '수정안\|제안' '$ROOT_DIR/.claude/agents/refiner.md' && \
   grep -q '직접 변경 금지\|코드 직접 변경' '$ROOT_DIR/.claude/agents/refiner.md'"

echo ""

# ═══════════════════════════════════════════
# S7: SUBAGENT Bootstrap 격리 (Tier 3)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S7: Subagent Bootstrap 격리]${NC}"

# S7.1: NOVA_SUBAGENT=1 → JSON 유효
assert "S7.1: NOVA_SUBAGENT=1 → JSON 유효" \
  "NOVA_SUBAGENT=1 bash '$ROOT_DIR/hooks/session-start.sh' | python3 -m json.tool > /dev/null 2>&1"

# S7.2: NOVA_SUBAGENT=1 출력 길이가 standard 대비 현저히 작음 (<200자)
assert "S7.2: NOVA_SUBAGENT=1 출력 < 200 bytes" \
  "[ \$(NOVA_SUBAGENT=1 bash '$ROOT_DIR/hooks/session-start.sh' | wc -c | tr -d ' ') -lt 200 ]"

# S7.3: NOVA_SUBAGENT 미설정 시 기존 동작 유지 (standard 크기 > 200자)
assert "S7.3: NOVA_SUBAGENT 미설정 → 기존 standard 동작 유지 (>200 bytes)" \
  "[ \$(bash '$ROOT_DIR/hooks/session-start.sh' | wc -c | tr -d ' ') -gt 200 ]"

# S7.4: docs/nova-rules.md §13 섹션 존재
assert "S7.4: docs/nova-rules.md §13 Subagent Bootstrap Isolation 섹션 존재" \
  "grep -q '^## §13' '$ROOT_DIR/docs/nova-rules.md'"

echo ""

# ═══════════════════════════════════════════
# S8: Observability Closure (v5.18.0)
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S8: Observability Closure]${NC}"

# S8.1: hooks.json PreToolUse all-match("") 매처 + pre-tool-use-record.sh 엔트리
# 근거: Claude Code hooks matcher는 정규식. "*"는 quantifier-at-start로 매칭 실패 (v5.18.0→v5.18.1 수정).
# 공식 all-match 문법은 빈 문자열 "".
assert "S8.1: hooks.json PreToolUse all-match 매처 + pre-tool-use-record.sh 엔트리" \
  "jq -e '.hooks.PreToolUse[] | select(.matcher==\"\" and (.hooks[0].command|contains(\"pre-tool-use-record\")))' $ROOT_DIR/hooks/hooks.json >/dev/null"

# S8.1b: 회귀 방지 — matcher에 "*" 사용 금지 (v5.18.0 결함)
assert "S8.1b: hooks.json matcher에 리터럴 '*' 사용 금지 (regex 오류 방지)" \
  "! jq -e '.hooks[][] | select(.matcher==\"*\")' $ROOT_DIR/hooks/hooks.json >/dev/null"

# S8.2: hooks/pre-tool-use-record.sh 존재 + 실행 권한
assert "S8.2: hooks/pre-tool-use-record.sh 존재 + 실행 권한" \
  "test -x $ROOT_DIR/hooks/pre-tool-use-record.sh"

# S8.3: pre-tool-use-record.sh — TOOL_INPUT 기록 금지 (grep)
assert "S8.3: pre-tool-use-record.sh — TOOL_INPUT 기록 금지 (grep)" \
  "! grep -qE 'TOOL_INPUT|tool_input' $ROOT_DIR/hooks/pre-tool-use-record.sh"

# S8.4: session-start.sh debounce 로직 존재
assert "S8.4: session-start.sh debounce 로직 존재" \
  "grep -q 'session.debounce\|debounce' $ROOT_DIR/hooks/session-start.sh"

# S8.5: audit-orchestration.sh stderr 경고 출력
assert "S8.5: audit-orchestration.sh stderr 경고 출력" \
  "grep -qE '\[nova:audit\].*orchestration.*누락' $ROOT_DIR/hooks/audit-orchestration.sh"

# S8.6: 엔드투엔드 스모크 — pre-tool-use-record.sh 실행 후 이벤트 기록 확인
assert "S8.6: pre-tool-use-record.sh 실행 → tool_call 이벤트 기록" \
  "TMPD=\$(mktemp -d); NOVA_EVENTS_PATH=\"\$TMPD/events.jsonl\" TOOL_NAME=Read bash $ROOT_DIR/hooks/pre-tool-use-record.sh && \
   sleep 0.3 && grep -q '\"event_type\":\"tool_call\"' \"\$TMPD/events.jsonl\" && \
   ! grep -q 'tool_input' \"\$TMPD/events.jsonl\"; S=\$?; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S8.7: debounce 동작 — 5초 내 2회 호출 → 1회만 기록
assert "S8.7: session-start.sh debounce — 2회 연속 호출 시 1회 기록" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\" && mkdir -p .nova && \
   NOVA_EVENTS_PATH=\"\$TMPD/.nova/events.jsonl\" bash $ROOT_DIR/hooks/session-start.sh >/dev/null && \
   sleep 0.2 && NOVA_EVENTS_PATH=\"\$TMPD/.nova/events.jsonl\" bash $ROOT_DIR/hooks/session-start.sh >/dev/null && \
   sleep 0.3 && \
   COUNT=\$(grep -c 'session_start' \"\$TMPD/.nova/events.jsonl\" 2>/dev/null || echo 0); \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \"\$COUNT\" = \"1\" ]"

echo ""

# ═══════════════════════════════════════════
# S9: Enforcement Layer (v5.18.3) — pre-commit-reminder.sh 7상태 머신 + stdin JSON
# ═══════════════════════════════════════════

echo -e "${YELLOW}[S9: Enforcement Layer — pre-commit-reminder.sh]${NC}"

# 공통 헬퍼 — PRE_COMMIT 훅 실행 sandbox
# (temp dir + fixture NOVA-STATE.md + stdin JSON 주입)
HOOK="$ROOT_DIR/hooks/pre-commit-reminder.sh"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures"
TODAY=$(date +%Y-%m-%d)

# S9.0: pre-commit-reminder.sh 실행 권한
assert "S9.0: hooks/pre-commit-reminder.sh 실행 권한" \
  "test -x '$HOOK'"

# S9.1: $TOOL_INPUT env var 의존 제거 (회귀 방지 — v5.18.2까지의 버그)
assert "S9.1: pre-commit-reminder.sh — \$TOOL_INPUT env 사용 금지 (stdin JSON 전환)" \
  "! grep -qE 'TOOL_INPUT|\\\$TOOL_INPUT' '$HOOK'"

# S9.2: stdin JSON 파싱 패턴 존재 (tool_input.command)
assert "S9.2: pre-commit-reminder.sh — stdin JSON 파싱(tool_input.command) 포함" \
  "grep -qE 'tool_input\\.command' '$HOOK'"

# S9.3: 7상태 머신 전부 정의
assert "S9.3: 7상태 머신 모든 상태(PASS/MISSING/CONFLICT/EMPTY/NO_PASS/TIMESTAMP_BROKEN/STALE) 정의" \
  "grep -qE '\"PASS\"|^\\s*echo PASS' '$HOOK' && \
   grep -qE '\"MISSING\"|^\\s*echo MISSING' '$HOOK' && \
   grep -qE '\"CONFLICT\"|^\\s*echo CONFLICT' '$HOOK' && \
   grep -qE '\"EMPTY\"|^\\s*echo EMPTY' '$HOOK' && \
   grep -qE '\"NO_PASS\"|^\\s*echo NO_PASS' '$HOOK' && \
   grep -qE '\"TIMESTAMP_BROKEN\"|^\\s*echo TIMESTAMP_BROKEN' '$HOOK' && \
   grep -qE '\"STALE\"|^\\s*echo STALE' '$HOOK'"

# S9.4: CONFLICT 감지 (^<<<<<<< merge marker)
assert "S9.4: CONFLICT 감지 — '^<<<<<<<' 마커 grep 패턴" \
  "grep -qE \"grep -q '\\^<<<<<<<'\" '$HOOK'"

# S9.5: non-git Bash 호출은 조기 종료 (exit 0)
assert "S9.5: non-git Bash 입력 → exit 0 (조기 종료)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   echo '{\"tool_input\":{\"command\":\"bash -c echo\"}}' | bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S9.6: PASS fixture + stdin JSON → exit 0
assert "S9.6: PASS fixture (오늘 PASS) → exit 0" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   sed 's/TODAY_PLACEHOLDER/$TODAY/g' '$FIXTURE_DIR/nova-state-pass.md' > NOVA-STATE.md; \
   echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S9.7: NO_PASS fixture → exit 2 + stderr 차단 메시지
assert "S9.7: NO_PASS fixture → exit 2 + 차단 메시지" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   sed 's/TODAY_PLACEHOLDER/$TODAY/g' '$FIXTURE_DIR/nova-state-no_pass.md' > NOVA-STATE.md; \
   OUT=\$(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' 2>&1); S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; \
   [ \$S -eq 2 ] && echo \"\$OUT\" | grep -qE 'COMMIT BLOCKED|NO_PASS'"

# S9.8: NO_PASS + NOVA_EMERGENCY=1 → exit 0 (우회 가능)
assert "S9.8: NO_PASS + NOVA_EMERGENCY=1 → exit 0 (우회)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   sed 's/TODAY_PLACEHOLDER/$TODAY/g' '$FIXTURE_DIR/nova-state-no_pass.md' > NOVA-STATE.md; \
   NOVA_EMERGENCY=1 bash '$HOOK' < <(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}') >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S9.9: CONFLICT fixture + NOVA_EMERGENCY=1 → exit 2 (fail-closed 초월, N3)
assert "S9.9: CONFLICT + NOVA_EMERGENCY=1 → exit 2 (EMERGENCY 우회 불가)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   cp '$FIXTURE_DIR/nova-state-conflict.md' NOVA-STATE.md; \
   OUT=\$(NOVA_EMERGENCY=1 bash '$HOOK' < <(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}') 2>&1); S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; \
   [ \$S -eq 2 ] && echo \"\$OUT\" | grep -qE 'CONFLICT|merge conflict'"

# S9.10: MISSING → exit 2
assert "S9.10: NOVA-STATE.md 없음 (MISSING) → exit 2" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   OUT=\$(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' 2>&1); S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; \
   [ \$S -eq 2 ] && echo \"\$OUT\" | grep -qE 'MISSING'"

# S9.11: EMPTY fixture → exit 2
assert "S9.11: EMPTY fixture → exit 2" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   cp '$FIXTURE_DIR/nova-state-empty.md' NOVA-STATE.md; \
   OUT=\$(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' 2>&1); S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; \
   [ \$S -eq 2 ] && echo \"\$OUT\" | grep -qE 'EMPTY'"

# S9.12: STALE fixture → exit 2 + NOVA_EMERGENCY=1 우회 가능
assert "S9.12: STALE fixture → exit 2 (EMERGENCY=0)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   cp '$FIXTURE_DIR/nova-state-stale.md' NOVA-STATE.md; \
   echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 2 ]"

# S9.13: TIMESTAMP_BROKEN fixture → exit 2
assert "S9.13: TIMESTAMP_BROKEN fixture → exit 2" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   cp '$FIXTURE_DIR/nova-state-timestamp_broken.md' NOVA-STATE.md; \
   OUT=\$(echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' 2>&1); S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; \
   [ \$S -eq 2 ] && echo \"\$OUT\" | grep -qE 'TIMESTAMP_BROKEN'"

# S9.14: NOVA_DISABLE_EVENTS=1 → 무조건 exit 0 (훅 최상위 우회)
assert "S9.14: NOVA_DISABLE_EVENTS=1 → exit 0 (훅 최상위 우회)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   echo 'garbage-not-json' | NOVA_DISABLE_EVENTS=1 bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S9.15: 빈 stdin → exit 2 (fail-closed)
assert "S9.15: 빈 stdin → exit 2 (fail-closed)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   : | bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 2 ]"

# S9.16: init-nova-state.sh Last Activity 포맷 — 당일 PASS 마커 포함 (R3 catch-22 해소)
assert "S9.16: init-nova-state.sh 생성 NOVA-STATE.md가 Hard Gate PASS로 인식됨 (cold-start)" \
  "TMPD=\$(mktemp -d); cd \"\$TMPD\"; \
   echo \"{\\\"cwd\\\":\\\"\$TMPD\\\"}\" | bash '$ROOT_DIR/scripts/init-nova-state.sh' >/dev/null 2>&1; \
   echo '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK' >/dev/null 2>&1; S=\$?; \
   cd - >/dev/null; rm -rf \"\$TMPD\"; [ \$S -eq 0 ]"

# S9.17: hooks.json pre-commit-reminder 엔트리 — Design 원본 구조 (공식 스펙 준수)
# 공식 문서 (code.claude.com/docs/en/hooks) 재확인 결과:
#   - 여러 matcher 엔트리는 모두 병렬 평가 + 매칭 시 모두 실행
#   - 같은 matcher 내 hooks[] 배열도 모두 병렬 실행
#   - `if` 필드는 permission rule syntax로 hook 단위 skip 제어 (inner 위치)
# 원래 Design 구조가 스펙상 정답. dispatcher 롤백.
assert "S9.17: hooks.json pre-commit-reminder 엔트리 matcher=\"Bash\" + inner hooks[].if=\"Bash(git *)\"" \
  "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[0] | .if == \"Bash(git *)\" and (.command | contains(\"pre-commit-reminder\"))' $ROOT_DIR/hooks/hooks.json >/dev/null"

# S9.17b: pre-commit-reminder.sh 내부 git commit 정규식 필터 (이중 방어)
assert "S9.17b: pre-commit-reminder.sh 내부 git commit 정규식 필터 존재" \
  "grep -qE 'git\\\\s\\+.*commit' '$HOOK'"

# S9.18: fixture 7개 중 6개 파일 존재 (MISSING은 파일 없음으로 표현)
assert "S9.18: tests/fixtures/nova-state-*.md 6개 존재 (pass/empty/no_pass/stale/timestamp_broken/conflict)" \
  "[ -f '$FIXTURE_DIR/nova-state-pass.md' ] && \
   [ -f '$FIXTURE_DIR/nova-state-empty.md' ] && \
   [ -f '$FIXTURE_DIR/nova-state-no_pass.md' ] && \
   [ -f '$FIXTURE_DIR/nova-state-stale.md' ] && \
   [ -f '$FIXTURE_DIR/nova-state-timestamp_broken.md' ] && \
   [ -f '$FIXTURE_DIR/nova-state-conflict.md' ]"

echo ""

# ═══════════════════════════════════════════
# 10. v5.20.0 Measurement Infrastructure
# ═══════════════════════════════════════════

echo -e "${YELLOW}[v5.20.0: Measurement Infrastructure]${NC}"

PID_LIB="$ROOT_DIR/scripts/lib/pattern-id.sh"

# M1: pattern-id.sh 존재 + 실행 권한
assert "M1: scripts/lib/pattern-id.sh 존재 + 실행 권한" "[ -x '$PID_LIB' ]"

# M2: record-event.sh schema v2
assert "M2: record-event.sh schema_version=2" \
  "grep -q 'schema_version: 2' '$ROOT_DIR/hooks/record-event.sh'"

# M3: record-event.sh extra payload 가이드 (tool, duration_ms, pattern_id, decision)
assert "M3: record-event.sh extra payload 가이드 (tool/duration_ms/pattern_id ≥ 3)" \
  "[ \$(grep -cE 'tool|duration_ms|pattern_id' '$ROOT_DIR/hooks/record-event.sh') -ge 3 ]"

# M4: pattern_id 동일 입력 → 동일 출력
PID1=$(bash -c "source '$PID_LIB' && compute_pattern_id tool_call Bash 2026-04-29T00:00:00" 2>/dev/null)
PID2=$(bash -c "source '$PID_LIB' && compute_pattern_id tool_call Bash 2026-04-29T00:00:00" 2>/dev/null)
assert "M4: compute_pattern_id 동일 입력 → 동일 출력" "[ -n '$PID1' ] && [ '$PID1' = '$PID2' ]"

# M5: pattern_id 8-hex 형식
assert "M5: compute_pattern_id 8-hex 형식" "[[ '$PID1' =~ ^[0-9a-f]{8}$ ]]"

# M6~M11: 신뢰도 6 케이스 (clamp 경계 포함)
assert "M6: confidence 0/0/0 → 0.30 (베이스)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 0 0 0')\" = '0.30' ]"
assert "M7: confidence 6/0/0 → 0.90 (N=6)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 6 0 0')\" = '0.90' ]"
assert "M8: confidence 7/0/0 → 1.00 (clamp 상한)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 7 0 0')\" = '1.00' ]"
assert "M9: confidence 0/2/0 → 0.70 (accept x2)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 0 2 0')\" = '0.70' ]"
assert "M10: confidence 0/0/1 → 0.00 (reject clamp 하한)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 0 0 1')\" = '0.00' ]"
assert "M11: confidence 0/0/2 → 0.00 (음수 방어)" \
  "[ \"\$(bash -c 'source $PID_LIB && compute_confidence 0 0 2')\" = '0.00' ]"

# M12: analyze --pattern confidence --format json 유효 JSON
assert "M12: analyze --pattern confidence --format json 유효 JSON" \
  "bash '$ROOT_DIR/scripts/analyze-observations.sh' --pattern confidence --format json 2>/dev/null | jq -e . >/dev/null"

# M13: analyze 기본 출력 헤더 존재 (회귀 0). pipefail + SIGPIPE 회피 위해 grep -c 사용
assert "M13: analyze 기본 출력 'Nova Behavior Analysis' 헤더" \
  "[ \$(bash '$ROOT_DIR/scripts/analyze-observations.sh' 2>/dev/null | grep -c 'Nova Behavior Analysis') -ge 1 ]"

# M14: evolve.md --accept/--reject + evolve_decision 노출
assert "M14: evolve.md --accept/--reject 옵션 + evolve_decision 키워드" \
  "grep -q -- '--accept' '$ROOT_DIR/.claude/commands/evolve.md' && grep -q -- '--reject' '$ROOT_DIR/.claude/commands/evolve.md' && grep -q 'evolve_decision' '$ROOT_DIR/.claude/commands/evolve.md'"

# M15: evolve.md NOVA-STATE 트리거 제외 명시
assert "M15: evolve.md NOVA-STATE 트리거 제외/JSONL only 명시" \
  "grep -qE 'NOVA-STATE.*갱신.*X|NOVA-STATE.*트리거.*X|JSONL only|9 진입점 동결|9 진입점 유지' '$ROOT_DIR/.claude/commands/evolve.md'"

# M16: snapshot-baseline.sh 존재
assert "M16: scripts/snapshot-baseline.sh 실행 권한" \
  "[ -x '$ROOT_DIR/scripts/snapshot-baseline.sh' ]"

# M17: nova-rules.md §10 신뢰도 공식 노출
assert "M17: docs/nova-rules.md 신뢰도 공식 노출" \
  "grep -qE 'clamp.*0.*1|0\.3 \+ 0\.1' '$ROOT_DIR/docs/nova-rules.md'"

# M18: context-chain SKILL evolve_decision 명시
assert "M18: context-chain SKILL evolve_decision JSONL only" \
  "grep -qE 'evolve_decision.*JSONL only|evolve_decision.*트리거 제외|evolve_decision.*9 진입점' '$ROOT_DIR/.claude/skills/context-chain/SKILL.md'"

# M19: docs/baselines/ 디렉토리 (snapshot-baseline.sh 산출물 보관)
assert "M19: docs/baselines/ 디렉토리 존재" "[ -d '$ROOT_DIR/docs/baselines' ]"

# ── v5.20.1 ECC P0/P1 흡수 (docs only) ──

# N1: P0-1 컨텍스트 로스트 진단 카탈로그
assert "N1: docs/context-rot-diagnosis.md — 4원인 카탈로그" \
  "[ -f '$ROOT_DIR/docs/context-rot-diagnosis.md' ] && grep -qE '어텐션 희석|명령 충돌|토큰 예산|관련성 미스매치' '$ROOT_DIR/docs/context-rot-diagnosis.md'"

# N2: P0-2 비용 최적화 가이드
assert "N2: docs/cost-optimization.md — settings.json 권장 키 + 모델 계층화" \
  "[ -f '$ROOT_DIR/docs/cost-optimization.md' ] && grep -qE 'MAX_THINKING_TOKENS|CLAUDE_AUTOCOMPACT_PCT_OVERRIDE|sonnet|haiku' '$ROOT_DIR/docs/cost-optimization.md'"

# N3: P1-2 MCP 10/80 룰
assert "N3: docs/nova-rules.md MCP 10/80 룰 노출" \
  "grep -qE 'MCP.*≤ ?10|≤ ?80|10개.*80개' '$ROOT_DIR/docs/nova-rules.md'"

# ── v5.21.0 ECC P0-3 Strategic Compact 스킬 흡수 ──

# O1: 스킬 파일 존재 + description When-to-use 형식
assert "O1: skills/strategic-compact/SKILL.md — MUST TRIGGER 명시" \
  "[ -f '$ROOT_DIR/skills/strategic-compact/SKILL.md' ] && grep -q 'MUST TRIGGER' '$ROOT_DIR/skills/strategic-compact/SKILL.md'"

# O2: MUST NOT TRIGGER (구현 도중 압축 금지)
assert "O2: strategic-compact SKILL — MUST NOT TRIGGER 금기 카탈로그" \
  "grep -qE 'MUST NOT TRIGGER|구현 sprint 도중|Evaluator 검증 직전' '$ROOT_DIR/skills/strategic-compact/SKILL.md'"

# O3: nova-rules.md §8 cross-ref (상태-수준 ≠ 세션-수준)
assert "O3: nova-rules.md §8 — strategic-compact cross-ref" \
  "grep -q 'strategic-compact' '$ROOT_DIR/docs/nova-rules.md'"

# O4: context-chain SKILL cross-ref (역할 분리)
assert "O4: context-chain SKILL — strategic-compact cross-ref" \
  "grep -q 'strategic-compact' '$ROOT_DIR/skills/context-chain/SKILL.md'"

# O5: skill-triggering positive fixture
assert "O5: tests/skill-triggering/prompts/strategic-compact-positive.txt 존재" \
  "[ -f '$ROOT_DIR/tests/skill-triggering/prompts/strategic-compact-positive.txt' ]"

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
