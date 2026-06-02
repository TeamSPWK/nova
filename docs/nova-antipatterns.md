# Nova Antipatterns — 에이전트 합리화 차단 리스트

에이전트가 스스로 회피할 가능성이 있는 13가지 패턴과 차단 규칙.
obra/superpowers writing-skills 근거 + Nova 특화 회피 패턴.

---

## §A 일반 합리화 (superpowers 원본 기반)

### A1. "이건 간단한 질문이라 Plan 없이 바로 해도 됩니다"

에이전트가 작업 복잡도를 낮게 자가 판정해 §1 규칙을 우회하는 패턴.

**차단 규칙**: §1 복잡도 판단 — 자가 완화 금지. "인프라성이라 과하다", "간단한 변경이다" 같은 자체 판단으로 Plan/Evaluator를 생략하는 것은 금지. `docs/nova-rules.md §1`

### A2. "맥락이 더 필요합니다" (실행 지연)

충분한 맥락이 있음에도 불확실성을 이유로 실행을 계속 미루는 패턴.

**차단 규칙**: NOVA-STATE.md를 먼저 읽는다. 맥락 부족이 진짜 Hard-Block이면 분류 후 사용자에게 알린다. 정보 수집을 이유로 3회 이상 실행 지연 금지. `docs/nova-rules.md §7`, `§8`

### A3. "Evaluator는 나중에 돌려도 됩니다"

커밋 직전 또는 배포 후로 Evaluator를 미루는 패턴. 사이클 비용이 급증한다.

**차단 규칙**: §2 하드게이트 — Evaluator PASS 없이 커밋 차단. `hooks/pre-commit-reminder.sh`가 exit 2로 강제. 유일한 예외는 `--emergency`. `docs/nova-rules.md §2`

### A4. "이 경우엔 테스트가 필요 없습니다"

도메인 특성(인프라, 문서, 스크립트)을 이유로 검증을 통째로 생략하는 패턴.

**차단 규칙**: §4 실행 검증 우선 — "코드가 존재한다" ≠ "동작한다". 빌드·테스트·curl 중 적용 가능한 것을 수행한다. `docs/nova-rules.md §4`

### A5. "이미 비슷한 코드를 봤으니 동작할 것입니다"

컨텍스트 창에 로드된 유사 코드 패턴으로 실제 실행 검증을 대체하는 패턴.

**차단 규칙**: §3 검증 기준 — 경계값(0, 음수, 빈 값)에서 크래시 여부를 실제 실행으로 확인한다. 특히 금융/계산/인증 도메인 필수. `docs/nova-rules.md §3`

### A6. "이건 제 판단 범위가 아닙니다" (책임 회피)

아키텍처나 설계 판단을 지속적으로 사용자에게 떠넘겨 작업이 교착되는 패턴.

**차단 규칙**: §7 블로커 분류 — 판단 불가 상황은 Hard-Block으로 명시적으로 분류하고 "무엇을 결정해달라"고 구체적으로 요청한다. 막연한 "어떻게 할까요?" 반복 금지. `docs/nova-rules.md §7`

---

## §B Nova 특화 회피

### B1. "Evaluator 건너뛰고 커밋"

"빠르게 커밋해야 한다", "이미 확인했다"를 이유로 Evaluator 독립 서브에이전트 실행을 생략하는 패턴.

**차단 규칙**: `/run`, `/check`, `/review` 내부 evaluator 호출이 MUST. `hooks/pre-commit-reminder.sh` exit 2 차단. 단독 에이전트 재확인은 독립 검증이 아님. `docs/nova-rules.md §2` 하드게이트

### B2. "CPS 없이 바로 구현"

복잡도 3+ 작업에서 Plan 없이 구현에 진입하는 패턴. "Plan이 번거롭다", "명확한 요청이라 생략 가능"이 합리화 근거.

**차단 규칙**: 복잡도 3+ (3파일 이상)는 Plan 필수. `hooks/pre-edit-check.sh`가 최근 7일 내 Plan/Design 없으면 경고 출력(lean 제외). `docs/nova-rules.md §1`

### B3. "세션 상태 갱신 생략"

커밋 후 NOVA-STATE.md 갱신을 "나중에"로 미루거나 아예 생략하는 패턴.

**차단 규칙**: 커밋 전 NOVA-STATE.md 일괄 갱신 의무. 블로커 발생/해소와 검증 FAIL은 즉시 갱신. `docs/nova-rules.md §8`

### B4. "메인 에이전트가 직접 검증"

구현한 동일 에이전트가 자기 코드를 재읽고 "문제 없다"고 판단하는 패턴. 컨텍스트 오염으로 편향 검증 발생.

**차단 규칙**: 독립 서브에이전트 spawn(별도 컨텍스트 창) 필수. 자가 점검: "나는 이 코드를 구현한 에이전트와 동일 컨텍스트 창에 있는가?" — 그렇다면 Evaluator가 아님. `docs/nova-rules.md §2`

### B5. "환경 설정 파일 직접 수정"

database.yml, config/*.yml 등을 직접 sed/awk로 수정해 로컬 전환하는 패턴. 프로덕션 설정 오염 위험.

**차단 규칙**: 환경변수(.env.local, DATABASE_URL 등) 또는 CLI 플래그로 전환. 설정 파일 직접 수정 금지. `docs/nova-rules.md §9`

### B6. "profile 무시하고 무거운 규칙 전체 주입"

NOVA_PROFILE=lean 상황(hotfix, 긴급 대응)에서도 전체 규칙 체크를 강제해 속도 저하를 유발하는 패턴.

**차단 규칙**: `NOVA_PROFILE=lean`은 §1~§3만 적용, antipatterns 체크 스킵. `--emergency` 플래그는 lean의 별칭. `hooks/session-start.sh` 프로파일 분기. `docs/nova-rules.md §12`

### B7. "팀 spawn 후 shutdown 누락"

`TeamCreate` / `Agent({team_name, name})` 로 teammate 를 spawn 한 leader 가 작업 완료 보고를 받고도 `SendMessage({type:"shutdown_request"})` 발송을 잊는다. `~/.claude/teams/<team>/config.json` 이 다음 세션까지 잔존하며 tmux pane·디스크를 점유. Claude Code 의 `idle_notification` 을 "종료 신호" 로 오해하는 데서 비롯.

**차단 규칙**: 모든 teammate 의 완료 보고를 받았다면 **같은 turn 안에** `SendMessage({to: name, message: {type: "shutdown_request"}})` 발송 → `shutdown_approved` 응답 확인 → `TeamDelete` 호출. `hooks/audit-teammates.sh` 가 Stop·SessionStart 시 좀비 카운트를 stderr WARN. `docs/nova-rules.md §2` · `.claude/skills/orchestrator/SKILL.md Phase 7` · `dev/commands/evolve.md Phase 1` (Nova 개발자 전용)

---

## 사용 안내

- `NOVA_PROFILE=strict`일 때 `hooks/session-start.sh`가 이 문서 링크를 additionalContext에 주입한다.
- Evaluator가 코드 리뷰 시 §B 패턴을 탐지하면 Hard-Block으로 분류한다.
- 항목 추가는 실사용에서 n>1 사례를 확인한 후 `docs/rules-changelog.md`에 기록하고 승인받는다.
