#!/usr/bin/env bash
# Nova Teammate Audit — 미정리 활성 teammate 팀 감지 (Stop + SessionStart hook 양용)
#
# leader 가 SendMessage shutdown_request 발송을 잊으면 ~/.claude/teams/ 에
# 디렉토리 + config.json 이 남아 다음 세션까지 좀비로 누적. 이를 stderr WARN
# + teammate_orphan 이벤트로 alert.
#
# Safe-default: 모든 에러 → exit 0 (audit-orchestration.sh 패턴)

set -u

TEAMS_DIR="${NOVA_TEAMS_DIR:-$HOME/.claude/teams}"

if [[ ! -d "$TEAMS_DIR" ]]; then
  exit 0
fi

# 활성 팀 = config.json 가 있는 디렉토리. 우리가 정리하지 않은 흔적.
ORPHAN_TEAMS=()
while IFS= read -r -d '' config_path; do
  team_dir="$(dirname "$config_path")"
  team_name="$(basename "$team_dir")"
  ORPHAN_TEAMS+=("$team_name")
done < <(find "$TEAMS_DIR" -mindepth 2 -maxdepth 2 -name config.json -print0 2>/dev/null)

COUNT=${#ORPHAN_TEAMS[@]}

if [[ $COUNT -eq 0 ]]; then
  exit 0
fi

TEAM_LIST=$(printf "%s, " "${ORPHAN_TEAMS[@]}" | sed 's/, $//')

# stderr WARN — leader 에게 즉시 도달
echo "[nova:audit] 미정리 teammate 팀 $COUNT 개 — leader shutdown_request 누락 의심: $TEAM_LIST. docs/nova-rules.md §2 참조." >&2

# event 기록 — events.jsonl 누적 (NOVA_DISABLE_EVENTS=1 시 skip, WARN 은 항상 발화)
if [[ -z "${NOVA_DISABLE_EVENTS:-}" ]] && command -v jq >/dev/null 2>&1; then
  EXTRA=$(jq -cn --argjson count "$COUNT" --arg teams "$TEAM_LIST" \
    '{orphan_count: $count, teams: $teams, reason: "leader_shutdown_request_missing"}')
  bash "${BASH_SOURCE%/*}/record-event.sh" teammate_orphan "$EXTRA" 2>/dev/null || true
fi

# Desktop notify (M-2 패턴 재사용)
if [[ "${NOVA_DESKTOP_NOTIFY:-0}" == "1" ]] && command -v jq >/dev/null 2>&1; then
  NOTIFY_SEQ=$(printf '\007\033]0;Nova: %d orphan teams\007' "$COUNT")
  jq -cn --arg seq "$NOTIFY_SEQ" '{terminalSequence: $seq}' 2>/dev/null || true
fi

exit 0
