#!/usr/bin/env bash
# Nova — 디자인 시스템 자동 감지 (deterministic)
# Usage: bash scripts/detect-design-system.sh
# Output: {"detected": bool, "sources": [...], "tokenCount": {...}, "tokens": {...}, "components": []}

set -euo pipefail

SOURCES='[]'
TOKEN_COLOR='[]'
TOKEN_SPACING='[]'
TOKEN_FONT='[]'
COUNT_COLOR=0
COUNT_SPACING=0
COUNT_FONT=0
DETECTED=false

add_source() {
  local type="$1" path="$2"
  SOURCES=$(echo "$SOURCES" | jq --arg t "$type" --arg p "$path" '. + [{"type":$t,"path":$p}]' 2>/dev/null || echo "$SOURCES")
  DETECTED=true
}

extract_first5() {
  echo "$1" | grep -oE '[a-zA-Z][a-zA-Z0-9_-]*' | head -5 | jq -R . | jq -sc . 2>/dev/null || echo '[]'
}

# 1. tailwind.config.{ts,js,mjs,cjs}
for f in tailwind.config.ts tailwind.config.js tailwind.config.mjs tailwind.config.cjs; do
  if [ -f "$f" ]; then
    add_source "tailwind" "$f"
    COLORS=$(grep -oE "'(primary|secondary|error|success|warning|neutral[^']*|[a-z]+-[0-9]+)'[[:space:]]*:" "$f" 2>/dev/null | grep -oE "^'[^']+'" | tr -d "'" | head -5 || true)
    [ -n "$COLORS" ] && TOKEN_COLOR=$(echo "$COLORS" | jq -R . | jq -sc . 2>/dev/null || echo '[]')
    COUNT_COLOR=$(echo "$TOKEN_COLOR" | jq 'length' 2>/dev/null || echo 0)
    break
  fi
done

# 2. theme.{ts,tsx,js} (root, src/, app/)
for d in "." "src" "app"; do
  for ext in ts tsx js; do
    f="$d/theme.$ext"
    if [ -f "$f" ]; then
      add_source "theme-file" "$f"
      KEYS=$(grep -oE 'export (const|default) \{[^}]+\}' "$f" 2>/dev/null | grep -oE '[a-zA-Z][a-zA-Z0-9_]*:' | tr -d ':' | head -5 || true)
      [ -n "$KEYS" ] && TOKEN_COLOR=$(echo "$KEYS" | jq -R . | jq -sc . 2>/dev/null || echo "$TOKEN_COLOR")
      break 2
    fi
  done
done

# 3. CSS 파일의 :root CSS 변수
CSS_VARS=$(find . -name "*.css" -not -path "*/node_modules/*" 2>/dev/null | head -5 || true)
for f in $CSS_VARS; do
  if grep -qE ':root[[:space:]]*\{' "$f" 2>/dev/null; then
    VARS=$(grep -oE '--[a-zA-Z][a-zA-Z0-9_-]*[[:space:]]*:' "$f" 2>/dev/null | tr -d ' :' | head -5 || true)
    if [ -n "$VARS" ]; then
      add_source "css-vars" "$f"
      if [ "$COUNT_COLOR" -eq 0 ]; then
        TOKEN_COLOR=$(echo "$VARS" | jq -R . | jq -sc . 2>/dev/null || echo '[]')
        COUNT_COLOR=$(echo "$TOKEN_COLOR" | jq 'length' 2>/dev/null || echo 0)
      fi
      break
    fi
  fi
done

# 4. design-tokens/*.{json,ts,js}
for f in design-tokens/*.json design-tokens/*.ts design-tokens/*.js; do
  [ -f "$f" ] || continue
  add_source "design-tokens" "$f"
  KEYS=$(grep -oE '"[a-zA-Z][a-zA-Z0-9_-]*"[[:space:]]*:' "$f" 2>/dev/null | tr -d '"' | tr -d ':' | head -5 || true)
  [ -n "$KEYS" ] && [ "$COUNT_COLOR" -eq 0 ] && TOKEN_COLOR=$(echo "$KEYS" | jq -R . | jq -sc . 2>/dev/null || echo '[]')
  break
done

# 5. packages/*/tokens/, packages/design-system/
for d in packages/*/tokens packages/design-system; do
  [ -d "$d" ] || continue
  for f in "$d"/*.json "$d"/*.ts "$d"/*.js; do
    [ -f "$f" ] || continue
    add_source "monorepo-tokens" "$f"
    break 2
  done
done

# 집계
COUNT_COLOR=$(echo "$TOKEN_COLOR" | jq 'length' 2>/dev/null || echo 0)
COUNT_SPACING=$(echo "$TOKEN_SPACING" | jq 'length' 2>/dev/null || echo 0)
COUNT_FONT=$(echo "$TOKEN_FONT" | jq 'length' 2>/dev/null || echo 0)

if [ "$DETECTED" = "false" ]; then
  echo '{"detected":false}'
  exit 0
fi

jq -cn \
  --argjson sources "$SOURCES" \
  --argjson tc "$TOKEN_COLOR" \
  --argjson ts "$TOKEN_SPACING" \
  --argjson tf "$TOKEN_FONT" \
  --argjson cc "$COUNT_COLOR" \
  --argjson cs "$COUNT_SPACING" \
  --argjson cf "$COUNT_FONT" \
  '{
    "detected": true,
    "sources": $sources,
    "tokenCount": {"color": $cc, "spacing": $cs, "fontSize": $cf},
    "tokens": {"color": $tc, "spacing": $ts, "fontSize": $tf},
    "components": []
  }'
