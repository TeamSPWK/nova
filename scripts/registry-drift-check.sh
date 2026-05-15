#!/usr/bin/env bash
# Nova registry-drift-check.sh — Hard 9 + Warn 9 = 18종 drift 검출 (Sprint 4)
#
# 사용:
#   bash scripts/registry-drift-check.sh                      # 전체 18 룰
#   bash scripts/registry-drift-check.sh --severity=critical  # Hard 9만
#   bash scripts/registry-drift-check.sh --severity=warning   # Warn 9만
#   bash scripts/registry-drift-check.sh --jsonl              # JSONL 진단 출력
#
# Exit code:
#   0 = PASS (위반 없음)
#   1 = Warn only (Hard 0, Warn 1+)
#   2 = Hard error (Hard 1+)
#
# 실행 순서 강제 (Critic #18): H1 → H2 → ... → H9. H1 실패 시 H2~H9 SKIP.
# 의존성: jq, git (선택)
# 환경: NOVA_REGISTRY_ROOT (CWD)

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REGISTRY_ROOT="${NOVA_REGISTRY_ROOT:-$PWD}"
WI_DIR="$REGISTRY_ROOT/.nova/work-items"
INDEX_FILE="$WI_DIR/index.json"
EVENTS_FILE="$REGISTRY_ROOT/.nova/events.jsonl"

SEVERITY="all"
JSONL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --severity=*)  SEVERITY="${1#*=}" ;;
    --jsonl)       JSONL=1 ;;
    -h|--help)
      cat <<'USAGE'
Nova registry-drift-check — Hard 9 + Warn 9 drift 검출

사용:
  bash scripts/registry-drift-check.sh                      전체 18 룰
  bash scripts/registry-drift-check.sh --severity=critical  Hard 9만
  bash scripts/registry-drift-check.sh --severity=warning   Warn 9만
  bash scripts/registry-drift-check.sh --jsonl              jsonl 진단

룰 (자세히: docs/designs/work-item-registry-v3.md §drift 룰):
  Hard 9: H1(schema) H2(id 유일) H3(status enum) H4(gitignore) H5(depends_on)
          H6(done evidence) H7(orphan) H8(pending transition) H9(blocked_reason 불변식)
  Warn 9: W1(stale STATE) W2(plan frontmatter) W3(unreferenced plan) W4(last_verified_at)
          W5(git 커밋 부재) W6(UUID fallback) W7(source_docs[0] plan 미매핑)
          W8(marker 손편집) W9(비표준 actor)

Exit: 0=PASS, 1=Warn, 2=Hard
USAGE
      exit 0
      ;;
    *) echo "[drift-check] ERR: 알 수 없는 옵션 '$1'" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$INDEX_FILE" ]; then
  echo "[drift-check] ERR: registry 미초기화 — $INDEX_FILE 부재" >&2
  exit 2
fi

# ── 진단 출력 도우미 ──
declare -i HARD_COUNT=0
declare -i WARN_COUNT=0

emit() {
  # emit <rule_id> <severity> <message> [wi_id]
  local rid=$1 sev=$2 msg=$3 wi=${4:-}
  if [ "$JSONL" = "1" ]; then
    jq -cn --arg r "$rid" --arg s "$sev" --arg m "$msg" --arg w "$wi" \
      '{rule_id:$r, severity:$s, message:$m, wi_id:($w | select(length>0))}'
  else
    local prefix
    case "$sev" in
      critical) prefix="❌ $rid" ;;
      warning)  prefix="⚠️  $rid" ;;
    esac
    echo "  $prefix: $msg${wi:+ (wi: $wi)}"
  fi
  case "$sev" in
    critical) HARD_COUNT=$((HARD_COUNT + 1)) ;;
    warning)  WARN_COUNT=$((WARN_COUNT + 1)) ;;
  esac
}

run_hard() { [ "$SEVERITY" = "all" ] || [ "$SEVERITY" = "critical" ]; }
run_warn() { [ "$SEVERITY" = "all" ] || [ "$SEVERITY" = "warning" ]; }

[ "$JSONL" = "0" ] && echo "[drift-check] 시작 (severity=$SEVERITY, root=$REGISTRY_ROOT)"

# ───────────────────────────────────────────────────────
# Hard 9 (순차 실행 — H1 실패 시 H2~H9 SKIP, Critic #18)
# ───────────────────────────────────────────────────────

SKIP_REMAINING_HARD=0

