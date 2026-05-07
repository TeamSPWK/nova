# [Plan] 하네스 엔지니어링 갭 보강 — 관찰성 레이어 + 도구 제약 레이어

> Nova Engineering — CPS Framework
> 작성일: 2026-04-19
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1 + U1 해소 (Critic FAIL → Refiner 1회 반영 → U1 해소 결과 반영 — 2026-04-19)
> U1 Resolution: `docs/unknowns-resolution.md` (B 미지원 확정 → C로 전환)
> Design: `docs/designs/harness-engineering-gap-coverage.md` (2026-04-19 작성, Sprint 1/2a/2b Sprint Contract 33건)

---

## Context (배경)

### 현재 상태

Nova v5.11.0은 하네스 엔지니어링의 6대 필수 요소(Generator-Evaluator 분리, 컨텍스트 리셋+handoff, Sprint Contract, 3-agent 파이프라인, 실행 검증, 피드백 루프)를 구현 + 명문화한 상태다. Anthropic의 "Harness design for long-running apps" 원문과 대조 시 Nova는 상위집합(superset)이다.

다만 하네스 엔지니어링의 상위 원칙 다섯 가지(*constrain · inform · verify · correct · human-in-the-loop*) 중 **constrain**(도구 제약)과 Nova 자체가 선언한 KPI 측정(docs/nova-engineering.md §9)의 **관찰성**이 미완성이다.

- **관찰성 부재**: NOVA-STATE.md는 사람이 읽는 상위 요약이며 기계 판독 가능한 이벤트 스트림이 없다. §9가 "도입 목표이며 실측 결과가 아니다"라고 자인한 상태 — KPI 4종(프로세스 일관성·갭 탐지율·규칙 진화율·다관점 효과)은 아직 수치로 입증되지 않는다.
- **도구 제약 미구현**: `.claude/agents/*.md` 5개가 frontmatter `tools:`를 선언하고 있으나 선언일 뿐, 플러그인 레벨 런타임 강제나 감사 경로가 없다. `.claude-plugin/plugin.json`에는 `permissions`/`tools` 필드가 없다.

### 왜 필요한가

1. **정당성**: `.claude-plugin/plugin.json`의 `keywords`에 `"harness-engineering"`이 등재됨 — 선언과 실제가 일치해야 한다.
2. **자기 진단**: Adaptive 기둥은 "규칙이 품질을 높였는가"가 측정 가능해야 진화한다.
3. **Always-On 신뢰성**: `hooks/session-start.sh`가 주입하는 6개 Always-On 행동의 실제 준수율이 측정되어야 한다.
4. **플러그인 사용자 일관성**: 플러그인 업데이트만으로 자동 적용되어야 한다. CLAUDE.md는 전달되지 않음.

### 관련 자료

- `docs/nova-engineering.md:364-375` — §9 KPI 목표(실측 없음 자인)
- `docs/nova-rules.md:53-85` — §2 Generator-Evaluator 분리
- `hooks/session-start.sh:18-26` — 현재 additionalContext 출력 3525 bytes (soft 1200/hard 2500 초과)
- `hooks/hooks.json:1-55` — SessionStart·PreCompact·PreToolUse만. PostToolUse·Stop 없음
- `.claude/agents/{architect,devops-engineer,qa-engineer,security-engineer,senior-dev}.md`
- `.claude-plugin/plugin.json` — v5.11.0, permissions/tools 필드 없음
- `.claude/skills/context-chain/SKILL.md`, `.claude/skills/evaluator/SKILL.md`, `.claude/skills/orchestrator/SKILL.md`
- `mcp-server/src/tools/orchestration-tracker.ts` — 인메모리 추적(영속 없음)

---

## Problem (문제 정의)

### 핵심 문제

Nova는 하네스 엔지니어링을 선언하지만 **(a) 실행이 측정되지 않고**, **(b) 에이전트가 다룰 수 있는 도구가 감사되지 않는다**.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| P1 | **이벤트 스트림 부재** | Evaluator 판정·Sprint 전이·블로커 발생이 NOVA-STATE 텍스트에만 기록. 구조화된 JSONL 없음 | H |
| P2 | **KPI 실측 경로 없음** | §9 KPI 4종의 데이터 소스도 스크립트도 없음 | H |
| P3 | **도구 권한 감사 부재** | agent frontmatter `tools:`가 선언만. 위배 감지·경고 경로 없음. deferred 도구(ToolSearch) 상호작용 미정의 | M |
| P4 | **플러그인 permission 템플릿 부재** | 사용자 프로젝트 `.claude/settings.json` 빈 상태. deny-by-default 권장 세트 없음 | M |
| P5 | **session-start 예산 압박** | 현재 3525 bytes, hard 2500 초과. 새 규칙 추가 시 릴리스 블로커 위험 | H (prerequisite) |
| P6 | **fewer-permission-prompts 역할 혼선** | 빌트인 스킬과 Nova 도구 제약의 경계 불명 | M |
| P7a | **Privacy 누출 리스크** | 이벤트 로그에 비밀/토큰/경로가 평문 저장될 가능성 | H |
| P7b | **디스크 무한 누적 리스크** | rotation 없으면 수 GB 누적 → OS 디스크풀 | H |
| P7c | **동시성 쓰기 리스크** | 병렬 에이전트 append 시 라인 interleaving → JSONL 파괴 | H |
| P8 | **운영 마이그레이션 부재** | 기존 사용자 업그레이드·CI 러너·규제 환경(옵트아웃) 경로 없음 | M |
| P9 | **리얼리티 부채** | 이벤트 타입 목록·KPI 조작적 정의·정규식 커버리지가 "Design으로 위임" 상태 → 구현자 해석 분산 위험 | H |

### 제약 조건

