# Nova 자동 적용 규칙 (상세)

> 이 문서는 자동 적용 규칙의 **소스 문서**다.
> 실제 주입은 `hooks/session-start.sh` (경량 요약).
> 규칙 수정 시 반드시 session-start.sh와 동기화하고 `bash tests/test-scripts.sh` 통과 확인.

---

## Nova = AI Agent Ops 프레임워크

Nova는 **AI 에이전트가 안정적으로 일하도록 만드는 개발 프레임워크**다. 품질 게이트에서 출발해 다섯 기둥으로 확장됐다.

| 기둥 | 역할 | 구성 요소 |
|------|------|-----------|
| **환경** | worktree·secret·격리 환경 셋업 | `hooks/`, worktree 스킬 (예정) |
| **맥락** | 세션 간 상태·메모리 연속성 | `context-chain`, `NOVA-STATE.md` |
| **품질** | Generator-Evaluator 분리, 검증 하드 게이트 | `evaluator`, `jury`, `/nova:review`, `/nova:check` |
| **협업** | 설계→구현→검증 오케스트레이션, 멀티 AI 자문 | `orchestrator`, `/nova:auto`, `/nova:ask` |
| **진화** | 자기 진단, 자동 업그레이드 | `evolution`, `/nova:scan`, `/nova:next` |

아래 규칙 10개는 이 중 **품질 기둥**의 실행 계약이다. 가장 강한 기둥이고, 세션마다 자동 주입되는 유일한 전역 규칙이다. 다른 기둥은 각 커맨드·스킬에서 로드된다.

---

## §0. 세션 주입 범위 (on-demand 로드 패턴)

세션 시작 시 `hooks/session-start.sh`는 **핵심 5개**만 경량 주입한다:

| 세션 시작 주입 | 상세 로드 위치 (on-demand) |
|---------------|------------------------------|
| §1 복잡도 판단 | `/nova:plan`, `/nova:deepplan` — §1 "deepplan 권장 조건" 로드 |
| §2 검증 분리 + 하드 게이트 | `/nova:run`, `/nova:check` — Evaluator 독립성 기술 정의 |
| §4 실행 검증 | `/nova:run`, `/nova:auto` — 배포 후 체크리스트 |
| §7 블로커 분류 | `/nova:auto`, `/nova:run` — 자동 트리거 상세 |
| §9 환경 설정 안전 | `/nova:setup`, `/nova:run` |
| §10 관찰성 계약 (v5.12.0+) | `evaluator`, `orchestrator`, `context-chain` 스킬 / `/nova:next` KPI 요약 |
| §11 도구 제약 계약 (v5.14.0+) | `/nova:setup --permissions`, `scripts/audit-agent-tools.sh`, 런타임 `scripts/precheck-tool.sh`(Sprint 2b) |

**on-demand 로드 대상**(세션 시작에는 없음, 해당 커맨드·스킬이 자체 로드):

| 규칙 | 로드 위치 |
|------|----------|
| §3 검증 기준 | `/nova:check`, `/nova:review` |
| §5 검증 경량화 원칙 | `/nova:check`, `/nova:review`, `/nova:run` |
| §6 복잡한 작업의 스프린트 분할 | `/nova:run`, `/nova:auto` |
| §8 세션 상태 유지 | `context-chain` 스킬, `/nova:next` |
| §9 긴급 모드 (`--emergency`) | `/nova:auto`, `/nova:run` |

**이유**: `hooks/session-start.sh` 출력은 hard 2500 bytes / soft 1900 bytes 상한. 모든 규칙을 매 세션 주입하면 예산 초과 → 플러그인 로드 파손 리스크. `tests/test-scripts.sh`가 hard/soft 상한을 자동 검증한다.

**동기화 의무**: 이 문서의 §1~§9 내용이 변경되면 반드시:
1. 핵심 5개인 경우 → `hooks/session-start.sh` 동기화
2. on-demand 5개인 경우 → 해당 커맨드·스킬 파일의 "적용 규칙" 섹션 동기화
3. `bash tests/test-scripts.sh` 통과 확인 (동기화 자동 검증)

---

## §1. 작업 전 복잡도 + 위험도 판단

| 복잡도 | 기준 | 자동 행동 |
|--------|------|----------|
| **간단** | 버그 수정, 1~2 파일 수정, 명확한 변경 | 바로 구현 → 구현 후 독립 검증 |
| **보통** | 3~7 파일, 새 기능 추가 | Plan 작성 → 승인 → 구현 → 독립 검증 |
| **복잡** | 8+ 파일, 다중 모듈, 외부 의존성 | Plan → Design → 스프린트 분할 → 구현 → 독립 검증 |

