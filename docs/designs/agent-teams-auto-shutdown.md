---
schema_version: 1
wi_id: WI-0014
design_id: agent-teams-auto-shutdown
plan_ref: docs/plans/agent-teams-auto-shutdown.md
created_at: 2026-05-23
---

# Design — Agent Teams 자동 종료 hook 강제 (WI-0014)

> Plan: [agent-teams-auto-shutdown.md](../plans/agent-teams-auto-shutdown.md)

## 결정

| # | 결정 | 대안 | 선택 이유 |
|---|------|------|----------|
| D1 | `~/.claude/teams/` 디렉토리 스캔 방식 | TaskList MCP 호출 / `Agent` 도구 introspection | hook 환경에서 도구 호출 불가. 파일 시스템 inspection 만 가능 |
| D2 | Stop hook + SessionStart hook 양쪽 호출 | Stop 만 / SessionStart 만 | Stop = turn 끝 alert, SessionStart = 좀비 잔존 감지. 두 trigger 모두 필요 |
| D3 | safe-default exit 0 | hook 실패 시 차단 | audit 실패가 leader 다음 turn 차단해서는 안 됨. 기존 audit-orchestration.sh 패턴 따름 |
| D4 | leader 가 누구인지 hook 에서 식별 X | leader name 까지 출력 | hook 환경에서 leader = main Claude. WARN 메시지 자체가 leader 에게 도달 |
| D5 | Antipattern ID = B7 | B6 끝에 부록 | B 시리즈 단조 증가 컨벤션 보존 |

## audit-teammates.sh (NEW · ~60줄)

```bash
#!/usr/bin/env bash
# Nova Teammate Audit — 미정리 활성 teammate 팀 감지 (Stop + SessionStart hook 양용)
#
# leader 가 SendMessage shutdown_request 발송을 잊으면 ~/.claude/teams/ 에
# 디렉토리 + config.json 이 남아 다음 세션까지 좀비로 누적. 이를 stderr WARN
# + teammate_orphan 이벤트로 alert.
#
# Safe-default: 모든 에러 → exit 0 (audit-orchestration.sh 패턴)

set -u

if [[ -n "${NOVA_DISABLE_EVENTS:-}" ]]; then
  exit 0
fi

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

# event 기록 — events.jsonl 누적
if command -v jq >/dev/null 2>&1; then
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
```

## stop-event.sh 갱신 (1줄 추가)

`audit-orchestration.sh` 호출 직후:

```diff
 bash "${BASH_SOURCE%/*}/audit-orchestration.sh" || true
+bash "${BASH_SOURCE%/*}/audit-teammates.sh" || true
```

## session-start.sh lean profile (Always-On 9번 추가)

현재 lean profile 의 ADDITIONAL_CONTEXT 에는 Always-On 1~5만 있음. standard/strict 와 동기화하여 9번 추가:

```diff
- ## Always-On\n\n1. 모든 코드 변경에 자동 규칙. 2. 3파일+ 변경 시 Plan. 3. Evaluator 독립 서브에이전트. 4. 커밋 전 /nova:review --fast. 5. NOVA-STATE.md 본문 스냅샷.
+ ## Always-On\n\n1. 모든 코드 변경에 자동 규칙. 2. 3파일+ 변경 시 Plan. 3. Evaluator 독립 서브에이전트. 4. 커밋 전 /nova:review --fast. 5. NOVA-STATE.md 본문 스냅샷. 6. 팀 spawn → teammate shutdown_request 의무 (idle≠종료, §2).
```

(lean 은 압축이 목적이라 9번 → 6번으로 번호 축소. 키워드 "shutdown_request 의무"는 유지 — 회귀 가드 매칭용.)

또한 ADDITIONAL_CONTEXT 끝에 좀비 카운트 inject 로직 (있을 때만):

```bash
# Always-On 직전에 추가
ORPHAN_TEAMS_DIR="${NOVA_TEAMS_DIR:-$HOME/.claude/teams}"
if [[ -d "$ORPHAN_TEAMS_DIR" ]]; then
  ORPHAN_COUNT=$(find "$ORPHAN_TEAMS_DIR" -mindepth 2 -maxdepth 2 -name config.json 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$ORPHAN_COUNT" =~ ^[0-9]+$ ]] && (( ORPHAN_COUNT > 0 )); then
    ORPHAN_HINT="\n\n⚠️ 이전 세션 미정리 teammate 팀 ${ORPHAN_COUNT}개 — \`ls ~/.claude/teams/\` 확인 후 TeamDelete 또는 rm 으로 정리"
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}${ORPHAN_HINT}"
  fi
fi
```

## nova-antipatterns.md § B7 신설