- **플러그인 배포 경로**: `hooks/`, `.claude/commands/*`, `.claude/agents/*`, `.claude/skills/*`, `.claude-plugin/plugin.json`, `docs/nova-rules.md`, `scripts/*`, `tests/*`만 사용자에게 전달. CLAUDE.md는 전달 안 됨.
- **수동 설정 금지**: 플러그인 업데이트만으로 자동 적용(메모리: `feedback_no_manual_setup`).
- **session-start 경량화**: soft 1200 / hard 2500 bytes. 현재 초과 상태 — 추가 규칙은 기존 규칙을 뺀 만큼만 넣을 수 있음(on-demand 로드 패턴).
- **NOVA-STATE.md 병행 유지**: JSONL은 기계용, NOVA-STATE.md는 사람용(상위 요약). 이중화 아닌 역할 분담.
- **런타임 강제 한계**: Claude Code가 plugin.json 레벨 permission을 enforce하는지 미확인(U1). Nova는 "선언 + 감사" 스코프로 한정하고 런타임 enforcement는 Claude Code 권한 시스템에 위임.

---

## Solution (해결 방안)

### 선택한 방안

**관찰성**: A(JSONL append-only + rotation + flock atomic write) 채택.
**도구 제약**: U1 해소 결과(2026-04-19) — plugin.json permission 필드는 **공식 미지원** 확정. `.claude/agents/*.md` frontmatter `tools:`는 **선언적 힌트**일 뿐 런타임 enforcement 없음. Claude Code 공식 런타임 enforcement 경로는 **PreToolUse 훅**이 유일하며, 우선순위는 **Managed > Project `.claude/settings.json` > User settings** 공식 정의. → **C(PreToolUse 훅으로 실제 차단) + D(`/nova:setup --permissions` 템플릿)** 핵심 + **A(frontmatter 선언 보조) + B(plugin.json 문서 목적)** 조합으로 수정.

### 대안 비교 — 관찰성 레이어

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | JSONL append-only + rotation + flock | 플러그인 패치 자동, privacy 제어 용이, Bash 친화 | rotation/lock 구현 필요, gitignore 동기화 필수 | ⭐ |
| B | SQLite 임베디드 | 구조화 쿼리·ACID | sqlite3 의존, 스키마 마이그레이션 부담 | |
| C | stdout emit + 사용자 리다이렉션 | 극단적 경량 | 수동 설정 위배, 기본 상태 KPI 불가 | |

### 대안 비교 — 도구 제약 레이어

| 방안 | 접근 | 장점 | 단점 | 권장도 (U1 해소 후) |
|------|------|------|------|--------|
| A | agent frontmatter `tools:` 엄격화 + audit 스크립트 | 기존 구조 활용, 선언 문서화 | **U1: 런타임 enforcement 없음 — 선언적 힌트일 뿐** | ⭐ 보조 (선언/감사 목적) |
| B | plugin.json `tool_contract` 필드 | 정적 감지, 스키마 선언 | **U1: plugin.json 공식 스키마 미지원** — 문서 필드로만 존속 | (문서 목적) |
| C | `.claude/settings.json`의 PreToolUse 훅으로 차단 | **U1: 유일한 공식 런타임 enforcement 경로** · Project settings 우선순위 공식 보장 | 훅 스크립트 구현 필요 · 성능 부하(이벤트당 fork) · fewer-permission-prompts와 경합 가능 | ⭐ **핵심(Sprint 2b)** |
| D | `/nova:setup --permissions`로 settings 템플릿 병합(opt-in) | deny-by-default 제공 · 사용자 제어권 · C의 훅 엔트리도 함께 주입 가능 | 기본 미적용(opt-in) | ⭐ **핵심(Sprint 2a)** |

### 이벤트 타입 v1 목록 (확정 — 11종)

| # | event_type | 발생 시점 | 필수 extra 필드 | 기록 주체 |
|---|-----------|----------|---------------|----------|
| 1 | `session_start` | hooks/session-start.sh 마지막 | `nova_version`, `cwd_hash` | hooks |
| 2 | `session_end` | Stop 후크 | `duration_ms`, `exit_reason` | hooks |
| 3 | `phase_transition` | orchestrator Phase 전이 | `orchestration_id`, `phase_name`, `from_status`, `to_status` | orchestrator 스킬 |
| 4 | `evaluator_verdict` | evaluator 스킬 판정 직후 | `verdict` (PASS/CONDITIONAL/FAIL), `critical_issues`, `target` (code/plan/design) | evaluator 스킬 |
| 5 | `sprint_started` | 스프린트 착수 | `sprint_name`, `planned_files` | run/auto 커맨드 |
| 6 | `sprint_completed` | 스프린트 종료 | `sprint_name`, `verdict`, `regression_tests_pass` | run/auto 커맨드 |
| 7 | `blocker_raised` | 블로커 분류 시 | `blocker_type` (auto-resolve/soft/hard), `cause`, `file_count` | 모든 커맨드 |
| 8 | `blocker_resolved` | 블로커 해소 | `blocker_type`, `resolution` | 모든 커맨드 |
| 9 | `plan_created` | /nova:plan·/nova:deepplan 완료 | `path`, `mode` (plan/deep), `iterations`, `critic_resolved` | plan/deepplan |
| 10 | `jury_verdict` | /nova:ask·jury 스킬 완료 | `consensus_level`, `changed_direction` (bool) | ask/jury |
| 11 | `tool_constraint_violation` | audit 스크립트 감지 | `agent`, `tool_attempted`, `declared_tools` | scripts/audit-agent-tools.sh |

> 이 11종이 Sprint 1 파일 수 견적(9~11)의 기반. 추가 타입은 Sprint 1b 재평가.

### KPI 4종 조작적 정의 + 의사코드

모든 계산은 `scripts/nova-metrics.sh`가 `.nova/events.jsonl`을 입력으로 수행. 기본 윈도우는 **최근 30일**(CLI 플래그 `--since 7d|30d|all`로 override).

**1. process_consistency** — 3파일 이상 변경되는 작업 중 plan_created가 선행된 비율

