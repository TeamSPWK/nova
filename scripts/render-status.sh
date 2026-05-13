#!/bin/bash
# render-status.sh — StatusData JSON → stand-alone HTML (template inject)
# Contract: docs/designs/status-dashboard.md §7 (HTML template) + §3 (pipeline render step)
# Usage:    ./scripts/render-status.sh [--plan <path>|--data <path>] [--out <path>] [--open] [--since <date>]
# Guide:    docs/guides/status-dashboard.md

set -euo pipefail

DATA=""
PLAN=""
ROADMAP=""
STALE_THRESHOLD=""
NO_ROADMAP=false
OUT=".nova/status/index.html"
SINCE=""
OPEN=false

print_help() {
  cat <<'EOF'
Usage: render-status.sh [options]

Options:
  --plan <path>             Plan markdown. build-status.sh를 내부 호출.
  --roadmap <path>          ROADMAP.md path (Phase 2 통합 모드)
  --data <path>             이미 생성된 StatusData JSON. (--plan과 동시 X)
  --out  <path>             출력 HTML 경로. Default: .nova/status/index.html
  --since <date>            --plan/--roadmap 사용 시 git --since (Default: "7 days ago")
  --stale-threshold <days>  ROADMAP stale 임계 (default 7)
  --no-roadmap              ROADMAP 발견 시도 X — Phase 1 강제
  --open                    렌더 후 브라우저로 열기 (macOS open / Linux xdg-open)
  -h, --help                Show this help

둘 다 미지정 시: build-status.sh가 ROADMAP.md → docs/plans/*.md 순으로 자동 발견.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data) DATA="$2"; shift 2 ;;
    --plan) PLAN="$2"; shift 2 ;;
    --roadmap) ROADMAP="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --stale-threshold) STALE_THRESHOLD="$2"; shift 2 ;;
    --no-roadmap) NO_ROADMAP=true; shift ;;
    --open) OPEN=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "[render-status] Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

if [[ -n "$DATA" && -n "$PLAN" ]]; then
  echo "[render-status] --data와 --plan은 동시 사용 불가" >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "[render-status] python3 required" >&2; exit 3; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
TEMPLATE="$ROOT/templates/status-dashboard/index.html"

[[ -f "$TEMPLATE" ]] || { echo "[render-status] Template not found: $TEMPLATE" >&2; exit 3; }

# data source 결정 — DATA가 없으면 build 호출
CLEANUP=""
if [[ -z "$DATA" ]]; then
  DATA="$(mktemp -t nova-status-XXXXXX)"
  CLEANUP="$DATA"
  trap '[[ -n "$CLEANUP" ]] && rm -f "$CLEANUP"' EXIT
  BUILD_ARGS=(--out "$DATA" --quiet)
  [[ -n "$PLAN" ]] && BUILD_ARGS+=(--plan "$PLAN")
  [[ -n "$ROADMAP" ]] && BUILD_ARGS+=(--roadmap "$ROADMAP")
  [[ -n "$SINCE" ]] && BUILD_ARGS+=(--since "$SINCE")
  [[ -n "$STALE_THRESHOLD" ]] && BUILD_ARGS+=(--stale-threshold "$STALE_THRESHOLD")
  $NO_ROADMAP && BUILD_ARGS+=(--no-roadmap)
  "$DIR/build-status.sh" "${BUILD_ARGS[@]}"
fi

[[ -f "$DATA" ]] || { echo "[render-status] JSON not found: $DATA" >&2; exit 4; }

mkdir -p "$(dirname "$OUT")"

# Inject (Python — 마커 결정론 치환)
python3 - "$TEMPLATE" "$DATA" "$OUT" <<'PY'
import re, sys
from pathlib import Path
tpl_path, data_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
tpl = Path(tpl_path).read_text(encoding='utf-8')
data = Path(data_path).read_text(encoding='utf-8').strip()
marker_open = '/*__NOVA_DATA__*/'
marker_close = '/*__NOVA_DATA_END__*/'
pattern = re.escape(marker_open) + r'.*?' + re.escape(marker_close)
new_block = marker_open + data + marker_close
new_html, n = re.subn(pattern, lambda _: new_block, tpl, count=1, flags=re.S)
if n != 1:
    print(f"[render-status] Marker block not found in template", file=sys.stderr)
    sys.exit(5)
Path(out_path).write_text(new_html, encoding='utf-8')
PY

echo "[render-status] Rendered: $OUT" >&2

if $OPEN; then
  ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  case "$(uname -s)" in
    Darwin) open "file://$ABS" ;;
    Linux)  xdg-open "file://$ABS" >/dev/null 2>&1 || true ;;
    *)      echo "[render-status] --open: 알 수 없는 OS, 수동으로 열어주세요: file://$ABS" >&2 ;;
  esac
fi
