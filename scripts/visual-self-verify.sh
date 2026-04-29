#!/usr/bin/env bash
# Nova — Visual Self-Verify (G3) Information Collector
#
# Collects information for visual verification:
# - Reads intent.json (G1 output)
# - Detects available capture infrastructure (Playwright MCP / manual / fallback)
# - Generates evaluator prompt for Agent subagent (the actual VLM judge)
#
# This script does NOT call any external API. It outputs ready_for_judge JSON
# which the calling command (/nova:run, /nova:check) passes to an Agent subagent.
# The Agent uses the user's Claude Code session model (vision-capable Claude).
#
# Usage:
#   bash scripts/visual-self-verify.sh --intent <path> [options]
#
# Options:
#   --intent <path>          intent.json path (required)
#   --screenshots <glob>     Existing screenshots glob
#   --mode {auto|manual|code-only}   Capture mode (default: auto)
#   --non-interactive        Skip user-manual fallback
#   --skip-visual-verify     Opt-out (returns skipped:true)
#   --strict-vlm             Hint to caller: spawn Agent with model: opus
#   --output <path>          Output JSON path (default: .nova/visual-audit/<slug>-<ts>.json)
#   -h, --help               Show help and guide path
#
# Output (JSON to stdout):
#   {
#     "ready_for_judge": bool,
#     "intent_path": str,
#     "screenshot_paths": [str],
#     "screenshot_source": "playwright-mcp | user-manual | code-only-fallback",
#     "evaluator_prompt": str,
#     "cache_hit": bool,
#     "hash": str,
#     "skipped": bool,
#     "skip_reason": str?,
#     "agent_model_hint": "default | opus"
#   }
#
# Spec: docs/designs/visual-intent-verify.md (Sprint A2)
# Guide: docs/guides/ui-quality-gate.md

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
INTENT_PATH=""
SCREENSHOTS_GLOB=""
MODE="auto"
NON_INTERACTIVE=false
SKIP=false
STRICT_VLM=false
OUTPUT_PATH=""

show_help() {
  cat <<'EOF'
Nova — Visual Self-Verify (G3) Information Collector

USAGE:
  bash scripts/visual-self-verify.sh --intent <path> [options]

OPTIONS:
  --intent <path>          intent.json path (required, from G1 capture)
  --screenshots <glob>     Existing screenshot paths glob
  --mode {auto|manual|code-only}   Capture mode (default: auto)
  --non-interactive        Skip user-manual fallback (CI mode)
  --skip-visual-verify     Opt-out (returns skipped:true)
  --strict-vlm             Hint caller to use opus model in Agent
  --output <path>          Output JSON path
  -h, --help               This help

OUTPUT (stdout JSON):
  ready_for_judge / intent_path / screenshot_paths / screenshot_source /
  evaluator_prompt / cache_hit / hash / skipped / agent_model_hint

DEPENDENCIES:
  Anthropic API key:   NOT REQUIRED (Agent subagent uses session model)
  Playwright MCP:       OPTIONAL (graceful fallback to manual/code-only)

GUIDE:
  docs/guides/ui-quality-gate.md (TL;DR + 절차 + FAIL 해결 + cheatsheet)
EOF
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --intent) INTENT_PATH="$2"; shift 2 ;;
    --screenshots) SCREENSHOTS_GLOB="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --skip-visual-verify) SKIP=true; shift ;;
    --strict-vlm) STRICT_VLM=true; shift ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
  esac
done

# === Skip path (opt-out) ===
if [ "$SKIP" = true ]; then
  jq -cn '{
    ready_for_judge: false,
    skipped: true,
    skip_reason: "user --skip-visual-verify",
    cache_hit: false
  }'
  # log-metric (best-effort)
  if [ -x "$ROOT_DIR/scripts/log-metric.sh" ]; then
    bash "$ROOT_DIR/scripts/log-metric.sh" --event visual_verify_skipped --reason flag 2>/dev/null || true
  fi
  exit 0
fi

# nova-config.json opt-out
if [ -f "nova-config.json" ]; then
  CFG_OPT=$(jq -r '.auto.visualVerify // true' nova-config.json 2>/dev/null || echo "true")
  if [ "$CFG_OPT" = "false" ]; then
    jq -cn '{
      ready_for_judge: false,
      skipped: true,
      skip_reason: "nova-config.json auto.visualVerify=false",
      cache_hit: false
    }'
    if [ -x "$ROOT_DIR/scripts/log-metric.sh" ]; then
      bash "$ROOT_DIR/scripts/log-metric.sh" --event visual_verify_skipped --reason config 2>/dev/null || true
    fi
    exit 0
  fi
fi

# === Required: intent.json ===
if [ -z "$INTENT_PATH" ]; then
  echo "Error: --intent <path> required" >&2
  show_help
  exit 1
fi

if [ ! -f "$INTENT_PATH" ]; then
  echo "Error: intent.json not found: $INTENT_PATH" >&2
  echo "Hint: run /nova:plan first (G1 capture) — see docs/guides/ui-quality-gate.md" >&2
  exit 1
fi