# H1: schema 유효성 (jq fallback 4종)
if run_hard; then
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    if ! jq empty "$f" 2>/dev/null; then
      emit "H1" "critical" "invalid JSON ($f)" "$base"
      SKIP_REMAINING_HARD=1
      continue
    fi
    if ! jq -e '.status | IN("proposed","active","blocked","done","superseded")' "$f" >/dev/null 2>&1; then
      emit "H1" "critical" "status enum 위반" "$base"; SKIP_REMAINING_HARD=1
    fi
    if ! jq -e '.review_required | type == "boolean"' "$f" >/dev/null 2>&1; then
      emit "H1" "critical" "review_required bool 위반" "$base"; SKIP_REMAINING_HARD=1
    fi
    if ! jq -e '.evidence.commit_sha | type == "array"' "$f" >/dev/null 2>&1; then
      emit "H1" "critical" "evidence.commit_sha array 위반" "$base"; SKIP_REMAINING_HARD=1
    fi
    if ! jq -e '.id | test("^WI-([0-9]{4}|[a-f0-9]{8})-.+$")' "$f" >/dev/null 2>&1; then
      emit "H1" "critical" "id pattern 위반" "$base"; SKIP_REMAINING_HARD=1
    fi
  done
fi

# H2~H9는 H1 통과 시만 (Critic #18 unhandled jq 실패 방어)
if run_hard && [ "$SKIP_REMAINING_HARD" = "0" ]; then
  # H2: id 유일성
  dup=$(jq -r '.work_items[].id' "$INDEX_FILE" | sort | uniq -d)
  [ -n "$dup" ] && while IFS= read -r d; do emit "H2" "critical" "id 중복" "$d"; done <<< "$dup"

  # H3: status enum (index.json)
  bad_status=$(jq -r '.work_items[] | select(.status | IN("proposed","active","blocked","done","superseded") | not) | .id' "$INDEX_FILE")
  [ -n "$bad_status" ] && while IFS= read -r b; do emit "H3" "critical" "index.json status enum 위반" "$b"; done <<< "$bad_status"

  # H4: gitignore 제외 보장 (git check-ignore 사용 가능 시)
  if command -v git >/dev/null 2>&1 && git -C "$REGISTRY_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$REGISTRY_ROOT" check-ignore "$INDEX_FILE" >/dev/null 2>&1; then
      emit "H4" "critical" "index.json이 .gitignore에 의해 제외됨 — git-tracked 보장 실패"
    fi
  fi

  # H5: depends_on 미존재 id
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    deps=$(jq -r '.depends_on[]?' "$f" 2>/dev/null)
    [ -z "$deps" ] && continue
    while IFS= read -r dep; do
      [ -z "$dep" ] && continue
      [ -f "$WI_DIR/$dep.json" ] || emit "H5" "critical" "depends_on '$dep' 파일 부재" "$base"
    done <<< "$deps"
  done

  # H6: done evidence 부재
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    if jq -e 'select(.status=="done") | (.evidence.commit_sha | length == 0)' "$f" >/dev/null 2>&1; then
      emit "H6" "critical" "status=done인데 evidence.commit_sha 비어있음" "$base"
    fi
  done

  # H7: orphan id (index ↔ 파일 불일치)
  idx_ids=$(jq -r '.work_items[].id' "$INDEX_FILE" | sort)
  file_ids=$(ls "$WI_DIR"/WI-*.json 2>/dev/null | sed 's|.*/||; s|\.json$||' | sort)
  orphan_in_idx=$(comm -23 <(echo "$idx_ids") <(echo "$file_ids"))
  orphan_in_files=$(comm -13 <(echo "$idx_ids") <(echo "$file_ids"))
  [ -n "$orphan_in_idx" ] && while IFS= read -r o; do emit "H7" "critical" "index에는 있지만 파일 없음" "$o"; done <<< "$orphan_in_idx"
  [ -n "$orphan_in_files" ] && while IFS= read -r o; do emit "H7" "critical" "파일은 있지만 index에 없음" "$o"; done <<< "$orphan_in_files"

  # H8: 부분 전이 마커 잔류
  pending=$(ls "$WI_DIR"/.pending-transition-* 2>/dev/null)
  [ -n "$pending" ] && while IFS= read -r p; do
    pname=$(basename "$p")
    emit "H8" "critical" "부분 전이 마커 잔류 — recover_pending_transitions 또는 수동 복구 필요" "$pname"
  done <<< "$pending"

  # H9: status=blocked인데 blocked_reason 비어있음
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    if jq -e 'select(.status=="blocked") | (.blocked_reason | (. == null or . == ""))' "$f" >/dev/null 2>&1; then
      emit "H9" "critical" "status=blocked인데 blocked_reason 비어있음 (invariant 위반)" "$base"
    fi
  done
fi

# ───────────────────────────────────────────────────────
# Warn 9
# ───────────────────────────────────────────────────────

