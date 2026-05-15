#!/usr/bin/env bash
# Nova registry-write.sh — work-item registry 단일 쓰기 경로 (v3.0)
#
# Sprint 1-B 산출물. design: docs/designs/work-item-registry-v3.md §API 설계 / §핵심 로직.
# Sprint 0 권한 spec: docs/specs/registry-write-authority-v3.md.
#
# 5 sub-command: create / update / transition / evaluator-pass / require-review
# 부속: flock 우선 / mkdir + PID stale 검출 fallback / .pending-transition-<wi> 마커
# 의존성: jq (필수), python3 (slug 한글 처리), 선택적으로 flock
#
# 환경변수:
#   NOVA_PLUGIN_PATH  : record-event.sh 경유용. 미지정 시 스크립트 dirname/.. 추정
#   NOVA_CALLER       : actor 추론 (예: "command:/nova:run", "skill:orchestrator", "user:direct")
#   NOVA_REGISTRY_ROOT: .nova/ 위치 (테스트용). 미지정 시 CWD
#   NOVA_DRY_RUN=1    : 파일 쓰지 않음

set -u

# ── 경로 ────────────────────────────────────────────────────────────────
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-$(dirname "$SCRIPT_DIR")}"
REGISTRY_ROOT="${NOVA_REGISTRY_ROOT:-$PWD}"
WI_DIR="$REGISTRY_ROOT/.nova/work-items"
INDEX_FILE="$WI_DIR/index.json"
LOCK_DIR="$WI_DIR/.lock"
LOCK_FILE="$LOCK_DIR/index.lock"
LOCK_HOLD="$LOCK_DIR/index.lock.d"
LOCK_PID="$LOCK_HOLD/pid"

SCHEMA_VERSION="3.0"

# ── 로그 ────────────────────────────────────────────────────────────────
log_err()  { echo "[registry-write] ERR: $*" >&2; }
log_warn() { echo "[registry-write] WARN: $*" >&2; }

# ── 시각 ────────────────────────────────────────────────────────────────
get_timestamp() { date -u +%FT%TZ; }

# ── slug 생성 (한글 보존) ────────────────────────────────────────────────
slugify() {
  # title → lowercase + 한글 보존 + 특수문자 제거 + 하이픈 압축
  python3 - "$1" <<'PYEOF'
import sys, re
t = sys.argv[1].strip().lower()
t = re.sub(r'[\s_/\\]+', '-', t)
t = re.sub(r'[^a-z0-9가-힣\-]+', '', t)
t = re.sub(r'-+', '-', t).strip('-')
if not t:
    t = 'untitled'
# 길이 제한: 60자 (id 전체 200자 미만 보장)
print(t[:60])
PYEOF
}

# ── actor 추론 ──────────────────────────────────────────────────────────
infer_actor() {
  if [ -n "${NOVA_CALLER:-}" ]; then
    echo "$NOVA_CALLER"
    return
  fi
  # 부모 PID가 bash interactive shell인지 판단 어려움 → user:direct 기본
  echo "user:direct"
}

# ── pre-flight ──────────────────────────────────────────────────────────
ensure_registry_initialized() {
  if [ ! -f "$INDEX_FILE" ]; then
    log_err "registry 미초기화: $INDEX_FILE 부재. 먼저 'bash scripts/setup.sh'를 실행하세요."
    return 2
  fi
  if ! jq empty "$INDEX_FILE" 2>/dev/null; then
    log_err "index.json invalid JSON: $INDEX_FILE"
    return 2
  fi
}

ensure_wi_exists() {
  local wi=$1
  local f="$WI_DIR/$wi.json"
  if [ ! -f "$f" ]; then
    log_err "work-item 미존재: $wi (file: $f)"
    return 2
  fi
}

# ── lock (flock 우선, mkdir + PID stale fallback) ────────────────────────
# Critic #2 SIGKILL stale: PID kill -0 검출 후 강제 정리
# Critic #12 lock 범위: index.json/WI 갱신만 lock 내부. record-event/render는 lock 외부.
LOCK_FD=""
_lock_method=""