> **복잡도 재판단**: 작업 중 수정 파일이 초기 예상을 넘어서면(예: 1파일 → 4파일 연쇄) 복잡도를 재판단한다.
> 인증/DB/결제 등 고위험 영역은 파일 수와 무관하게 한 단계 상향한다.

> **자가 완화 금지 (도메인 무관 적용)**: 인프라/빌드/설정/문서/테스트 변경도 파일 수 기준을 그대로 적용한다. "인프라성이라 과하다", "빌드 래퍼는 간단하다" 같은 자체 판단으로 Plan/Evaluator를 생략하는 것은 금지된다.
>
> **작업 중 재판단**: 구현 중 실제 변경 파일 수가 초기 판단을 초과하면(예: "간단(1~2파일)" 판단 후 3파일로 확장) 즉시 Plan 승격하고 사용자에게 알린다. 초기 판단 고수 금지. 파일 수가 계속 늘어나면 스프린트 분할 검토.
>
> 근거 사례: 2026-04 swk-cloud-manage 프로젝트에서 빌드 래퍼 4파일 수정이 "인프라성 간단 작업"으로 분류되어 Nova Always-On 규칙 전체가 우회됨. 이 패턴을 차단하기 위한 명시 조항.

> **최소 설계 기록**: Plan/Design을 생략하는 소규모 프로젝트도 비기능 요구사항(인증 방식, 외부 연동 인터페이스, 배포 환경 전환 조건)은 CLAUDE.md에 기록한다. 기록이 없으면 갭 분석 시 "의도적 미구현"과 "누락"을 구분할 수 없다.

> **deepplan 권장 조건 (복잡도 상향 조건)**: 아래 상황에서는 기본 `/nova:plan` 대신 `/nova:deepplan`을 권장한다. Explorer×3 병렬 탐색 + Critic + Refiner로 대안 비교·리스크 분석을 강화한다.
>
> - **아키텍처 전환**: 프레임워크 교체, 인증 구조 변경, 멀티 테넌트 전환 등
> - **큰 데이터 마이그레이션**: DB 스키마 변경, 데이터 이관, 외부 API 연동
> - **기존 시스템 다수 재구성**: 여러 모듈을 동시 변경하는 대형 리팩토링
> - **실패 비용이 높은 판단**: `/nova:plan`의 단일 패스 CPS로는 대안 비교가 불충분한 경우
>
> `/nova:auto --deep "요청"` 또는 단독 `/nova:deepplan "요청"` 으로 진입한다.

## §2. Generator-Evaluator 분리 (핵심)

**검증 분리는 필수(must), 구현 위임은 권장(should).**

> **Evaluator 독립성 기술적 정의**: "독립 서브에이전트"란 반드시 별도 서브에이전트 spawn으로 컨텍스트 창을 분리한 상태를 의미한다. 메인 에이전트가 직접 코드를 재읽고 "문제 없다"고 판단하는 것은 독립 검증이 아니다. 자가 점검: "나는 이 코드를 구현한 에이전트와 동일 컨텍스트 창에 있는가?" — 그렇다면 Evaluator가 아니다.

- 검증(Evaluator)은 **반드시** 독립 서브에이전트로 실행한다. 예외 없음.
- 검증 에이전트는 적대적 자세: "통과시키지 마라, 문제를 찾아라."
- **커밋 전 하드 게이트 (Hard Gate)**: 구현 완료 → tsc/lint 통과 → Evaluator 실행 → PASS → 커밋 허용. Evaluator PASS 없이 커밋 시 `hooks/pre-commit-reminder.sh`가 `exit 2`로 차단한다. 유일한 예외는 `--emergency` 플래그(프로덕션 장애 긴급 수정). 사용자가 "Evaluator 돌렸니?"라고 물어보는 상황은 프로세스 실패다.

구현(Generator) 위임은 복잡도에 따라 판단한다:

| 복잡도 | 구현 | 검증 |
|--------|------|------|
| **간단** (1~2 파일) | 메인 에이전트 직접 | 서브에이전트 필수 (Evaluator Lite) |
| **보통** (3~7 파일) | 메인 직접 가능, 서브에이전트 **권장** | 서브에이전트 필수 (Evaluator Standard) |
| **복잡** (8+ 파일) | 서브에이전트 **권장** | 서브에이전트 필수 (Evaluator Full) |

> **메인 에이전트가 직접 구현할 때의 위험**: 컨텍스트가 쌓이면 판단 품질이 떨어진다.
> 보통 이상의 작업에서 메인이 직접 구현하면, 검증 서브에이전트의 판정을 더 엄격히 적용한다.

> **배포 포함 작업의 검증 빈도**: 초반 1회만 돌리고 이후 생략하지 않는다. 배포 후 매번 경량 검증(환경변수, 엔드포인트, 로그)을 실행한다. 사용자가 스크린샷으로 버그를 보고하는 상황은 검증 실패다.

