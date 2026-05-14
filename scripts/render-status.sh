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
  # v5.36.0: macOS BSD와 GNU 간 mktemp 호환성 문제(-t 옵션 의미 다름) — 명시적 template path로 통일
  # TMPDIR이 set돼있지만 디렉토리가 없으면(다른 프로세스가 cleanup) fallback to /tmp
  TMP_BASE="${TMPDIR:-/tmp}"
  [[ -d "$TMP_BASE" ]] || TMP_BASE="/tmp"
  DATA="$(mktemp "$TMP_BASE/nova-status-XXXXXX")"
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
# OUT을 절대경로화 — auto-bootstrap rerender 시 cwd 변경되어도 안전 (v5.35.7)
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

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
    # slug sanitize — 영숫자/하이픈/언더스코어/점만 (path injection 차단)
    SLUG=$(printf '%s' "$SLUG" | tr -c 'A-Za-z0-9._-' '_' | tr -s '_' | sed 's/^_//;s/_$//')
    # 한글/CJK 등 비-ASCII만 있는 basename은 sanitize 후 빈 문자열·구분자 잔재만 남음 — fallback 강제
    if ! [[ "$SLUG" =~ [A-Za-z0-9] ]]; then
      SLUG="project"
    fi
    # v5.36.0: '..' 또는 점만 있는 slug는 path traversal 표면 — fallback (W1)
    if [[ "$SLUG" == "." || "$SLUG" == ".." || "$SLUG" =~ ^\.+$ ]]; then
      SLUG="project"
    fi
    DRAFT_PATH="/tmp/ROADMAP-${SLUG}-draft.md"

    # SOT 충돌 사전 검사 — 기존 docs/plans/*.md가 있으면 ROADMAP 채택은 N+1번째 SOT 추가 (drift 위험)
    PLAN_COUNT=0
    if [[ -d "docs/plans" ]]; then
      PLAN_COUNT=$(find docs/plans -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    echo "" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    echo "  ⚡ minimal mode 감지 — 자동 부트스트랩 (Phase 4+5)" >&2
    echo "     [EN] minimal mode detected — auto-bootstrap starting" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    # SOT 충돌 경고 — auto-fill 전에 사용자에게 알림 (PLAN_COUNT > 0 시)
    if [[ "$PLAN_COUNT" -gt 0 ]]; then
      echo "" >&2
      echo "  ⚠️  기존 docs/plans/*.md 발견 (${PLAN_COUNT}개) — SOT 충돌 가능" >&2
      echo "     [EN] Existing docs/plans/*.md found (${PLAN_COUNT}) — potential SOT conflict" >&2
      echo "     auto-fill 진행 — heuristic/api로 자동 추출 후 사용자 검수 권장" >&2
    fi

    # ─────────────────────────────────────────────────────────────
    # v5.37.0 Phase 5 — dual fallback: (B) ANTHROPIC_API → (A) heuristic → (마커)
    # 셸 단독 자동화 환경(CI, 사용자 셸)에서도 풍부 모드까지 자동 도달 보장
    # ─────────────────────────────────────────────────────────────
    AUTOFILL_DRAFT=""
    AUTOFILL_MODE=""
    # 시도 1: --api (ANTHROPIC_API_KEY 있을 때만)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
      echo "" >&2
      echo "  [auto-fill] (B) Anthropic API 시도..." >&2
      if "$DIR/init-roadmap.sh" --api --out "$DRAFT_PATH" --force >&2 2>&1; then
        AUTOFILL_DRAFT="$DRAFT_PATH"
        AUTOFILL_MODE="api"
        echo "  ✓ api 모드 성공 — phase 데이터 LLM 추론 완료" >&2
      else
        echo "  · api 모드 실패 — heuristic으로 fallback" >&2
      fi
    fi
    # 시도 2: --heuristic (LLM 없이 결정론적, 항상 시도)
    if [[ -z "$AUTOFILL_DRAFT" ]]; then
      echo "" >&2
      echo "  [auto-fill] (A) heuristic 결정론 추출 시도..." >&2
      if "$DIR/init-roadmap.sh" --heuristic --out "$DRAFT_PATH" --force >&2 2>&1; then
        AUTOFILL_DRAFT="$DRAFT_PATH"
        AUTOFILL_MODE="heuristic"
        echo "  ✓ heuristic 모드 성공 — frontmatter 없는 plan에서 phase 추출" >&2
      else
        echo "  · heuristic 모드 실패 — Plan 부재 또는 추출 불가" >&2
      fi
    fi
    # 시도 1/2 성공 → 풍부 모드 rerender 후 종료 (마커 출력 skip)
    if [[ -n "$AUTOFILL_DRAFT" ]]; then
      echo "" >&2
      echo "  [auto-fill] 풍부 모드 rerender 진행 (--no-bootstrap)..." >&2
      OUT_ABS_FOR_RERENDER="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
      if bash "$DIR/render-status.sh" --roadmap "$AUTOFILL_DRAFT" --out "$OUT_ABS_FOR_RERENDER" --no-bootstrap >&2 2>&1; then
        echo "" >&2
        echo "════════════════════════════════════════════════════════════" >&2
        echo "  ✅ 자동 풍부 모드 완료 (mode: ${AUTOFILL_MODE})" >&2
        echo "     [EN] Auto rich-mode completed (${AUTOFILL_MODE})" >&2
        echo "     Draft: ${AUTOFILL_DRAFT}" >&2
        echo "     HTML:  ${OUT_ABS_FOR_RERENDER}" >&2
        if [[ "$AUTOFILL_MODE" == "heuristic" ]]; then
          echo "     ⚠️ heuristic 정확도 낮을 수 있음 — Claude session에서 /nova:status 호출 권장" >&2
        fi
        echo "════════════════════════════════════════════════════════════" >&2
        # --open이 켜져 있으면 풍부 모드 HTML만 열기
        if $OPEN; then
          case "$(uname -s)" in
            Darwin) open "file://$OUT_ABS_FOR_RERENDER" ;;
            Linux)  xdg-open "file://$OUT_ABS_FOR_RERENDER" >/dev/null 2>&1 || true ;;
          esac
        fi
        exit 0
      else
        echo "  · rerender 실패 — 마커 흐름으로 fallback" >&2
      fi
    fi
    # 시도 3: 둘 다 실패 → 기존 마커 흐름 (Claude session 대기)
    echo "" >&2
    echo "  [auto-fill] 결정론 자동 추출 실패 — Claude session에 위임 (마커 출력)" >&2
    if [[ "$PLAN_COUNT" -gt 0 ]]; then
      echo "" >&2
      echo "  SOT 결정 옵션 (Plan/ROADMAP 충돌) / Options:" >&2
      echo "    (A) Plan frontmatter v1.0 phases 추가 → enrich-plans.sh --apply" >&2
      echo "    (B) ROADMAP 채택 후 Plan 마일스톤 흡수" >&2
      echo "    (C) draft 검수만 (default — 자동 commit 0건)" >&2
      echo "" >&2
    fi
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
      echo "        - title 필수(id와 다른 값), summary는 한 줄 요약" >&2
      if [[ "$PLAN_COUNT" -gt 0 ]]; then
        echo "      SOT 충돌 경고(중요):" >&2
        echo "        - 이 프로젝트는 docs/plans/*.md ${PLAN_COUNT}개를 이미 보유" >&2
        echo "        - draft 작성은 가능하나, 채택 권유 시 'Plan의 마일스톤과 겹치는 영역' 명시" >&2
        echo "        - draft 본문 첫 단락에 '⚠️ SOT 결정 필요' 섹션 추가 — Plan 흡수 vs ROADMAP 신규" >&2
        echo "        - 사용자가 채택을 결정한 후에만 mv 안내\"" >&2
      else
        echo "        - draft 채택 후 ROADMAP.md가 단일 SOT가 됨\"" >&2
      fi
      echo "" >&2
      echo "  [3/3] draft 생성 후 재실행:" >&2
      echo "     bash \"\$NOVA_PLUGIN_ROOT/scripts/render-status.sh\" --roadmap ${DRAFT_PATH} --open" >&2
      echo "" >&2
      echo "  ※ 자동 commit 0건 — 사용자 검수 후 명시적 commit" >&2
      echo "  ※ HTML은 minimal mode로 우선 생성됨 ($OUT) — 부트스트랩 후 갱신" >&2
      echo "  ※ draft 경로는 프로젝트 slug 기반 — 멀티 프로젝트 cross-pollution 차단 (v5.35.4)" >&2
      echo "════════════════════════════════════════════════════════════" >&2
      # ───────────────────────────────────────────────────────────
      # 메인 Claude 강제 신호 — commands/status.md §Step 3 자율 우회 차단
      # 이 마커가 stderr에 출력되면 메인 Claude는 무조건 Agent spawn → render 재실행까지 진행
      # OUT_PATH는 절대경로 — Agent Bash cwd가 다르더라도 정확한 위치에 갱신 보장 (v5.35.7)
      # 값은 single-quote escape — command injection 차단 (v5.36.0)
      # ───────────────────────────────────────────────────────────
      # single-quote escape: ' → '\'' (POSIX shell safe quoting)
      shesc() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
      DRAFT_PATH_Q=$(shesc "$DRAFT_PATH")
      OUT_ABS_Q=$(shesc "$OUT_ABS")
      echo "" >&2
      echo "[CLAUDE_AUTO_CONTINUE]" >&2
      echo "DRAFT_PATH=${DRAFT_PATH_Q}" >&2
      echo "OUT_PATH=${OUT_ABS_Q}" >&2
      echo "PLAN_COUNT=${PLAN_COUNT}" >&2
      echo "NEXT_ACTION=spawn_agent_then_rerender" >&2
      echo "AGENT_TYPE=general-purpose" >&2
      # RERENDER_CMD는 메인 Claude가 직접 eval하지 않고 인자 배열로 재구성해야 함
      # commands/status.md §Step 3.B 참조
      echo "RERENDER_CMD=bash \"\$NOVA_PLUGIN_ROOT/scripts/render-status.sh\" --roadmap ${DRAFT_PATH_Q} --out ${OUT_ABS_Q} --open --no-bootstrap" >&2
      echo "[/CLAUDE_AUTO_CONTINUE]" >&2
    fi
  fi
fi

if $OPEN; then
  # minimal HTML(빈 껍데기)는 브라우저로 열지 않음 — auto-bootstrap이 풍부 모드로 갱신 후 한 번만 열림 (v5.35.7)
  # MINIMAL_CHECK=TRIGGER이면 minimal+auto-bootstrap 케이스 → open skip
  if [[ "${MINIMAL_CHECK:-}" == "TRIGGER" ]]; then
    echo "[render-status] minimal HTML — 브라우저 open skip (풍부 모드 갱신 후 열림)" >&2
  else
    case "$(uname -s)" in
      Darwin) open "file://$OUT_ABS" ;;
      Linux)  xdg-open "file://$OUT_ABS" >/dev/null 2>&1 || true ;;
      *)      echo "[render-status] --open: 알 수 없는 OS, 수동으로 열어주세요: file://$OUT_ABS" >&2 ;;
    esac
  fi
fi
