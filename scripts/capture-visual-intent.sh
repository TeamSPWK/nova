#!/usr/bin/env bash
# Nova — Visual Intent Capture (G1)
# Captures user's visual intent into intent.json before UI implementation.
#
# Usage:
#   bash scripts/capture-visual-intent.sh --slug <slug> [options]
#
# Options:
#   --slug <slug>            Plan slug (required). Output: docs/plans/<slug>-intent.json
#   --quick                  1-second capture: shadcn default + auto-detected scope/DS
#   --from-prompt "<text>"   Auto-extract hints from user prompt
#   --non-interactive        CI/script mode — write placeholder intent.json with extracted defaults
#   --output <path>          Override output path (default: docs/plans/<slug>-intent.json)
#   --catalog <path>         Override catalog path (default: docs/catalogs/design-vocabulary.json)
#   -h, --help               Show this help and guide path
#
# Spec: docs/designs/visual-intent-verify.md (Sprint A1)
# Guide: docs/guides/ui-quality-gate.md
# Schema: intent.json v1.0 (defined in Design)

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
SLUG=""
QUICK=false
NON_INTERACTIVE=false
PROMPT_TEXT=""
OUTPUT_PATH=""
CATALOG_PATH="$ROOT_DIR/docs/catalogs/design-vocabulary.json"

show_help() {
  cat <<'EOF'
Nova — Visual Intent Capture (G1)

USAGE:
  bash scripts/capture-visual-intent.sh --slug <slug> [options]

OPTIONS:
  --slug <slug>            Plan slug (required)
  --quick                  1-second capture (shadcn default + auto-detected)
  --from-prompt "<text>"   Auto-extract hints from prompt
  --non-interactive        CI mode (placeholder + extracted defaults)
  --output <path>          Override output path
  --catalog <path>         Override catalog path
  -h, --help               This help

OUTPUT:
  docs/plans/<slug>-intent.json (intent.json v1.0)

GUIDE:
  docs/guides/ui-quality-gate.md (TL;DR + 절차 + FAIL 해결 + cheatsheet)

SCHEMA:
  See docs/designs/visual-intent-verify.md (Data Contract section)
EOF
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --quick) QUICK=true; shift ;;
    --from-prompt) PROMPT_TEXT="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    --catalog) CATALOG_PATH="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
  esac
done

if [ -z "$SLUG" ]; then
  echo "Error: --slug required" >&2
  show_help
  exit 1
fi

# Default output
if [ -z "$OUTPUT_PATH" ]; then
  OUTPUT_PATH="$ROOT_DIR/docs/plans/${SLUG}-intent.json"
fi

# Verify catalog exists
if [ ! -f "$CATALOG_PATH" ]; then
  echo "Error: catalog not found at $CATALOG_PATH" >&2
  exit 1
fi

# === Auto-extraction from prompt ===
extract_vocabulary_from_prompt() {
  local p="$1"
  [ -z "$p" ] && { echo "shadcn"; return; }

  # Match catalog keys + common phrases
  local lower
  lower=$(echo "$p" | tr '[:upper:]' '[:lower:]')

  case "$lower" in
    *liquid*glass*|*wwdc*2026*|*visionos*) echo "liquid-glass"; return ;;
    *material*3*|*material*you*) echo "material-3"; return ;;
    *apple*hig*|*ios*hig*) echo "apple-hig"; return ;;
    *shadcn*) echo "shadcn"; return ;;
    *linear*) echo "linear"; return ;;
    *vercel*|*geist*) echo "vercel"; return ;;
    *notion*) echo "notion"; return ;;
    *tailwind*ui*) echo "tailwind-ui"; return ;;
    *radix*) echo "radix"; return ;;
    *mantine*) echo "mantine"; return ;;
    *chakra*) echo "chakra"; return ;;
  esac

  # Detect Tailwind in workspace → suggest shadcn
  if [ -f "$ROOT_DIR/tailwind.config.ts" ] || [ -f "$ROOT_DIR/tailwind.config.js" ] || [ -f "tailwind.config.ts" ] || [ -f "tailwind.config.js" ]; then
    echo "shadcn"
    return
  fi

  echo "shadcn"  # safe default
}

