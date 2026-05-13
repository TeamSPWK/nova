#!/bin/bash
# enrich-plans.sh — docs/plans/*.md frontmatter v1.1 자동 추가
# Contract: docs/designs/status-dashboard.md §17~§19
# Usage:    ./scripts/enrich-plans.sh --collect     # Stage 1: 자료 수집
#           ./scripts/enrich-plans.sh --dry-run     # Stage 3: drafts 생성 (default 적용 모드)
#           ./scripts/enrich-plans.sh --patch       # Stage 3: unified diff 1개
#           ./scripts/enrich-plans.sh --apply       # Stage 3: 원본 prepend + .bak
# Guide:    docs/guides/status-dashboard.md §8

set -euo pipefail

MODE=""
ROADMAP=""
BATCH_SIZE=10
FORCE=false

print_help() {
  cat <<'EOF'
Usage: enrich-plans.sh --<mode> [options]

Modes (택1 필수):
  --collect      Stage 1. ROADMAP + docs/plans/* 스캔 → .nova/enrich-batches/*.json
  --dry-run      Stage 3 (default). 각 plan 옆에 <plan>.frontmatter.draft 생성
  --patch        Stage 3. .nova/enrich-plans.patch 1개 (unified diff)
  --apply        Stage 3. 원본에 prepend (.bak 자동 백업). --force 필요

Options:
  --roadmap <path>   외부 ROADMAP.md 경로 (default: auto-discover)
  --batch-size <n>   Default 10 (LLM context 폭증 방지)
  --force            --apply 시 명시적 동의 (안전 게이트)
  -h, --help         Show this help

흐름:
  1. ./scripts/enrich-plans.sh --collect
  2. (메인 Claude가 Agent subagent에게 batch별 frontmatter 제안 위임)
  3. ./scripts/enrich-plans.sh --dry-run  (또는 --patch/--apply)

자동 git commit 0건. 모든 모드는 파일만 생성/수정 후 사용자에게 git diff + commit 안내.

Spec: docs/designs/status-dashboard.md §17~§19
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collect) MODE="collect"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --patch)   MODE="patch"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --roadmap) ROADMAP="$2"; shift 2 ;;
    --batch-size) BATCH_SIZE="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "[enrich-plans] Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "[enrich-plans] 모드를 명시하세요 (--collect / --dry-run / --patch / --apply)" >&2
  print_help >&2
  exit 2
fi

if [[ "$MODE" == "apply" ]] && ! $FORCE; then
  echo "[enrich-plans] --apply는 --force 필수 (원본 직접 prepend, .bak 백업)" >&2
  echo "  안전: 먼저 --dry-run으로 검수 후 --apply --force" >&2
  exit 6
fi

command -v python3 >/dev/null 2>&1 || { echo "[enrich-plans] python3 required" >&2; exit 3; }
python3 -c "import yaml" 2>/dev/null || { echo "[enrich-plans] PyYAML required: pip3 install PyYAML" >&2; exit 3; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=(--mode "$MODE" --batch-size "$BATCH_SIZE")
[[ -n "$ROADMAP" ]] && ARGS+=(--roadmap "$ROADMAP")
$FORCE && ARGS+=(--force)

exec python3 "$DIR/lib/enrich-plans.py" "${ARGS[@]}"