acquire_lock() {
  mkdir -p "$LOCK_DIR" 2>/dev/null

  # NOVA_LOCK_MODE=mkdir → mkdir 분기 강제 (테스트에서 stale lock 검증용)
  if [ "${NOVA_LOCK_MODE:-auto}" != "mkdir" ] && command -v flock >/dev/null 2>&1; then
    # flock 분기: fd 200 사용
    LOCK_FD=200
    eval "exec $LOCK_FD>\"$LOCK_FILE\""
    if flock -x -w 5 "$LOCK_FD"; then
      _lock_method="flock"
      return 0
    fi
    # flock 실패 → fd 닫고 mkdir 폴백
    eval "exec $LOCK_FD>&-"
    LOCK_FD=""
  fi

  # mkdir 분기 + PID stale 검출
  local attempts=0
  while [ $attempts -lt 50 ]; do
    if mkdir "$LOCK_HOLD" 2>/dev/null; then
      echo $$ > "$LOCK_PID"
      _lock_method="mkdir"
      return 0
    fi
    if [ -f "$LOCK_PID" ]; then
      local holder
      holder=$(cat "$LOCK_PID" 2>/dev/null || echo "")
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
        log_warn "stale lock 정리: holder PID $holder 죽음"
        rm -rf "$LOCK_HOLD"
        continue
      fi
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

release_lock() {
  case "$_lock_method" in
    flock)
      [ -n "$LOCK_FD" ] && eval "exec $LOCK_FD>&-"
      LOCK_FD=""
      ;;
    mkdir)
      rm -rf "$LOCK_HOLD"
      ;;
  esac
  _lock_method=""
}

# 비정상 종료 시 lock 정리
trap 'release_lock 2>/dev/null || true' EXIT INT TERM