> **배포 전 검증 하드 게이트 (Hard Gate)**: Evaluator PASS 판정 전에는 배포 명령(deploy, push to production, docker push 등)을 실행하지 않는다. "auto로 진행", "빨리 배포" 요청이어도 이 게이트는 우회 불가. 유일한 예외는 `--emergency`(프로덕션 장애 긴급 수정). 로컬에서 curl 한 번이면 잡히는 버그를 프로덕션에서 사용자가 발견하는 것은 프로세스 실패다.

> **서브에이전트 가시성 (tmux split-pane)**:
> tmux 세션 내에서 서브에이전트를 별도 pane으로 표시하려면 **반드시 다음 패턴**을 사용한다:
> 1. `TeamCreate`로 팀 생성
> 2. `Agent`에 `name`, `team_name`, `run_in_background: true` 지정하여 스폰
>
> **단순 Agent 호출(foreground, 이름 없음)은 split-pane이 생성되지 않는다.**
> TeamCreate → 이름 붙인 에이전트 → 백그라운드 스폰이 pane 트리거다.
> 이 패턴은 필수(must)다. 단순 Agent 호출(foreground, 이름 없음)은 split-pane이 생성되지 않으며, Evaluator 독립성 요건을 충족하지 못한다.

## §3. 검증 기준

- **기능**: 요청한 것이 실제로 동작하는가? (CLAUDE.md 또는 NOVA-STATE.md의 요구사항 원문과 대조)
- **데이터 관통**: 입력 → 저장 → 로드 → 표시까지 완전한가? 트리거 이후 사용자에게 실제 전달되는가?
- **설계 정합성**: 기존 코드/아키텍처와 일관되는가?
- **요청 범위**: 변경된 라인이 사용자 요청과 직접 연결되는가? drive-by 리팩토링·포맷 교정·무관한 타입 힌트/주석 재작성 금지. (Karpathy "Surgical Changes" 원칙)
- **크래프트**: 에러 핸들링, 엣지 케이스, 타입 안전성
- **경계값**: 도메인 핵심 로직의 0, 음수, 빈 문자열, 최대값 등 경계 입력에서 크래시 없이 동작하는가?
- **Coverage Gate**: 변경 코드에 대한 테스트가 존재하는가? 커버리지가 하락하지 않았는가? (기본: Warning / `--strict`: FAIL 요소)
- **Learned Rules**: `.claude/rules/`에 프로젝트별 규칙이 있으면 Evaluation Criteria에 추가 적용한다.
- **자기 보안 진단** (v5.22.0+): Nova 플러그인 자기 코드(plugin.json/hooks/agents/skills/commands)는 `/nova:audit-self`로 정적 보안 룰셋(`docs/security-rules.md`) 검사.
- **메타-루프 가드** (v5.22.0+): 검사자(security-engineer) 자기 정의는 exclusion_list에 명시 제외. 검사자/검사 대상 분리 원칙이 깨지면 결과 무효 — v5.23.0+ 다관점(--jury) 외부 위임 예정.

## §4. 실행 검증 우선

"코드가 존재한다" ≠ "동작한다". 가능한 경우 실제 실행 테스트를 수행한다.

**배포 전 필수 검증 (Hard Gate)** — 이 항목을 통과하지 않으면 배포 금지:
- 로컬 빌드: 에러 없이 빌드 완료
- 로컬 테스트: 전수 테스트 통과 (테스트가 있는 경우)
- 핵심 API: curl로 주요 엔드포인트 정상 응답 확인 (서버 프로젝트)
- Evaluator: 독립 서브에이전트 검증 PASS 또는 CONDITIONAL(사용자 승인)

**배포 후 확인 검증** (배포가 포함된 작업 시 필수):
- 환경변수: 컨테이너/서버에 실제 반영되었는지 확인 (`docker exec`, `printenv` 등)
- 엔드포인트: curl로 주요 API 응답 확인
- 로그: 에러 로그 없는지 확인
- 사용자 흐름: 핵심 경로 1개 이상 수동 확인

**환경 변경 3단계**: 현재값 확인 → 변경 적용 → 반영 확인. 3단계를 모두 거치지 않으면 완료로 보지 않는다.

**경계값 검증**: 테스트 통과 ≠ 검증 완료. 도메인 핵심 로직은 경계값(0, 음수, 빈 값, 최대값)으로 크래시 여부를 추가 확인한다. 특히 금융/계산/인증 도메인은 필수.

## §5. 검증 경량화 원칙

- 검증이 무거우면 사용자가 우회한다.
- 기본 검증은 경량(Lite)으로 수행한다.
- `--strict`를 명시적으로 요청할 때만 풀 검증을 수행한다.