```bash
# 의사코드 (bash + jq)
window_events = jq --arg since "$(date -u -d '30 days ago' +%s)" '
  select(.timestamp_epoch >= ($since|tonumber))
' .nova/events.jsonl

sprint_completed_big = window | event_type=="sprint_completed" & planned_files>=3
# 각 sprint_completed에 대해, 같은 orchestration_id 내에서 plan_created가 이전 timestamp에 있는가?
preceded = sprint_completed_big | inner_join(plan_created by orchestration_id) where plan.ts < sprint.ts
process_consistency = len(preceded) / len(sprint_completed_big)  # 분모 0이면 "N/A"
```

**2. gap_detection_rate** — evaluator_verdict=FAIL 중 **같은 orchestration_id** 내에서 다음 `sprint_completed` 또는 `phase_transition(completed)`가 PASS로 종결된 비율

```bash
evaluator_fails = window | event_type=="evaluator_verdict" & verdict=="FAIL"
for each fail:
  same_orch_later = window | orchestration_id==fail.orchestration_id & ts > fail.ts
  resolved = same_orch_later has (sprint_completed with verdict=="PASS") or (phase_transition to completed)
gap_detection_rate = len(resolved) / len(evaluator_fails)
```

**3. rule_evolution_rate** — `docs/rules-changelog.md`의 제안된 규칙 중 `approved` 상태 비율 (이벤트 보조 — `rule_proposed`/`rule_approved`는 v1 스키마에 미포함, v2에서 추가)

```bash
# v1: 이벤트 없음 → rules-changelog.md 파싱
proposed = grep -c '^## .* — proposed' docs/rules-changelog.md
approved = grep -c '^## .* — approved' docs/rules-changelog.md
rule_evolution_rate = approved / proposed  # 분모 0이면 "N/A"
```

**4. multi_perspective_impact** — `jury_verdict` 중 `changed_direction=true` 비율 (jury/ask가 단일 AI 판단을 뒤집은 비율)

```bash
jury_events = window | event_type=="jury_verdict"
changed = jury_events | changed_direction==true
multi_perspective_impact = len(changed) / len(jury_events)
```

**공통 정책**:
- 분모 0이면 "N/A (insufficient data)" 출력, 숫자 강요 금지
- `bootstrap=true` 이벤트 이전 기간은 분모에서 제외(기존 사용자 업그레이드 보정)
- 모든 비율은 소수점 1자리 + 표본 크기(n=…) 병기

### Privacy 정규식 v1 (최소 14패턴 + 엔트로피 휴리스틱)

`hooks/record-event.sh`가 `extra_json` 저장 전 적용:

| # | 패턴 | 정규식(Bash ERE) | 예 |
|---|------|-----------------|-----|
| 1 | Anthropic API | `sk-ant-[A-Za-z0-9_-]{20,}` | `sk-ant-api03-xxx` |
| 2 | OpenAI API | `sk-(proj-)?[A-Za-z0-9]{20,}` | `sk-proj-xxx` |
| 3 | GitHub PAT | `gh[pous]_[A-Za-z0-9]{36,}` | `ghp_xxx`, `gho_xxx` |
| 4 | Slack token | `xox[baprs]-[A-Za-z0-9-]{10,}` | `xoxb-xxx` |
| 5 | Stripe live | `sk_live_[A-Za-z0-9]{24,}` | `sk_live_xxx` |
| 6 | Stripe test | `sk_test_[A-Za-z0-9]{24,}` | `sk_test_xxx` |
| 7 | Google API | `AIza[A-Za-z0-9_-]{35}` | `AIzaSy...` |
| 8 | AWS Access | `AKIA[0-9A-Z]{16}` | `AKIA...` |
| 9 | AWS Secret | `aws_?secret.{0,5}['\"=:][A-Za-z0-9/+=]{40}` | — |
| 10 | Bearer | `[Bb]earer [A-Za-z0-9._-]+` | — |
| 11 | JWT | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | — |
| 12 | password= | `(?i)(password\|passwd\|pwd)\s*[=:]\s*\S+` | — |
| 13 | .env 값 | `^[A-Z][A-Z0-9_]{2,}=[^\s]{8,}$` (줄 단위) | — |
| 14 | Private key | `-----BEGIN ((RSA\|EC\|OPENSSH) )?PRIVATE KEY-----` | — |

**엔트로피 휴리스틱**: 40자 이상 연속 `[A-Za-z0-9_/+=-]` 문자열 중 Shannon 엔트로피 > 4.5 비트/문자 → redact 의심 마커(`"suspicious_token":true`). False positive 허용(보수적 재현).

**적용 순서**: `extra_json` 원본에 정규식 match 시 해당 부분을 `<redacted:{pattern_name}>`로 치환 + 최상위 `"redacted":true, "redaction_reasons":["pattern1","pattern2"]` 필드 주입.

### 이벤트 기록 실패 시 상위 skill 동작 정책

`hooks/record-event.sh` 실패(권한 거부 / 디스크 풀 / flock 타임아웃) 시:

1. **기본**: `stderr`에 `[nova:event] WARN: record failed — {reason}` 출력 후 상위 skill은 **계속 진행**(silent skip 금지, 반드시 WARN).
2. **스크립트 자체**: exit code 0을 **강제 반환**(관찰성 장애가 파이프라인을 죽이지 않음).
3. **옵트아웃**: `NOVA_DISABLE_EVENTS=1` 환경변수 시 즉시 exit 0 (기록 생략, WARN 없음).
4. **CI 러너**: `CI=true`에서는 `.nova/events.jsonl` 경로를 `$CI_ARTIFACTS/.nova/events.jsonl`로 자동 치환(configure 가능).

### Rotation 알고리즘 (race-safe)

