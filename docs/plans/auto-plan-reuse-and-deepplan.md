# [Plan] `/nova:auto` Plan 재사용 + `/nova:deepplan` 고성능 Plan 모드

> Nova Engineering — CPS Framework
> 작성일: 2026-04-19
> 작성자: jay
> Design: designs/auto-plan-reuse-and-deepplan.md

---

## Context (배경)

### 현재 상태
- `/nova:auto`는 `skills/orchestrator/SKILL.md` Phase 1에서 NOVA-STATE.md만 참고하고, `docs/plans/{slug}.md`·`docs/designs/{slug}.md`를 **전혀 확인하지 않는다**.
- 결과적으로 `/nova:plan` → `/nova:design` → `/nova:auto` 순서로 쓰면 Architect가 fresh spawn되어 CPS를 처음부터 다시 작성한다. 앞 단계 산출물이 폐기된다.
- `/nova:plan`은 CPS 골격의 단일 패스 생성이다. "기획/설계가 정말 중요한 시점"에는 Explorer/Critic 없이 얕다는 사용자 피드백.
- Claude Code `/ultraplan`은 클라우드 전용(30분, 별도 세션)이라 Nova 체인과 분리돼 있다. Nova는 **로컬 동기 강화판**이 필요하다.

### 왜 필요한가
- **중복 제거**: 사용자가 의도적으로 작성한 Plan/Design을 auto가 존중해야 "구조 우선" 철학이 유지된다.
- **깊이 있는 플래닝**: 아키텍처 전환·큰 마이그레이션 시점에 기본 `/nova:plan`은 부족. 사용자가 고성능 모드를 명시적으로 선택할 수 있어야 한다.
- **Nova 범용성 유지**: 외부 AI(GPT/Gemini) 의존 없이 Anthropic 키만으로 동작해야 함. 멀티 AI 자문은 `/nova:ask` 전용으로 분리.

### 관련 자료
- `skills/orchestrator/SKILL.md` — auto 파이프라인 소스
- `commands/plan.md`, `commands/auto.md` — 사용자 진입점
- `skills/jury/SKILL.md` — Claude 서브에이전트 다관점 평가 (재활용 대상)
- `skills/evaluator/SKILL.md` — 적대적 검증 엔진 (Plan 대상으로 재활용)
- 리서치 인사이트: Anthropic multi-agent research system (orchestrator-worker, +90%/15×토큰), Self-Refine/Reflexion (+10~20%p), Tree-of-Thought (대안 분기), Adaptive thinking (고정 budget 열위)

---

## Problem (문제 정의)

### 핵심 문제
`/nova:auto`의 Plan/Design 무시 + 기본 `/nova:plan`의 얕은 단일 패스 — 두 이슈를 함께 해결해야 "Plan이 구현보다 먼저다" 원칙이 사용자 경험 전반에서 작동한다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **Plan/Design 재사용 누락** | orchestrator Phase 1~3이 기존 산출물 미참조, Architect fresh spawn | 높음 |
| 2 | **Plan 깊이 부족** | 단일 패스 CPS, 대안 탐색·적대적 비판·반복 리파인 없음 | 높음 |
| 3 | **단독·통합 양립** | deepplan이 `/nova:deepplan` 단독 + `/nova:auto --deep` 통합 둘 다 지원해야 함 | 중간 |
| 4 | **범용성 (외부 AI 의존 금지)** | GPT/Gemini를 jury로 쓰면 키 없는 사용자는 동작 불가. Claude 서브에이전트 기반 필수 | 높음 |
| 5 | **커맨드/스킬 동기화** | 신규 커맨드 추가 시 hooks/session-start.sh, tests/test-scripts.sh, commands/next.md 동기화 필요 | 중간 |

### 제약 조건
- **기술적**: Claude Code 플러그인 구조 준수, CLAUDE.md는 사용자에게 전달 안 됨 → 모든 규칙은 `commands/*.md` · `skills/*/SKILL.md` · `hooks/session-start.sh`에 위치.
- **호환성**: 기존 `/nova:plan` 동작은 그대로 유지. deepplan은 **추가 모드**.
- **자원**: deepplan은 토큰 3~5×, 시간 10~20분 증가. 사용자에게 명시적으로 안내.
- **외부 의존**: OpenAI/Google API 키 없이도 deepplan 동작해야 함. 멀티 AI 자문은 `/nova:ask`에 한정.

