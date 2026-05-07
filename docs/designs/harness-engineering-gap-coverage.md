# [Design] 하네스 엔지니어링 갭 보강 — Sprint 1/2a/2b 기술 설계

> Nova Engineering — CPS Framework (Design)
> 작성일: 2026-04-19
> 작성자: Nova Main Agent
> Plan: `docs/plans/harness-engineering-gap-coverage.md`
> 대상: Sprint 1 (관찰성) + Sprint 2a (도구 제약 정적) + Sprint 2b (PreToolUse 런타임 차단). Sprint 0은 v5.11.1로 완료.
> U1 해소: `docs/unknowns-resolution.md` — plugin.json permission 공식 미지원 확정 → Sprint 2b를 PreToolUse 훅 차단으로 승격.

---

## Context (설계 배경)

### Plan 요약
Plan은 Nova를 하네스 엔지니어링 **상위집합**으로 정립하기 위해 두 갭을 해소한다:
- **관찰성 부재** (docs/nova-engineering.md §9 "실측 없음" 부채) → `.nova/events.jsonl` 기반 KPI 4종 자동 산출
- **도구 제약 미구현** (하네스 `constrain` 원칙) → agent 선언 감사 + PreToolUse 훅 실제 차단 + settings 템플릿

### 설계 원칙
1. **플러그인 배포 일관성**: 모든 산출물은 `hooks/`, `.claude/commands/*`, `.claude/skills/*`, `scripts/`, `docs/nova-rules.md`, `.claude-plugin/plugin.json`, `.gitignore`, `tests/` 경로에만. CLAUDE.md 건드리지 않음.
2. **수동 설정 금지**: 기본 상태에서 이벤트 기록 동작(Sprint 1은 opt-out). 도구 제약은 `/nova:setup --permissions` opt-in.
3. **Privacy-first**: 정규식 필터 14종 + 엔트로피 휴리스틱 + `{"redacted":true}` 마커. Base64 인코딩 우회까지 방어.
4. **Safe-default for 관찰성 실패**: `record-event.sh` 실패는 상위 skill을 죽이지 않음(stderr WARN + exit 0). 기록 실패가 파이프라인 장애로 전파되지 않게.
5. **Safe-default for 도구 제약 실패**: `precheck-tool.sh` 자체 실패도 `exit 0`(도구 실행 허용). 관찰성 WARN만. 훅 고장이 사용자 작업을 마비시키지 않게.
6. **역할 분담**: NOVA-STATE.md(사람용 상위 요약) × `.nova/events.jsonl`(기계용 원자 이벤트). 이중화 아님.
7. **U1 결과 반영**: plugin.json `tool_contract`은 **문서 필드**로만(enforce 아님). 실제 강제는 `.claude/settings.json` PreToolUse 훅으로.

---

## Problem (설계 과제)

### 기술적 과제
| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| T1 | 이벤트 스키마 v1 확정(11종) + JSON Schema 작성 | Medium | 모든 스킬 호출처가 이 스키마 준수 |
| T2 | `record-event.sh` bash/python3 하이브리드(JSON escape, flock+mkdir fallback, privacy filter, rotation race-safe) | High | `python3`(JSON escape) + `flock`(macOS fallback 필요) |
| T3 | KPI 4종 산출 `nova-metrics.sh` 구현 (bash + jq) | Medium | `jq` 필수, `rules-changelog.md` 파싱 |
| T4 | Privacy 14 정규식 + 엔트로피 휴리스틱 | Medium | `python3` 또는 `awk` for entropy |
| T5 | `audit-agent-tools.sh` — frontmatter vs plugin.json 대조 | Low | `jq`, `yq` 또는 awk frontmatter 파싱 |
| T6 | `permissions-template.json` 설계 — PreToolUse 훅 엔트리 + Bash denylist | Medium | Claude Code settings 스키마 |
| T7 | `/nova:setup --permissions` — jq 기반 merge(합집합, 충돌 deny 우선, stderr 리포트) | High | `jq` 필수 |
| T8 | `precheck-tool.sh` — stdin JSON 파싱, policy 평가, exit 2 차단, violation 이벤트 | High | `jq` 필수, record-event.sh 연계 |
| T9 | 기존 skill 3종(evaluator/orchestrator/context-chain)의 호출 지점에 record-event.sh 삽입 | Low | Sprint 0에서 on-demand 선언 완료 |
| T10 | docs/nova-rules.md §11/§12 신설 + session-start.sh 1줄 요약 추가 (예산 내) | Medium | 예산 확인: 1766 + 새 요약 1줄 ≤ 1900 bytes |
| T11 | docs/nova-engineering.md §9 "실측 없음" 제거 + nova-metrics.sh 참조 | Low | Sprint 1 Exit 후 |