```
while record_event:
  flock -x $LOCKFILE
    size = stat .nova/events.jsonl
    if size + line_len > MAX_SIZE (default 10MB):
      # rotation sequence (locked):
      find existing events.N.jsonl → bump N → rename
      rename events.jsonl → events.1.jsonl
      create events.jsonl (empty, chmod 600)
      if N > MAX_FILES (default 5): delete oldest
    append line to events.jsonl
  flock -u
```

**macOS/BSD `flock` 부재 대응**: `hooks/record-event.sh`가 `command -v flock` 확인 후 없으면 **mkdir 기반 잠금**으로 fallback(`mkdir .nova/.lock` 성공=획득, 실패 시 100ms × 30회 재시도 → 초과 시 WARN + exit 0).

**V20 테스트**: 9.99MB fixture 상태에서 xargs -P 20으로 record-event.sh 20회 → 모든 라인 보존(두 파일 합산 = 시작 라인 수 + 20) + 모든 라인 JSON parse.

### `/nova:setup --permissions` JSON merge 알고리즘

**입력**: 사용자 기존 `.claude/settings.json` (없으면 `{}`) + Nova 템플릿 (`scripts/permissions-template.json`)

**구현**: `jq` 의존(setup 진입 시 존재 확인, 미설치 시 명확한 에러 + 설치 안내).

**병합 규칙**:

| 필드 타입 | 규칙 |
|-----------|------|
| 스칼라(`permissions.defaultMode`) | 사용자 기존값 **보존**. Nova 값은 신규 키일 때만 주입 |
| 배열(`permissions.allow`, `permissions.deny`) | **합집합 + 중복 제거**. 정렬하지 않음(사용자 순서 보존) |
| 충돌(같은 항목이 allow/deny 양쪽) | **deny 우선** + stderr 리포트: `[nova:setup] CONFLICT: "Bash(rm -rf *)" in both allow and deny → deny wins` |
| 객체(중첩) | 재귀 병합 |

**구현체**:
```bash
jq --slurpfile user .claude/settings.json \
   --slurpfile nova scripts/permissions-template.json \
   'reduce_merge_with_conflict_report' > .claude/settings.json.new
# atomic replace
mv .claude/settings.json.new .claude/settings.json
```

**테스트 fixture 3종**:
1. 빈 프로젝트(settings.json 없음) → Nova 템플릿 그대로
2. 기존 allow 배열 있음 → 합집합, 기존 항목 보존
3. 충돌 항목(같은 Bash 패턴이 user allow + nova deny) → deny 적용, stderr에 CONFLICT 리포트 1건

### 구현 범위 (스프린트 경계 포함)

> 총 예상 **25~30 파일** → **4 스프린트**로 분할. 각 스프린트 끝에 독립 Evaluator 필수.

#### Sprint 0 — session-start 경량화 (prerequisite, 10~12 파일)

**목표**: 현재 3525 bytes → **1900 bytes 이하**로 축소. on-demand 로드 패턴 확립.

- [x] `hooks/session-start.sh` — 핵심 5개만 유지(§1, §2, §4, §7, §9). 나머지는 on-demand 로드.
- [x] `.claude/commands/check.md`, `review.md`, `run.md`, `auto.md`, `plan.md`, `deepplan.md` — 각 규칙 on-demand 로드 선언 (§3/§5/§6/§9)
- [x] `.claude/skills/context-chain/SKILL.md` — §8 on-demand 선언
- [x] `.claude/skills/evaluator/SKILL.md` — §2/§3 on-demand 선언
- [x] `.claude/skills/orchestrator/SKILL.md` — §2/§6 on-demand 선언
- [x] `docs/nova-rules.md` — §0 신설(on-demand 로드 선언)
- [x] `tests/test-scripts.sh` — hard 2500/soft 1900 상한 강제 + §6/§9 부재 + plan/deepplan/evaluator/orchestrator on-demand 선언 존재 검증
- [x] `NOVA-STATE.md` — Known Gaps task #7 + 이관 대기에서 task #7 토큰 제거
- [x] `.gitignore` — `.claude/settings.local.json` 추가 (per-user 로컬 설정 커밋 방지)

**Exit**: `bash hooks/session-start.sh | wc -c < 1900` (실측 1766 bytes 달성). 302+ 회귀 전수 PASS.

#### Sprint 1 — 관찰성 레이어 (10~12 파일)

**목표**: 11종 이벤트 JSONL 기록 + KPI 4종 집계. `/nova:next`가 실측 수치 표시.

- [ ] `hooks/record-event.sh` (신규) — flock-atomic append, 14 패턴 privacy 필터, 실패 시 stderr WARN + exit 0, `NOVA_DISABLE_EVENTS=1` 옵트아웃
- [ ] `hooks/hooks.json` — Stop 후크 추가(session_end 이벤트)
- [ ] `scripts/nova-metrics.sh` (신규) — KPI 4종 집계 + N/A 처리 + bootstrap 보정
- [ ] `scripts/permissions-template.json` (신규) — 이건 Sprint 2a와 공유 파일 — Sprint 1에서 빈 스텁만 생성
- [ ] `.claude/skills/evaluator/SKILL.md` — 판정 직후 `record-event.sh evaluator_verdict …` 호출
- [ ] `.claude/skills/orchestrator/SKILL.md` — Phase 전이 시 `phase_transition` 기록
- [ ] `.claude/skills/context-chain/SKILL.md` — NOVA-STATE(사람) + JSONL(기계) 역할 분담 명시
- [ ] `.claude/commands/next.md` — `scripts/nova-metrics.sh` 출력 1줄 요약 포함
- [ ] `docs/nova-engineering.md §9` — "실측 없음" → `scripts/nova-metrics.sh` 참조 + 지표 정의 구체화
- [ ] `docs/nova-rules.md` — §11 "관찰성 계약"(스키마 v1, privacy 원칙, rotation 정책, NOVA_DISABLE_EVENTS 옵트아웃)
- [ ] `.gitignore` + `hooks/worktree-setup.sh` — `.nova/` 자동 추가
- [ ] `tests/test-scripts.sh` — V2~V7 + V18~V24 + V27 테스트 추가