extract_scope_files() {
  # Use detect-ui-change.sh --planning if available
  local files_json="[]"
  if [ -x "$ROOT_DIR/scripts/detect-ui-change.sh" ]; then
    files_json=$(bash "$ROOT_DIR/scripts/detect-ui-change.sh" --planning 2>/dev/null | jq -c '.files // []' 2>/dev/null || echo "[]")
  fi
  echo "$files_json"
}

detect_design_system() {
  if [ -x "$ROOT_DIR/scripts/detect-design-system.sh" ]; then
    bash "$ROOT_DIR/scripts/detect-design-system.sh" 2>/dev/null || echo '{"detected":false}'
  else
    echo '{"detected":false}'
  fi
}

# === Load catalog ===
get_catalog_url() {
  local key="$1"
  jq -r --arg k "$key" '.vocabulary[] | select(.key == $k) | .url' "$CATALOG_PATH" 2>/dev/null
}

# === Auto-extract defaults ===
DEFAULT_VOCAB=$(extract_vocabulary_from_prompt "$PROMPT_TEXT")
DEFAULT_VOCAB_URL=$(get_catalog_url "$DEFAULT_VOCAB")
SCOPE_FILES=$(extract_scope_files)
DS_RESULT=$(detect_design_system)
DS_DETECTED=$(echo "$DS_RESULT" | jq -r '.detected // false')

# Scope file count
SCOPE_FILE_COUNT=$(echo "$SCOPE_FILES" | jq 'length' 2>/dev/null || echo 0)

# Determine scope_type heuristic
if [ "$SCOPE_FILE_COUNT" -le 1 ]; then
  DEFAULT_SCOPE_TYPE="single-component"
elif [ "$SCOPE_FILE_COUNT" -le 5 ]; then
  DEFAULT_SCOPE_TYPE="screen"
elif [ "$SCOPE_FILE_COUNT" -le 15 ]; then
  DEFAULT_SCOPE_TYPE="feature"
else
  DEFAULT_SCOPE_TYPE="full-renewal"
fi

# DS mode default
if [ "$DS_DETECTED" = "true" ]; then
  DEFAULT_DS_MODE="use-existing"
else
  DEFAULT_DS_MODE="none"
fi

# === Quick or non-interactive mode → freeze immediately ===
write_intent_json() {
  local vocab="$1" vocab_url="$2" scope_type="$3" scope_files="$4" ds_mode="$5" captured_by="$6"
  local ds_source="none" ds_tokens='{"color":[],"spacing":[],"fontSize":[]}'
  if [ "$DS_DETECTED" = "true" ]; then
    ds_source=$(echo "$DS_RESULT" | jq -r '.sources[0].type // "none"')
    ds_tokens=$(echo "$DS_RESULT" | jq -c '.tokens // {}')
  fi

  local plan_path="docs/plans/${SLUG}.md"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  jq -cn \
    --arg slug "$SLUG" \
    --arg ts "$ts" \
    --arg captured_by "$captured_by" \
    --arg plan_path "$plan_path" \
    --arg vocab "$vocab" \
    --arg vocab_url "$vocab_url" \
    --arg raw_phrase "$PROMPT_TEXT" \
    --argjson scope_files "$scope_files" \
    --arg scope_type "$scope_type" \
    --arg ds_mode "$ds_mode" \
    --arg ds_source "$ds_source" \
    --argjson ds_tokens "$ds_tokens" \
    '{
      "$schema": "https://json-schema.org/draft-07/schema",
      "version": "1.0",
      "meta": {
        "slug": $slug,
        "created_at": $ts,
        "captured_by": $captured_by,
        "plan_path": $plan_path
      },
      "vocabulary": {
        "primary": $vocab,
        "primary_reference_url": $vocab_url,
        "fallback": [],
        "raw_user_phrase": $raw_phrase
      },
      "scope": {
        "included": $scope_files,
        "excluded": [],
        "scope_type": $scope_type,
        "user_explicit": false,
        "agent_inferred_excluded": []
      },
      "design_system": {
        "mode": $ds_mode,
        "source": $ds_source,
        "detected_tokens": $ds_tokens,
        "user_decision": "auto-detected (review and update if needed)"
      },
      "references": {
        "figma_url": null,
        "screenshot_paths": [],
        "natural_language": $raw_phrase,
        "wireframe_ascii": null,
        "inspiration_urls": []
      },
      "success_criteria": [],
      "visual_checks": []
    }'
}

