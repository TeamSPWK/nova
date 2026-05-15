#!/usr/bin/env bash
# Nova registry-render-state.sh — NOVA-STATE.md marker 영역 자동 렌더 (Sprint 2-B)
#
# 사용:
#   bash scripts/registry-render-state.sh                # 적용
#   bash scripts/registry-render-state.sh --dry-run      # diff만 출력
#   bash scripts/registry-render-state.sh --state-file=PATH
#   bash scripts/registry-render-state.sh --force        # marker 부재 시 추가
#
# 동작:
#   - marker `<!-- nova:registry-rendered:start -->` ~ `<!-- nova:registry-rendered:end -->` 안쪽만 갱신
#   - marker 외 영역 byte-level 일치 보존 (사람 손편집 보존)
#   - 렌더 내용:
#     · Active Tree: index.json work_items 중 status ∈ {active, proposed} 상위 10 (priority desc)
#     · Recent Activity: events.jsonl의 last 7d work_item_transitioned + work_item_created (top 7)
#
# 의존성: jq (필수)
# 환경변수: NOVA_REGISTRY_ROOT (CWD), NOVA_STATE_FILE (NOVA-STATE.md)

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REGISTRY_ROOT="${NOVA_REGISTRY_ROOT:-$PWD}"
STATE_FILE="${NOVA_STATE_FILE:-$REGISTRY_ROOT/NOVA-STATE.md}"
INDEX_FILE="$REGISTRY_ROOT/.nova/work-items/index.json"
EVENTS_FILE="$REGISTRY_ROOT/.nova/events.jsonl"

DRY_RUN=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)     DRY_RUN=1 ;;
    --force)       FORCE=1 ;;
    --state-file=*) STATE_FILE="${1#*=}" ;;
    -h|--help)
      cat <<'USAGE'
Nova registry-render-state — NOVA-STATE.md marker 영역 자동 렌더

사용:
  bash scripts/registry-render-state.sh                  적용
  bash scripts/registry-render-state.sh --dry-run        diff만 출력
  bash scripts/registry-render-state.sh --force          marker 부재 시 추가
  bash scripts/registry-render-state.sh --state-file=P   대상 파일 지정

렌더 영역:
  <!-- nova:registry-rendered:start -->
  ... (Active Tree + Recent Activity)
  <!-- nova:registry-rendered:end -->

marker 외 영역은 byte-level 일치 보존.
USAGE
      exit 0
      ;;
    *) echo "[render-state] ERR: 알 수 없는 옵션 '$1'" >&2; exit 2 ;;
  esac
  shift
done

MARK_BEGIN="<!-- nova:registry-rendered:start -->"
MARK_END="<!-- nova:registry-rendered:end -->"

log()  { echo "[render-state] $*"; }
warn() { echo "[render-state] WARN: $*" >&2; }
err()  { echo "[render-state] ERR: $*" >&2; }

# ── pre-flight ──
if ! command -v jq >/dev/null 2>&1; then
  err "jq 미설치"
  exit 2
fi
if [ ! -f "$INDEX_FILE" ]; then
  err "registry 미초기화: $INDEX_FILE 부재. 'bash scripts/setup.sh' 먼저 실행."
  exit 2
fi
if [ ! -f "$STATE_FILE" ]; then
  warn "NOVA-STATE.md 부재: $STATE_FILE — 렌더 대상 없음. skip."
  exit 0
fi

