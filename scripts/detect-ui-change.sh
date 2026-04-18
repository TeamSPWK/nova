#!/usr/bin/env bash
# Nova — UI 변경 감지 휴리스틱 (deterministic, LLM 호출 없음)
# Usage:
#   bash scripts/detect-ui-change.sh --planning    → {"likely_ui": bool, "files": [...]}
#   bash scripts/detect-ui-change.sh --post-impl   → {"is_ui": bool, "files": [...], "loc": N, "reason": "...", "hash": "...", "cache_hit": bool}
#   bash scripts/detect-ui-change.sh --check-cache → {"hit": bool, "prev_hash": "..."}

set -uo pipefail

MODE="${1:---post-impl}"
NOVA_DIR=".nova"
LAST_AUDIT="$NOVA_DIR/last-audit.json"

# git 저장소 여부 확인
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo '{"is_ui":false,"likely_ui":false,"reason":"not a git repo"}'
  exit 0
fi

# UI 경로 패턴
UI_EXT_PATTERN='\.(tsx|jsx|vue|svelte)$'
UI_DIR_PATTERN='(^|/)styles/|(^|/)theme/|(^|/)design-tokens/|(^|/)src/components/|(^|/)app/|packages/[^/]+/src/components/|packages/[^/]+/styles/|apps/[^/]+/app/|apps/[^/]+/src/components/'
EXCLUDE_PATTERN='\.(test|spec|stories)\.'
CSS_IN_JS_IMPORTS='styled-components|@emotion/styled|@emotion/react|@linaria/core|@stitches/react|@vanilla-extract/css'
UI_KEYWORDS='className=|style=\{|styled\.|css\(|class=|:class=|<style|<template|\b(color|background|border|padding|margin|font-size|font-weight|font-family|line-height|width|height|display|position|gap|grid|flex)\b|#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\('

# 변경 파일 목록 추출 (staged → HEAD~1..HEAD → HEAD 단독커밋 → worktree 전체)
get_changed_files() {
  if [ "$MODE" = "--planning" ]; then
    git status --porcelain 2>/dev/null | awk '{print $2}' || true
    return
  fi
  # staged
  STAGED=$(git diff --name-only --cached 2>/dev/null || true)
  if [ -n "$STAGED" ]; then echo "$STAGED"; return; fi
  # HEAD~1..HEAD (2개 이상 커밋)
  PARENT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  if [ "$PARENT_COUNT" -ge 2 ]; then
    git diff --name-only HEAD~1..HEAD 2>/dev/null || true
  else
    # 첫 커밋: show --name-only로 전체 파일 목록
    git show --name-only --format="" HEAD 2>/dev/null | grep -v '^$' || true
  fi
}

# diff 텍스트 추출
get_diff_text() {
  if [ "$MODE" = "--planning" ]; then
    git diff 2>/dev/null || true
    return
  fi
  STAGED=$(git diff --name-only --cached 2>/dev/null || true)
  if [ -n "$STAGED" ]; then
    git diff --cached 2>/dev/null || true
    return
  fi
  PARENT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  if [ "$PARENT_COUNT" -ge 2 ]; then
    git diff HEAD~1..HEAD 2>/dev/null || true
  else
    # 첫 커밋: show로 diff 추출
    git show HEAD 2>/dev/null | grep -E '^[+-][^+-]' || true
  fi
}

# --check-cache 모드
if [ "$MODE" = "--check-cache" ]; then
  if [ -f "$LAST_AUDIT" ]; then
    PREV_HASH=$(jq -r '.hash // ""' "$LAST_AUDIT" 2>/dev/null || echo "")
    printf '{"hit":false,"prev_hash":"%s"}\n' "$PREV_HASH"
  else
    echo '{"hit":false,"prev_hash":""}'
  fi
  exit 0
fi

# 변경 파일 + diff 수집
ALL_FILES=$(get_changed_files 2>/dev/null || true)
DIFF_TEXT=$(get_diff_text 2>/dev/null || true)

# UI 파일 후보 수집
UI_FILES=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "$f" | grep -qE "$EXCLUDE_PATTERN" && continue
  if echo "$f" | grep -qE "$UI_EXT_PATTERN"; then
    UI_FILES="${UI_FILES}${f}"$'\n'
  elif echo "$f" | grep -qE "$UI_DIR_PATTERN"; then
    UI_FILES="${UI_FILES}${f}"$'\n'
  elif echo "$f" | grep -qE '\.(ts)$'; then
    # CSS-in-JS 승격: diff 전체에 import 패턴 있으면
    if echo "$DIFF_TEXT" | grep -qE "$CSS_IN_JS_IMPORTS"; then
      UI_FILES="${UI_FILES}${f}"$'\n'
    fi
  fi
done <<< "$ALL_FILES"