# === Interactive prompt (skipped in --quick / --non-interactive) ===
prompt_user() {
  local question="$1" default="$2" answer
  printf '%s [default: %s] > ' "$question" "$default" >&2
  read -r answer
  echo "${answer:-$default}"
}

if [ "$QUICK" = true ] || [ "$NON_INTERACTIVE" = true ]; then
  # Freeze with auto-extracted defaults
  CAPTURED_BY="quick"
  [ "$NON_INTERACTIVE" = true ] && CAPTURED_BY="non-interactive"
  INTENT_JSON=$(write_intent_json \
    "$DEFAULT_VOCAB" "$DEFAULT_VOCAB_URL" \
    "$DEFAULT_SCOPE_TYPE" "$SCOPE_FILES" \
    "$DEFAULT_DS_MODE" "$CAPTURED_BY")

  mkdir -p "$(dirname "$OUTPUT_PATH")"
  echo "$INTENT_JSON" | jq . > "$OUTPUT_PATH"
  echo "[Nova] Intent captured ($CAPTURED_BY): $OUTPUT_PATH" >&2
  echo "$OUTPUT_PATH"
  exit 0
fi

# === Interactive 4-stage capture ===
echo "[Nova UI Intent Capture] visual-intent-verify를 위한 시각 의도를 캡처합니다." >&2
echo "" >&2

# 1/4 vocabulary
echo "[1/4] 디자인 어휘 — 어떤 트렌드/시스템을 따를까요?" >&2
echo "  자동 추천: $DEFAULT_VOCAB ($DEFAULT_VOCAB_URL)" >&2
echo "" >&2
jq -r '.vocabulary[] | "  " + .key + " — " + .name + " (" + .url + ")"' "$CATALOG_PATH" >&2
echo "" >&2
VOCAB_KEY=$(prompt_user "어휘 key (Enter for default)" "$DEFAULT_VOCAB")
VOCAB_URL=$(get_catalog_url "$VOCAB_KEY")
[ -z "$VOCAB_URL" ] && VOCAB_URL="(custom: $VOCAB_KEY)"

# 2/4 scope
echo "" >&2
echo "[2/4] 스코프 — 어디까지 변경할까요?" >&2
echo "  자동 감지 파일 ($SCOPE_FILE_COUNT개): $SCOPE_FILES" >&2
echo "  옵션: single-component | screen | feature | full-renewal" >&2
SCOPE_TYPE=$(prompt_user "scope type" "$DEFAULT_SCOPE_TYPE")

# 3/4 design system
echo "" >&2
echo "[3/4] 디자인 시스템 — 토큰 활용 방식?" >&2
if [ "$DS_DETECTED" = "true" ]; then
  echo "  감지: $(echo "$DS_RESULT" | jq -r '.sources[0].path // "(unknown)"')" >&2
  echo "  토큰 카운트: $(echo "$DS_RESULT" | jq -c '.tokenCount // {}')" >&2
else
  echo "  감지: 디자인 시스템 미정의" >&2
fi
echo "  옵션: use-existing | extend | create-new | none" >&2
DS_MODE=$(prompt_user "DS mode" "$DEFAULT_DS_MODE")

