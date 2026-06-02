#!/usr/bin/env bash
# Nova /nova:setup --permissions 구현 (Sprint 2a)
#
# 사용법:
#   bash scripts/setup-permissions.sh [--target <path>] [--force]
#
# 동작:
#   - scripts/permissions-template.json(Nova deny-by-default 세트)을
#     사용자 .claude/settings.json에 병합한다(기본 대상).
#   - 배열 키(allow/deny): 합집합 + 중복 제거.
#   - 충돌(같은 항목이 user.allow + nova.deny): **deny 우선** + stderr CONFLICT 리포트.
#   - 스칼라(defaultMode): 사용자 기존값 보존. Nova 값은 신규 키일 때만 주입.
#   - 최초 실행 시 bootstrap=true session_start 이벤트 기록(nova-metrics 분모 보정용).
#
# Exit:
#   0 — 성공 (병합 완료 or 대상 이미 일치)
#   2 — jq 미설치, 템플릿 누락, write 실패

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${ROOT_DIR}/scripts/permissions-template.json"

TARGET=".claude/settings.json"
ALLOW_OUTSIDE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --allow-outside) ALLOW_OUTSIDE=1; shift ;;
    --force) shift ;;  # reserved
    *) shift ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "[nova:setup] ERROR: jq 필요 (brew install jq)" >&2
  exit 2
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "[nova:setup] ERROR: permissions 템플릿 없음: $TEMPLATE" >&2
  exit 2
fi

# ── Symlink 방어 (Sprint 2a Evaluator Issue #2) ──
if [[ -L "$TARGET" ]]; then
  echo "[nova:setup] ERROR: TARGET이 symlink — 원본 파일 덮어쓰기 방지 (realpath: $(readlink "$TARGET"))" >&2
  exit 2
fi

# ── Path traversal 방어 (Sprint 2a Evaluator Issue #1 + Issue #1') ──
# 전략: parent dir을 먼저 mkdir -p 한 뒤 `cd && pwd -P`로 realpath 확보.
# 이 방식은 `..` 같은 traversal이 포함된 경로도 실제 커널이 해석한 canonical path로 정규화된다.
TARGET_PARENT="$(dirname "$TARGET")"
TARGET_BASE="$(basename "$TARGET")"

mkdir -p "$TARGET_PARENT" 2>/dev/null || {
  echo "[nova:setup] ERROR: TARGET parent dir 생성 실패: $TARGET_PARENT" >&2
  exit 2
}
TARGET_PARENT_REAL="$(cd "$TARGET_PARENT" 2>/dev/null && pwd -P)"
if [[ -z "$TARGET_PARENT_REAL" ]]; then
  echo "[nova:setup] ERROR: TARGET parent realpath 해석 실패: $TARGET_PARENT" >&2
  exit 2
fi
TARGET_REAL="${TARGET_PARENT_REAL}/${TARGET_BASE}"
CWD_REAL="$(pwd -P)"
HOME_REAL="$(cd "$HOME" 2>/dev/null && pwd -P || echo "$HOME")"