# Validate intent.json schema (minimum)
if ! jq -e '.version == "1.0" and .meta.slug and .vocabulary.primary' "$INTENT_PATH" > /dev/null 2>&1; then
  echo "Error: intent.json invalid (must be version 1.0 with .meta.slug and .vocabulary.primary)" >&2
  exit 1
fi

SLUG=$(jq -r '.meta.slug' "$INTENT_PATH")

# === Cache check (reuse detect-ui-change.sh hash) ===
CACHE_HIT=false
CURRENT_HASH=""
LAST_VISUAL_AUDIT=".nova/last-visual-audit.json"

if [ -x "$ROOT_DIR/scripts/detect-ui-change.sh" ]; then
  DETECT_OUT=$(bash "$ROOT_DIR/scripts/detect-ui-change.sh" --post-impl 2>/dev/null || echo '{}')
  CURRENT_HASH=$(echo "$DETECT_OUT" | jq -r '.hash // ""')
  if [ -f "$LAST_VISUAL_AUDIT" ] && [ -n "$CURRENT_HASH" ]; then
    PREV_HASH=$(jq -r '.hash // ""' "$LAST_VISUAL_AUDIT" 2>/dev/null || echo "")
    PREV_VERDICT=$(jq -r '.verdict // ""' "$LAST_VISUAL_AUDIT" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" = "$PREV_HASH" ] && [ "$PREV_VERDICT" = "pass" ]; then
      CACHE_HIT=true
    fi
  fi
fi

if [ "$CACHE_HIT" = true ]; then
  jq -cn --arg ip "$INTENT_PATH" --arg h "$CURRENT_HASH" '{
    ready_for_judge: false,
    cache_hit: true,
    hash: $h,
    intent_path: $ip,
    skipped: true,
    skip_reason: "cache hit (same change previously verified PASS)"
  }'
  if [ -x "$ROOT_DIR/scripts/log-metric.sh" ]; then
    bash "$ROOT_DIR/scripts/log-metric.sh" --event visual_verify_cache_hit 2>/dev/null || true
  fi
  exit 0
fi

# === Screenshot acquisition (fallback chain) ===
SCREENSHOT_PATHS='[]'
SCREENSHOT_SOURCE=""
FALLBACK_LEVEL=0

# Helper: detect Playwright MCP availability
playwright_mcp_available() {
  # Check if Claude Code config or env hints at Playwright MCP
  # Conservative detection: env var, config file, or existing MCP config
  [ -n "${NOVA_PLAYWRIGHT_MCP:-}" ] && return 0
  [ -f "$HOME/.claude/mcp_servers.json" ] && grep -q "playwright" "$HOME/.claude/mcp_servers.json" 2>/dev/null && return 0
  [ -f ".claude/mcp_servers.json" ] && grep -q "playwright" .claude/mcp_servers.json 2>/dev/null && return 0
  return 1
}

# 1차: explicit screenshots provided?
if [ -n "$SCREENSHOTS_GLOB" ]; then
  # Expand glob
  SCREENSHOT_PATHS=$(ls -1 $SCREENSHOTS_GLOB 2>/dev/null | jq -R . | jq -sc . || echo '[]')
  SCREENSHOT_COUNT=$(echo "$SCREENSHOT_PATHS" | jq 'length')
  if [ "$SCREENSHOT_COUNT" -gt 0 ]; then
    SCREENSHOT_SOURCE="provided"
    FALLBACK_LEVEL=1
  fi
fi

# 1차: auto + Playwright MCP available
if [ "$FALLBACK_LEVEL" -eq 0 ] && [ "$MODE" = "auto" ]; then
  if playwright_mcp_available; then
    SCREENSHOT_SOURCE="playwright-mcp"
    FALLBACK_LEVEL=1
    # Note: actual screenshot capture is delegated to caller (Claude Code with MCP).
    # Script outputs intent for Agent that will request MCP screenshot via tool calls.
    # Provide marker that caller should use Playwright MCP first.
  fi
fi

# 2차: manual mode (interactive, user provides path)
if [ "$FALLBACK_LEVEL" -eq 0 ] && [ "$MODE" != "code-only" ] && [ "$NON_INTERACTIVE" = false ]; then
  if [ -t 0 ] && [ -t 1 ]; then  # stdin/stdout are tty
    echo "[Nova] Visual self-verify: Playwright MCP 미연결." >&2
    echo "[Nova] 수동 스크린샷 경로를 입력하세요 (여러 개는 공백 구분, Enter만 누르면 코드 분석 폴백):" >&2
    printf "> " >&2
    read -r MANUAL_PATHS
    if [ -n "$MANUAL_PATHS" ]; then
      # Validate each path exists
      VALID_PATHS=""
      for p in $MANUAL_PATHS; do
        if [ -f "$p" ]; then
          VALID_PATHS="${VALID_PATHS}${p}"$'\n'
        else
          echo "[Nova] 경고: '$p' 파일 없음. 스킵." >&2
        fi
      done
      if [ -n "$VALID_PATHS" ]; then
        SCREENSHOT_PATHS=$(echo "$VALID_PATHS" | grep -v '^[[:space:]]*$' | jq -R . | jq -sc . || echo '[]')
        SCREENSHOT_SOURCE="user-manual"
        FALLBACK_LEVEL=2
      fi
    fi
  fi
