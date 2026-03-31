#!/usr/bin/env bash
# Nova 버전 범프 스크립트
# 사용법: bash scripts/bump-version.sh <patch|minor|major>
# 또는:  bash scripts/bump-version.sh 2.2.0  (직접 지정)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/scripts/.nova-version"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "❌ $VERSION_FILE 파일을 찾을 수 없습니다."
  exit 1
fi

CURRENT=$(tr -d '[:space:]' < "$VERSION_FILE")
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "${1:-}" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *)
    if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      IFS='.' read -r MAJOR MINOR PATCH <<< "${1:-}"
    else
      echo "사용법: bash scripts/bump-version.sh <patch|minor|major|X.Y.Z>"
      echo "현재 버전: $CURRENT"
      exit 1
    fi
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

if [[ "$NEW_VERSION" == "$CURRENT" ]]; then
  echo "⚠️  버전이 동일합니다: $CURRENT"
  exit 0
fi

echo "🔄 $CURRENT → $NEW_VERSION"

# macOS/Linux 호환 sed in-place
sedi() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# 1. Single source of truth
echo "$NEW_VERSION" > "$VERSION_FILE"

# 2. README.md + README.ko.md 배지
for readme in "$ROOT/README.md" "$ROOT/README.ko.md"; do
  if [[ -f "$readme" ]]; then
    sedi "s/version-[0-9]*\.[0-9]*\.[0-9]*/version-$NEW_VERSION/" "$readme"
    echo "  ✅ $(basename "$readme")"
  fi
done

# 3. plugin.json
PLUGIN="$ROOT/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN" ]]; then
  sedi "s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"$NEW_VERSION\"/" "$PLUGIN"
  echo "  ✅ plugin.json"
fi

echo "✅ 버전 범프 완료: $NEW_VERSION"