# ── jq 원자 쓰기 ─────────────────────────────────────────────────────────
jq_write_atomic() {
  # jq_write_atomic <target_file> <jq_args...> <jq_expr>
  local target=$1
  shift
  local tmp="${target}.tmp.$$"
  # 마지막 인자가 expr
  local args=()
  while [ "$#" -gt 1 ]; do
    args+=("$1")
    shift
  done
  local expr=$1
  if [ "${NOVA_DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] jq ${args[*]} '$expr' $target" >&2
    return 0
  fi
  if ! jq "${args[@]}" "$expr" "$target" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    log_err "jq 실패: $target  expr=$expr"
    return 2
  fi
  mv "$tmp" "$target"
}

# ── 검증 (ajv 부재 시 jq fallback 4종) ────────────────────────────────────
# 부재 시: status enum + review_required bool + evidence.commit_sha array + id pattern
validate_wi_jq_fallback() {
  local f=$1
  if ! jq empty "$f" 2>/dev/null; then log_err "validate: invalid JSON ($f)"; return 2; fi
  jq -e '.status | IN("proposed","active","blocked","done","superseded")' "$f" >/dev/null \
    || { log_err "validate: status enum 위반 ($f)"; return 2; }
  jq -e '.review_required | type == "boolean"' "$f" >/dev/null \
    || { log_err "validate: review_required bool 위반 ($f)"; return 2; }
  jq -e '.evidence.commit_sha | type == "array"' "$f" >/dev/null \
    || { log_err "validate: evidence.commit_sha array 위반 ($f)"; return 2; }
  jq -e '.id | test("^WI-([0-9]{4}|[a-f0-9]{8})-.+$")' "$f" >/dev/null \
    || { log_err "validate: id pattern 위반 ($f)"; return 2; }
  # 조건부 invariant
  local status review_required commit_count blocked_reason archived_at
  status=$(jq -r '.status' "$f")
  if [ "$status" = "done" ]; then
    review_required=$(jq -r '.review_required' "$f")
    commit_count=$(jq -r '.evidence.commit_sha | length' "$f")
    [ "$review_required" = "true" ] && { log_err "invariant: status=done ⟹ review_required=false ($f)"; return 2; }
    [ "$commit_count" -eq 0 ] && { log_err "invariant: status=done ⟹ evidence.commit_sha 최소 1개 ($f)"; return 2; }
  fi
  if [ "$status" = "blocked" ]; then
    blocked_reason=$(jq -r '.blocked_reason // ""' "$f")
    [ -z "$blocked_reason" ] && { log_err "invariant: status=blocked ⟹ blocked_reason 필수 ($f)"; return 2; }
  fi
  if [ "$status" = "superseded" ]; then
    archived_at=$(jq -r '.archived_at // ""' "$f")
    [ -z "$archived_at" ] && { log_err "invariant: status=superseded ⟹ archived_at 필수 ($f)"; return 2; }
  fi
  return 0
}

# ── record-event 호출 (lock 외부) ────────────────────────────────────────
record_event_safe() {
  # record_event_safe <event_type> <extra_json>
  local etype=$1
  local extra=${2:-'{}'}
  local actor
  actor=$(infer_actor)
  # actor 필드 + schema_version 3.0 명시
  local payload
  payload=$(jq -cn --arg a "$actor" --argjson e "$extra" \
    '{actor:$a, schema_version:"3.0"} + $e' 2>/dev/null) || payload="$extra"
  local rec="$NOVA_PLUGIN_PATH/hooks/record-event.sh"
  if [ -x "$rec" ] || [ -f "$rec" ]; then
    bash "$rec" "$etype" "$payload" 2>/dev/null || true
  fi
}

# ── 부분 전이 마커 ─────────────────────────────────────────────────────
mark_pending() {
  local wi=$1 target=$2
  local p="$WI_DIR/.pending-transition-$wi"
  echo "{\"wi\":\"$wi\",\"target\":\"$target\",\"ts\":\"$(get_timestamp)\",\"pid\":$$}" > "$p"
}
clear_pending() {
  local wi=$1
  rm -f "$WI_DIR/.pending-transition-$wi"
}

# ── 채번 (atomic increment) ──────────────────────────────────────────────
assign_id() {
  # stdout: id (정규 또는 UUID fallback)
  # exit 0: 성공, exit 1: lock 실패 → fallback
  local slug=$1
  if ! acquire_lock; then
    log_warn "lock 획득 실패 (50회 retry) — UUID fallback id 발급. 추후 'bash scripts/reindex-work-items.sh' 권장."
    local uuid
    if command -v uuidgen >/dev/null 2>&1; then
      uuid=$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-8)
    else
      uuid=$(python3 -c "import secrets; print(secrets.token_hex(4))")
    fi
    echo "WI-${uuid}-${slug}"
    return 1
  fi
  local next
  next=$(jq -r '.next_seq' "$INDEX_FILE")
  local id
  id=$(printf "WI-%04d-%s" "$next" "$slug")
  local ts
  ts=$(get_timestamp)
  jq_write_atomic "$INDEX_FILE" \
    --argjson n "$((next + 1))" --arg ts "$ts" \
    '.next_seq = $n | .generated_at = $ts' || { release_lock; return 2; }
  release_lock
  echo "$id"
  return 0
}

# ── index.json 항목 upsert ──────────────────────────────────────────────
index_upsert() {
  # caller가 이미 lock 들고 있다고 가정
  local wi=$1 status=$2 review_required=$3 priority=$4 updated_at=$5
  jq_write_atomic "$INDEX_FILE" \
    --arg id "$wi" --arg s "$status" --argjson r "$review_required" \
    --arg p "$priority" --arg ts "$updated_at" \
    '
    .work_items |= (
      map(select(.id != $id)) +
      [{id:$id, status:$s, review_required:$r, priority:$p, updated_at:$ts}]
    ) | .generated_at = $ts
    '
}