if (( ALLOW_OUTSIDE == 0 )); then
  case "$TARGET_REAL" in
    "$CWD_REAL"/*|"$HOME_REAL"/*|"$CWD_REAL") ;;  # 허용
    *)
      echo "[nova:setup] ERROR: TARGET 경로가 cwd($CWD_REAL) 또는 \$HOME($HOME_REAL) 하위가 아님" >&2
      echo "  resolved: $TARGET_REAL" >&2
      echo "  외부 경로에 기록하려면 --allow-outside 명시" >&2
      exit 2
      ;;
  esac
fi

# 기존 settings.json 또는 빈 객체
if [[ -f "$TARGET" ]]; then
  USER_JSON=$(cat "$TARGET")
  [[ -z "$USER_JSON" ]] && USER_JSON='{}'
else
  USER_JSON='{}'
  mkdir -p "$TARGET_PARENT" 2>/dev/null || true
fi

# ── 충돌 리포트: user.allow ∩ nova.deny → deny wins ──
USER_ALLOW=$(printf '%s' "$USER_JSON" | jq -r '.permissions.allow // [] | .[]' 2>/dev/null || true)
NOVA_DENY=$(jq -r '.permissions.deny[]' "$TEMPLATE")

if [[ -n "$USER_ALLOW" ]]; then
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if printf '%s\n' "$NOVA_DENY" | grep -Fxq "$item"; then
      echo "[nova:setup] CONFLICT: \"$item\" in user allow + Nova deny → deny wins" >&2
    fi
  done <<< "$USER_ALLOW"
fi

# ── Merge ──
# - defaultMode: 사용자값 유지, 없으면 Nova 값
# - allow: (user + nova) 합집합에서 nova.deny 제거 (충돌 시 deny 우선)
# - deny: (user + nova) 합집합
# - hooks.PreToolUse: §11 Sprint 2b 런타임 enforcement(precheck-tool.sh) 엔트리 주입.
#   사용자 기존 hooks 보존 + precheck-tool.sh가 이미 등록돼 있으면 재주입 안 함(idempotent).
#   (이 머지 누락이 §11이 약속한 런타임 enforcement 미설치 버그 — v5.51.x 수정)
# - 기타 최상위 키: 보존
MERGED=$(printf '%s' "$USER_JSON" | jq --slurpfile tpl "$TEMPLATE" '
  def merge_arr(a; b): ((a // []) + (b // [])) | unique;
  def nova: $tpl[0];

  . as $u |
  ($u.hooks // {}) as $uh |
  ($uh.PreToolUse // []) as $upre |
  # 사용자 PreToolUse 훅 command 중 precheck-tool.sh 참조가 이미 있으면 재주입 금지
  ([$upre[].hooks[]?.command // ""] | any(contains("precheck-tool.sh"))) as $has_precheck |
  $u + {
    permissions: {
      defaultMode: ($u.permissions.defaultMode // nova.permissions.defaultMode),
      allow: (merge_arr($u.permissions.allow; nova.permissions.allow) - (nova.permissions.deny // [])),
      deny:  merge_arr($u.permissions.deny;  nova.permissions.deny)
    },
    hooks: ($uh + {
      PreToolUse: (if $has_precheck then $upre else ($upre + (nova.hooks.PreToolUse // [])) end)
    })
  }
')

if [[ -z "$MERGED" ]]; then
  echo "[nova:setup] ERROR: jq merge 실패" >&2
  exit 2
fi

# Atomic write
TMP_FILE="${TARGET}.nova.tmp.$$"
printf '%s\n' "$MERGED" | jq '.' > "$TMP_FILE" 2>/dev/null
WRITE_RC=$?

if [[ $WRITE_RC -ne 0 || ! -s "$TMP_FILE" ]]; then
  rm -f "$TMP_FILE"
  echo "[nova:setup] ERROR: write 실패 ($TARGET)" >&2
  exit 2
fi

mv "$TMP_FILE" "$TARGET"
echo "[nova:setup] permissions 병합 완료: $TARGET"

# Bootstrap 이벤트 (nova-metrics 분모 보정 — §10 알려진 제약 해소)
# Sprint 2a Evaluator Issue #3: 중복 주입 방지 — 기존 bootstrap 있으면 skip
if [[ -f "${ROOT_DIR}/hooks/record-event.sh" ]]; then
  BOOTSTRAP_EXISTS="false"
  if [[ -f .nova/events.jsonl ]] && command -v jq >/dev/null 2>&1; then
    BOOTSTRAP_EXISTS=$(jq -s 'any(.[]; .event_type=="session_start" and (.extra.bootstrap // false) == true)' .nova/events.jsonl 2>/dev/null || echo false)
  fi
  if [[ "$BOOTSTRAP_EXISTS" != "true" ]]; then
    bash "${ROOT_DIR}/hooks/record-event.sh" session_start '{"bootstrap":true,"trigger":"setup-permissions"}' 2>/dev/null || true
  fi
fi

exit 0