---

## Solution (해결 방안)

### 선택한 방안

**방안 A 채택**: 2개 변경을 한 번의 minor 릴리스로 묶되, 스프린트 3개로 분할하여 독립 검증.

- **Sprint 1**: orchestrator에 Plan/Design 재사용 로직 추가
- **Sprint 2**: `/nova:deepplan` 단독 커맨드 + `deepplan` 스킬 신규 (Explorer→Synth→Critic→Refiner 파이프라인)
- **Sprint 3**: `/nova:auto --deep` 통합 + 문서/테스트/동기화

### 대안 비교

| 기준 | 방안 A (통합 minor) | 방안 B (2회 patch+minor) | 방안 C (deepplan만) |
|------|---------------------|--------------------------|---------------------|
| 릴리스 횟수 | 1회 minor | 2회 (patch→minor) | 1회 minor |
| 테스트 부담 | 1회 통합 | 2회 | 1회 |
| 사용자 인지 | 한 번에 명확 | 점진적(분산) | 일부만 개선 |
| 롤백 위험 | 중간 (묶음) | 낮음 (작은 단위) | 낮음 |
| 선택 | **채택** | 기각 (릴리스 오버헤드) | 기각 (1번 문제 방치) |

### 구현 범위

#### Sprint 1 — orchestrator Plan/Design 재사용 (1파일)

- [ ] `skills/orchestrator/SKILL.md` Phase 1에 slug 추출 + `docs/plans/{slug}.md`·`docs/designs/{slug}.md` 존재 확인
- [ ] Phase 2(Architect) 진입 전 분기:
  - Design 있음 → Phase 2·3 건너뛰고 Phase 4(Generator)로. Design을 Dev 프롬프트 기반으로 사용
  - Plan만 있음 → Phase 2 Architect가 **Plan을 기반으로** 설계 (fresh 금지)
  - 둘 다 없음 → 기존 동작 유지
- [ ] slug 후보가 여러 개 매칭되면 사용자에게 "기존 Plan {후보 목록} 재사용?" 확인
- [ ] `--fresh` 플래그 추가: 기존 산출물 무시하고 처음부터 (escape hatch)
- [ ] Phase 1 로그에 재사용 여부 명시 ("[Orchestrator] Plan 재사용: docs/plans/xxx.md")

#### Sprint 2 — `/nova:deepplan` 단독 모드 (3~4파일)

- [ ] `commands/deepplan.md` 신규 — 사용자 진입점, `deepplan` 스킬 호출
- [ ] `skills/deepplan/SKILL.md` 신규 — Explorer→Synth→Critic→Refiner 파이프라인 정의
- [ ] Explorer 서브에이전트 프롬프트 설계 (3개 역할):
  - `code-explorer`: 기존 코드/패턴/의존성 조사
  - `risk-explorer`: 실패 시나리오·블로커·엣지 케이스
  - `option-explorer`: 대안 3개 생성 (ToT식 분기)
- [ ] Synthesizer 로직: 3개 탐색 결과를 CPS 골격에 배치 + **Risk Map / Unknowns / Verification Hooks** 3섹션 추가
- [ ] Critic 단계:
  - 기본: `evaluator` 스킬 1회 (Plan 대상 적대적 검증 — "이 Plan이 실패할 3가지 시나리오")
  - `--jury` 옵션: `jury` 스킬 3인(architect/security/qa 페르소나)
- [ ] Refiner: Critic FAIL 이슈 반영 재작성, 기본 iteration=1, `--iterations=N` 지원
- [ ] Adaptive thinking 활용 (고정 budget 노출 X)
- [ ] 출력: `docs/plans/{slug}.md` + 헤더에 `> Mode: deep` 마커
- [ ] NOVA-STATE.md Phase를 `deep-planning`으로 설정 후 완료 시 `planning`으로 전환

#### Sprint 3 — `/nova:auto --deep` 통합 + 동기화 (5~6파일)

- [ ] `commands/auto.md` — `--deep` 플래그 문서화
- [ ] `skills/orchestrator/SKILL.md` Phase 1에 `--deep` 처리:
  - Plan **없음** + `--deep` → deepplan 호출해서 Plan 생성 후 기존 파이프라인 진입
  - Plan **있음** + `--deep` → `--deep` 무시 + 경고 ("기존 Plan 존중, deepplan 재실행하려면 `--fresh --deep`")