# ── 사용법 ──────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
사용:
  registry-write.sh create <title> [--priority=low|medium|high|critical] [--source-doc=PATH]
  registry-write.sh update <wi-id> <field>=<value> [<field>=<value> ...]
  registry-write.sh transition <wi-id> <new-status> [--evidence-commit=SHA] [--blocked-reason=TEXT] [--superseded-by=WI-ID]
  registry-write.sh evaluator-pass <wi-id> --commit-sha=SHA [--test-output=PATH] [--files=PATH1,PATH2,...]
  registry-write.sh require-review <wi-id>

상태 (5값 동결): proposed | active | blocked | done | superseded
우선순위 (4값): low | medium | high | critical

자세히: docs/designs/work-item-registry-v3.md
USAGE
}

# ── cmd: create ──────────────────────────────────────────────────────────
cmd_create() {
  local title="" priority="medium" source_doc=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --priority=*)   priority="${1#*=}" ;;
      --source-doc=*) source_doc="${1#*=}" ;;
      --*)            log_err "create: 알 수 없는 옵션 '$1'"; return 2 ;;
      *)
        if [ -z "$title" ]; then title="$1"
        else log_err "create: title은 1개만 입력하세요 (현재 '$title', 추가 '$1')"; return 2
        fi
        ;;
    esac
    shift
  done
  [ -z "$title" ] && { log_err "create: title 인자 필요"; usage; return 2; }
  case "$priority" in
    low|medium|high|critical) ;;
    *) log_err "create: priority enum 위반 ($priority)"; return 2 ;;
  esac
  ensure_registry_initialized || return 2

  local slug
  slug=$(slugify "$title")
  [ -z "$slug" ] && { log_err "create: slug 생성 실패 — title이 비어 있거나 인식 불가"; return 2; }

  local id
  if ! id=$(assign_id "$slug"); then
    # lock 실패 (UUID fallback). assign_id가 이미 id를 echo했고 exit 1 반환.
    # 이 경우 id는 stdout으로 출력됐지만 WI 파일은 아직 안 만듦.
    # UUID fallback 시에도 파일 생성 + index upsert 시도 (lock 다시 시도)
    log_warn "create: UUID fallback 진행 — index upsert 시도"
  fi

  local ts
  ts=$(get_timestamp)
  local source_docs_json="[]"
  if [ -n "$source_doc" ]; then
    source_docs_json=$(jq -cn --arg s "$source_doc" '[$s]')
  fi
  local wi_file="$WI_DIR/$id.json"

  # WI 파일 생성 (lock 없이 — 신규 파일이라 race 없음)
  if [ "${NOVA_DRY_RUN:-0}" != "1" ]; then
    jq -n \
      --arg sv "$SCHEMA_VERSION" --arg id "$id" --arg title "$title" \
      --arg p "$priority" --arg ts "$ts" --argjson srcs "$source_docs_json" \
      '{
        schema_version: $sv, id: $id, title: $title,
        status: "proposed", review_required: false, archived_at: null,
        priority: $p, depends_on: [], source_docs: $srcs,
        evidence: { commit_sha: [], test_output: null, files_changed: null, pr_url: null },
        created_at: $ts, updated_at: $ts,
        owner: null, notes: "", superseded_by: null, blocked_reason: null,
        last_verified_at: null
      }' > "$wi_file"
  fi

  # index 갱신 (lock 다시 시도 — assign_id에서 lock 실패했어도 여기서 재시도)
  if acquire_lock; then
    index_upsert "$id" "proposed" "false" "$priority" "$ts"
    release_lock
  else
    log_warn "create: index upsert 시 lock 실패 — 'bash scripts/reindex-work-items.sh' 권장"
  fi

  validate_wi_jq_fallback "$wi_file" || return 2

  record_event_safe "work_item_created" \
    "$(jq -cn --arg id "$id" --arg s "proposed" --arg p "$priority" \
       '{wi_id:$id, status:$s, priority:$p}')"

  echo "$id"
  return 0
}