## §6. 복잡한 작업의 스프린트 분할

8개 이상 파일을 수정하는 작업은 독립 검증 가능한 스프린트로 분할한다.
- 각 스프린트마다 구현 → 검증 사이클을 반복한다.
- **스프린트 완료 = Evaluator 실행 필수**. 구현이 끝나면 다음 스프린트로 넘어가기 전에 반드시 Evaluator를 실행한다. Evaluator 없이 다음 스프린트 진행은 금지.
- 스프린트 간 전환 시 사용자에게 보고하고 확인받는다.
- NOVA-STATE.md에 전환 이력을 기록한다: "Sprint N 완료 → 확인 → Sprint N+1 시작".

## §7. 블로커 분류

구현 중 장애물을 만나면 다음 기준으로 분류한다:

| 분류 | 조건 | 대응 |
|------|------|------|
| **Auto-Resolve** | 외부 상태 변경 없이 되돌리기 가능 | 자동 해결 |
| **Soft-Block** | 진행 가능하나 런타임 실패 가능성 | 기록 후 계속 |
| **Hard-Block** | 데이터 손실/보안/돌이킬 수 없는 변경 | 즉시 중단, 사용자 판단 요청 |

불확실하면 Hard-Block으로 상향한다.

**자동 트리거**: 같은 원인의 실패가 2회 반복되면 블로커 분류를 강제한다. 분류 없이 3회 이상 수정→실패를 반복하지 않는다.

**코드 리뷰 시 블로커 기준** (구현 중 블로커와 별도):
- **런타임 크래시 유발**: 특정 입력에서 예외/크래시 → Hard-Block
- **데이터 손상/무결성 위반**: FK 미검증, 잘못된 집계 → Hard-Block
- **사용자 오판단 유발**: 잘못된 금액/상태 표시 → Hard-Block
- **기능 미동작**: 정의만 있고 호출 안 됨, dead code → Soft-Block

## §8. 세션 상태 유지

- 프로젝트 루트에 `NOVA-STATE.md`가 있으면 세션 시작 시 반드시 읽는다.
- 상태 파일은 50줄 이내를 유지한다 — 인덱스 역할만, 상세는 링크로.
- **Known Gaps 필수**: 검증 후 발견된 미커버 영역을 NOVA-STATE.md에 기록한다. "ALL PASS"만 기록하면 과신을 유도한다. 미커버 경계값, 미테스트 경로, 알려진 제약을 명시한다.

**즉시 업데이트 트리거** (이 2가지만 즉시, 나머지는 커밋 전 일괄):
- 블로커 발생/해소
- 검증 FAIL 수신

**커밋 전 일괄 갱신**: 배포 결과, 테스트 통과, 스프린트 완료 등은 커밋 전에 일괄 반영한다. 작업 중 관성적 갱신을 줄여 흐름을 유지한다.

**상태-수준 트림 ≠ 세션-수준 압축 (v5.21.0+)**: NOVA-STATE 50줄 트림은 *상태-수준* 인덱스 정리이고, Claude Code 세션 컨텍스트 창 자체의 `/clear`·`/compact` 시점은 별개다. 세션-수준 압축은 `skills/strategic-compact/SKILL.md` (마일스톤 직후 / 토큰 70%+ / 무관 작업 전환). 둘을 같은 것으로 혼동하면 토큰 압박이 해소되지 않는다.

## §9. 환경 설정 안전 규칙