UI_FILES=$(echo "$UI_FILES" | grep -v '^[[:space:]]*$' || true)
UI_COUNT=0
if [ -n "$UI_FILES" ]; then
  UI_COUNT=$(echo "$UI_FILES" | grep -c '.' 2>/dev/null || echo 0)
fi

# --planning 모드
if [ "$MODE" = "--planning" ]; then
  FILES_JSON=$(echo "$UI_FILES" | grep -v '^[[:space:]]*$' | jq -R . | jq -sc . 2>/dev/null || echo '[]')
  if [ "$UI_COUNT" -ge 1 ]; then
    printf '{"likely_ui":true,"files":%s}\n' "$FILES_JSON"
  else
    echo '{"likely_ui":false,"files":[]}'
  fi
  exit 0
fi

# --post-impl: UI 파일 없음
if [ "$UI_COUNT" -eq 0 ]; then
  echo '{"is_ui":false,"files":[],"loc":0,"reason":"no UI files","hash":"","cache_hit":false}'
  exit 0
fi

# UI 파일 한정 diff 추출 (Design 사양 부합 — 백엔드 라인 제외)
UI_FILES_ARGS=()
while IFS= read -r f; do
  [ -n "$f" ] && UI_FILES_ARGS+=("$f")
done <<< "$UI_FILES"

UI_DIFF_TEXT=""
if [ ${#UI_FILES_ARGS[@]} -gt 0 ]; then
  if [ "$MODE" = "--planning" ]; then
    UI_DIFF_TEXT=$(git diff -- "${UI_FILES_ARGS[@]}" 2>/dev/null || true)
  else
    STAGED_CHECK=$(git diff --name-only --cached 2>/dev/null || true)
    if [ -n "$STAGED_CHECK" ]; then
      UI_DIFF_TEXT=$(git diff --cached -- "${UI_FILES_ARGS[@]}" 2>/dev/null || true)
    elif [ "$(git rev-list --count HEAD 2>/dev/null || echo 0)" -ge 2 ]; then
      UI_DIFF_TEXT=$(git diff HEAD~1..HEAD -- "${UI_FILES_ARGS[@]}" 2>/dev/null || true)
    else
      UI_DIFF_TEXT=$(git show HEAD -- "${UI_FILES_ARGS[@]}" 2>/dev/null | grep -E '^[+-][^+-]' || true)
    fi
  fi
fi

# LoC 계산 (UI 파일만, added + deleted 줄수)
UI_LOC=0
if [ -n "$UI_DIFF_TEXT" ]; then
  UI_LOC=$(echo "$UI_DIFF_TEXT" | grep -cE '^[+-][^+-]' 2>/dev/null || true)
  UI_LOC=$(echo "$UI_LOC" | tr -d '[:space:]')
  [[ "$UI_LOC" =~ ^[0-9]+$ ]] || UI_LOC=0
fi

# 임계치: ui_files >= 2 OR ui_loc >= 20
if [ "$UI_COUNT" -lt 2 ] && [ "$UI_LOC" -lt 20 ]; then
  printf '{"is_ui":false,"files":[],"loc":%d,"reason":"below threshold","hash":"","cache_hit":false}\n' "$UI_LOC"
  exit 0
fi

# diff 키워드 정밀 체크 (UI 파일 diff만 검사)
if [ -z "$UI_DIFF_TEXT" ] || ! echo "$UI_DIFF_TEXT" | grep -qE "$UI_KEYWORDS"; then
  printf '{"is_ui":false,"files":[],"loc":%d,"reason":"no UI keywords (logic-only change)","hash":"","cache_hit":false}\n' "$UI_LOC"
  exit 0
fi

# 캐시 체크 (hash 계산 — UI 파일 + UI diff만)
SORTED_FILES=$(echo "$UI_FILES" | sort | tr -d '[:space:]')
CURRENT_HASH=$(printf '%s%s' "$SORTED_FILES" "$UI_DIFF_TEXT" | { shasum -a 256 2>/dev/null || sha256sum; } | awk '{print "sha256:"$1}')

CACHE_HIT=false
if [ -f "$LAST_AUDIT" ]; then
  PREV_HASH=$(jq -r '.hash // ""' "$LAST_AUDIT" 2>/dev/null || echo "")
  PREV_RESULT=$(jq -r '.result // ""' "$LAST_AUDIT" 2>/dev/null || echo "")
  if [ "$PREV_HASH" = "$CURRENT_HASH" ] && [ "$PREV_RESULT" = "PASS" ]; then
    CACHE_HIT=true
  fi
fi

FILES_JSON=$(echo "$UI_FILES" | grep -v '^[[:space:]]*$' | jq -R . | jq -sc . 2>/dev/null || echo '[]')
printf '{"is_ui":true,"files":%s,"loc":%d,"reason":"ui change detected","hash":"%s","cache_hit":%s}\n' \
  "$FILES_JSON" "$UI_LOC" "$CURRENT_HASH" "$CACHE_HIT"