# ── cmd: update ──────────────────────────────────────────────────────────
cmd_update() {
  local wi=${1:-}
  [ -z "$wi" ] && { log_err "update: wi-id 인자 필요"; return 2; }
  shift
  [ $# -eq 0 ] && { log_err "update: field=value 인자 1개 이상 필요"; return 2; }
  ensure_registry_initialized || return 2
  ensure_wi_exists "$wi" || return 2

  local ts
  ts=$(get_timestamp)
  local wi_file="$WI_DIR/$wi.json"
  local jq_args=(--arg ts "$ts")
  local jq_expr=".updated_at = \$ts"

  # immutable: id, schema_version, created_at
  # transition 전용: status, archived_at, last_verified_at, evidence.*, review_required (Evaluator만)
  # update 허용: title, priority, owner, notes, blocked_reason, superseded_by, depends_on (JSON), source_docs (JSON)
  local IMMUTABLE_RE="^(id|schema_version|created_at|status|archived_at|last_verified_at|review_required|evidence)$"
  local STRING_FIELDS_RE="^(title|owner|notes|blocked_reason|superseded_by)$"
  local ENUM_PRIORITY_RE="^(low|medium|high|critical)$"

  for kv in "$@"; do
    local k="${kv%%=*}"
    local v="${kv#*=}"
    if [[ "$k" =~ $IMMUTABLE_RE ]]; then
      log_err "update: '$k'는 update 금지 (transition 또는 evaluator-pass 사용)"
      return 2
    fi
    case "$k" in
      title|owner|notes|blocked_reason|superseded_by)
        jq_args+=(--arg "f_$k" "$v")
        jq_expr+=" | .$k = \$f_$k"
        ;;
      priority)
        if ! [[ "$v" =~ $ENUM_PRIORITY_RE ]]; then
          log_err "update: priority enum 위반 ('$v')"
          return 2
        fi
        jq_args+=(--arg "f_$k" "$v")
        jq_expr+=" | .$k = \$f_$k"
        ;;
      depends_on|source_docs)
        # JSON 배열 입력 기대: ["a","b"] 또는 a,b (콤마 split)
        local arr
        if [[ "$v" =~ ^\[.*\]$ ]]; then
          arr="$v"
        else
          arr=$(python3 -c "import json,sys; print(json.dumps([x.strip() for x in sys.argv[1].split(',') if x.strip()]))" "$v")
        fi
        if ! echo "$arr" | jq empty 2>/dev/null; then
          log_err "update: $k 배열 파싱 실패 ('$v')"
          return 2
        fi
        jq_args+=(--argjson "f_$k" "$arr")
        jq_expr+=" | .$k = \$f_$k"
        ;;
      *)
        log_err "update: 알 수 없는 필드 '$k'"
        return 2
        ;;
    esac
  done

  acquire_lock || { log_err "update: lock 획득 실패"; return 1; }
  jq_write_atomic "$wi_file" "${jq_args[@]}" "$jq_expr" || { release_lock; return 2; }

  # index 동기화 (priority/updated_at 갱신될 수 있음)
  local idx_priority
  idx_priority=$(jq -r '.priority' "$wi_file")
  local idx_status
  idx_status=$(jq -r '.status' "$wi_file")
  local idx_rev
  idx_rev=$(jq -r '.review_required' "$wi_file")
  index_upsert "$wi" "$idx_status" "$idx_rev" "$idx_priority" "$ts"
  release_lock

  validate_wi_jq_fallback "$wi_file" || return 2

  record_event_safe "work_item_updated" \
    "$(jq -cn --arg id "$wi" '{wi_id:$id}')"

  echo "$wi"
  return 0
}