- [ ] `commands/plan.md` — `/nova:deepplan` 크로스 레퍼런스 추가 (언제 deepplan 써야 하는지)
- [ ] `docs/nova-rules.md` — deepplan 트리거 기준 추가 (§복잡도 판단 상향 조건)
- [ ] `hooks/session-start.sh` — 커맨드 목록에 `/nova:deepplan` 추가
- [ ] `tests/test-scripts.sh` EXPECTED_COMMANDS 배열에 `deepplan` 추가 + 동기화 테스트
- [ ] `commands/next.md` 워크플로우 추천 경로에 deepplan 진입 조건 추가

### 검증 기준

- **Sprint 1**: `/nova:auto "기능"`이 기존 `docs/plans/기능.md`를 감지하고 Phase 2 스킵 로그 출력. 없을 때는 기존 동작 그대로.
- **Sprint 2**: `/nova:deepplan "기능"` 단독 실행 시 `docs/plans/기능.md`에 Risk Map·Unknowns·Verification Hooks 섹션 존재. Explorer 3개 병렬 실행 로그 확인.
- **Sprint 3**: `/nova:auto --deep "기능"` 실행 시 deepplan 호출 후 orchestrator 파이프라인 진입. `bash tests/test-scripts.sh` 전체 통과. `bash hooks/session-start.sh | python3 -m json.tool` JSON 유효.

---

## Sprints (스프린트 분할)

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | orchestrator Plan/Design 재사용 | `skills/orchestrator/SKILL.md` (1) | 없음 | Plan/Design 있는 프로젝트에서 `/nova:auto` 실행 시 "재사용" 로그 + Phase 2 스킵 확인. `--fresh` 플래그로 기존 동작 복원 가능 |
| 2 | deepplan 파이프라인 신규 | `commands/deepplan.md` + `skills/deepplan/SKILL.md` + (선택) Explorer 서브에이전트 정의 (2~4) | Sprint 1 권장 (재사용 로직 먼저) | `/nova:deepplan "기능"` 실행 → `docs/plans/기능.md` 생성 + 3 섹션(Risk Map/Unknowns/Verification Hooks) 포함 + Critic PASS |
| 3 | auto 통합 + 동기화 | `commands/auto.md`, `commands/plan.md`, `commands/next.md`, `docs/nova-rules.md`, `hooks/session-start.sh`, `tests/test-scripts.sh` (5~6) | Sprint 1 + 2 | `/nova:auto --deep "기능"` 실행 시 deepplan 호출 후 기존 파이프라인 진입. 전체 테스트 통과. 플러그인 설치 시 커맨드 자동 등록 확인 |

- 각 스프린트는 독립 검증 가능
- Sprint 2는 Sprint 1 없이도 이론적으로 가능하지만, 통합 시나리오 테스트 일관성을 위해 순서 권장
- Sprint 3 완료 = `--deep` 사용자 플로우 end-to-end 동작

---

## X-Verification (다관점 수집)

> 이번 Plan은 주 리서치 + 사용자 피드백 2라운드로 수렴 완료. 추가 멀티 AI 자문 불필요. 섹션 유지는 추적용.

| AI | 의견 요약 | 합의 |
|----|----------|------|
| Claude (메인) | 통합 minor + 3 스프린트 분할 권고. 외부 AI jury 분리 필수 | O |
| 리서치 에이전트 | Anthropic multi-agent 패턴 채택, ToT식 대안 분기, Adaptive thinking 권고 | O |
| 사용자 | 멀티 AI 제거 → Claude 서브에이전트 jury만, `/ask`는 분리 | O |

합의 수준: **Strong Consensus**

---

## Notes
- Design 단계에서 **Sprint Contract**(Generator-Evaluator 사전 합의)를 스프린트별로 정의한다.
- Explorer 3개의 구체 프롬프트와 핸드오프 포맷은 Design에서 확정.
- deepplan과 `/ultraplan`(Claude Code 클라우드)의 역할 분리는 Sprint 2의 `commands/deepplan.md`에서 명시.
- 릴리스 수준: **minor** (새 커맨드 + 새 스킬 추가). 버전 예상: 현재 v5.10.2 → v5.11.0.
