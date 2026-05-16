#!/usr/bin/env bash
# Nova reindex-work-items.sh — UUID fallback id 정상화 (Sprint 1-C)
#
# 사용:
#   bash scripts/reindex-work-items.sh           # 실제 적용
#   bash scripts/reindex-work-items.sh --dry-run # 매핑만 출력
#
# 동작:
#   1) WI-XXXXXXXX-slug (8 hex) 형식 work-item 찾음
#   2) index.next_seq 기준 WI-NNNN-slug로 재번호
#   3) depends_on / superseded_by 자동 갱신 (모든 WI 파일 스캔)
#   4) source_docs는 path라 갱신 안 함
#   5) index.json 재생성 (재번호 반영)
#
# 보장:
#   - lock 들고 작업 (다른 registry-write 호출과 race 안 함)
#   - dry-run: 매핑 + 영향 받는 파일 수만 출력
#   - 실패 시 부분 적용 방지 (전체 매핑 계산 → 일괄 rename → index 재생성)

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-${NOVA_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}}"
REGISTRY_ROOT="${NOVA_REGISTRY_ROOT:-$PWD}"
WI_DIR="$REGISTRY_ROOT/.nova/work-items"
INDEX_FILE="$WI_DIR/index.json"
LOCK_DIR="$WI_DIR/.lock"
LOCK_HOLD="$LOCK_DIR/index.lock.d"
LOCK_PID="$LOCK_HOLD/pid"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "usage: $0 [--dry-run]"
      exit 0
      ;;
    *) echo "[reindex] ERR: 알 수 없는 옵션 '$1'" >&2; exit 2 ;;
  esac
  shift
done

log()  { echo "[reindex] $*"; }
err()  { echo "[reindex] ERR: $*" >&2; }

if [ ! -f "$INDEX_FILE" ]; then
  err "registry 미초기화: $INDEX_FILE 부재. 먼저 'bash scripts/setup.sh'를 실행하세요."
  exit 2
fi

# ── 간이 lock (registry-write.sh와 동일 mkdir 방식) ────────────────────
acquire_lock() {
  mkdir -p "$LOCK_DIR" 2>/dev/null
  local attempts=0
  while [ $attempts -lt 50 ]; do
    if mkdir "$LOCK_HOLD" 2>/dev/null; then
      echo $$ > "$LOCK_PID"
      return 0
    fi
    if [ -f "$LOCK_PID" ]; then
      local holder
      holder=$(cat "$LOCK_PID" 2>/dev/null || echo "")
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
        rm -rf "$LOCK_HOLD"
        continue
      fi
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}
release_lock() { rm -rf "$LOCK_HOLD"; }
trap 'release_lock 2>/dev/null || true' EXIT INT TERM

# ── UUID fallback 패턴 매칭 ─────────────────────────────────────────────
UUID_RE='^WI-[a-f0-9]{8}-.+$'

# ── 1) 매핑 계산 ────────────────────────────────────────────────────────
declare -a UUID_FILES=()
for f in "$WI_DIR"/WI-*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f" .json)
  if [[ "$base" =~ $UUID_RE ]]; then
    UUID_FILES+=("$f")
  fi
done

if [ ${#UUID_FILES[@]} -eq 0 ]; then
  log "UUID fallback id 없음. 작업 불필요."
  exit 0
fi

log "UUID fallback id 발견: ${#UUID_FILES[@]}개"

if ! acquire_lock; then
  err "lock 획득 실패 (다른 registry 작업 진행 중일 수 있음)"
  exit 1
fi

next_seq=$(jq -r '.next_seq' "$INDEX_FILE")

# bash 3.2 호환: associative array 대신 indexed array 2개 (parallel)
OLD_IDS=()
NEW_IDS=()
for f in "${UUID_FILES[@]}"; do
  base=$(basename "$f" .json)
  slug="${base#WI-????????-}"
  new_id=$(printf "WI-%04d-%s" "$next_seq" "$slug")
  OLD_IDS+=("$base")
  NEW_IDS+=("$new_id")
  next_seq=$((next_seq + 1))
done

# 매핑 jq 객체 (한 번만 빌드 — 모든 WI 파일에서 재사용)
map_json="{"
for i in "${!OLD_IDS[@]}"; do
  [ "$i" -gt 0 ] && map_json+=","
  map_json+="\"${OLD_IDS[$i]}\":\"${NEW_IDS[$i]}\""
done
map_json+="}"

log "매핑 (${#OLD_IDS[@]}건):"
for i in "${!OLD_IDS[@]}"; do
  echo "  ${OLD_IDS[$i]}  →  ${NEW_IDS[$i]}"
done

if [ "$DRY_RUN" = "1" ]; then
  affected=0
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    if jq -e --argjson m "$map_json" '
      ((.depends_on // []) | map(select($m[.] != null)) | length) > 0
      or (.superseded_by != null and $m[.superseded_by // ""] != null)
    ' "$f" >/dev/null 2>&1; then
      affected=$((affected + 1))
    fi
  done
  log "참조 갱신 영향 파일: ${affected}건"
  log "DRY-RUN 종료 (실제 적용 시 --dry-run 제거)"
  exit 0
fi

# ── 2) WI 파일 rename + 내부 id 필드 갱신 ─────────────────────────────
ts=$(date -u +%FT%TZ)
for i in "${!OLD_IDS[@]}"; do
  old="${OLD_IDS[$i]}"
  new="${NEW_IDS[$i]}"
  old_file="$WI_DIR/$old.json"
  new_file="$WI_DIR/$new.json"
  if [ -e "$new_file" ]; then
    err "rename 충돌: $new_file 이미 존재. 작업 중단."
    exit 2
  fi
  jq --arg id "$new" --arg ts "$ts" '.id = $id | .updated_at = $ts' "$old_file" > "$new_file"
  rm -f "$old_file"
done

# ── 3) 모든 WI 파일의 depends_on / superseded_by 참조 갱신 ─────────────
for f in "$WI_DIR"/WI-*.json; do
  [ -f "$f" ] || continue
  tmp="${f}.tmp.$$"
  jq --argjson m "$map_json" '
    .depends_on = ((.depends_on // []) | map(if $m[.] then $m[.] else . end))
    | (if (.superseded_by != null and $m[.superseded_by] != null) then .superseded_by = $m[.superseded_by] else . end)
  ' "$f" > "$tmp" && mv "$tmp" "$f"
done

# ── 4) index.json 재생성 ────────────────────────────────────────────────
tmp_index="$INDEX_FILE.tmp.$$"
jq -n --arg ts "$ts" --argjson sv "\"3.0\"" \
  --argjson nsq "$next_seq" \
  --slurpfile items <(for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    jq '{id:.id, status:.status, review_required:.review_required, priority:.priority, updated_at:.updated_at}' "$f"
  done | jq -s '.') \
  '{
    schema_version: $sv,
    next_seq: $nsq,
    work_items: $items[0],
    generated_at: $ts
  }' > "$tmp_index" && mv "$tmp_index" "$INDEX_FILE"

release_lock

log "✅ reindex 완료: ${#OLD_IDS[@]}건 재번호화, index.json 재생성"
exit 0
