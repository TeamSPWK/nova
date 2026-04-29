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

if [[ -z "$LEVEL" || -z "$COMMIT_MSG" ]]; then
  echo "사용법: bash scripts/release.sh <patch|minor|major> \"커밋 메시지\""
  echo ""
  echo "  patch  — 버그 수정, 문서 정리"
  echo "  minor  — 새 커맨드/스킬 추가, 기존 기능 개선"
  echo "  major  — 호환성 깨지는 변경, 아키텍처 전환"
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
      (cd "$(dirname "$MCP_SRC_DIR")" && pnpm build) > /dev/null 2>&1 || {
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

# ── Step 2.5: 릴리스 위생 게이트 (fail-open 권고형, v5.22.3+) ──
# 4회 릴리스 전 review 0회 패턴(NOVA-STATE Known Risks Medium) 인지 강화.
# 차단하지 않음 — 경고만 출력. 강제 차단은 v5.23.0+에서 검토.
echo "━━━ Step 2.5/7: 릴리스 위생 게이트 ━━━"

# (a) 제거 리포트 (기존)
REMOVAL_REPORT="${NOVA_REMOVAL_REPORT:-}"
for arg in "$@"; do
  case "$arg" in
    --removal=*) REMOVAL_REPORT="${arg#--removal=}" ;;
  esac
done
if [[ -z "$REMOVAL_REPORT" ]]; then
  echo "  ⚠️  제거 리포트가 비어 있습니다 — A/B 측정 문화: --removal=\"...\" 또는 NOVA_REMOVAL_REPORT" >&2
fi

# (b) /nova:review 흔적 검증 (Always-On 4)
# 커밋 메시지 또는 환경변수에 review 흔적이 있으면 통과 권고.
if echo "$COMMIT_MSG" | grep -qiE 'review (PASS|통과)|/nova:review|senior-dev|reviewer (PASS|통과)|reviewed:'; then
  echo "  ✅ /nova:review 흔적 감지 (커밋 메시지)"
elif [[ -n "${NOVA_RELEASE_REVIEWED:-}" ]]; then
  echo "  ✅ NOVA_RELEASE_REVIEWED=$NOVA_RELEASE_REVIEWED 명시"
else
  echo "  ⚠️  /nova:review --fast 흔적 미감지 — Always-On 4 (커밋 전 review)" >&2
  echo "     해소: 커밋 메시지에 'review PASS' 또는 NOVA_RELEASE_REVIEWED=1 환경변수" >&2
fi

# (c) NOVA-STATE.md 신선도 (Last Activity 1시간 이내)
if [[ -f NOVA-STATE.md ]]; then
  _STATE_EPOCH=$(date -r NOVA-STATE.md +%s 2>/dev/null || echo 0)
  _AGE=$(($(date +%s) - _STATE_EPOCH))
  if (( _AGE > 3600 )); then
    echo "  ⚠️  NOVA-STATE.md 마지막 수정 ${_AGE}s 전 — 본 릴리스 반영 의심" >&2
    echo "     해소: Last Activity 1줄 추가 + 50줄 트림" >&2
  else
    echo "  ✅ NOVA-STATE.md 신선 (${_AGE}s)"
  fi
else
  echo "  ⚠️  NOVA-STATE.md 부재 — /nova:setup 또는 init-nova-state.sh 권장" >&2
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
echo ""

# ── Step 3: 변경사항 커밋 ──
echo "━━━ Step 3/7: 커밋 ━━━"
# unstaged 파일이 있으면 staged만 커밋
if ! git diff --cached --quiet; then
  git commit -m "$COMMIT_MSG"
else
  git add -A
  git commit -m "$COMMIT_MSG"
fi
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

# ── Step 5: 태그 + 푸시 ──
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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 릴리스 완료: v${NEW_VERSION}"
echo "  📦 landing 자동 동기화가 트리거됩니다"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
