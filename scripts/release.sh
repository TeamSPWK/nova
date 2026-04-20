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
# 커밋 메시지에서 릴리스 제목 추출 (prefix 제거)
TITLE=$(echo "$COMMIT_MSG" | sed 's/^[a-z]*: //' | sed 's/^[a-z]*(.*): //')
gh release create "v${NEW_VERSION}" \
  --title "v${NEW_VERSION} — ${TITLE}" \
  --notes "${COMMIT_MSG}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 릴리스 완료: v${NEW_VERSION}"
echo "  📦 landing 자동 동기화가 트리거됩니다"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