```markdown
### B7. "팀 spawn 후 shutdown 누락"

**증상**: `TeamCreate` / `Agent({team_name, name})` 로 teammate 를 spawn 한 leader 가 작업 완료 보고를 받고도 `SendMessage({type:"shutdown_request"})` 발송을 잊는다. `~/.claude/teams/<team>/config.json` 이 다음 세션까지 잔존하며 tmux pane·디스크를 점유.

**원인**: Claude Code 의 `idle_notification` 은 종료 신호가 아님. leader 가 "idle = 끝"이라 오해.

**올바른 행동**:
1. 모든 teammate 의 완료 보고를 받았다면 **같은 turn 안에** `SendMessage({to: name, message: {type: "shutdown_request"}})` 발송.
2. `shutdown_approved` 응답 확인 후 `TeamDelete` 호출.
3. 좀비 audit: `bash hooks/audit-teammates.sh` 또는 SessionStart hook 의 stderr WARN 확인.

**코드화 위치**: `skills/orchestrator/SKILL.md` Phase 7, `commands/evolve.md` Phase 1, `hooks/audit-teammates.sh`, `hooks/session-start.sh` (Always-On 9번 / lean 6번).
```

## nova-rules.md §2 인용 블록 1줄 추가

```diff
- > 코드화 위치: `skills/orchestrator/SKILL.md` Phase 7 + `commands/evolve.md` Phase 1.
+ > 코드화 위치: `skills/orchestrator/SKILL.md` Phase 7 + `commands/evolve.md` Phase 1 + `hooks/audit-teammates.sh` (Stop + SessionStart audit, v5.47.9+).
```

## tests/test-scripts.sh 회귀 가드 (4건)

```bash
# audit-teammates.sh 존재 + executable
test_audit_teammates_exists() {
  [[ -x "$NOVA_ROOT/hooks/audit-teammates.sh" ]] || fail "audit-teammates.sh 미존재"
}

# audit-teammates.sh dry-run (빈 디렉토리 → exit 0, no stderr)
test_audit_teammates_clean_dryrun() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local out
  out=$(NOVA_TEAMS_DIR="$tmpdir" NOVA_DISABLE_EVENTS= bash "$NOVA_ROOT/hooks/audit-teammates.sh" 2>&1)
  [[ -z "$out" ]] || fail "clean state 에서 출력 발생: $out"
  rm -rf "$tmpdir"
}

# audit-teammates.sh orphan 시뮬 → WARN 텍스트 매치
test_audit_teammates_orphan_detected() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/zombie-team"
  echo '{"team_name":"zombie-team"}' > "$tmpdir/zombie-team/config.json"
  local out
  out=$(NOVA_TEAMS_DIR="$tmpdir" NOVA_DISABLE_EVENTS=1 bash "$NOVA_ROOT/hooks/audit-teammates.sh" 2>&1)
  echo "$out" | grep -q "미정리 teammate" || fail "WARN 미발생: $out"
  rm -rf "$tmpdir"
}

# session-start.sh lean profile 에 shutdown 키워드 존재
test_session_start_lean_has_shutdown_keyword() {
  local out
  out=$(NOVA_PROFILE=lean bash "$NOVA_ROOT/hooks/session-start.sh" 2>/dev/null)
  echo "$out" | grep -qF "shutdown_request 의무" || fail "lean profile 에 키워드 누락"
}

# nova-antipatterns.md B7 항목 존재
test_antipatterns_b7_exists() {
  grep -qF "### B7" "$NOVA_ROOT/docs/nova-antipatterns.md" || fail "B7 antipattern 누락"
  grep -qF "팀 spawn 후 shutdown 누락" "$NOVA_ROOT/docs/nova-antipatterns.md" || fail "B7 제목 누락"
}
```

5건 (위에 4 + B7 1) — 단조 증가.

## self_verify

```bash
# 1. 코드 변경 검증
bash hooks/audit-teammates.sh             # 좀비 1개 이상 있으면 WARN
NOVA_PROFILE=lean bash hooks/session-start.sh | grep "shutdown_request 의무"
grep "B7" docs/nova-antipatterns.md
grep "audit-teammates.sh" docs/nova-rules.md

# 2. 회귀
bash tests/test-scripts.sh                # 5건 추가 후 PASS 확인

# 3. audit
bash scripts/audit-agent-tools.sh         # 6/6 PASS

# 4. Evaluator (독립)
# nova:qa-engineer 서브에이전트로 Layer 1~5 검증

# 5. 릴리스
bash scripts/release.sh patch "WI-0014 Agent Teams 자동 종료 audit hook"
```

## Out of scope (확인)

- 자동 `TeamDelete` / `worktree prune`: 다음 사이클 (`NOVA_AUTO_CLEAN_TEAMS=1` 환경변수로 opt-in)
- runner 보고 일치성 (Friction #4): 별도 WI
- worktree venv (Friction #5): `nova:worktree-setup` skill 확장