fi

# 3차: code-only fallback (ux-audit Lite — caller decides to invoke)
if [ "$FALLBACK_LEVEL" -eq 0 ]; then
  SCREENSHOT_SOURCE="code-only-fallback"
  FALLBACK_LEVEL=3
fi

# === Generate evaluator prompt (for Agent subagent) ===
INTENT_INLINE=$(cat "$INTENT_PATH")
RAW_PHRASE=$(jq -r '.vocabulary.raw_user_phrase // ""' "$INTENT_PATH")

EVALUATOR_PROMPT=$(cat <<EOF
너는 Visual Intent Verifier — 디자인 의도와 실제 렌더링 결과를 비교하는 적대적 평가자다.
한국어 사용자 의도를 정확히 해석하고, 결과물이 그 의도에 부합하는지 엄격하게 판정하라.

[Intent JSON]
$INTENT_INLINE

[Screenshots / Code]
$([ "$FALLBACK_LEVEL" -le 2 ] && echo "다음 스크린샷을 분석:" || echo "스크린샷 미제공 — 코드 기반 분석:")
$(echo "$SCREENSHOT_PATHS" | jq -r '.[]' 2>/dev/null | sed 's/^/- /')
$([ "$FALLBACK_LEVEL" -eq 3 ] && echo "(code-only-fallback: ux-audit Lite로 위임 권장)")

[평가 절차]
1. intent.vocabulary.primary 어휘의 시각 원칙을 적용 (예: shadcn → 미니멀 + 접근성, Linear → 고밀도 + 키보드 우선, Liquid Glass → translucency + depth, Material 3 → expressive + dynamic color)
2. intent.scope.scope_type 범위만 평가. 범위 외 영역은 무시.
3. intent.success_criteria 각 항목을 결과에서 검증.
4. intent.visual_checks 각 check_id를 검증 (없으면 success_criteria로 대체).
5. raw_user_phrase ("$RAW_PHRASE")가 결과에 자연스럽게 반영됐는지 판단.
6. 사이드 사례 차단 — "광범위 리뉴얼" 같은 스코프 확장이 의심되면 fail.

[차단 정책]
- critical mismatch 1+ → verdict: fail
- high mismatch 2+ → verdict: fail
- medium만 → verdict: pass (warning)
- code-only-fallback 시 → verdict: degraded (차단 X)

[출력 형식 — JSON only, no prose]
{
  "verdict": "pass | fail | degraded",
  "overall_score": 0-100,
  "mismatches": [
    {
      "check_id": "vc-001",
      "expected": "...",
      "observed": "...",
      "severity": "critical | high | medium",
      "fix_suggestion": "..."
    }
  ],
  "strengths": ["..."],
  "rationale": "200단어 이내 한국어"
}
EOF
)

# === Output ready_for_judge JSON ===
AGENT_MODEL_HINT="default"
[ "$STRICT_VLM" = true ] && AGENT_MODEL_HINT="opus"

# log-metric for fallback level
if [ -x "$ROOT_DIR/scripts/log-metric.sh" ]; then
  bash "$ROOT_DIR/scripts/log-metric.sh" --event visual_verify_fallback --level "$FALLBACK_LEVEL" --source "$SCREENSHOT_SOURCE" 2>/dev/null || true
fi

jq -cn \
  --arg ip "$INTENT_PATH" \
  --argjson sp "$SCREENSHOT_PATHS" \
  --arg src "$SCREENSHOT_SOURCE" \
  --arg ep "$EVALUATOR_PROMPT" \
  --arg h "$CURRENT_HASH" \
  --arg amh "$AGENT_MODEL_HINT" \
  --argjson level "$FALLBACK_LEVEL" \
  '{
    ready_for_judge: true,
    intent_path: $ip,
    screenshot_paths: $sp,
    screenshot_source: $src,
    fallback_level: $level,
    evaluator_prompt: $ep,
    cache_hit: false,
    hash: $h,
    skipped: false,
    agent_model_hint: $amh
  }'

# Write to output file if specified
if [ -n "$OUTPUT_PATH" ]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  jq -cn \
    --arg ip "$INTENT_PATH" \
    --argjson sp "$SCREENSHOT_PATHS" \
    --arg src "$SCREENSHOT_SOURCE" \
    --arg ep "$EVALUATOR_PROMPT" \
    --arg h "$CURRENT_HASH" \
    --arg amh "$AGENT_MODEL_HINT" \
    --argjson level "$FALLBACK_LEVEL" \
    '{
      ready_for_judge: true,
      intent_path: $ip,
      screenshot_paths: $sp,
      screenshot_source: $src,
      fallback_level: $level,
      evaluator_prompt: $ep,
      cache_hit: false,
      hash: $h,
      skipped: false,
      agent_model_hint: $amh
    }' > "$OUTPUT_PATH"
fi