# ── cmd: transition ─────────────────────────────────────────────────────
cmd_transition() {
  local wi=${1:-} new_status=${2:-}
  [ -z "$wi" ] && { log_err "transition: wi-id 인자 필요"; return 2; }
  [ -z "$new_status" ] && { log_err "transition: new-status 인자 필요"; return 2; }
  shift 2
  case "$new_status" in
    proposed|active|blocked|done|superseded) ;;
    *) log_err "transition: status enum 위반 ('$new_status')"; return 2 ;;
  esac

  local evidence_sha="" blocked_reason="" superseded_by=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --evidence-commit=*) evidence_sha="${1#*=}" ;;
      --blocked-reason=*)  blocked_reason="${1#*=}" ;;
      --superseded-by=*)   superseded_by="${1#*=}" ;;
      *) log_err "transition: 알 수 없는 옵션 '$1'"; return 2 ;;
    esac
    shift
  done

  if [ "$new_status" = "done" ] && [ -z "$evidence_sha" ]; then
    log_err "transition: status=done은 --evidence-commit=SHA 필수"
    return 2
  fi
  if [ "$new_status" = "blocked" ] && [ -z "$blocked_reason" ]; then
    log_err "transition: status=blocked는 --blocked-reason=TEXT 필수"
    return 2
  fi

  ensure_registry_initialized || return 2
  ensure_wi_exists "$wi" || return 2

  local wi_file="$WI_DIR/$wi.json"
  local from_status
  from_status=$(jq -r '.status' "$wi_file")
  local ts
  ts=$(get_timestamp)

  acquire_lock || { log_err "transition: lock 획득 실패"; return 1; }
  mark_pending "$wi" "$new_status"

  # jq expression 구성
  local jq_args=(--arg s "$new_status" --arg ts "$ts")
  local jq_expr='.status = $s | .updated_at = $ts'
  case "$new_status" in
    done)
      jq_args+=(--arg sha "$evidence_sha")
      jq_expr+=' | .review_required = false | .evidence.commit_sha += [$sha] | .last_verified_at = $ts'
      ;;
    superseded)
      jq_expr+=' | .archived_at = $ts'
      if [ -n "$superseded_by" ]; then
        jq_args+=(--arg sby "$superseded_by")
        jq_expr+=' | .superseded_by = $sby'
      fi
      ;;
    blocked)
      jq_args+=(--arg br "$blocked_reason")
      jq_expr+=' | .blocked_reason = $br'
      ;;
    active|proposed)
      # 이동 후 blocked_reason/archived_at 정리 (논리 복귀)
      [ "$from_status" = "blocked" ] && jq_expr+=' | .blocked_reason = null'
      ;;
  esac

  if ! jq_write_atomic "$wi_file" "${jq_args[@]}" "$jq_expr"; then
    release_lock
    return 2
  fi

  # index 동기화
  local priority review_required
  priority=$(jq -r '.priority' "$wi_file")
  review_required=$(jq -r '.review_required' "$wi_file")
  index_upsert "$wi" "$new_status" "$review_required" "$priority" "$ts"

  clear_pending "$wi"
  release_lock

  validate_wi_jq_fallback "$wi_file" || return 2

  record_event_safe "work_item_transitioned" \
    "$(jq -cn --arg id "$wi" --arg f "$from_status" --arg t "$new_status" \
       '{wi_id:$id, from:$f, to:$t, trigger:"transition"}')"

  echo "$wi"
  return 0
}