**Exit**: `/nova:run` 1회 후 `.nova/events.jsonl` 최소 3라인, 11종 중 3종 이상 관찰. `nova-metrics.sh` 출력 4행(혹은 N/A). V18 secrets 8종 redacted. V20 rotation race 라인 유실 0.

#### Sprint 2a — 도구 제약 (정적 + 선언 + 템플릿, Sprint 0 이후 병행 가능 — 7~8 파일)

**목표**: frontmatter audit + `/nova:setup --permissions`가 settings.json 권장 세트(deny-by-default + PreToolUse 훅 엔트리)를 병합.

- [ ] `.claude/agents/*.md` × 5 — frontmatter `tools:` 주석 마커(선언/감사 목적 명시) + deferred 암묵 허용 정책
- [ ] `docs/nova-rules.md` — §12 "도구 제약 계약": (a) frontmatter 선언 필수 (b) 선언 외 도구 사용은 Evaluator 적대적 포인트 (c) **런타임 강제는 `.claude/settings.json`의 PreToolUse 훅이 유일 — U1 해소 확정** (d) `/nova:setup --permissions`로 템플릿 제공(opt-in)
- [ ] `.claude-plugin/plugin.json` — `tool_contract` 추가 **+ 주석 "공식 스키마 미지원 — Nova 감사 스크립트 소스 목적(U1:2026-04-19)"**
- [ ] `scripts/audit-agent-tools.sh` (신규) — frontmatter × plugin.json tool_contract 대조, 불일치 exit 1
- [ ] `scripts/permissions-template.json` (완성) — (1) deny-by-default Bash 위험 패턴(`rm -rf`, `:(){ :|:&`, `curl … | sh` 등) (2) PreToolUse 훅 엔트리(`scripts/precheck-tool.sh` 참조) (3) Nova Sprint 2b에서 사용할 훅 스크립트 경로 — **Sprint 2b에서 실제 스크립트 추가 시 템플릿 재배포 없이 즉시 활성**
- [ ] `.claude/commands/setup.md` — `--permissions` 옵션 + `jq` 기반 merge(배열 합집합, 충돌 deny 우선 + stderr 리포트, 3 fixture)
- [ ] `tests/test-scripts.sh` — V9/V10/V11/V25 + permissions-template 스키마 검증

**Exit**: 5개 agent frontmatter 선언 + `audit-agent-tools.sh` exit 0. `/nova:setup --permissions`가 빈/기존/충돌 3 fixture 전수 PASS + 사용자 기존 키 보존.

#### Sprint 2b — 도구 제약 (런타임 강제, Sprint 1 + 2a 이후 — 4~5 파일)

**목표**: **PreToolUse 훅으로 실제 도구 차단** + JSONL에 `tool_constraint_violation` 이벤트 기록. C 경로 완성.

- [ ] `scripts/precheck-tool.sh` (신규) — **PreToolUse 훅 스크립트**. stdin으로 `{tool, input}` 받아 `scripts/permissions-template.json` 또는 사용자 `.claude/settings.json` 기반 정책 평가. 거부 시 `exit 2` + stderr에 정책 이유 + `hooks/record-event.sh tool_constraint_violation <agent> <tool> <declared>` 호출.
- [ ] `scripts/permissions-template.json` (업데이트) — Sprint 2a에서 참조만 된 훅 엔트리를 실 스크립트 경로로 활성. 사용자는 `/nova:setup --permissions` 재실행으로 최신 템플릿 병합.
- [ ] `hooks/record-event.sh` — `tool_constraint_violation` 이벤트 타입 공식 지원(11종에 이미 포함, 이 스프린트에서 실제 기록 경로 연결 확정)
- [ ] `.claude/skills/evaluator/SKILL.md` — §3 검증 기준에 "사후 감사: `.nova/events.jsonl`에서 `tool_constraint_violation` 건수 조회" 추가(`jq` 쿼리 예시 포함)
- [ ] `scripts/nova-metrics.sh` — `tool_violation_rate` KPI 5번째 추가(선택적 출력)
- [ ] `tests/test-scripts.sh` — V14(deferred 도구 통과) + V28(훅 차단 + JSONL 기록) + V30(훅 지연 100ms 이내)

**Exit**:
- 의도 위반 fixture(denylist의 Bash 패턴) → PreToolUse 훅이 `exit 2`로 **실제 차단** + stderr에 정책 이유 + JSONL에 `tool_constraint_violation` 1건 기록.
- 정상 도구 호출(allowlist) → 훅 통과(`exit 0`) + stderr 침묵.
- 훅 자체 실패(스크립트 파일 없음 / 권한 거부) → **safe-default: exit 0**(관찰성 WARN만, 도구 실행 차단 금지 — 사용자 작업 마비 방지).

### 검증 기준

§3 검증 기준 + 갭 고유 항목:

- **기능**: Sprint별 Exit criteria 100% 충족
- **데이터 관통**: 이벤트 → JSONL → 스크립트 집계 → `/nova:next` 표시 4단 완전성
- **설계 정합성**: NOVA-STATE(사람) / JSONL(기계) 역할 분담 유지
- **크래프트**: flock 동시성 + rotation race + JSON escape + CRLF normalize + session_id 충돌 방지(PID + /dev/urandom)
- **경계값**: 빈 JSONL, MAX_SIZE±1byte, 병렬 20/50회, JSON embedded `\n`/CRLF/Unicode
- **배포 일관성**: `docs/nova-rules.md` §수 == session-start 주입 규칙 수(test-scripts 자동 검증)
- **Privacy**: 14 패턴 + 엔트로피 휴리스틱 + Base64 인코딩 우회 + GitHub/Slack/Anthropic/Stripe/Google/JWT 최소 8종 레드팀
- **업그레이드/옵트아웃**: 기존 사용자 bootstrap 이벤트 + `NOVA_DISABLE_EVENTS=1` 동작 + CI 러너 경로 치환

