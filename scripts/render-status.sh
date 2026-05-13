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
AUTO_BOOTSTRAP=false
NO_BOOTSTRAP=false

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
  --auto-bootstrap          minimal mode 감지 시 init-roadmap.sh --llm 자동 호출 + 안내 (Phase 4+)
  --no-bootstrap            --auto-bootstrap이 켜져 있어도 명시적 OFF (bin/nova-status 우회용)
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
    --auto-bootstrap) AUTO_BOOTSTRAP=true; shift ;;
    --no-bootstrap) NO_BOOTSTRAP=true; shift ;;
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
# XSS guard: escape `</` so embedded `</script>` cannot terminate the host tag.
# JSON.parse decodes `<\/` back to `</`, so payload roundtrips losslessly.
data = data.replace('</', '<\\/')
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

# ─────────────────────────────────────────────────────────────
# Phase 4 — minimal 자동 부트스트랩 (Design §22)
# ─────────────────────────────────────────────────────────────
if $AUTO_BOOTSTRAP && ! $NO_BOOTSTRAP; then
  MINIMAL_CHECK=$(python3 -c "
import json, sys
try:
    d = json.load(open('$DATA'))
    mode = d.get('mode', '')
    minimal = d.get('minimal', False)
    print('TRIGGER' if (mode == 'phase1' and minimal) else 'OK')
except Exception:
    print('OK')
")
  if [[ "$MINIMAL_CHECK" == "TRIGGER" ]]; then
    # 프로젝트 slug 산출 — /tmp draft 경로 cross-pollution 방지
    # 우선순위: git root basename → cwd basename → "project"
    SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 2>/dev/null)
    SLUG="${SLUG:-project}"
    # slug sanitize — 영숫자/하이픈/언더스코어만 (path injection 차단)
    SLUG=$(printf '%s' "$SLUG" | tr -c 'A-Za-z0-9._-' '_' | tr -s '_' | sed 's/^_//;s/_$//')
    SLUG="${SLUG:-project}"
    DRAFT_PATH="/tmp/ROADMAP-${SLUG}-draft.md"

    echo "" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    echo "  ⚡ minimal mode 감지 — 자동 부트스트랩 (Phase 4)" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    echo "  [1/3] 자료 수집 (init-roadmap.sh --llm)" >&2
    if "$DIR/init-roadmap.sh" --llm >&2 2>&1; then
      echo "" >&2
      echo "  [2/3] Claude(메인)에게 위임:" >&2
      echo "     Agent(general-purpose) prompt:" >&2
      echo "     \"docs/designs/status-dashboard.md §12 + .nova/init-input.json 기반으로" >&2
      echo "      ${DRAFT_PATH} 작성. ⚠️ unsure rule 준수. 자동 commit 금지." >&2
      echo "      Phase status 규칙(중요):" >&2
      echo "        - done/in_progress/pending/blocked 4개만 허용" >&2
      echo "        - blocked = 외부 trigger(승인·사고·사람) 필요한 phase 전용" >&2
      echo "        - 선행 phase 미완료로 인한 대기는 반드시 pending (blocked 금지)" >&2
      echo "        - title 필수(id와 다른 값), summary는 한 줄 요약\"" >&2
      echo "" >&2
      echo "  [3/3] draft 생성 후 재실행:" >&2
      echo "     bash \"\$NOVA_PLUGIN_ROOT/scripts/render-status.sh\" --roadmap ${DRAFT_PATH} --open" >&2
      echo "" >&2
      echo "  ※ 자동 commit 0건 — 사용자 검수 후 명시적 commit" >&2
      echo "  ※ HTML은 minimal mode로 우선 생성됨 ($OUT) — 부트스트랩 후 갱신" >&2
      echo "  ※ draft 경로는 프로젝트 slug 기반 — 멀티 프로젝트 cross-pollution 차단 (v5.35.4)" >&2
      echo "════════════════════════════════════════════════════════════" >&2
    fi
  fi
fi

if $OPEN; then
  ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  case "$(uname -s)" in
    Darwin) open "file://$ABS" ;;
    Linux)  xdg-open "file://$ABS" >/dev/null 2>&1 || true ;;
    *)      echo "[render-status] --open: 알 수 없는 OS, 수동으로 열어주세요: file://$ABS" >&2 ;;
  esac
fi
