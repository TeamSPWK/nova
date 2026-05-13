#!/bin/bash
# init-roadmap.sh — ROADMAP.md init wizard (§15)
# Contract: docs/designs/status-dashboard.md §15 (3 modes: blank / scan / llm)
# Usage:    ./scripts/init-roadmap.sh --blank | --scan | --llm
# Guide:    docs/guides/status-dashboard.md

set -euo pipefail

MODE=""
OUT="ROADMAP.md"
FORCE=false

print_help() {
  cat <<'EOF'
Usage: init-roadmap.sh --<mode> [options]

Modes (택1 필수):
  --blank   빈 ROADMAP.md 템플릿 (1초). 기존 docs 0건 참조.
  --scan    docs/plans/*.md frontmatter 추출 (5초). parent_phase 기반 자동 추출.
  --llm     LLM 자료 수집 → .nova/init-input.json. 실제 초안 작성은 Claude Agent.

Options:
  --out <path>   출력 경로. Default: ROADMAP.md (루트)
  --force        기존 ROADMAP.md 덮어쓰기 (default: 거부)
  -h, --help     Show this help

자동 commit 0건. 모든 모드는 파일만 생성 후 사용자에게 commit 안내.

Spec: docs/designs/status-dashboard.md §15
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --blank) MODE="blank"; shift ;;
    --scan)  MODE="scan";  shift ;;
    --llm)   MODE="llm";   shift ;;
    --out) OUT="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "[init-roadmap] Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "[init-roadmap] 모드를 명시하세요 (--blank / --scan / --llm)" >&2
  print_help >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "[init-roadmap] python3 required" >&2; exit 3; }
python3 -c "import yaml" 2>/dev/null || { echo "[init-roadmap] PyYAML required: pip3 install PyYAML" >&2; exit 3; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=(--mode "$MODE" --out "$OUT")
$FORCE && ARGS+=(--force)

exec python3 "$DIR/lib/init-roadmap.py" "${ARGS[@]}"
