#!/usr/bin/env bash
# Nova 릴리스 스크립트
# 커밋 → 리뷰 → 버전 범프 → 태그 → 푸시 → GitHub 릴리스를 한 명령으로 실행.
#
# 사용법:
#   bash scripts/release.sh patch "커밋 메시지"
#   bash scripts/release.sh minor "커밋 메시지"
#   bash scripts/release.sh major "커밋 메시지"
#
# 예시:
#   bash scripts/release.sh minor "feat: Coverage Gate + Learned Rules 추가"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── 인자 검증 ──
LEVEL="${1:-}"
COMMIT_MSG="${2:-}"

usage() {
  echo "사용법: bash scripts/release.sh <patch|minor|major> \"커밋 메시지\""
  echo ""
  echo "  patch  — 버그 수정, 문서 정리"
  echo "  minor  — 새 커맨드/스킬 추가, 기존 기능 개선"
  echo "  major  — 호환성 깨지는 변경, 아키텍처 전환"
}

if [[ "$LEVEL" == "-h" || "$LEVEL" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$LEVEL" || -z "$COMMIT_MSG" ]]; then
  usage
  exit 1
fi

if [[ ! "$LEVEL" =~ ^(patch|minor|major)$ ]]; then
  echo "❌ 수준은 patch, minor, major 중 하나여야 합니다: $LEVEL"
  exit 1
fi

# ── 상태 확인 ──
if git diff --cached --quiet && git diff --quiet; then
  echo "❌ 커밋할 변경사항이 없습니다."
  exit 1
fi

# ── Step 0: marketplace.json validate (Claude Code 2.1.118+, fail-open) ──
# 공식 plugin CLI로 marketplace 매니페스트 스키마 검증. plugin.json은 Nova 커스텀
# 필드(tool_contract) 때문에 validate 스킵 — 버전 일치는 bump-version.sh가 보장.
if command -v claude >/dev/null 2>&1 && [[ -f .claude-plugin/marketplace.json ]]; then
  echo "━━━ Step 0/7: marketplace.json validate ━━━"
  if ! claude plugin validate .claude-plugin/marketplace.json; then
    echo "❌ marketplace.json 검증 실패 — 릴리스 중단"
    exit 1
  fi
  echo ""
fi

# ── Step 1: MCP dist 무결성 게이트 ──
# v5.15.1/v5.15.2 사고 재발 방지: .mcp.json이 참조하는 빌드 산출물이 tracked이고
# 최신 소스와 일치하는 빌드인지 검증한다.
echo "━━━ Step 1/7: MCP dist 무결성 게이트 ━━━"
MCP_ENTRY=$(jq -r '.mcpServers[].args[]?' .mcp.json 2>/dev/null | grep -F 'dist/' | sed 's|.*\${CLAUDE_PLUGIN_ROOT}/||' | head -1)
if [[ -n "$MCP_ENTRY" ]]; then
  if ! git ls-files --error-unmatch "$MCP_ENTRY" >/dev/null 2>&1; then
    echo "❌ $MCP_ENTRY 가 git tracked 아님 — 플러그인 entrypoint는 반드시 커밋되어야 함"
    exit 1
  fi
  if git check-ignore "$MCP_ENTRY" >/dev/null 2>&1; then
    echo "❌ $MCP_ENTRY 가 .gitignore에 걸려있음 — v5.15.1 스타일 사고 재발 위험"
    exit 1
  fi
  MCP_SRC_DIR="$(dirname "$(dirname "$MCP_ENTRY")")/src"
  if [[ -d "$MCP_SRC_DIR" ]]; then
    SRC_CHANGED=0
    git diff --quiet HEAD -- "$MCP_SRC_DIR" 2>/dev/null || SRC_CHANGED=1
    git diff --cached --quiet -- "$MCP_SRC_DIR" 2>/dev/null || SRC_CHANGED=1
    if [[ $SRC_CHANGED -eq 1 ]]; then
      echo "  mcp-server 소스 변경 감지 — 빌드 일관성 검증"
      (cd "$(dirname "$MCP_SRC_DIR")" && COREPACK_ENABLE_AUTO_PIN=0 pnpm build) > /dev/null 2>&1 || {
        echo "❌ mcp-server 빌드 실패 — 릴리스 중단"
        exit 1
      }
      if ! git diff --quiet -- "$MCP_ENTRY" 2>/dev/null; then
        echo "❌ 소스 수정 후 dist가 staged/commit에 반영 안 됨"
        echo "   해결: git add $MCP_ENTRY 후 재시도"
        exit 1
      fi
    fi
  fi
  echo "  ✅ $MCP_ENTRY tracked + 빌드 동기화 OK"
fi
echo ""

# ── Step 2: 테스트 ──
echo "━━━ Step 2/7: 테스트 실행 ━━━"
bash tests/test-scripts.sh
echo ""


# ── Step 2.5: 릴리스 위생 게이트 (v5.32.0+: review/STATE는 hard gate 승격) ──
# 4회 릴리스 전 review 0회 패턴(NOVA-STATE Known Risks Medium) 인지 강화.
# (b)/(c)는 fail-close. NOVA_RELEASE_ACK_ADVISORY=1 명시 우회만 허용.
# (a) removal, (d) audit-self는 advisory 유지(추가-only 릴리스 차단 부적합).
echo "━━━ Step 2.5/7: 릴리스 위생 게이트 ━━━"

# 우회 플래그: 환경변수만 허용 (--플래그 거부 — AI 자동 우회 마찰 유지)
ACK_ADVISORY="${NOVA_RELEASE_ACK_ADVISORY:-}"
GATE_FAIL=0
GATE_REASONS=()

# (a) 제거 리포트 (advisory 유지)
REMOVAL_REPORT="${NOVA_REMOVAL_REPORT:-}"
for arg in "$@"; do
  case "$arg" in
    --removal=*) REMOVAL_REPORT="${arg#--removal=}" ;;
  esac
done
if [[ -z "$REMOVAL_REPORT" ]]; then
  echo "  ⚠️  제거 리포트가 비어 있습니다 — A/B 측정 문화: --removal=\"...\" 또는 NOVA_REMOVAL_REPORT" >&2
fi

# (b) /nova:review 흔적 검증 (Always-On 4) — hard gate
if echo "$COMMIT_MSG" | grep -qiE 'review (PASS|통과)|/nova:review|senior-dev|reviewer (PASS|통과)|reviewed:'; then
  echo "  ✅ /nova:review 흔적 감지 (커밋 메시지)"
elif [[ -n "${NOVA_RELEASE_REVIEWED:-}" ]]; then
  echo "  ✅ NOVA_RELEASE_REVIEWED=$NOVA_RELEASE_REVIEWED 명시"
else
  echo "  ❌ /nova:review --fast 흔적 미감지 — Always-On 4 (커밋 전 review)" >&2
  echo "     해소: 커밋 메시지에 'review PASS' 또는 NOVA_RELEASE_REVIEWED=1 환경변수" >&2
  GATE_FAIL=1
  GATE_REASONS+=("review_unrun")
fi

# (c) NOVA-STATE.md 신선도 (1시간 이내) — hard gate
if [[ -f NOVA-STATE.md ]]; then
  _STATE_EPOCH=$(date -r NOVA-STATE.md +%s 2>/dev/null || echo 0)
  _AGE=$(($(date +%s) - _STATE_EPOCH))
  if (( _AGE > 3600 )); then
    echo "  ❌ NOVA-STATE.md 마지막 수정 ${_AGE}s 전 — 본 릴리스 반영 누락" >&2
    echo "     해소: Last Activity 1줄 추가 + 50줄 트림" >&2
    GATE_FAIL=1
    GATE_REASONS+=("state_stale")
  else
    echo "  ✅ NOVA-STATE.md 신선 (${_AGE}s)"
  fi
else
  echo "  ❌ NOVA-STATE.md 부재 — /nova:setup 또는 init-nova-state.sh 권장" >&2
  GATE_FAIL=1
  GATE_REASONS+=("state_missing")
fi

# (d) audit-self 회귀 통합 (v5.22.2+ test-scripts.sh에 위임 통합 확인)
if grep -q 'tests/test-audit-self.sh' tests/test-scripts.sh 2>/dev/null; then
  echo "  ✅ audit-self 회귀 통합 (test-scripts.sh)"
else
  echo "  ⚠️  audit-self 회귀 미통합 — Nova 자기 보안 진단 회귀 가드 누락" >&2
fi

# (e) .nova/ 차단 가드 (Sprint 3, measurement-spec.md §4 — privacy 사고 방지, fail-closed)
# .nova/events.jsonl 등이 staged면 즉시 abort. 사용자 환경 데이터를 절대 commit하지 않는다.
if git diff --cached --name-only 2>/dev/null | grep -E '^\.nova/' >/dev/null; then
  echo "  ❌ FATAL: .nova/ 파일이 staged — privacy 사고 위험" >&2
  echo "     git rm --cached .nova/<파일> 후 재시도" >&2
  exit 2
fi
if git diff --name-only 2>/dev/null | grep -E '^\.nova/' >/dev/null; then
  echo "  ⚠️  .nova/ 파일 변경 감지 (unstaged) — 절대 commit 금지" >&2
fi

# (f) hard gate enforcement — (b)/(c) 위반 시 차단, ACK 명시 우회 시 통과 + evolve_decision 기록
if (( GATE_FAIL == 1 )); then
  if [[ -n "$ACK_ADVISORY" ]]; then
    _REASONS_JOIN=$(IFS=,; echo "${GATE_REASONS[*]}")
    echo "  ⚠️  NOVA_RELEASE_ACK_ADVISORY=$ACK_ADVISORY — hard gate 우회 (사유: $_REASONS_JOIN)" >&2
    echo "     evolve 후보로 기록 — 누적 시 강제 정도 재조정 검토" >&2
    if [[ -x "${CLAUDE_PLUGIN_ROOT:-.}/hooks/record-event.sh" ]] || [[ -x "hooks/record-event.sh" ]]; then
      _REC="${CLAUDE_PLUGIN_ROOT:-.}/hooks/record-event.sh"
      [[ -x "$_REC" ]] || _REC="hooks/record-event.sh"
      bash "$_REC" evolve_decision "{\"kind\":\"release_ack_advisory\",\"reasons\":\"$_REASONS_JOIN\"}" 2>/dev/null || true
    fi
  else
    echo "" >&2
    echo "  ❌ 릴리스 위생 게이트 차단 — Always-On 자가 규칙 위반" >&2
    echo "     실패 항목: ${GATE_REASONS[*]}" >&2
    echo "     해소 후 재시도, 또는 명시적으로 NOVA_RELEASE_ACK_ADVISORY=1 bash scripts/release.sh ..." >&2
    echo "     (--플래그 우회 없음 — AI 자동 우회 마찰 유지)" >&2
    exit 2
  fi
fi
echo ""

# ── Step 2.7: ledger append 흡수 (B 조치, v5.49.1+) ──
# NOVA_LEDGER_APPEND 환경변수에 값이 있으면 _ABSORBED.md에 append 후 통합 commit에 포함.
# evolve --apply/--auto가 minor/major 머지 시 별도 commit으로 분리되던 패턴을 release.sh로 흡수.
# 형식: literal newline으로 구분된 markdown table row (`| slug | url | ver | path | active |`)
# 사유: 별도 ledger commit이 STALE Hard Gate 차단 → --emergency 남용 유발.
if [[ -n "${NOVA_LEDGER_APPEND:-}" ]]; then
  echo "━━━ Step 2.7/7: ledger append (NOVA_LEDGER_APPEND) ━━━"
  LEDGER_BYTES=$(printf '%s' "$NOVA_LEDGER_APPEND" | wc -c | tr -d ' ')
  if (( LEDGER_BYTES > 10240 )); then
    echo "  ⚠️  NOVA_LEDGER_APPEND ${LEDGER_BYTES} bytes (>10KB) — _ABSORBED.md 비대화 위험. 분할 release 권장" >&2
  fi
  LEDGER_FILE="$ROOT/dev/docs/proposals/_ABSORBED.md"
  if [[ -f "$LEDGER_FILE" ]]; then
    printf '\n%s\n' "$NOVA_LEDGER_APPEND" >> "$LEDGER_FILE"
    LEDGER_LINES=$(printf '%s\n' "$NOVA_LEDGER_APPEND" | grep -c '^|' 2>/dev/null || echo 0)
    echo "  ✅ _ABSORBED.md에 ${LEDGER_LINES}개 row append (${LEDGER_BYTES}B, 통합 commit 포함)"
  else
    echo "  ⚠️ _ABSORBED.md 미존재 — ledger append 스킵" >&2
  fi
  echo ""
fi

# ── Step 3: 변경사항 커밋 ──
# v5.26.2+: staged/unstaged 분리 로직 제거 — 모든 working tree 변경을 통합 commit.
# 이전 로직(staged만 commit)은 사용자가 일부만 git add 했을 때 unstaged 변경이
# 누락된 채 push되는 사고 원인이었음 (v5.26.1: 13 fix 선언했으나 7 spec 파일만 commit).
# .gitignore가 .nova/, secrets, OS 노이즈 등을 차단하므로 git add -A는 안전.
# 의도적으로 일부만 commit하려면 release.sh 우회하고 직접 git commit.
echo "━━━ Step 3/7: 커밋 ━━━"

# 변경 통계 미리 노출 (사용자가 콘솔에서 확인 가능, 의도와 다르면 Ctrl+C로 중단)
echo "  ─ 통합 commit 대상 (staged + unstaged + untracked):"
git status --short | sed 's/^/    /'
echo ""

git add -A
git commit -m "$COMMIT_MSG"
echo ""

# ── Step 3: 버전 범프 (nova-meta.json + README 자동 갱신 포함) ──
echo "━━━ Step 4/7: 버전 범프 ━━━"
bash scripts/bump-version.sh "$LEVEL"

# 현재 버전 읽기
NEW_VERSION=$(tr -d '[:space:]' < scripts/.nova-version)
echo ""

# ── Step 4: 범프 파일 커밋 ──
echo "━━━ Step 5/7: 범프 커밋 ━━━"
git add scripts/.nova-version .claude-plugin/plugin.json README.md README.ko.md docs/nova-meta.json
# .codex-plugin/plugin.json은 선택적 — 과거 태그 rollback 시 파일이 없을 수 있음
[[ -f .codex-plugin/plugin.json ]] && git add .codex-plugin/plugin.json
git commit -m "chore(v${NEW_VERSION}): 버전 범프"
echo ""

# ── Step 5.5: clean-clone 재실행 가드 (v5.26.1+) ──
# v5.26.0 사고: 작성자 로컬엔 있지만 git에 등록 안 된 파일이 release에 빠진 채 push.
# commit 직후 push 직전에 git clone --local 하여 "tracked 파일만으로 정말 동작하는가" 검증.
# 다른 머신/CI에서 받게 될 정확한 상태를 시뮬.
# NOVA_SKIP_CLEAN_CLONE=1 로 override 가능 (긴급 hotfix 등 — 책임 사용자에게).
if [[ "${NOVA_SKIP_CLEAN_CLONE:-0}" != "1" ]]; then
  echo "━━━ Step 5.5/7: clean-clone 재실행 가드 ━━━"
  CLEAN_CLONE_DIR=$(mktemp -d)
  trap 'rm -rf "$CLEAN_CLONE_DIR"' EXIT
  git clone --local --quiet "$ROOT" "$CLEAN_CLONE_DIR/nova" 2>/dev/null
  if ! ( cd "$CLEAN_CLONE_DIR/nova" && bash tests/test-scripts.sh > /tmp/clean-clone-test.log 2>&1 ); then
    echo "❌ clean-clone 환경에서 테스트 실패 — push 차단"
    echo "   로그: /tmp/clean-clone-test.log"
    tail -10 /tmp/clean-clone-test.log
    echo ""
    echo "   힌트: 마지막 2개 commit 이후에도 git tracked 파일만으로 동작해야 함."
    echo "   누락 파일이 있으면 git add 후 amend 또는 새 commit으로 추가 → 다시 release.sh 시도."
    echo "   NOVA_SKIP_CLEAN_CLONE=1 로 우회 가능하나 v5.26.0 사고 재발 위험."
    exit 1
  fi
  echo "  ✅ clean-clone 환경 테스트 통과 — push 진행"
  echo ""
fi

# ── Step 6: 태그 + 푸시 ──
echo "━━━ Step 6/7: 태그 + 푸시 ━━━"
git tag "v${NEW_VERSION}"
git push origin main --tags
echo ""

# ── Step 6: GitHub 릴리스 ──
echo "━━━ Step 7/7: GitHub 릴리스 ━━━"
# 커밋 메시지에서 릴리스 제목 추출 (prefix 제거 + 첫 줄만, 240자 이하로 잘라 GitHub 256자 한도 방어)
TITLE_FIRST_LINE=$(echo "$COMMIT_MSG" | head -1 | sed 's/^[a-z]*: //' | sed 's/^[a-z]*(.*): //')
# "vX.Y.Z — " prefix 고려해 본문 240자 제한
TITLE_TRIMMED=$(printf '%s' "$TITLE_FIRST_LINE" | cut -c1-240)
# REMOVAL_REPORT가 있으면 GitHub release 본문에 ## Removed 섹션 삽입
if [[ -n "$REMOVAL_REPORT" ]]; then
  RELEASE_NOTES="${COMMIT_MSG}

## Removed

${REMOVAL_REPORT}"
else
  RELEASE_NOTES="${COMMIT_MSG}"
fi

gh release create "v${NEW_VERSION}" \
  --title "v${NEW_VERSION} — ${TITLE_TRIMMED}" \
  --notes "${RELEASE_NOTES}"
echo ""

# ── Step 7.5: review_pass 이벤트 자동 기록 (A 조치, v5.49.1+ / v5.53.0+ 파일 바인딩) ──
# release.sh가 Step 1(test) + Step 2.5(review 흔적) + Step 5.5(clean-clone) 3중 게이트를 통과했으므로
# 본 릴리스는 사실상 review PASS. events.jsonl에 review_pass를 명시 기록해 직후 4h 동안 doc-only/ledger
# follow-up commit이 STALE Hard Gate에 차단되지 않도록 한다.
# v5.53.0+: review_pass에 릴리스 커밋(HEAD) 파일 sha를 바인딩한다. 게이트가 무바인딩 review_pass를
# 더 이상 인정하지 않으므로(self-attest 우회 차단), HEAD 파일에 한정해 윈도를 충전한다.
# doc-only/ledger follow-up은 게이트 SCOPE_SKIP가 별도 처리하므로 영향 없음.
if [[ -x "$ROOT/hooks/record-event.sh" ]]; then
  REVIEW_FILES_JSON=$(bash "$ROOT/scripts/lib/build-files-payload.sh" --head 2>/dev/null || echo "[]")
  [ -n "$REVIEW_FILES_JSON" ] || REVIEW_FILES_JSON="[]"
  if bash "$ROOT/hooks/record-event.sh" review_pass \
    "$(printf '{"verdict":"PASS","source":"release.sh","version":"%s","strength":"Release","scope":"release","files":%s}' "$NEW_VERSION" "$REVIEW_FILES_JSON")" \
    2>/dev/null; then
    echo "  ✅ events.jsonl review_pass 자동 기록 (HEAD 파일 바인딩, 4h 윈도 충전)"
  else
    echo "  ⚠️  review_pass 기록 실패 — 4h 윈도 미충전 (record-event.sh 또는 .nova/events.jsonl 쓰기 권한 확인)" >&2
  fi
fi

# §16 impl-tracker reset — 릴리스 성공 = review/STATE 통과 = 미해소 신호 해소
rm -f .nova/impl-tracker.json 2>/dev/null

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 릴리스 완료: v${NEW_VERSION}"
echo "  📦 landing 자동 동기화가 트리거됩니다"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