# ── 렌더 본문 생성 ──
render_active_tree() {
  # status ∈ {active, proposed} top 10, priority desc (critical=0 → low=3), updated_at desc 보조
  jq -r '
    .work_items
    | map(select(.status == "active" or .status == "proposed"))
    | sort_by(
        ({critical:3, high:2, medium:1, low:0}[.priority] // -1),
        (.updated_at | sub("Z$"; ""))
      )
    | reverse
    | .[0:10]
    | if length == 0 then
        "_(active|proposed 항목 없음)_"
      else
        map(
          (if .status == "active" then "🔄"
           elif .review_required then "⬜⚠️"
           else "⬜" end) + " " +
          "[" + .id + "](.nova/work-items/" + .id + ".json)" +
          " — " + .priority +
          (if .review_required then " · review_required" else "" end)
        )
        | map("- " + .)
        | join("\n")
      end
  ' "$INDEX_FILE"
}

render_recent_activity() {
  # events.jsonl에서 last 7d work_item_* 이벤트 (top 7)
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "_(이벤트 로그 없음 — .nova/events.jsonl 부재)_"
    return
  fi
  # cutoff = now - 7d (epoch)
  local cutoff
  cutoff=$(python3 -c "import time; print(int(time.time()) - 7*86400)")
  jq -sr --argjson cutoff "$cutoff" '
    map(select(
      (.event_type // "" | test("^work_item_"))
      and (.timestamp_epoch // 0) >= $cutoff
    ))
    | sort_by(.timestamp_epoch // 0) | reverse | .[0:7]
    | if length == 0 then
        "_(최근 7일 work-item 활동 없음)_"
      else
        map(
          (.timestamp[0:10]) + ": " +
          (.extra.wi_id // "?") + " — " +
          (if .event_type == "work_item_created" then
             "created (" + (.extra.status // "proposed") + ")"
           elif .event_type == "work_item_transitioned" then
             (.extra.from // "?") + " → " + (.extra.to // "?") +
             (if .extra.commit_sha then " (" + (.extra.commit_sha[0:7]) + ")" else "" end)
           elif .event_type == "registry_rendered" then
             "STATE 렌더 (" + ((.extra.items_in_view | tostring) // "?") + " items)"
           else
             .event_type
           end)
        )
        | map("- " + .)
        | join("\n")
      end
  ' "$EVENTS_FILE"
}

build_rendered_block() {
  local active recent ts items_count
  active=$(render_active_tree)
  recent=$(render_recent_activity)
  ts=$(date -u +%FT%TZ)
  items_count=$(jq '.work_items | length' "$INDEX_FILE")
  cat <<EOF
$MARK_BEGIN
<!-- 자동 생성 영역 — bash scripts/registry-render-state.sh가 갱신. 손편집하지 마세요. -->
<!-- 손편집 필요 시: NOVA-STATE.md의 marker 바깥 영역에 작성. -->

**Active Tree** (registry: ${items_count} work-items, 갱신: ${ts}):

${active}

**Recent Activity** (last 7d):

${recent}

$MARK_END
EOF
}

# ── 새 블록 작성 ──
new_block_file=$(mktemp -t nova-render-XXXX)
build_rendered_block > "$new_block_file"

# ── marker 존재 여부 ──
if ! grep -qF "$MARK_BEGIN" "$STATE_FILE"; then
  if [ "$FORCE" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[dry-run] marker 부재 — --force로 STATE 끝에 추가 예정"
      cat "$new_block_file"
    else
      {
        echo ""
        cat "$new_block_file"
      } >> "$STATE_FILE"
      log "marker 블록을 STATE 끝에 추가했습니다"
    fi
    items_in_view=$(jq '.work_items | map(select(.status == "active" or .status == "proposed")) | .[0:10] | length' "$INDEX_FILE")
    bash "$SCRIPT_DIR/../hooks/record-event.sh" "registry_rendered" "$(jq -cn --argjson n "$items_in_view" --arg path "$STATE_FILE" '{render_path:$path, items_in_view:$n, trigger:"force_append"}')" 2>/dev/null || true
    rm -f "$new_block_file"
    exit 0
  else
    warn "marker 부재 — $STATE_FILE에 다음 추가 후 재실행 (또는 --force):"
    echo "  $MARK_BEGIN"
    echo "  $MARK_END"
    rm -f "$new_block_file"
    exit 0
  fi
fi

# ── 기존 블록 추출 ──
cur_block=$(mktemp -t nova-render-cur-XXXX)
awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0==b{f=1} f{print} $0==e{f=0}
' "$STATE_FILE" > "$cur_block"

if cmp -s "$cur_block" "$new_block_file"; then
  log "변경 없음 (renderer 결과 동일)"
  rm -f "$new_block_file" "$cur_block"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN diff:"
  diff -u "$cur_block" "$new_block_file" | sed 's/^/  /' | head -60
  rm -f "$new_block_file" "$cur_block"
  exit 0
fi

# ── 실제 교체 (marker 외 영역 byte-level 보존) ──
tmp_state=$(mktemp -t nova-render-state-XXXX)
awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v nbf="$new_block_file" '
  BEGIN {
    while ((getline line < nbf) > 0) {
      new_content = new_content (new_content ? "\n" : "") line
    }
    close(nbf)
  }
  $0==b { print new_content; skip=1; next }
  $0==e && skip { skip=0; next }
  !skip { print }
' "$STATE_FILE" > "$tmp_state"

mv "$tmp_state" "$STATE_FILE"
log "✅ marker 영역 렌더 완료: $STATE_FILE"

# ── 이벤트 기록 (lock 외부) ──
items_in_view=$(jq '.work_items | map(select(.status == "active" or .status == "proposed")) | .[0:10] | length' "$INDEX_FILE")
bash "$SCRIPT_DIR/../hooks/record-event.sh" "registry_rendered" \
  "$(jq -cn --argjson n "$items_in_view" --arg path "$STATE_FILE" \
     '{render_path:$path, items_in_view:$n, trigger:"post_write"}')" \
  2>/dev/null || true

rm -f "$new_block_file" "$cur_block"
exit 0
