#!/bin/bash
# build-status.sh — Plan frontmatter + git log → StatusData JSON v1.0
# Contract: docs/designs/status-dashboard.md §4 (input) + §5 (output) + §6 (drift) + §8 (degradation)
# Usage:    ./scripts/build-status.sh [--plan <path>] [--since <date>] [--out <path>] [--quiet]
# Guide:    docs/guides/status-dashboard.md

set -euo pipefail

PLAN=""
ROADMAP=""
SINCE=""
STALE_THRESHOLD=""
NO_ROADMAP=false
OUT=""
QUIET=false

print_help() {
  cat <<'EOF'
Usage: build-status.sh [options]

Options:
  --plan <path>             Plan markdown file (for goals/groups/drift). Default: docs/plans/*.md 자동
  --roadmap <path>          ROADMAP.md path. Default: ROADMAP.md → docs/ROADMAP.md → docs/roadmap.md 자동 발견
  --since <date>            git log --since (e.g. "7 days ago"). Default: "7 days ago"
  --stale-threshold <days>  ROADMAP stale 임계. Default: 7
  --no-roadmap              ROADMAP 발견 시도 X → Phase 1 동작 강제
  --out <path>              Output JSON path. Default: stdout
  --quiet                   Suppress warnings to stderr
  -h, --help                Show this help

Modes:
  Phase 1 (ROADMAP 부재): plan frontmatter SOT (§4)
  Phase 2 (ROADMAP 존재): ROADMAP + docs/plans/*.md 멀티 통합 (§12~§15)

Output: StatusData JSON v1.0 (docs/designs/status-dashboard.md §5)
Render: scripts/render-status.sh < <(this)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --roadmap) ROADMAP="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --stale-threshold) STALE_THRESHOLD="$2"; shift 2 ;;
    --no-roadmap) NO_ROADMAP=true; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --quiet) QUIET=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "[build-status] python3 required" >&2; exit 3; }
command -v git >/dev/null 2>&1 || { echo "[build-status] git required" >&2; exit 3; }
python3 -c "import yaml" 2>/dev/null || { echo "[build-status] PyYAML required: pip3 install PyYAML" >&2; exit 3; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=()
[[ -n "$PLAN" ]] && ARGS+=(--plan "$PLAN")
[[ -n "$ROADMAP" ]] && ARGS+=(--roadmap "$ROADMAP")
[[ -n "$SINCE" ]] && ARGS+=(--since "$SINCE")
[[ -n "$STALE_THRESHOLD" ]] && ARGS+=(--stale-threshold "$STALE_THRESHOLD")
$NO_ROADMAP && ARGS+=(--no-roadmap)
[[ -n "$OUT" ]] && ARGS+=(--out "$OUT")
$QUIET && ARGS+=(--quiet)

exec python3 "$DIR/lib/build-status.py" "${ARGS[@]}"