- 설정 파일(database.yml, config/*.yml 등)을 직접 수정하여 환경을 전환하지 않는다.
- 환경변수(.env.local, DATABASE_URL 등) 또는 CLI 플래그로 전환한다.
- 프로덕션 설정이 포함된 파일을 sed/awk로 일괄 치환하지 않는다 — 의도하지 않은 범위 변경 위험.
- 로컬 테스트를 위해 설정 파일을 수정했다면, 작업 완료 전 반드시 원복 확인.

## §10. 관찰성 계약 (Sprint 1부터, v5.12.0)

모든 Nova 이벤트는 `.nova/events.jsonl`에 JSONL 라인으로 기록된다. KPI 자동 산출, 회귀 분석, 감사 용도. 기존 `NOVA-STATE.md`(사람용 상위 요약)과 **병행**한다 — 이중화 아닌 역할 분담.

**12 이벤트 타입 (v2 스키마, v5.20.0+)**: `session_start`, `session_end`, `phase_transition`, `evaluator_verdict`, `sprint_started`, `sprint_completed`, `blocker_raised`, `blocker_resolved`, `plan_created`, `jury_verdict`, `tool_constraint_violation`(Sprint 2b), `evolve_decision`(v5.20.0).

**신뢰도 산출 (v5.20.0+)**: `analyze-observations.sh --pattern confidence`가 분석 시점에 in-memory 계산. 공식: `clamp(0, 1, 0.3 + 0.1·N_unique_sessions + 0.2·N_accept - 0.3·N_reject)`. **자동 승격 금지** — 신뢰도 0.9여도 사용자 명시 결정 필수. `evolve_decision` 이벤트는 NOVA-STATE 갱신 트리거 X (JSONL only, 9 진입점 동결).

**MCP 부하 제한 (v5.20.1+, ECC P1-2 흡수)**: 프로젝트당 MCP 서버 ≤ 10개, 활성 도구 ≤ 80개 권장. 초과 시 200K 컨텍스트 창이 ~70K 이하로 잠식되어 컨텍스트 로스트 토큰 압박 원인이 됨 (출처: ECC 측정). 비용/컨텍스트 가이드 상세는 `docs/cost-optimization.md`, 진단/대응은 `docs/context-rot-diagnosis.md`.

**기록 주체**:
- `hooks/session-start.sh` → `session_start`
- `hooks/stop-event.sh` (Stop 후크) → `session_end`
- `evaluator` 스킬 → `evaluator_verdict` (판정 직후)
- `orchestrator` 스킬 → `phase_transition` (Phase 전이)
- `plan`/`deepplan` 커맨드 → `plan_created`
- `ask`/`jury` → `jury_verdict`

**Privacy**: `hooks/_privacy-filter.py`가 14 정규식 + 엔트로피 휴리스틱 + sensitive key 검사로 자동 redact. 결과: `{"redacted":true, "redaction_reasons":[...]}` 마커.

**옵트아웃**: `NOVA_DISABLE_EVENTS=1` → 즉시 기록 생략 (WARN 없음).
**경로 override**: `NOVA_EVENTS_PATH=<path>`. CI 러너(`CI=true`)는 자동으로 `${CI_ARTIFACTS:-.}/nova-events/events.jsonl`로.
**Rotation**: 기본 10MB / 5 파일 / 30일. `NOVA_EVENTS_MAX_SIZE`, `NOVA_EVENTS_MAX_FILES`로 override.

**Safe-default**: `record-event.sh` 실패(권한 거부/디스크 풀/lock 타임아웃/privacy 필터 실패)는 **stderr WARN + exit 0**. 관찰성 장애가 상위 skill을 마비시키지 않는다.

**KPI 산출**: `scripts/nova-metrics.sh [--since 7d|30d|all]` — 4종 KPI 출력. 분모 0이면 `N/A (insufficient data)`.

| KPI | 정의 |
|-----|------|
| Process consistency | 3파일+ 스프린트 중 같은 orchestration_id 내 plan_created가 선행된 비율 |
| Gap detection rate | evaluator_verdict=FAIL 중 같은 orchestration 내 이후 PASS 종결 비율 |
| Rule evolution rate | `docs/rules-changelog.md`의 approved / proposed 비율 |
| Multi-perspective impact | jury_verdict 중 `changed_direction=true` 비율 |

**상세 계약**: `docs/designs/harness-engineering-gap-coverage.md` — 이벤트 스키마 v1, 필드 단위, KPI 계산 정의(분자/분모/제외 조건), rotation 알고리즘.

**알려진 제약 (v5.12.0)**:
- **Entropy 휴리스틱 오탐**: 48자 이상 연속 `[A-Za-z0-9_/+=-]` + Shannon entropy > 4.5 토큰은 redact 대상. 긴 URL-safe 식별자·압축 payload preview·Base64 인코딩 데이터가 false-positive로 `<redacted:high_entropy>` 치환될 수 있다. **수용**: 과도한 redact가 누출보다 안전. Sprint 2b의 `input_preview`도 영향 가능 — Design 문서에 대안(화이트리스트) 명시.
- **`monotonic_ns` BSD 폴백**: `python3` 없는 환경(주로 BSD 최소 쉘)에서 `monotonic_ns` 필드는 `timestamp_epoch × 10⁹` 폴백. 이 폴백은 wall clock 따라 역행 가능(NTP 보정 시). 엄격한 단조 순서 보장은 `python3` 있을 때만.
- **`bootstrap=true` 이벤트**: v5.14.0+에서 `/nova:setup --permissions` 최초 실행 시 `scripts/setup-permissions.sh`가 자동 주입. 그 이전 사용자는 수동 트리거 필요.

## §11. 도구 제약 계약 (Sprint 2a부터, v5.14.0)

하네스 엔지니어링의 **constrain** 원칙: 에이전트가 사용할 수 있는 도구를 선언하고 감사·강제한다. Nova는 3 레이어로 구성한다.

### 3 레이어

| 레이어 | 담당 | 강제력 |
|--------|------|--------|
| **Declaration (선언)** | `.claude/agents/*.md` frontmatter `tools:` + `.claude-plugin/plugin.json` `tool_contract.per_agent` | 문서 |
| **Audit (감사)** | `scripts/audit-agent-tools.sh` — frontmatter × plugin.json 대조. 불일치 exit 1 | CI 게이트 |
| **Enforcement (강제)** | `.claude/settings.json` PreToolUse 훅(`scripts/precheck-tool.sh` — Sprint 2b) + `scripts/permissions-template.json` deny-by-default 리스트 | 런타임(사용자 프로젝트 opt-in) |

### U1 해소 결과 (2026-04-19)

- Claude Code v2.1.112 `plugin.json`은 permission 필드 **공식 미지원**(출처: [Plugins reference](https://code.claude.com/docs/en/plugins-reference.md)).
- 그래서 `plugin.json.tool_contract`는 **문서 + audit 소스**로만 존속, 런타임 enforcement는 아님.
- 우선순위(공식): **Managed Settings > Project `.claude/settings.json` > User settings**. 플러그인은 기본값(default)만 제공.
- 실제 런타임 차단은 **PreToolUse 훅**(Sprint 2b)이 유일.

### 사용자 프로젝트 적용 (`/nova:setup --permissions`)

`scripts/setup-permissions.sh`가 Nova 템플릿을 사용자 기존 `.claude/settings.json`에 **병합**한다(덮어쓰기 금지):

- **스칼라** (`permissions.defaultMode`): 사용자 기존값 보존
- **배열** (`permissions.allow`, `permissions.deny`): 합집합 + 중복 제거
- **충돌** (같은 항목이 user.allow + nova.deny): **deny 우선** + stderr `CONFLICT:` 리포트
- **최초 실행** 시 `bootstrap=true` session_start 이벤트 기록 (nova-metrics 분모 보정)

### `fewer-permission-prompts`와의 역할 분담

`fewer-permission-prompts`는 Claude Code **빌트인 스킬**로, 반복 승인 프롬프트를 줄이는 목적(사용자 편의). Nova `/nova:setup --permissions`는 보안 기반선(deny-by-default)을 **선언·감사·강제** 목적. 두 스킬은 같은 `.claude/settings.json`을 쓰므로 Nova의 병합 전략이 사용자 설정을 보존하도록 설계(위 참조).

### Deferred 도구

`ToolSearch` 같은 deferred 도구는 `tool_contract.deferred_allow`에 등재되어 audit을 통과한다. Agent에 `Agent` 도구가 포함되면 ToolSearch 암묵 허용. 상세: `docs/unknowns-resolution.md §U2`.

### 알려진 제약 (v5.14.0)

- **`disallowedTools` 필드는 Claude Code 측 enforce**: `.claude/agents/*.md` frontmatter의 `disallowedTools:`는 Claude Code 런타임이 자체 해석·강제한다. Nova `audit-agent-tools.sh`는 **`tools:` 선언만** plugin.json과 대조한다. `disallowedTools`를 Nova 감사에도 포함시키려면 `tool_contract.per_agent_disallow` 필드 추가 필요(미래 범위).
- **CONFLICT 리포트는 정확 매칭만**: `scripts/setup-permissions.sh`의 conflict 감지는 **문자열 정확 일치** 기준. glob 의미상 겹침(예: 사용자 `Bash(rm -rf /tmp/foo/*)` × Nova deny `Bash(rm -rf *)`)은 감지 못한다. Prefix/subset 감지는 Sprint 2b 이후 범위. 사용자는 최종 결과의 `deny` 배열을 직접 검토 권장.
- **Path traversal 방어**: `/nova:setup --permissions`의 `--target`은 cwd 또는 `$HOME` 하위만 허용(Sprint 2a Evaluator Issue #1 해소). 외부 경로 필요 시 `--allow-outside` 명시.
- **Symlink 거부**: `--target`이 symlink면 exit 2(원본 파일 덮어쓰기 방지, Issue #2 해소).
- **Bootstrap 중복 방지**: `setup-permissions.sh`는 `.nova/events.jsonl`에 `bootstrap=true` 이벤트가 이미 있으면 재주입하지 않는다(Issue #3 해소). **단 병렬 실행 시 race 존재**: 동시에 `xargs -P N setup-permissions.sh`로 N개 프로세스가 jq 체크와 record-event 사이 창에서 각자 bootstrap 주입 가능. 실무 빈도 낮음(사용자 1회 실행이 일반적). 후속 Sprint에서 flock 기반 dedup 적용 예정(Issue #3' 잔류).

### 런타임 Enforcement 범위와 한계 (Sprint 2b, v5.15.0)

`scripts/precheck-tool.sh`는 PreToolUse 훅으로 `.claude/settings.json permissions.deny` 패턴을 강제한다. **커버 범위**:

- **Bash**: `tool_input.command`를 `;`, `&&`, `||`, `|`로 **세그먼트 분리** 후 각 세그먼트 + 원본 전체에 glob 매칭 (복합 명령 bypass 방어, Sprint 2b Evaluator Issue #1 해소).
- **Write / Edit / NotebookEdit**: `tool_input.file_path`(또는 `notebook_path`) glob 매칭 (Issue #2 해소).
- **Settings 합집합**: `.claude/settings.json` + `.claude/settings.local.json`의 `permissions.deny`를 **union**한다. local이 project deny를 축소할 수 없음 (Issue #3 해소).

**알려진 한계 (수용)**:
- `$()`, 백틱, `eval` 내부 **동적 평가 경로는 lexical 검사로 탐지 불가**. 예: `X="rm -rf *"; $X`는 bypass 가능. 이런 경로는 allowlist에서 `Bash($X*)` 등 구조적 패턴으로 별도 제어 필요.
- **`sh -c/bash -c "..."` 래핑 bypass**: `Bash(bash -c "rm -rf *")`처럼 quoted argument 내부는 세그먼트 분리가 도달 못 함 → 현재 bypass 가능. 방어: `permissions.deny`에 `Bash(*sh -c*)`, `Bash(*bash -c*)` 광범위 패턴 추가 권장(단, 정상 `bash script.sh`도 걸릴 수 있음 — 사용자 판단).
- **Write/Edit `file_path` 정규화 없음**: glob 매칭은 문자열 그대로. `../` 상대경로, `//etc/passwd` 이중슬래시, symlink 해석 없음 → cwd 밖 write 우회 가능. 방어: `Write(*)` 또는 `Write(../*)` 전역 패턴 + `Write(/etc/*)`와 병용 권장.
- Write/Edit glob은 **파일 경로 기준**만. 콘텐츠 기반 차단(예: 특정 문자열 삽입 금지)은 미지원.
- Sprint 2b는 `matcher: "Bash|Write|Edit"` 범위만 훅 호출. Agent/ToolSearch/MCP 등 기타 도구는 훅 자체 미실행. 확장은 후속 Sprint.

**Fail-open 정책 (명시)**:
`precheck-tool.sh` 자체 오류(jq 없음 / settings.json invalid JSON / stdin 파싱 실패 / chmod 000)는 **exit 0**(도구 허용) + 가능한 경우 `schema_error` 이벤트 기록. 이는 "관찰성/감사 장애가 사용자 작업을 마비시키지 않는다"는 Nova 원칙의 귀결. **주의**: 공격자가 settings.json을 일부러 invalid JSON으로 만들면 fail-open이 발생 → 모든 deny 우회 가능. 사용자는 `.nova/events.jsonl`에서 `schema_error` 이벤트 빈도 관측으로 이 공격 탐지 권장.

**일시 해제 (`NOVA_BYPASS_PRECHECK`)**:
임시 위험 명령이 필요할 때 `NOVA_BYPASS_PRECHECK=1 bash ...` 또는 세션 env로 `export NOVA_BYPASS_PRECHECK=1`. precheck-tool은 차단 없이 통과하되 `tool_constraint_bypass` 이벤트를 감사용으로 기록.

**업그레이드 경로 (기존 사용자)**:
v5.14.0 이전에 `/nova:setup --permissions`를 실행했다면 `hooks.PreToolUse` 엔트리가 settings.json에 없다. **v5.15.0+ 첫 실행 시 `/nova:setup --permissions` 재실행** 필요. 자동 감지 + 추가는 후속 범위.

**In-situ 검증 권장**:
`tests/test-scripts.sh`는 stdin 모의 기반. 실제 Claude Code 런타임이 precheck-tool을 호출하는지 확인하려면 `field-test` 스킬로 격리된 worktree에서 실 플러그인 E2E 테스트 권장.

### autoMode `$defaults` 병행 사용 가이드 (Claude Code v2.1.118+)

Claude Code v2.1.118부터 사용자 `settings.json`의 `autoMode.allow` / `autoMode.soft_deny` / `autoMode.environment` 배열에 `"$defaults"` 토큰을 포함하면 **built-in 규칙을 보존하면서 커스텀 규칙을 덧붙일 수 있다**. 이전 버전은 사용자 선언이 built-in을 전체 대체.

Nova `permissions`와 autoMode는 **독립 스키마**다. autoMode는 사용자 전용 영역이고 Nova `setup-permissions.sh`는 건드리지 않는다. 하지만 autoMode를 쓰는 사용자가 Nova allow/deny를 병행할 때는 autoMode 쪽에서도 `$defaults`를 명시해야 Claude Code built-in을 유지한 채 Nova 영역이 그대로 동작한다.

**권장 패턴** (사용자 `.claude/settings.json` 일부):

```jsonc
{
  "permissions": { /* Nova가 관리. 수동 편집 지양 */ },
  "autoMode": {
    "allow": ["$defaults", "Bash(pnpm test)"],
    "soft_deny": ["$defaults"],
    "environment": ["$defaults"]
  }
}
```

`$defaults`를 생략하면 Claude Code built-in deny(예: `rm -rf` 계열)가 사라진다 → Nova `permissions.deny`만으로 방어. 둘 다 `$defaults`로 유지하는 것이 안전 기반선.

> Nova §9 "환경 설정 안전 규칙"의 "설정 파일 직접 수정 금지"는 유지. 본 가이드는 사용자가 autoMode를 **이미 사용 중일 때** Nova와 병행하는 정석 패턴만 문서화한다.

## §12. Profile Gate (v5.18.0)

`NOVA_PROFILE` 환경변수로 세션별 규칙 강도를 런타임에 선택한다. 기본값은 `standard`.

| 프로파일 | 적용 규칙 | 사용 시점 |
|----------|-----------|-----------|
| **lean** | §1~§3만 (복잡도·검증 분리·검증 기준). antipatterns 체크 스킵. pre-edit-check CPS 경고 스킵. | hotfix, 긴급 장애 대응, 실험적 탐색 |
| **standard** (기본) | 현재와 동일 — §1~§11 + 커맨드 전체. | 일반 개발 세션 |
| **strict** | standard + `docs/nova-antipatterns.md` 요약 주입. | 릴리스 전, 중요 아키텍처 변경, 코드 리뷰 집중 세션 |

**`--emergency` 호환성**: `hooks/session-start.sh`의 `--emergency` 플래그는 `lean` 프로파일의 별칭으로 동작한다. 기존 사용법(`bash session-start.sh --emergency`) 호환 유지.

**사용 예시**:
```bash
# hotfix 세션
NOVA_PROFILE=lean claude code .