# ── cmd: evaluator-pass ─────────────────────────────────────────────────
# transition done의 sugar. /nova:run·auto가 호출.
cmd_evaluator_pass() {
  local wi=${1:-}
  [ -z "$wi" ] && { log_err "evaluator-pass: wi-id 인자 필요"; return 2; }
  shift
  local sha="" test_output="" files=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --commit-sha=*)  sha="${1#*=}" ;;
      --test-output=*) test_output="${1#*=}" ;;
      --files=*)       files="${1#*=}" ;;
      *) log_err "evaluator-pass: 알 수 없는 옵션 '$1'"; return 2 ;;
    esac
    shift
  done
  [ -z "$sha" ] && { log_err "evaluator-pass: --commit-sha=SHA 필수"; return 2; }
  if ! [[ "$sha" =~ ^[a-f0-9]{7,40}$ ]]; then
    log_err "evaluator-pass: --commit-sha 형식 위반 (a-f0-9, 7~40자)"
    return 2
  fi

  ensure_registry_initialized || return 2
  ensure_wi_exists "$wi" || return 2

  local wi_file="$WI_DIR/$wi.json"
  local from_status
  from_status=$(jq -r '.status' "$wi_file")
  if [ "$from_status" = "done" ]; then
    log_err "evaluator-pass: WI '$wi' 이미 done"
    return 2
  fi
  local ts
  ts=$(get_timestamp)

  acquire_lock || { log_err "evaluator-pass: lock 획득 실패"; return 1; }
  mark_pending "$wi" "done"

  local jq_args=(--arg sha "$sha" --arg ts "$ts")
  local jq_expr='
    .status = "done" |
    .review_required = false |
    .evidence.commit_sha += [$sha] |
    .last_verified_at = $ts |
    .updated_at = $ts
  '
  if [ -n "$test_output" ]; then
    jq_args+=(--arg to "$test_output")
    jq_expr+=' | .evidence.test_output = $to'
  fi
  if [ -n "$files" ]; then
    local files_arr
    files_arr=$(python3 -c "import json,sys; print(json.dumps([x.strip() for x in sys.argv[1].split(',') if x.strip()]))" "$files")
    jq_args+=(--argjson fa "$files_arr")
    jq_expr+=' | .evidence.files_changed = $fa'
  fi

  if ! jq_write_atomic "$wi_file" "${jq_args[@]}" "$jq_expr"; then
    release_lock
    return 2
  fi

  local priority
  priority=$(jq -r '.priority' "$wi_file")
  index_upsert "$wi" "done" "false" "$priority" "$ts"

  clear_pending "$wi"
  release_lock

  validate_wi_jq_fallback "$wi_file" || return 2

  record_event_safe "work_item_transitioned" \
    "$(jq -cn --arg id "$wi" --arg f "$from_status" --arg sha "$sha" \
       '{wi_id:$id, from:$f, to:"done", trigger:"evaluator_pass", commit_sha:$sha}')"

  echo "PASS $wi"
  return 0
}

# ── cmd: require-review ─────────────────────────────────────────────────
cmd_require_review() {
  local wi=${1:-}
  [ -z "$wi" ] && { log_err "require-review: wi-id 인자 필요"; return 2; }
  ensure_registry_initialized || return 2
  ensure_wi_exists "$wi" || return 2

  local wi_file="$WI_DIR/$wi.json"
  local cur
  cur=$(jq -r '.review_required' "$wi_file")
  if [ "$cur" = "true" ]; then
    log_err "require-review: WI '$wi' 이미 review_required=true"
    return 2
  fi
  local status
  status=$(jq -r '.status' "$wi_file")
  if [ "$status" = "done" ]; then
    log_err "require-review: status=done WI에는 review_required set 불가 (invariant 충돌)"
    return 2
  fi

  local ts
  ts=$(get_timestamp)
  acquire_lock || { log_err "require-review: lock 획득 실패"; return 1; }
  if ! jq_write_atomic "$wi_file" --arg ts "$ts" \
       '.review_required = true | .updated_at = $ts'; then
    release_lock
    return 2
  fi
  local priority
  priority=$(jq -r '.priority' "$wi_file")
  index_upsert "$wi" "$status" "true" "$priority" "$ts"
  release_lock

  validate_wi_jq_fallback "$wi_file" || return 2

  record_event_safe "work_item_review_required" \
    "$(jq -cn --arg id "$wi" '{wi_id:$id, review_required:true}')"

  echo "REVIEW_REQUIRED $wi"
  return 0
}

# ── 디스패처 ────────────────────────────────────────────────────────────
main() {
  local sub=${1:-}
  [ -z "$sub" ] && { usage; exit 2; }
  shift
  case "$sub" in
    create)          cmd_create "$@"          ;;
    update)          cmd_update "$@"          ;;
    transition)      cmd_transition "$@"      ;;
    evaluator-pass)  cmd_evaluator_pass "$@"  ;;
    require-review)  cmd_require_review "$@"  ;;
    -h|--help|help)  usage; exit 0            ;;
    *) log_err "알 수 없는 명령 '$sub'"; usage; exit 2 ;;
  esac
}

main "$@"