### 기존 시스템과의 접점
- `hooks/hooks.json` — Stop 후크 추가(session_end), 기존 PreToolUse 훅에 precheck-tool.sh 엔트리 병행
- `.claude/skills/evaluator/SKILL.md` / `orchestrator/SKILL.md` / `context-chain/SKILL.md` — 판정·Phase 전이·NOVA-STATE 갱신 시점에 record-event.sh 호출 지시
- `scripts/bump-version.sh` + `scripts/generate-meta.sh` — 건드리지 않음(기존 릴리스 파이프라인 영향 없음)
- `tests/test-scripts.sh` — V2~V30 중 해당 스프린트 테스트 추가(기존 309 테스트 유지)
- `.claude/commands/next.md` — `scripts/nova-metrics.sh` 출력 1줄 요약 포함

---

## Solution (설계 상세)

### 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                        Nova Session                              │
│                                                                  │
│  evaluator/orchestrator/context-chain SKILL.md                   │
│              │                                                   │
│              ▼ 호출                                              │
│  hooks/record-event.sh <type> <phase> <result> <extra_json>     │
│   │                                                              │
│   ├─ NOVA_DISABLE_EVENTS=1 → exit 0 (opt-out)                   │
│   ├─ Privacy filter (14 regex + entropy)                        │
│   ├─ JSON escape (python3/jq)                                    │
│   ├─ Lock (flock -x OR mkdir fallback)                          │
│   ├─ Rotation check (size/count/age)                            │
│   └─ append → .nova/events.jsonl (chmod 600, schema_version=1)  │
│                                                                  │
│  hooks/hooks.json → Stop 후크 → session_end 이벤트              │
│                                                                  │
│  .claude/settings.json → PreToolUse → scripts/precheck-tool.sh  │
│   ├─ policy 평가(settings.json의 permissions allow/deny)         │
│   ├─ 위반 시 exit 2 + stderr 이유 + tool_constraint_violation    │
│   └─ 허용 시 exit 0                                              │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  scripts/nova-metrics.sh ── reads .nova/events.jsonl             │
│   ├─ process_consistency                                         │
│   ├─ gap_detection_rate                                          │
│   ├─ rule_evolution_rate (rules-changelog.md 병용)              │
│   ├─ multi_perspective_impact                                    │
│   └─ tool_violation_rate (Sprint 2b 이후, 선택)                  │
│       ↓                                                          │
│  /nova:next 출력 1줄 요약                                        │
│                                                                  │
│  scripts/audit-agent-tools.sh (정적 감사)                        │
│   ├─ .claude/agents/*.md frontmatter vs                          │
│   └─ .claude-plugin/plugin.json tool_contract 대조              │
└──────────────────────────────────────────────────────────────────┘
```

---

### 데이터 모델 — 이벤트 스키마 v1

#### 공통 필수 필드 (모든 이벤트)

| 필드 | 타입 | 단위/포맷 | 변환 규칙 |
|------|------|----------|----------|
| `schema_version` | int | 1 고정 | 스키마 bump 시 major 버전 올림 |
| `timestamp` | string | ISO 8601 UTC (`2026-04-19T12:34:56.789Z`) | `date -u +%Y-%m-%dT%H:%M:%S.%3NZ`, GNU/BSD 양쪽 호환 |
| `timestamp_epoch` | int | Unix epoch seconds | `date -u +%s` (nova-metrics의 윈도우 필터용) |
| `monotonic_ns` | int | nanoseconds (wallclock skew 보정) | `date +%s%N` (GNU) 또는 python3 fallback |
| `session_id` | string | `<sha256(cwd+pid+rand8)>` 앞 12자리 | hooks/session-start.sh 또는 최초 호출 시 1회 생성 후 `.nova/session.id` 캐시 |
| `event_type` | string | 11종 enum (아래 테이블) | — |
| `nova_version` | string | `5.11.x` | `scripts/.nova-version` 읽기 |
| `redacted` | bool | privacy 필터 적용 여부 | true이면 `redaction_reasons` 배열 동반 |
| `extra` | object | event_type별 필드 | 아래 각 타입 섹션 참조 |

#### 이벤트 타입 11종 + extra 필드

| # | event_type | extra 필수 필드 | 기록 주체 | 트리거 |
|---|-----------|----------------|----------|--------|
| 1 | `session_start` | `cwd_hash` | hooks/session-start.sh | SessionStart 후크 |
| 2 | `session_end` | `duration_ms`, `exit_reason` | hooks/stop-event.sh (신규) | Stop 후크 |
| 3 | `phase_transition` | `orchestration_id`, `phase_name`, `from_status`, `to_status` | orchestrator 스킬 | Phase 전이 |
| 4 | `evaluator_verdict` | `verdict` (PASS/CONDITIONAL/FAIL), `critical_issues` (int), `target` (code/plan/design), `sprint` (optional) | evaluator 스킬 | 판정 직후 |
| 5 | `sprint_started` | `sprint_name`, `planned_files` (int) | run/auto 커맨드 | 스프린트 착수 |
| 6 | `sprint_completed` | `sprint_name`, `verdict`, `regression_tests_pass` (bool) | run/auto 커맨드 | 스프린트 종료 |
| 7 | `blocker_raised` | `blocker_type` (auto-resolve/soft/hard), `cause` | 모든 커맨드 | §7 분류 |
| 8 | `blocker_resolved` | `blocker_type`, `resolution` | 모든 커맨드 | 해소 |
| 9 | `plan_created` | `path`, `mode` (plan/deep), `iterations` (int), `critic_resolved` (bool) | plan/deepplan | Phase E 완료 |
| 10 | `jury_verdict` | `consensus_level` (strong/partial/divergent), `changed_direction` (bool) | ask/jury | 판정 직후 |
| 11 | `tool_constraint_violation` | `agent`, `tool_attempted`, `declared_tools` (array), `input_preview` (200자 preview) | precheck-tool.sh (Sprint 2b) | 위반 감지 시 |

#### 예시 (session_start)

```json
{
  "schema_version": 1,
  "timestamp": "2026-04-19T12:34:56.789Z",
  "timestamp_epoch": 1776605696,
  "monotonic_ns": 1776605696789012000,
  "session_id": "a7b9c2e4f1d3",
  "event_type": "session_start",
  "nova_version": "5.12.0",
  "redacted": false,
  "extra": {
    "cwd_hash": "3f2a8b1c"
  }
}
```

#### 예시 (evaluator_verdict)

```json
{
  "schema_version": 1,
  "timestamp": "2026-04-19T13:02:15.456Z",
  "timestamp_epoch": 1776607335,
  "monotonic_ns": 1776607335456789000,
  "session_id": "a7b9c2e4f1d3",
  "event_type": "evaluator_verdict",
  "nova_version": "5.12.0",
  "redacted": false,
  "extra": {
    "verdict": "PASS",
    "critical_issues": 0,
    "target": "code",
    "sprint": "Sprint 1"
  }
}
```

---

### scripts/hooks API 계약

#### 1. `hooks/record-event.sh <event_type> <extra_json>`

**인자**: `$1` event_type (11종 enum), `$2` extra JSON (stringified)
**환경변수**:
- `NOVA_DISABLE_EVENTS=1` → 즉시 exit 0, 기록 생략
- `NOVA_EVENTS_PATH=<path>` → 기본 `.nova/events.jsonl` 대신 지정 경로 사용
- `CI=true` → 자동으로 `${CI_ARTIFACTS:-.}/nova-events/events.jsonl`로 치환

**동작**:
```bash
if [[ -n "$NOVA_DISABLE_EVENTS" ]]; then exit 0; fi
# 1. session_id 로드 (없으면 생성 + .nova/session.id 캐시)
# 2. 공통 필드 조립 (timestamp/epoch/monotonic/nova_version 등)
# 3. extra에 privacy 필터 적용 (Appendix A)
# 4. 전체를 jq -cn '{schema_version:1, ...}'로 JSON 완성
# 5. flock -x OR mkdir fallback으로 .nova/.lock 획득 (최대 3초)
# 6. rotation 체크 (size/count/age)
# 7. append (printf '%s\n' "$line" >> .nova/events.jsonl)
# 8. flock 해제
# 실패 시: stderr로 "[nova:event] WARN: {reason}" + exit 0
exit 0  # 항상 성공
```

**에러 처리**: 어떤 에러도 non-zero exit 금지. stderr WARN만.

#### 2. `scripts/nova-metrics.sh [--since 7d|30d|all] [--fixture <path>]`

**입력**: `.nova/events.jsonl` (기본) 또는 `--fixture` 경로
**출력**:
```
Process consistency:    78% (n=41)
Gap detection rate:     85% (n=13)
Rule evolution rate:    N/A (insufficient data)
Multi-perspective:      62% (n=8)
```

**구현 규칙** (Appendix B의 의사코드 참조):
- 각 KPI 개별 함수로 분리 (`calc_process_consistency`, `calc_gap_detection_rate`, ...)
- 분모 0이면 `N/A (insufficient data)` 출력
- `bootstrap=true` 이벤트 이전 기간은 분모에서 제외(기존 사용자 보정)
- 소수점 1자리 + 표본 크기(n=…) 병기

#### 3. `scripts/audit-agent-tools.sh`

**입력**: `.claude/agents/*.md` (5개) + `.claude-plugin/plugin.json`
**출력** (성공 시):
```
[audit] 5/5 agents have frontmatter tools declaration
[audit] plugin.json tool_contract.per_agent matches frontmatter
```
**출력** (실패 시):
```
[audit] FAIL: architect.md frontmatter tools=[Read,Glob,Grep,Agent,WebSearch] vs plugin.json per_agent.architect=[Read,Glob,Grep,Agent,WebSearch,WebFetch] — diff: +WebFetch
exit 1
```

#### 4. `scripts/precheck-tool.sh` (Sprint 2b, PreToolUse 훅)

**입력**: stdin JSON `{tool: "Bash(rm -rf ...)", input: "...", agent_id: "..."}`
**참조**: `.claude/settings.json`의 `permissions.deny`와 `permissions.allow` 배열
**동작**:
```bash
# 1. stdin 읽기 + jq로 tool 추출
# 2. settings.json의 deny 패턴과 비교 (glob 매칭)
# 3. 위반 시:
#    - stderr: "[nova:precheck] DENIED: Bash(rm -rf ...) — policy: permissions.deny"
#    - record-event.sh tool_constraint_violation '{"agent":"...","tool_attempted":"...","declared_tools":[...]}'
#    - exit 2 (PreToolUse에서 exit 2는 도구 실행 차단)
# 4. 허용 시: exit 0
# 5. 자체 오류(settings.json 없음/jq 없음):
#    - stderr WARN
#    - exit 0 (safe-default: 도구 허용)
```

#### 5. `scripts/permissions-template.json`

**구조** (Sprint 2a에서 정적, Sprint 2b에서 훅 엔트리 활성):
```json
{
  "permissions": {
    "defaultMode": "ask",
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -rf /*)",
      "Bash(:(){ :|:&};:)",
      "Bash(curl * | sh)",
      "Bash(wget * | sh)",
      "Bash(chmod 777 *)",
      "Bash(sudo *)"
    ],
    "allow": [
      "Bash(bash hooks/*.sh)",
      "Bash(bash scripts/*.sh)",
      "Bash(bash tests/*.sh)",
      "Read(*)",
      "Grep(*)",
      "Glob(*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/precheck-tool.sh\""
          }
        ]
      }
    ]
  }
}
```

**주의**: `hooks.PreToolUse` 블록은 Sprint 2a에서는 **주석만** 포함(참조 경로 placeholder). Sprint 2b에서 `scripts/precheck-tool.sh`가 추가된 후 실제 엔트리 활성.

#### 6. `/nova:setup --permissions` merge 알고리즘

**입력**: 사용자 기존 `.claude/settings.json` (없으면 `{}`) + `scripts/permissions-template.json`
**출력**: 병합된 `.claude/settings.json` + stderr에 충돌 리포트

**구현 의사코드** (jq):
```bash
jq --slurpfile tpl scripts/permissions-template.json \
   --slurpfile usr .claude/settings.json \
   '
def merge_arrays(a; b):
  (a + b) | unique;

def conflict_report(user_allow; nova_deny):
  [user_allow[] as $ua | select(nova_deny | index($ua))];

def merge_permissions(u; t):
  {
    defaultMode: (u.defaultMode // t.defaultMode),
    allow: merge_arrays(u.allow // []; t.allow // []),
    deny: merge_arrays(u.deny // []; t.deny // [])
  };

. + {
  permissions: merge_permissions($usr[0].permissions // {}; $tpl[0].permissions),
  hooks: ($usr[0].hooks // {}) + ($tpl[0].hooks // {})
}
' .claude/settings.json > .claude/settings.json.new

# 충돌 리포트 (stderr)
jq -n --slurpfile usr .claude/settings.json --slurpfile tpl scripts/permissions-template.json '
  ($usr[0].permissions.allow // []) as $ua |
  ($tpl[0].permissions.deny // []) as $nd |
  [$ua[] as $a | select($nd | index($a))]
' | jq -r '.[]' | while read conflict; do
  echo "[nova:setup] CONFLICT: \"$conflict\" in user allow + Nova deny → deny wins" >&2
done

mv .claude/settings.json.new .claude/settings.json
```

---

### 에러 처리 정책 (요약)

| 컴포넌트 | 에러 상황 | 동작 |
|----------|----------|------|
| `record-event.sh` | 권한 거부 / 디스크 풀 / flock 타임아웃 / privacy 필터 실패 | stderr WARN + **exit 0** (관찰성이 파이프라인을 죽이지 않음) |
| `record-event.sh` | `NOVA_DISABLE_EVENTS=1` | 즉시 exit 0, WARN 없음 |
| `nova-metrics.sh` | 빈 JSONL | 4 KPI 모두 `N/A (insufficient data)` + exit 0 |
| `nova-metrics.sh` | JSONL 파싱 실패 라인 | 해당 라인 skip + stderr WARN + 계속 |
| `audit-agent-tools.sh` | 불일치 감지 | stderr 상세 diff + **exit 1** (CI 실패 유도) |
| `audit-agent-tools.sh` | `jq` 없음 | stderr "install jq" + exit 2 |
| `precheck-tool.sh` | 정책 위반 | stderr DENIED + JSONL violation + **exit 2** (도구 차단) |
| `precheck-tool.sh` | 스크립트 자체 오류 (settings.json 없음 등) | stderr WARN + **exit 0** (safe-default) |
| `/nova:setup --permissions` | `jq` 없음 | stderr "install jq" + exit 2 |
| `/nova:setup --permissions` | 충돌 항목 | stderr CONFLICT 리포트 + merge 진행 (deny 우선) |

---

## Data Contract (데이터 계약)

> Sprint 1/2a/2b 구현자가 잘못된 가정을 하지 않도록 **반드시** 준수.

### 타임스탬프 필드
| 필드 | 단위 | 예 | 생성 방법 |
|------|------|-----|----------|
| `timestamp` | ISO 8601 UTC ms precision | `2026-04-19T12:34:56.789Z` | `date -u +%Y-%m-%dT%H:%M:%S.%3NZ` (GNU) / BSD는 python3 fallback |
| `timestamp_epoch` | Unix seconds (int) | `1776605696` | `date -u +%s` |
| `monotonic_ns` | 나노초 (wallclock skew 불문 강단조 증가) | `1776605696789012000` | GNU: `date +%s%N` / BSD: python3 `time.monotonic_ns()` |
| `duration_ms` | 밀리초 (세션 지속 시간) | `4830120` | `session_end - session_start` (epoch 차이 * 1000) |

### 식별자 필드
| 필드 | 생성 규칙 | 유효 범위 |
|------|----------|----------|
| `session_id` | `sha256(cwd + pid + /dev/urandom[0:8])[0:12]` | 단일 세션 내 유지 (`.nova/session.id` 캐시) |
| `cwd_hash` | `sha256(realpath(cwd))[0:8]` | 프로젝트별 고정 (로그 분석 시 경로 누출 방지) |
| `orchestration_id` | `orchestration_start` MCP 도구 응답의 `orch-*` | Phase 전이 이벤트 간 연결 키 |

### Boolean/Enum 필드
| 필드 | 값 | 대소문자 |
|------|-----|---------|
| `verdict` | `"PASS"`, `"CONDITIONAL"`, `"FAIL"` | 대문자 고정 |
| `consensus_level` | `"strong"`, `"partial"`, `"divergent"` | 소문자 고정 |
| `blocker_type` | `"auto-resolve"`, `"soft"`, `"hard"` | 소문자 + 하이픈 |
| `mode` (plan_created) | `"plan"`, `"deep"` | 소문자 고정 |
| `target` (evaluator_verdict) | `"code"`, `"plan"`, `"design"` | 소문자 고정 |
| `redacted` | `true` / `false` | bool |

### KPI 계산 정의 (확정)

| KPI | 분자 | 분모 | 제외 조건 |
|-----|------|------|----------|
| `process_consistency` | sprint_completed 이벤트 중 같은 `orchestration_id`에 **이전 timestamp의 plan_created** 존재 | `planned_files >= 3`인 sprint_completed 총수 | 분모 0 → N/A |
| `gap_detection_rate` | evaluator_verdict=FAIL 이벤트 중 **같은 orchestration_id 내 이후 timestamp에 sprint_completed(verdict=PASS) 또는 phase_transition(to_status=completed)** 존재 | evaluator_verdict=FAIL 총수 | 분모 0 → N/A |
| `rule_evolution_rate` | `docs/rules-changelog.md`에서 `^## .* — approved` 라인 수 | `^## .* — proposed` 라인 수 | 분모 0 → N/A. v2 스키마에 `rule_proposed`/`rule_approved` 이벤트 추가 시 교체 |
| `multi_perspective_impact` | jury_verdict 중 `changed_direction=true` | jury_verdict 총수 | 분모 0 → N/A |
| `tool_violation_rate` (Sprint 2b, 선택) | tool_constraint_violation 이벤트 수 | 총 tool_use 시도 수 (이벤트 없음 → precheck-tool 통과 로그로 추정) | v1에서는 `tool_violation_count` 절대값만 출력 |

---

## Sprint Contract (스프린트별 검증 계약)

> **구현 전에 합의. 구현 후에 검증. Evaluator는 아래 테이블을 체크리스트로 사용.**

### Sprint 1 — 관찰성 레이어

| # | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|---|----------|----------|----------|---------|
| S1.1 | `.nova/events.jsonl`이 생성되고 최소 3라인 기록 | `/nova:run` 후 라인 수 확인 | `/nova:run >/dev/null 2>&1 && [ $(wc -l < .nova/events.jsonl) -ge 3 ]` | Critical |
| S1.2 | 11 이벤트 타입 중 3종 이상(session_start/phase_transition/evaluator_verdict) 관찰 | `jq` event_type 추출 | `jq -r '.event_type' .nova/events.jsonl \| sort -u \| wc -l` ≥ 3 | Critical |
| S1.3 | 모든 JSONL 라인 parse 가능 + 필수 필드 포함 | `jq -c '.schema_version,.timestamp,.session_id,.event_type'` 전수 non-null | `jq -c 'select(.schema_version==null or .timestamp==null)' events.jsonl \| wc -l` == 0 | Critical |
| S1.4 | Privacy 필터 — sk-ant / sk-proj / ghp_ / xoxb- / sk_live_ / AIza / AKIA / eyJ / Base64 인코딩 sk- / aws_secret 10종 모두 redacted | fixture 10종 입력 | `bash tests/privacy-fixture.sh \| jq '.redacted' \| grep -c true` == 10 | Critical |
| S1.5 | 동시성 — xargs -P 20 append 후 S1.3 재실행 PASS | 병렬 스모크 | `seq 20 \| xargs -P 20 -I{} bash hooks/record-event.sh phase_transition '{}' && jq -s '.' events.jsonl > /dev/null` | Critical |
| S1.6 | Rotation 트리거 — 9.99MB fixture + append → 2 파일, 새 파일 첫 라인에 `rotation_from` 마커 | rotation 트리거 | `bash tests/rotation-fixture.sh && ls .nova/events*.jsonl \| wc -l` ≥ 2 + `jq '.rotation_from' <events.jsonl \| head -1` non-null | High |
| S1.7 | KPI 스냅샷 일치 — 고정 fixture → expected 값 정확 일치 | fixture 비교 | `diff <(bash scripts/nova-metrics.sh --fixture tests/events-fixture.jsonl) tests/metrics-expected.txt` | Critical |
| S1.8 | `.gitignore`에 `.nova/events*.jsonl` 포함 | — | `grep -q '.nova/events' .gitignore` | High |
| S1.9 | `NOVA_DISABLE_EVENTS=1`에서 `/nova:run` → JSONL 0 라인 | 옵트아웃 확인 | `rm -f .nova/events.jsonl; NOVA_DISABLE_EVENTS=1 /nova:run >/dev/null 2>&1; [ ! -s .nova/events.jsonl ]` | High |
| S1.10 | 기록 실패 전파 — chmod 000 `.nova/` → record-event.sh stderr WARN + exit 0 | 실패 시나리오 | `mkdir -p .nova && chmod 000 .nova && bash hooks/record-event.sh session_start '{}' ; [ $? -eq 0 ]; chmod 755 .nova` | Critical |
| S1.11 | docs/nova-engineering.md §9 — "실측 없음" 제거 + `scripts/nova-metrics.sh` 참조 | grep | `grep -q 'scripts/nova-metrics.sh' docs/nova-engineering.md && ! grep -q '실측 결과가 아니다' docs/nova-engineering.md` | High |
| S1.12 | session-start.sh 1766 + §11 1줄 요약 ≤ 1900 bytes | 예산 확인 | `bash hooks/session-start.sh \| wc -c` ≤ 1900 | Critical |
| S1.13 | nova-rules.md §10 "관찰성 계약" 신설 (§10이 환경안전 §9 다음 신설됨 — Plan에서 §11로 표기했으나 구현은 §10) | grep | `grep -q '^## §10' docs/nova-rules.md` | Critical |
| S1.14 | 309+ 회귀 테스트 전수 PASS | 회귀 | `bash tests/test-scripts.sh \| tail -1 \| grep -q 'ALL PASS'` | Critical |

### Sprint 2a — 도구 제약 정적

| # | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|---|----------|----------|----------|---------|
| S2a.1 | 5개 agent 모두 frontmatter `tools:` 선언 + Sprint 2 마커 | grep | `for f in .claude/agents/*.md; do grep -q "^tools:" "$f" \|\| exit 1; done` | Critical |
| S2a.2 | `scripts/audit-agent-tools.sh` exit 0 (기본 상태) | audit | `bash scripts/audit-agent-tools.sh` | Critical |
| S2a.3 | `scripts/permissions-template.json` 존재 + 유효 JSON + `permissions.deny` 7개 이상 | jq | `jq '.permissions.deny \| length' scripts/permissions-template.json` ≥ 7 | Critical |
| S2a.4 | `/nova:setup --permissions` 빈 프로젝트 fixture — settings.json 생성 + Nova 템플릿 전량 반영 | fixture 1 | `rm -f test.settings.json; bash scripts/setup-permissions.sh --target test.settings.json && [ $(jq '.permissions.deny \| length' test.settings.json) -ge 7 ]` | Critical |
| S2a.5 | `/nova:setup --permissions` 기존 allow 있는 fixture — 사용자 allow 보존 + Nova deny 추가 | fixture 2 | `cp tests/fixtures/settings-with-allow.json test.settings.json; bash scripts/setup-permissions.sh --target test.settings.json && jq '.permissions.allow \| contains(["Bash(git status)"])' test.settings.json` == true | Critical |
| S2a.6 | `/nova:setup --permissions` 충돌 fixture — deny 우선 + stderr CONFLICT 리포트 1건 | fixture 3 | `cp tests/fixtures/settings-with-conflict.json test.settings.json; bash scripts/setup-permissions.sh --target test.settings.json 2>&1 \| grep -c 'CONFLICT'` ≥ 1 | Critical |
| S2a.7 | `docs/nova-rules.md §12 "도구 제약 계약"` 신설 + fewer-permission-prompts 역할 분담 명시 | grep | `grep -q '^## §12' docs/nova-rules.md && grep -q 'fewer-permission-prompts' docs/nova-rules.md` | Critical |
| S2a.8 | `plugin.json tool_contract` 필드 존재 + 주석(미지원 명시) | jq | `jq '.tool_contract' .claude-plugin/plugin.json` non-null + source에 "공식 스키마 미지원" 주석 | High |
| S2a.9 | `.claude/commands/setup.md` `--permissions` 옵션 문서화 | grep | `grep -q -- '--permissions' .claude/commands/setup.md` | Critical |
| S2a.10 | 309+ 회귀 전수 PASS | 회귀 | `bash tests/test-scripts.sh \| tail -1 \| grep -q 'ALL PASS'` | Critical |

### Sprint 2b — 도구 제약 런타임 (PreToolUse 차단)

| # | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|---|----------|----------|----------|---------|
| S2b.1 | `scripts/precheck-tool.sh` 존재 + 실행 권한 | — | `[ -x scripts/precheck-tool.sh ]` | Critical |
| S2b.2 | 허용 도구(`Read`) → exit 0 | 허용 경로 | `echo '{"tool":"Read","input":{}}' \| bash scripts/precheck-tool.sh; [ $? -eq 0 ]` | Critical |
| S2b.3 | 위반 도구(`Bash(rm -rf *)`) → exit 2 + stderr DENIED + JSONL violation | 차단 경로 | `echo '{"tool":"Bash(rm -rf /tmp/*)","input":{}}' \| bash scripts/precheck-tool.sh 2>&1; [ $? -eq 2 ] && tail -1 .nova/events.jsonl \| jq -r '.event_type' \| grep -q tool_constraint_violation` | Critical |
| S2b.4 | 자체 오류(settings.json 없음) → exit 0 + stderr WARN (safe-default) | 실패 시나리오 | `mv .claude/settings.json .claude/settings.json.bak; echo '{"tool":"Bash(echo)","input":{}}' \| bash scripts/precheck-tool.sh; code=$?; mv .claude/settings.json.bak .claude/settings.json; [ $code -eq 0 ]` | Critical |
| S2b.5 | `permissions-template.json` PreToolUse 훅 엔트리 활성 (placeholder → 실 스크립트) | jq | `jq '.hooks.PreToolUse[0].hooks[0].command' scripts/permissions-template.json \| grep -q precheck-tool.sh` | Critical |
| S2b.6 | `hooks/record-event.sh`가 `tool_constraint_violation` 타입 accept | schema 테스트 | `bash hooks/record-event.sh tool_constraint_violation '{"agent":"test","tool_attempted":"Bash(rm)","declared_tools":["Read"]}' && tail -1 .nova/events.jsonl \| jq -r '.event_type' \| grep -q tool_constraint_violation` | Critical |
| S2b.7 | evaluator SKILL.md에 "사후 감사: tool_constraint_violation 쿼리" 섹션 + jq 예시 | grep | `grep -q 'tool_constraint_violation' .claude/skills/evaluator/SKILL.md` | High |
| S2b.8 | 훅 지연 벤치 — 100ms 이내 (Sprint 1 R13 완화) | time | `time (echo '{"tool":"Read","input":{}}' \| bash scripts/precheck-tool.sh)` real ≤ 0.1s | Nice |
| S2b.9 | 309+ 회귀 전수 PASS | 회귀 | `bash tests/test-scripts.sh \| tail -1 \| grep -q 'ALL PASS'` | Critical |

---

## 관통 검증 조건 (End-to-End)

> 입력 → 저장 → 집계 → 표시 4단 완전성.

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| E1 | `/nova:run "간단한 변경"` 실행 | `.nova/events.jsonl`에 session_start/phase_transition/evaluator_verdict 최소 3건 기록 | Critical |
| E2 | Sprint 1 완료 후 `/nova:next` 호출 | 출력 하단에 `KPI: process_consistency=…%, gap_detection_rate=…%` 1줄 요약 표시 | Critical |
| E3 | `/nova:ask "test"` 실행 (jury verdict 발생) | `.nova/events.jsonl`에 `jury_verdict` 이벤트 기록 + nova-metrics.sh `multi_perspective_impact` 반영 | Critical |
| E4 | `/nova:setup --permissions` 후 `echo '{"tool":"Bash(rm -rf /)","input":{}}' \| precheck-tool.sh` | exit 2 + stderr DENIED + `.nova/events.jsonl`에 `tool_constraint_violation` 기록 | Critical (Sprint 2b) |
| E5 | 연속 3회 `/nova:run` 실행 → 30일 윈도우에 축적 | `scripts/nova-metrics.sh --since 30d` 출력이 N/A가 아닌 실제 수치 (n=3+) | High |

---

## 평가 기준 (Evaluation Criteria)

- **기능**: Sprint 1/2a/2b 각 Sprint Contract 전수 충족
- **데이터 관통**: E1~E5 전 경로 실측 PASS
- **설계 품질**: 스키마 v1이 v2 확장 시 back-compat 깨지지 않음 (`schema_version` 분기)
- **단순성**: 스크립트 파일당 300라인 이하. 11 이벤트 타입 외 확장은 Sprint 3(해당 없음)으로 미룸.
- **Privacy 커버리지**: 14 정규식 + 엔트로피 휴리스틱 + fixture 8종 이상 PASS
- **플러그인 배포 일관성**: CLAUDE.md 건드리지 않음. 모든 변경이 사용자 전달 경로에 있음.
- **회귀 방지**: 309+ 기존 테스트 + Sprint별 신규 assert 전수 PASS
- **Safe-default 원칙**: record-event.sh / precheck-tool.sh 자체 오류가 사용자 작업을 마비시키지 않음

---

## 역방향 검증 체크리스트

- [ ] Plan의 Risk Map 24건 중 H/H 4건(R1/R2/R7/R9)에 대한 완화 컨트롤이 Sprint Contract에 반영됐는가? → S1.4(R1), S1.6+rotation(R2), V14 deferred 도구(R7), S1.12(R9)
- [ ] Plan의 Verification Hooks 30건 중 Critical 전수를 Sprint Contract에 흡수했는가? → V2~V7+V18~V30 매핑 완료
- [ ] Plan의 이벤트 타입 11종이 Design의 스키마 섹션에 1:1 매핑됐는가? → 위 테이블 11행 확인
- [ ] Plan의 KPI 조작적 정의 4종이 Design의 Data Contract에 공식 반영됐는가? → KPI 계산 정의 테이블 확인
- [ ] Plan의 Privacy 14 정규식이 Design에 그대로 있는가? → Appendix A 참조 (Plan Solution 섹션에 이미 완전 명세, Design은 참조)
- [ ] U1 해소 결과가 Sprint 2b 설계에 반영됐는가? → `precheck-tool.sh`로 C 경로 승격 확인
- [ ] fewer-permission-prompts 빌트인 스킬과 역할 분담이 명시됐는가? → S2a.7에서 nova-rules §12로 강제
- [ ] 누락된 엣지 케이스: R14(session_id 충돌), R15(시계 skew), R16(CRLF), R18(JSON embedded `\n`), R21(BSD flock)이 Data Contract에 반영됐는가? → 타임스탬프/식별자 필드 생성 규칙 확인

---

## Appendix A — Privacy 정규식 v1 (Plan Solution 섹션과 동일)

14 패턴 + 엔트로피 휴리스틱. Plan 본문 `docs/plans/harness-engineering-gap-coverage.md §Privacy 정규식 v1` 참조.

**구현 노트**:
- Bash ERE(`[[ =~ ]]`)로는 lookahead 미지원 → `grep -E` 또는 python3 `re` 사용
- `record-event.sh`는 `python3 -c 'import re,sys,json; ...'`로 extra_json을 입력받아 14 패턴 치환 + entropy 체크 후 출력
- entropy 계산: `scipy` 없이 bash+awk로 가능하나 python3이 가독성 우위

---

## Appendix B — KPI 의사코드 (실 스크립트는 Sprint 1 구현)

Plan Solution의 의사코드를 실 스크립트로 옮긴다. 주요 구현 노트:

- 모든 함수가 `.nova/events.jsonl` 또는 `--fixture <path>`를 인자로 받음
- `jq` `--argfile` 또는 `--slurpfile`로 윈도우 필터 적용
- `date -u -d '30 days ago' +%s`는 GNU 전용. BSD는 `date -u -v-30d +%s` — OS 감지 필요(`case $(uname) in Darwin) ... ;; Linux) ... ;; esac`)
- bootstrap 보정: `jq 'select(.event_type=="session_start" and .extra.bootstrap==true)'` 이후 이벤트만 분모

---

## Next Steps

1. Sprint 1 착수 (`/nova:run` 또는 `/nova:auto`) — Sprint Contract S1.1~S1.14 기준
2. Sprint 1 Evaluator 서브에이전트 PASS 확인 → minor 릴리스 (v5.12.0)
3. Sprint 2a 병행 가능(Sprint 1 독립) — 타이밍은 사용자 판단
4. Sprint 2b는 Sprint 1 + 2a 완료 후
5. 각 스프린트마다 별도 minor 릴리스(v5.12.0 / v5.13.0 / v5.14.0)