if run_warn; then
  # W1: stale STATE 7일+
  STATE_FILE="$REGISTRY_ROOT/NOVA-STATE.md"
  if [ -f "$STATE_FILE" ]; then
    state_mtime=$(stat -f %m "$STATE_FILE" 2>/dev/null || stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    days_stale=$(( (now_epoch - state_mtime) / 86400 ))
    [ "$days_stale" -gt 7 ] && emit "W1" "warning" "NOVA-STATE.md ${days_stale}일 미갱신 (>7일)"
  fi

  # W2: plan frontmatter 누락
  if [ -d "$REGISTRY_ROOT/docs/plans" ]; then
    no_fm=$(find "$REGISTRY_ROOT/docs/plans" -maxdepth 2 -name '*.md' 2>/dev/null | while read p; do
      head -1 "$p" 2>/dev/null | grep -q '^---' || echo "$p"
    done)
    [ -n "$no_fm" ] && while IFS= read -r p; do
      emit "W2" "warning" "plan frontmatter 부재 — $(basename "$p")"
    done <<< "$no_fm"
  fi

  # W3: unreferenced plan (work-item source_docs 역참조 없음)
  if [ -d "$REGISTRY_ROOT/docs/plans" ]; then
    all_plans=$(find "$REGISTRY_ROOT/docs/plans" -maxdepth 2 -name '*.md' 2>/dev/null | sed "s|$REGISTRY_ROOT/||")
    referenced=$(jq -r '.work_items[].id' "$INDEX_FILE" | while read id; do
      jq -r '.source_docs[]?' "$WI_DIR/$id.json" 2>/dev/null
    done | sort -u)
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      echo "$referenced" | grep -qF "$p" || emit "W3" "warning" "unreferenced plan — $p"
    done <<< "$all_plans"
  fi

  # W4: last_verified_at 30일+ stale (status=active만)
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    if jq -e '
      select(.status == "active") |
      select(.last_verified_at != null) |
      ((now - (.last_verified_at | sub("Z$"; "+00:00") | fromdateiso8601)) > 2592000)
    ' "$f" >/dev/null 2>&1; then
      emit "W4" "warning" "status=active이지만 last_verified_at >30일 stale" "$base"
    fi
  done

  # W5: git 커밋 이력 부재 (index.json staged/committed 없음)
  if command -v git >/dev/null 2>&1 && git -C "$REGISTRY_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$REGISTRY_ROOT" log --oneline -1 -- ".nova/work-items/index.json" 2>/dev/null | grep -q .; then
      git -C "$REGISTRY_ROOT" diff --cached --name-only 2>/dev/null | grep -qF ".nova/work-items/index.json" || \
        emit "W5" "warning" "index.json git 커밋·staged 이력 부재 — 'git add .nova/work-items/' 권장"
    fi
  fi

  # W6: UUID fallback id
  uuid_ids=$(jq -r '.work_items[].id' "$INDEX_FILE" | grep -E '^WI-[a-f0-9]{8}-' || true)
  [ -n "$uuid_ids" ] && while IFS= read -r u; do
    emit "W6" "warning" "UUID fallback id — 'bash scripts/reindex-work-items.sh' 권장" "$u"
  done <<< "$uuid_ids"

  # W7: source_docs[0] plan 미매핑
  for f in "$WI_DIR"/WI-*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    src=$(jq -r '.source_docs[0] // ""' "$f")
    if [ -z "$src" ]; then
      emit "W7" "warning" "source_docs 비어있음 — sprint 소속 추론 불가" "$base"
    elif [ -f "$REGISTRY_ROOT/$src" ]; then
      head -1 "$REGISTRY_ROOT/$src" 2>/dev/null | grep -q '^---' || \
        emit "W7" "warning" "source_docs[0]에 frontmatter 부재 — $src" "$base"
    fi
  done

  # W8: marker 영역 손편집 감지 (사후 검출)
  if [ -f "$STATE_FILE" ] && grep -qF "<!-- nova:registry-rendered:start -->" "$STATE_FILE"; then
    # render-state dry-run으로 현재 marker와 새 렌더 결과 비교
    if cur_diff=$(NOVA_REGISTRY_ROOT="$REGISTRY_ROOT" bash "$SCRIPT_DIR/registry-render-state.sh" --dry-run 2>/dev/null | grep -E '^[+-]' | head -1); then
      [ -n "$cur_diff" ] && emit "W8" "warning" "marker 영역과 현재 registry 상태 불일치 — 손편집 의심 또는 외부 변경 (render-state 실행 권장)"
    fi
  fi

  # W9: 비표준 actor가 registry-write 호출
  if [ -f "$EVENTS_FILE" ]; then
    non_std_actors=$(jq -r 'select((.event_type // "" | test("^work_item_")) and (.extra.actor // "")) | .extra.actor' "$EVENTS_FILE" 2>/dev/null \
      | grep -vE '^(command:/nova:|skill:orchestrator|user:direct)' | sort -u || true)
    [ -n "$non_std_actors" ] && while IFS= read -r a; do
      emit "W9" "warning" "비표준 actor가 work-item 이벤트 기록: '$a'"
    done <<< "$non_std_actors"
  fi
fi

# ── 결과 ──
if [ "$JSONL" = "0" ]; then
  echo ""
  echo "[drift-check] 결과: Hard=$HARD_COUNT, Warn=$WARN_COUNT"
fi

if [ "$HARD_COUNT" -gt 0 ]; then
  exit 2
elif [ "$WARN_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