---

## Sprints (스프린트 분할)

| # | 스프린트 | 파일 수 | 전제 | Exit |
|---|----------|---------|------|------|
| 0 | session-start 경량화 | 8~10 | — | 출력 < 1900 bytes, 169+ 회귀 PASS |
| 1 | 관찰성 레이어 (JSONL + KPI + privacy) | 10~12 | Sprint 0 | events.jsonl 기록 / KPI 4종 출력 / V18·V20 PASS |
| 2a | 도구 제약 정적 (audit + settings 템플릿) | 6~7 | Sprint 0 (Sprint 1과 병행 가능) | audit exit 0, 3 fixture PASS |
| 2b | 도구 제약 런타임 감사 | 3~4 | Sprint 1 + 2a | violation 기록 + V14/V28 PASS |

**스프린트 간 하드 게이트**: 각 스프린트 완료 시 독립 Evaluator(서브에이전트) PASS 필수. Sprint 0/1/2a/2b 각각 **독립 릴리스**(patch/minor 4회) — 한 major로 묶지 않음(실측 피드백 수집 목적).

---

## Risk Map

| # | 리스크 | 가능성 | 영향 | 완화 |
|---|--------|--------|------|------|
| R1 | Privacy Leak via Unredacted JSONL | H | H | Sprint 1 14 패턴 + 엔트로피 휴리스틱. V18 secrets 8종 적대적 테스트 |
| R2 | Disk Space Exhaustion | H | H | maxSize=10MB, maxFiles=5, maxDays=30 기본. `.nova/nova-config.json` opt-in override |
| R3 | Concurrent Write Corruption | M | H | `flock -x` atomic + `mkdir` fallback. V20 병렬 20회 라인 유실 0 |
| R4 | Path Portability | M | M | 로그는 cwd_hash(session_id)만 저장. 절대경로 저장 금지 |
| R5 | Gitignore Drift | H | M | `hooks/worktree-setup.sh` + `scripts/init-nova-state.sh`에서 `.gitignore` 자동 추가. V8 |
| R6 | Schema Evolution Incompatibility | M | M | 모든 라인에 `schema_version=1`. reader 라인별 분기, 미지원 버전 warning+skip |
| R7 | Deferred Tools Blocked by Whitelist | H | H | agent frontmatter `Agent` 포함 시 `ToolSearch` 암묵 허용. audit 스크립트 deferred 네임스페이스 통과 |
| R8 | settings.json Priority Collision | M | M | `/nova:setup --permissions`는 병합 전용(배열 합집합, 충돌 deny 우선 + stderr 리포트) |
| R9 | session-start Hard Limit Overflow | H | H | Sprint 0 prerequisite. test-scripts 2500 bytes 상한 강제 |
| R10 | nova-rules ↔ session-start ↔ commands 삼중 동기화 | H | H | test-scripts §수 동기화 검증. 커밋 메시지 체크리스트 convention |
| R11 | ~~Claude Code permissions 필드 비표준~~ **해소(2026-04-19)** — plugin.json 미지원 확정, `.claude/settings.json` PreToolUse 훅으로 전환 | — | — | `docs/unknowns-resolution.md` §U1 참조. Sprint 2b를 C 경로(PreToolUse)로 재설계 완료 |
| **R12** | **hook 자기 차단** — `/nova:setup --permissions` deny가 `record-event.sh` Bash 호출 차단 | **M** | **H** | 템플릿의 allowlist에 `Bash(bash hooks/*.sh)`, `Bash(scripts/*.sh)` 명시적 포함. V26 회귀 테스트 |
| **R13** | **성능 부하** — 이벤트당 bash fork 수백 회 | **M** | **M** | 측정: Sprint 1 Exit에 `time` 벤치 추가(목표: +<100ms per /nova:run). 초과 시 버퍼링 구현 이관 |
| **R14** | **session_id 충돌** — 초 단위 timestamp 기반 hash, 동시 2세션 충돌 | **H** | **M** | PID + `/dev/urandom` 4 bytes 결합. 충돌 테스트: 동시 10세션 stub → unique id |
| **R15** | **시계 skew / NTP** — timestamp 역전, duration_ms 음수 | **L** | **M** | ISO8601 UTC + `monotonic_ns` 보조 필드. nova-metrics에서 `duration_ms<0` 경고 |
| **R16** | **CRLF 오염** — Windows/WSL 편집기 삽입 시 `jq`/`awk` 파싱 실패 | **M** | **M** | record-event.sh가 append 직전 `tr -d '\r'`. reader는 `\r?\n` 허용 |
| **R17** | **Rotation race** — rename→create 사이 창 라인 유실 | **M** | **H** | flock 구간 안에서 rename+create+append가 원자적으로 수행(위 알고리즘 참조). V20 |
| **R18** | **JSON embedded `\n`** — 인자 개행 이스케이프 누락 | **H** | **H** | record-event.sh가 `python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))'` 또는 `jq -Rs .`로 강제 이스케이프. V3/V21 |
| **R19** | **멀티 worktree** — 레포 동일, `.nova/events.jsonl` 각각 | **M** | **M** | nova-metrics에 `--merge-worktrees <path1> <path2> …` 플래그. 중복 session_id 제거 |
| **R20** | **CI ephemeral KPI** — 러너 매번 초기화, `process_consistency` 진동 | **M** | **M** | CI 러너 감지(`$CI=true`) 시 metrics를 `$CI_ARTIFACTS/.nova/`로 자동 이동, 로컬 KPI와 분리 |
| **R21** | **BSD flock 부재** — macOS 기본 PATH에 없음 | **H** | **H** | mkdir fallback + `command -v flock` 검사. V26 테스트 |
| **R22** | **hook 실패 전파 정책 미정** | **M** | **M** | 명시(위 정책): stderr WARN + exit 0 강제. 상위 skill silent skip 금지 |
| **R23** | **기존 사용자 업그레이드 편향** — 빈 JSONL로 KPI=0% 오인 | **M** | **M** | 최초 기동 시 `bootstrap=true` 이벤트. nova-metrics가 bootstrap 이전 기간을 분모에서 제외 |
| **R24** | **fewer-permission-prompts 공존 충돌** — 두 시스템 같은 settings 수정 | **M** | **M** | U4 해소 후 확정. 현 버전은 병합 전용 + stderr 리포트로 사용자 판단 위임 |