# 릴리스 전 엄격 검토
NOVA_PROFILE=strict claude code .
```

**상세 카탈로그**: `docs/nova-antipatterns.md` — 12가지 합리화 패턴 + 차단 규칙.

## §13. Subagent Bootstrap Isolation (v5.19.0)

서브에이전트는 메인 컨텍스트에서 이미 전체 Nova 규칙을 받으므로, 동일한 1200~1900자 규칙을 재주입할 필요가 없다. `NOVA_SUBAGENT=1` 환경변수로 bootstrap을 격리해 토큰/속도를 절감한다.

### 원칙

- 서브에이전트가 session-start.sh를 받을 때, 메인 에이전트의 컨텍스트 창에 Nova 규칙이 이미 존재한다
- 중복 주입은 서브에이전트 토큰 예산을 낭비하고 context window 혼잡을 유발한다
- 격리는 **옵트인** — 환경변수 미설정 시 기존 동작(standard 프로파일) 유지

### 설정 방법

서브에이전트 spawn 시 환경변수를 설정한다:

```bash
# Claude Code 서브에이전트 launch 시
NOVA_SUBAGENT=1 <subagent-command>

# 또는 플랫폼 변수 (Claude Code 내부 서브에이전트 자동 감지용, 향후 지원 시)
CLAUDE_CODE_SUBAGENT=1 <subagent-command>
```

`NOVA_SUBAGENT=1`이 설정되면 `hooks/session-start.sh`는 다음 최소 메시지만 반환한다:
```
Nova subagent bootstrap skipped — 상세 규칙은 메인 컨텍스트 참조.
```

### 우선순위

`NOVA_SUBAGENT` 감지는 `NOVA_PROFILE` 분기보다 **우선** 처리된다. 서브에이전트에서는 NOVA_PROFILE 값에 관계없이 최소 메시지가 반환된다.

### 토큰 절감 추정

| 상황 | session-start.sh 출력 크기 | 절감 |
|------|--------------------------|------|
| 메인 에이전트 (standard) | ~1600 bytes | — |
| 서브에이전트 (NOVA_SUBAGENT=1) | ~100 bytes | ~94% |

서브에이전트가 1 세션에 N회 spawn되면 약 `(N × 1500) bytes`의 context window가 절감된다.

### 알려진 제약

- `NOVA_SUBAGENT` 감지는 환경변수 기반이므로 사용자가 직접 설정해야 한다. Claude Code가 서브에이전트를 자동으로 표시하는 플랫폼 변수(`CLAUDE_CODE_SUBAGENT`)가 공식 지원되면 자동 감지로 업그레이드 예정.
- 서브에이전트가 메인 컨텍스트 없이 독립 실행되는 경우(예: 별도 터미널 세션)에는 `NOVA_SUBAGENT=1`을 설정하지 않아야 한다.
