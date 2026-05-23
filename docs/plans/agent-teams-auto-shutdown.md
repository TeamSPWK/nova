---
schema_version: 1
wi_id: WI-0014
plan_id: agent-teams-auto-shutdown
created_at: 2026-05-23
status: draft
---

# Plan — Agent Teams 자동 종료 hook 강제 (WI-0014 · 1a+1b)

## Context

- v5.47.7 (`8c75b23`) — `skills/orchestrator/SKILL.md` Phase 7 + `commands/evolve.md` Phase 1 에 teammate shutdown 의무 SKILL 명세 추가
- v5.47.8 (`26c7820`) — `docs/nova-rules.md` §2 인용 블록 + `hooks/session-start.sh` standard/strict Always-On 9번 항목 추가
- 그러나 **이번 세션(2026-05-23 jayst 병렬 worktree 실험)에서 leader 였던 메인 Claude 가 두 teammate에 수동으로 shutdown_request 를 발송해야 했다**. SKILL 미경유 일반 Agent Teams 사용 경로에서 leader 자각이 약함.
- 좀비 증거: `~/.claude/teams/` 에 `mill-zip-review`, `yeongjong-life-dev` 디렉토리 잔존 — 이전 세션의 미정리 팀.

## Problem

1. **Hook 은 SendMessage 도구 호출 불가** — 자동 shutdown 발송은 hook level 에서 불가능.
2. **leader 자각 mechanism 약함** — session-start 메시지에 1줄 들어가 있으나, 일반 Agent Teams 워크플로우 (orchestrator skill 미경유) 에서는 turn 진행 중 잊기 쉬움.
3. **좀비 누적 가시성 0** — `~/.claude/teams/` 잔존 디렉토리를 audit 하는 메커니즘 없음. 다음 세션 시작 시도 알리지 않음.
4. **Antipattern 카탈로그 누락** — `nova-antipatterns.md` 에 "팀 spawn 후 shutdown 누락" 항목 없음. self-audit·`/nova:check` 에서 잡히지 않음.

## Solution

### 1a — Hook level 자각 강제

**새 hook 스크립트**: `hooks/audit-teammates.sh`
- 호출 시점: `hooks/stop-event.sh` (turn 종료) + `hooks/session-start.sh` (세션 시작)
- 동작:
  1. `~/.claude/teams/` 디렉토리 스캔 (없으면 silent exit 0)
  2. 각 팀의 `config.json` 읽고 `members[]` 존재 + `lead_agent_id` 확인
  3. 활성 팀 ≥1 시:
     - stderr WARN: `[nova:audit] 미정리 teammate 팀 N개 — leader shutdown_request 미발송 의심: <team1>, <team2>...`
     - `record-event.sh teammate_orphan` 기록
     - `NOVA_DESKTOP_NOTIFY=1` 시 desktop notification (기존 stop-event.sh 패턴 재사용)
- safe-default: jq 미설치/파싱 실패 시 silent exit 0

**`hooks/stop-event.sh` 갱신**: `audit-orchestration.sh` 호출 후 `audit-teammates.sh` 호출 추가 (병렬 호출, 둘 다 exit 0).

### 1b — Always-On 규칙 강화 + Antipattern 등록

1. **`hooks/session-start.sh` lean profile** 에도 9번 규칙 추가 (현재 standard/strict 만 보유).
2. **`docs/nova-antipatterns.md` § B7** 신설: "팀 spawn 후 shutdown 누락"
3. **`hooks/session-start.sh`** ADDITIONAL_CONTEXT 끝에 좀비 팀 카운트 1줄 inject (있을 때만, 없으면 미표시).

## Out of scope (이번 사이클)

- 자동 `TeamDelete` / `worktree prune` — hook level 안전 불가, 사용자 의도 확인 필요. `NOVA_AUTO_CLEAN_TEAMS=1` 환경변수는 후속 사이클.
- `Friction #4` (runner 보고 vs 실제 상태 일치성) — 별도 작업으로 분리.
- `Friction #5` (worktree venv 자동 링크) — `nova:worktree-setup` skill 확장으로 분리.

## File-by-file 변경 예상

| File | 변경 |
|------|------|
| `hooks/audit-teammates.sh` | NEW. ~50줄. audit-orchestration.sh 패턴 미러 |
| `hooks/stop-event.sh` | audit-teammates.sh 호출 1줄 추가 |
| `hooks/session-start.sh` | lean profile ADDITIONAL_CONTEXT 9번 항목 추가 + 좀비 카운트 inject 로직 |
| `docs/nova-antipatterns.md` | § B7 "팀 spawn 후 shutdown 누락" 신설 |
| `docs/nova-rules.md` | §2 인용 블록에 audit-teammates.sh 코드화 위치 추가 (1줄) |
| `tests/test-scripts.sh` | 회귀 가드 4건 추가 (audit-teammates.sh 존재·dryrun·session-start lean 키워드·antipatterns B7) |
| `.claude-plugin/plugin.json` | 버전 5.47.8 → 5.47.9 (release.sh patch 자동 처리) |

## 검증 명령

```bash
# 1. audit-teammates.sh dry run (좀비 없는 상태)
NOVA_DISABLE_EVENTS=1 bash hooks/audit-teammates.sh

# 2. 좀비 시뮬레이션 (~/.claude/teams/test-zombie/config.json 임시 생성)
mkdir -p ~/.claude/teams/test-zombie
echo '{"team_name":"test-zombie","members":[{"name":"x"}]}' > ~/.claude/teams/test-zombie/config.json
bash hooks/audit-teammates.sh 2>&1 | grep "미정리 teammate"
rm -rf ~/.claude/teams/test-zombie

# 3. session-start.sh lean profile 키워드
NOVA_PROFILE=lean bash hooks/session-start.sh | grep -F "shutdown_request 의무"

# 4. 회귀 가드
bash tests/test-scripts.sh

# 5. audit
bash scripts/audit-agent-tools.sh
```

## 복잡도

- 7 파일 변경 → **보통(3~7) 상위**. Plan ✅ (이 문서).
- Design 문서 별도 작성 (다음 단계).
- 단일 트랙, 단일 sprint 로 완주 가능.
- Evaluator: nova:qa-engineer 독립 서브에이전트 호출.

## 일정

- Plan ✅ (지금)
- Design → 30분
- 구현 → 1시간
- Evaluator → 20분
- 릴리스 patch v5.47.9 → 10분