---

## Unknowns

> 착수 전 반드시 해소하거나 스코프에서 제외. **해소 절차 포함**.

### U1 — Claude Code plugin.json permission 필드 지원 범위

- **질문**: `.claude-plugin/plugin.json`이 `permissions`/`tool_contract` 필드를 공식 지원하는가?
- **해소 결과 (2026-04-19)**: **미지원 확정**. 상세: `docs/unknowns-resolution.md` §U1.
  - plugin.json 공식 스키마에 permission 필드 **없음** (Plugins reference 문서 확인)
  - agent frontmatter `tools:` / `disallowedTools:`는 **선언적 힌트**일 뿐 런타임 enforcement 없음
  - 공식 런타임 enforcement 경로: **`.claude/settings.json`의 PreToolUse 훅**이 유일. 우선순위 **Managed > Project > User** 공식 정의
- **Plan 영향**:
  - Sprint 2a의 `plugin.json tool_contract` 필드는 **문서 목적**으로만 유지(주석 명시)
  - Sprint 2b를 **"PreToolUse 훅으로 실제 차단"** 으로 재설계(C 경로 승격)
  - `/nova:setup --permissions`는 사용자 `.claude/settings.json`에 훅 엔트리까지 병합
- **Owner**: main-agent (완료)

### U2 — Deferred 도구 resolution 타이밍

- **질문**: ToolSearch가 deferred 도구 로드 시 permission 체크가 (a) ToolSearch 호출 (b) tool resolution (c) tool execution 중 어디?
- **해소 절차**:
  1. Sprint 2a 착수 **전**: `.claude/agents/architect.md`가 `Agent` 도구 포함 → ToolSearch("select:WebSearch") 호출 스모크 테스트
  2. 성공/실패 + 타이밍 로그 `docs/unknowns-resolution.md`에 기록
  3. `c` 실행 시점이면 런타임 차단(C안)이 technically 가능 — Sprint 2b 스코프 확장 재평가
- **Owner**: Sprint 2a 담당

### U3 — 이벤트 로그 저장 경로

- **결정**: (a) 프로젝트 루트 `.nova/events.jsonl` **기본**
- **근거**: 프로젝트 격리, .gitignore 간단, `/nova:next` 접근 용이
- **Opt-in 확장**: `NOVA_EVENTS_PATH` 환경변수로 `~/.claude/nova-logs/<cwd_hash>/events.jsonl` 이동 가능(멀티 프로젝트 통합용)

### U4 — plugin.json ↔ CLAUDE.md 우선순위

- **질문**: 플러그인 자동 규칙과 프로젝트 CLAUDE.md 충돌 시 우선순위?
- **해소 절차**:
  1. Sprint 2a 착수 **전**: `/nova:ask "Claude Code plugin vs project CLAUDE.md precedence"` 실행
  2. 결과 반영: 공식 규칙이 "project first"이면 docs/nova-rules.md §0에 명시(프로젝트 .claude/rules/ 우선)
- **Owner**: Sprint 2a 담당

### U5 — 이벤트 로그 파일 권한

- **결정**: `hooks/record-event.sh` 최초 호출 시 `chmod 600 .nova/events.jsonl` 명시적 적용. macOS/Linux `umask` 차이 우회.

### U6 — 스키마 혼재 로그 reader 정책

- **결정**: 라인별 `schema_version` 감지. 미지원 버전은 warning + skip. 스키마 major 변경 시 기존 파일은 `.nova/events-v1.jsonl`로 rotate 권장(자동 아님, 수동 스크립트 `scripts/migrate-events.sh` 제공).

---

## Verification Hooks