# 4/4 references
echo "" >&2
echo "[4/4] 시각 reference (선택) — 의도를 보강할 자료?" >&2
echo "  Figma URL, 스크린샷 경로, 또는 (없음 — Enter)" >&2
REF_INPUT=$(prompt_user "reference (Enter to skip)" "")

REFERENCES_JSON='{"figma_url":null,"screenshot_paths":[],"natural_language":null,"wireframe_ascii":null,"inspiration_urls":[]}'
if [ -n "$REF_INPUT" ]; then
  if echo "$REF_INPUT" | grep -qE '^https?://(www\.)?figma\.com'; then
    REFERENCES_JSON=$(jq -cn --arg url "$REF_INPUT" '{figma_url: $url, screenshot_paths: [], natural_language: null, wireframe_ascii: null, inspiration_urls: []}')
  elif [ -f "$REF_INPUT" ]; then
    REFERENCES_JSON=$(jq -cn --arg p "$REF_INPUT" '{figma_url: null, screenshot_paths: [$p], natural_language: null, wireframe_ascii: null, inspiration_urls: []}')
  elif echo "$REF_INPUT" | grep -qE '^https?://'; then
    REFERENCES_JSON=$(jq -cn --arg url "$REF_INPUT" '{figma_url: null, screenshot_paths: [], natural_language: null, wireframe_ascii: null, inspiration_urls: [$url]}')
  else
    REFERENCES_JSON=$(jq -cn --arg t "$REF_INPUT" '{figma_url: null, screenshot_paths: [], natural_language: $t, wireframe_ascii: null, inspiration_urls: []}')
  fi
fi

# Freeze intent.json
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
DS_SOURCE="none"
DS_TOKENS='{"color":[],"spacing":[],"fontSize":[]}'
if [ "$DS_DETECTED" = "true" ]; then
  DS_SOURCE=$(echo "$DS_RESULT" | jq -r '.sources[0].type // "none"')
  DS_TOKENS=$(echo "$DS_RESULT" | jq -c '.tokens // {}')
fi

INTENT_JSON=$(jq -cn \
  --arg slug "$SLUG" \
  --arg ts "$TS" \
  --arg plan_path "docs/plans/${SLUG}.md" \
  --arg vocab "$VOCAB_KEY" \
  --arg vocab_url "$VOCAB_URL" \
  --arg raw_phrase "$PROMPT_TEXT" \
  --argjson scope_files "$SCOPE_FILES" \
  --arg scope_type "$SCOPE_TYPE" \
  --arg ds_mode "$DS_MODE" \
  --arg ds_source "$DS_SOURCE" \
  --argjson ds_tokens "$DS_TOKENS" \
  --argjson refs "$REFERENCES_JSON" \
  '{
    "$schema": "https://json-schema.org/draft-07/schema",
    "version": "1.0",
    "meta": {
      "slug": $slug,
      "created_at": $ts,
      "captured_by": "user",
      "plan_path": $plan_path
    },
    "vocabulary": {
      "primary": $vocab,
      "primary_reference_url": $vocab_url,
      "fallback": [],
      "raw_user_phrase": $raw_phrase
    },
    "scope": {
      "included": $scope_files,
      "excluded": [],
      "scope_type": $scope_type,
      "user_explicit": true,
      "agent_inferred_excluded": []
    },
    "design_system": {
      "mode": $ds_mode,
      "source": $ds_source,
      "detected_tokens": $ds_tokens,
      "user_decision": "user-confirmed"
    },
    "references": $refs,
    "success_criteria": [],
    "visual_checks": []
  }')

mkdir -p "$(dirname "$OUTPUT_PATH")"
echo "$INTENT_JSON" | jq . > "$OUTPUT_PATH"
echo "" >&2
echo "[Nova] Intent captured: $OUTPUT_PATH" >&2
echo "$OUTPUT_PATH"