> Sprint Contract 씨앗 — `/nova:design`에서 구체화.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| V1 | session-start 출력 < 1900 bytes | `bash hooks/session-start.sh \| wc -c` | Critical (Sprint 0 exit) |
| V2 | events.jsonl 생성 + 최소 3라인 + 3종 이상 event_type 관찰 | `/nova:run` 후 `wc -l` + `jq -r '.event_type' \| sort -u \| wc -l` | Critical (Sprint 1 exit) |
| V3 | JSONL 모든 라인 parse + 최소 라인 수 동시 충족 | `[[ $(wc -l < events.jsonl) -ge 3 ]] && jq -s '.' events.jsonl > /dev/null` | Critical |
| V4 | Privacy 필터 — sk-ant, sk-proj, ghp_, xoxb-, sk_live_, AIza, AKIA, eyJ 8종 redacted | fixture 8종 입력 → 출력에 `"redacted":true` 전수 | Critical |
| V5 | 동시성 — xargs -P 20 append 후 V3 | — | Critical |
| V6 | Rotation 트리거 — 9.99MB fixture + append → 2 파일, 새 파일 첫 라인에 `rotation_from` 마커 | `ls .nova/events*.jsonl \| wc -l ≥ 2` + `jq '.rotation_from' events.jsonl` | High |
| V7 | KPI 스크립트 스냅샷 일치 — 고정 fixture → expected 값 정확 일치 | `diff <(nova-metrics.sh --fixture test/events.jsonl) test/expected.txt` | Critical (Sprint 1 exit) |
| V8 | .gitignore에 `.nova/events*.jsonl` 포함 | `grep -q '.nova/events' .gitignore` | High |
| V9 | Agent frontmatter tools 선언 강제 | `scripts/audit-agent-tools.sh` exit 0 | Critical (Sprint 2a exit) |
| V10 | plugin.json tool_contract 주석 포함 | `jq '.tool_contract' plugin.json` non-null | Nice |
| V11 | `/nova:setup --permissions` 병합 안전 — 3 fixture 전수 PASS | 빈/기존/충돌 3종 fixture 돌려 merge 결과 검증 | Critical (Sprint 2a exit) |
| V12 | session-start 규칙 수 ↔ nova-rules §수 동기화 | `tests/test-scripts.sh` 자동 실행 | Critical |
| V13 | 169+ 회귀 테스트 전수 통과 | `bash tests/test-scripts.sh` | Critical (모든 스프린트) |
| V14 | Deferred 도구 통과 — ToolSearch audit 실패 없음 | `scripts/audit-agent-tools.sh`에서 deferred 제외 확인 | High |
| V15 | session-start hard limit 2500 상한 강제 | test-scripts에서 `[[ $size -le 2500 ]]` | Critical (회귀) |
| V16 | nova-engineering.md §9 수치 업데이트 자동 검증 | `grep -q "scripts/nova-metrics.sh" docs/nova-engineering.md` + `grep -vq "실측 결과가 아니다" docs/nova-engineering.md` | High |
| V17 | NOVA-STATE.md(사람) ↔ JSONL(기계) 역할 분담 | `/nova:run` 후 NOVA-STATE에는 Last Activity 1줄 + JSONL에는 원자 이벤트 ≥3 | High |
| **V18** | **Secrets 적대적 확장** — GitHub/Slack/Anthropic/Stripe/Google/AWS/JWT/Base64 인코딩 sk- 총 10종 redacted | fixture 10종 입력 | **Critical** |
| **V19** | **기록 실패 전파** — chmod 000 / 디스크 풀 모사 → record-event.sh exit 0 + stderr WARN + 상위 skill 계속 | — | Critical |
| **V20** | **Rotation race** — 9.99MB + xargs -P 20 → 라인 수 보존 + 2 파일 parse 전수 | — | Critical |
| **V21** | **Event schema conformance** — 이벤트 타입별 JSON Schema 검증(`ajv`/`jsonschema`) | — | High |
| **V22** | **NOVA_DISABLE_EVENTS=1** — set 후 `/nova:run` → JSONL 0 라인 | — | High |
| **V23** | **Multi-worktree 격리** — 같은 레포 worktree 2개 동시 → 각자 JSONL, 교차 오염 0 | — | Nice |
| **V24** | **KPI 스냅샷 일치** (V7과 중첩 — fixture 이벤트 3종류) | — | Critical |
| **V25** | **fewer-permission-prompts 공존** — 기존 allowlist 있는 settings → merge 후 사용자 allow 보존 + Nova deny 추가 + 충돌 stderr 리포트 | — | Critical |
| **V26** | **flock fallback** — `PATH=/usr/bin`(flock 없음) → mkdir 잠금으로 동시성 유지 | — | Critical |
| **V27** | **CRLF normalize** — `printf '...\r\n'`로 한 줄 주입 → reader 정규화 or 경고 | — | High |
| **V28** | **Tool constraint 실제 차단** — 위반 fixture(denylist Bash) → PreToolUse 훅 `exit 2` + stderr 정책 이유 + JSONL `tool_constraint_violation` 1건. 허용 도구는 훅 `exit 0` + stderr 침묵. 훅 자체 실패는 safe-default(exit 0 + WARN) | — | Critical (Sprint 2b exit) |
| **V29** | **Bootstrap 이벤트** — 기존 사용자(이벤트 없음) → `bootstrap=true` 1건 자동 기록 + nova-metrics가 이전 기간 분모 제외 | — | High |
| **V30** | **Performance bench** — `/nova:run` 전후 wallclock +<100ms, 초과 시 Warning | `time` 측정 | Nice |

---

## Next Steps (착수 전 해소 필수 — Critic 피드백 반영)

1. **U1 해소 완료 (2026-04-19)** — plugin.json permission 공식 미지원 확정. Sprint 2b를 PreToolUse 훅 차단으로 재설계. 상세: `docs/unknowns-resolution.md`
2. **이벤트 타입 v1 목록 확정** — 본 Plan Solution에 11종 표 삽입 완료
3. **KPI 4종 조작적 정의 + 의사코드** — 본 Plan Solution에 삽입 완료
4. **Privacy 정규식 v1(14 패턴 + 엔트로피 휴리스틱)** — 본 Plan Solution에 삽입 완료
5. **NOVA_DISABLE_EVENTS + CI 러너 정책** — 본 Plan Solution에 삽입 완료
6. **`/nova:setup --permissions` merge 알고리즘** — 본 Plan Solution에 삽입 완료 (`jq` 의존 확정, 배열 합집합, 충돌 deny 우선 + stderr 리포트)
7. **Sprint 2 분할** — Sprint 2a(정적, Sprint 1과 병행 가능) / Sprint 2b(런타임 감사, Sprint 1 의존)로 분리 완료
8. **기록 실패 시 상위 skill 정책** — stderr WARN + exit 0 강제 확정
9. **Rotation 알고리즘** — flock 구간 안 rename+create+append + mkdir fallback 확정
10. **업그레이드 마이그레이션** — bootstrap 이벤트 + 분모 보정 + CI 러너 경로 치환 확정

**다음 실행**:
- `/nova:design "하네스 엔지니어링 갭 보강"` — 이벤트 타입 11종 × 필드 × JSON Schema, KPI 의사코드를 실 스크립트로, rotation 코드 블록 등을 Sprint Contract로 구체화
- Sprint 0 착수(`/nova:run` 또는 `/nova:auto`) — 기존 Known Gap task #7과 연계
- 릴리스 4회(Sprint 0/1/2a/2b 각각 patch/minor) — 실측 데이터 피드백 수집 후 Sprint 2b 확장 여부 판단
