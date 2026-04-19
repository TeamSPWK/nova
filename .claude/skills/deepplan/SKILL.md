---
name: deepplan
description: "Nova DeepPlan — Explorer×3 병렬 탐색 → Synthesizer → Critic → Refiner 4단 파이프라인으로 깊이 있는 Plan 문서를 생성한다."
user-invocable: false
---

# Nova DeepPlan

자연어 요청을 받아 Explorer 3개를 병렬로 실행하고, 그 결과를 종합하여 Critic-Refiner 루프로 강화된 Plan 문서를 생성한다.

## 핵심 원칙

- **기존 체계 침범 금지**: CPS 골격을 유지한다. deepplan 출력물은 `/nova:design`, `/nova:auto`가 그대로 소비할 수 있어야 한다.
- **구조화된 핸드오프**: Explorer 3개의 출력 포맷을 사전 정의해서 Synthesizer가 예측 가능하게 통합한다.
- **Adaptive thinking 우선**: Explorer/Critic/Refiner 서브에이전트에 고정 thinking budget을 강제하지 않는다. 모델이 작업 복잡도에 따라 자율로 조절한다. (Anthropic 권고 — 고정 budget은 복잡한 작업에서 열위)
- **Generator ≠ Evaluator**: Critic(evaluator/jury)은 Plan을 작성한 컨텍스트와 독립된 서브에이전트로 실행한다.
- **무한 루프 방지**: `--iterations` 최대 3으로 clamp. Critic이 PASS를 내거나 iteration 소진 시 종료.

## 오케스트레이션 추적

Phase 진행 시 MCP 도구로 추적한다. MCP 도구가 사용 불가능한 환경에서는 추적 없이 실행한다.

| 시점 | MCP 도구 호출 |
|------|--------------|
| 파이프라인 시작 | `orchestration_start` |
| Phase 시작/완료 | `orchestration_update` |

---

## Execution

### 사전 처리: 플래그 파싱 + NOVA-STATE.md 갱신

1. `$ARGUMENTS`에서 요청 텍스트와 플래그를 분리한다.

   | 플래그 | 기본값 | 규칙 |
   |--------|--------|------|
   | `--iterations=N` | 1 | `max(1, min(N, 3))` — 초과 시 3으로 clamp, 미만 시 1로 clamp |
   | `--jury` | false | true이면 Critic에서 jury 스킬 호출 |

2. **slug 추출** (orchestrator와 동일 규칙):
   - 따옴표(`'` 또는 `"`) 안의 텍스트를 추출한다. 따옴표가 없으면 플래그(`--xxx`)를 제외한 전체 텍스트를 사용한다.
   - 공백을 `-`로 치환한다.
   - 한글·영문·숫자·하이픈 이외의 특수문자를 제거한다. **한글은 유지한다.**
   - slug가 빈 문자열이면 요청 첫 단어를 slug로 사용하고 경고를 출력한다: `[DeepPlan] slug 추출 실패 — 첫 단어를 slug로 사용: {단어}`
   - 예시: `"건폐율 시각화 추가"` → `건폐율-시각화-추가`, `"add carousel"` → `add-carousel`

3. **NOVA-STATE.md 갱신** (파일이 있을 때만):
   - Phase를 `deep-planning`으로 설정한다.
   - Last Activity 갱신:
     ```
     - /nova:deepplan → 시작 — docs/plans/{slug}.md | {ISO 8601}
     ```

4. 로그 출력:
   ```
   [DeepPlan] 시작 — slug: {slug}, iterations: {N}, jury: {true/false}
   [DeepPlan] 출력 경로: docs/plans/{slug}.md
   ```

---

### Phase A: Explorer × 3 병렬

3개 Explorer 서브에이전트를 **병렬**로 spawn한다 (`run_in_background: true`).
각 Explorer는 서로 독립적이며 출력 포맷이 고정되어 있다.

> Explorer는 Read/Glob/Grep 도구를 사용한다. 코드를 수정하지 않는다.

로그:
```
[DeepPlan] Phase A — Explorer × 3 병렬 시작
[DeepPlan]   code-explorer    spawn
[DeepPlan]   risk-explorer    spawn
[DeepPlan]   option-explorer  spawn
```

모든 Explorer 완료를 기다린다. 타임아웃은 10분.

#### Explorer 실패 처리

| 상황 | 동작 |
|------|------|
| 1개 실패 | 나머지 2개 결과로 Phase B 진행. 경고: `[DeepPlan] 경고: {역할}-explorer 실패 — 2개 결과로 진행` |
| 2개 실패 | 나머지 1개 결과로 진행. 경고 + 품질 저하 알림 |
| 3개 모두 실패 | 중단. 사용자에게 `/nova:plan` 폴백 안내: `[DeepPlan] Explorer 전체 실패 — /nova:plan으로 폴백하거나 재시도하세요` |

#### code-explorer 프롬프트

```
역할: 코드 탐색가. 주어진 요청과 관련된 기존 코드·패턴·의존성을 조사한다.

요청: {요청 원문}

수행할 것:
1. Read/Glob/Grep으로 요청과 관련된 파일, 모듈, 패턴을 탐색한다.
2. 현재 코드베이스의 관련 구조와 제약을 파악한다.
3. 구현에 영향을 줄 수 있는 의존성과 기존 패턴을 식별한다.

출력 형식 — 반드시 아래 헤더와 구조를 그대로 사용한다:

## Code Survey
- 관련 파일: [path:line 형태로 최대 10개]
- 주요 패턴: [현재 코드베이스에서 사용 중인 관련 패턴, 최대 5개]
- 의존성: [요청 구현에 필요한 외부/내부 모듈 의존성]
- 현재 제약: [현재 코드 구조가 구현에 가하는 기술적 제약, 최대 5개]

코드를 수정하지 않는다. 탐색과 분석만 수행한다.
```

#### risk-explorer 프롬프트

```
역할: 리스크 분석가. 주어진 요청의 실패 시나리오·엣지 케이스·운영 리스크를 브레인스토밍한다.

요청: {요청 원문}

수행할 것:
1. "이 기능이 실패할 3~7가지 시나리오"를 적대적으로 탐색한다.
2. 외부 의존성, 데이터 경계, 동시성, 배포 순서에서 발생할 수 있는 리스크를 식별한다.
3. 현재 모르거나 추가 조사가 필요한 항목을 열거한다.

출력 형식 — 반드시 아래 헤더와 구조를 그대로 사용한다:

## Risk Map
| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| {구체적 실패 시나리오} | H/M/L | H/M/L | {완화 방안} |

(H=High, M=Medium, L=Low. 최소 3개, 최대 8개 항목)

## Unknowns
- [추가 조사 없이 진행하면 위험한 항목. 구체적으로 "무엇을 모르는지" 서술. 최대 5개]

코드를 수정하지 않는다. 분석만 수행한다.
```

#### option-explorer 프롬프트

```
역할: 대안 탐색가. 주어진 요청에 대한 구현 방안 3개를 Tree-of-Thought 방식으로 생성하고 비교한다.

요청: {요청 원문}

수행할 것:
1. 구현 방안 3개(A/B/C)를 독립적으로 설계한다. 서로 명확히 구별되는 접근이어야 한다.
2. 각 방안의 장점, 단점, 구현 비용, 운영 리스크를 분석한다.
3. 현재 맥락(코드베이스 특성, 팀 역량, 시간 제약)에서 가장 권장되는 방안을 선택하고 ⭐ 표시한다.

출력 형식 — 반드시 아래 헤더와 구조를 그대로 사용한다:

## Alternatives
| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | {방안 A 한 줄 설명} | {장점} | {단점} | ⭐ 또는 빈칸 |
| B | {방안 B 한 줄 설명} | {장점} | {단점} | ⭐ 또는 빈칸 |
| C | {방안 C 한 줄 설명} | {장점} | {단점} | ⭐ 또는 빈칸 |

**권장 방안**: {A/B/C} — {선택 근거 2~3줄}

코드를 수정하지 않는다. 분석만 수행한다.
```

---

### Phase B: Synthesizer (메인 컨텍스트)

Explorer 결과를 CPS 골격에 배치하여 Plan 초안을 작성한다.

로그:
```
[DeepPlan] Phase B — Synthesizer 시작
[DeepPlan]   수집된 탐색 결과: code({완료/실패}), risk({완료/실패}), option({완료/실패})
```

**배치 규칙** — 새로 작성하지 않고, Explorer 출력을 merge/정렬한다:

| Plan 섹션 | 출처 |
|-----------|------|
| `## Context` | 요청 원문에서 배경·현재 상태·동기 도출 |
| `## Problem` | 요청 원문에서 핵심 문제 + MECE 분해. risk-explorer의 `## Risk Map` 항목을 제약 조건에 반영 |
| `## Solution — 선택한 방안` | option-explorer의 권장 방안 채택 근거 |
| `## Solution — 대안 비교` | option-explorer의 `## Alternatives` 테이블 그대로 사용 |
| `## Solution — 구현 범위` | code-explorer의 `현재 제약`을 기반으로 구현 체크리스트 도출 |
| `## Solution — 검증 기준` | `## Verification Hooks`의 Done 조건에서 핵심 항목 발췌 |
| `## Risk Map` | risk-explorer의 `## Risk Map` 그대로 주입 |
| `## Unknowns` | risk-explorer의 `## Unknowns` 그대로 주입 |
| `## Verification Hooks` | 신규 생성 — 검증 가능한 Done 조건 초안 (Sprint Contract 씨앗) |

**출력 파일 구조** (최종 Plan):

```markdown
# [Plan] {요청에서 추출한 기능명}

> Nova Engineering — CPS Framework
> 작성일: {YYYY-MM-DD}
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: {Refiner 실행 횟수 — Phase C 완료 후 갱신}
> Design: {designs/slug.md — Design 작성 후 경로 추가}

---

## Context (배경)

### 현재 상태
{현재 시스템/프로세스 상태}

### 왜 필요한가
{기술적·비즈니스 동기}

### 관련 자료
{code-explorer의 관련 파일 목록}

---

## Problem (문제 정의)

### 핵심 문제
{한 문장 요약}

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|

### 제약 조건
{code-explorer의 현재 제약 + risk-explorer 리스크 중 구조적 제약}

---

## Solution (해결 방안)

### 선택한 방안
{option-explorer 권장 방안 근거}

### 대안 비교
{option-explorer ## Alternatives 테이블 그대로}

### 구현 범위
- [ ] {code-explorer 현재 제약 기반 태스크}
- [ ] ...

### 검증 기준
{## Verification Hooks의 핵심 항목 발췌}

---

## Sprints (스프린트 분할)

{수정 파일 8개 이상이면 스프린트 분할, 이하면 단일 구현}

---

## Risk Map

{risk-explorer ## Risk Map 그대로}

---

## Unknowns

{risk-explorer ## Unknowns 그대로}

---

## Verification Hooks

> Sprint Contract 씨앗 — 이후 /nova:design 단계에서 구체화한다.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | {검증 가능한 Done 조건} | {grep/test/curl 등 구체적 명령} | Critical/Nice-to-have |
```

`docs/plans/` 디렉토리가 없으면 생성한다.
파일을 `docs/plans/{slug}.md`에 저장한다.

---

### Phase C: Critic

Critic 서브에이전트를 spawn하여 Plan 초안을 적대적으로 검증한다.

로그:
```
[DeepPlan] Phase C — Critic 시작 (모드: {evaluator/jury})
```

#### 기본 모드: evaluator 스킬 (Plan 검증 모드)

`evaluator` 스킬을 **Plan 대상 적대적 검증 모드**로 호출한다.
기존 코드 검증(Layer 1~3)과 구별되는 Plan 전용 검증이다. (evaluator SKILL.md "Plan 검증 모드" 참조)

Critic에게 전달하는 컨텍스트:
```
target: plan
file: docs/plans/{slug}.md

이 Plan 문서가 실패할 3가지 시나리오를 제시하라.
다음 관점에서 검증하라:
1. MECE 구멍: 문제 분해에서 빠진 영역이 있는가?
2. 검증 불가능한 Done 조건: Verification Hooks가 실제로 측정 가능한가?
3. 빠진 엣지 케이스: Risk Map에서 고위험 시나리오가 누락되었는가?
4. 대안 비교 타당성: 선택한 방안의 근거가 충분한가?

판정: PASS 또는 FAIL
FAIL이면 이슈 목록을 구조화하여 반환한다:
## Critic Issues
| # | Plan 섹션 | 이슈 | 심각도 | 수정 방향 |
|---|----------|------|--------|----------|
```

#### `--jury` 모드: jury 스킬 (Plan 모드)

`jury` 스킬을 **Plan 리뷰 모드**로 호출한다. (jury SKILL.md "Plan 모드" 참조)
architect/security/qa 3 페르소나가 독립적으로 Plan을 검토한다.

jury 스킬에 전달하는 컨텍스트:
```
mode: plan
file: docs/plans/{slug}.md
```

jury 합의 결과를 Critic 판정으로 사용한다.

#### Critic 판정 분기

| 판정 | 동작 |
|------|------|
| PASS | Phase D(저장/완료)로 진행 |
| FAIL | Refiner 진입. iteration 카운터 +1 |

---

### Phase D: Refiner 루프

Critic FAIL 시 Refiner를 실행한다.

로그:
```
[DeepPlan] Phase D — Refiner 시작 (iteration {현재}/max {N})
```

**루프 로직**:

```
iteration_count = 0
max_iterations = min(flags.iterations or 1, 3)

loop:
  verdict = critic(plan_draft)            # Phase C
  if verdict.pass or iteration_count >= max_iterations:
    break
  plan_draft = refine(plan_draft, verdict.issues)
  iteration_count += 1
```

**Refiner 서브에이전트 프롬프트**:

```
역할: Plan 개선자. Critic 이슈 목록을 받아 Plan을 재작성한다.

현재 Plan: {plan_draft 전체 내용}

Critic 이슈:
{verdict.issues 목록}

수행할 것:
1. Critic이 지적한 각 이슈를 Plan의 해당 섹션에서 수정한다.
2. 이슈와 무관한 섹션은 건드리지 않는다 (최소 변경 원칙).
3. Risk Map, Unknowns, Verification Hooks를 Critic 지적에 맞게 보강한다.
4. 수정 후 전체 Plan을 반환한다. (파일 저장은 Orchestrator가 수행)
```

**iteration 소진 시 (최대 도달, Critic 여전히 FAIL)**:

Plan을 저장하되 헤더에 미해결 마커를 추가한다:

```markdown
> Mode: deep
> Iterations: {N}
> ⚠️ Critic Unresolved: {N}건 — 사용자 검토 권장
```

로그:
```
[DeepPlan] 경고: iteration 한도({N}) 도달, Critic 이슈 {M}건 미해결 — 사용자 검토 필요
```

---

### Phase E: 저장 및 완료

1. **최종 Plan 헤더 업데이트**:
   ```markdown
   > Mode: deep
   > Iterations: {실제 Refiner 실행 횟수}
   ```

2. **파일 저장**: `docs/plans/{slug}.md`에 최종 Plan 저장.

3. **NOVA-STATE.md 갱신** (파일이 있을 때만):
   - Phase를 `planning`으로 복귀.
   - Last Activity 갱신:
     ```
     - /nova:deepplan → 완료 — docs/plans/{slug}.md | {ISO 8601}
     ```

4. **완료 보고**:
   ```
   ━━━ Nova DeepPlan — 완료 ━━━━━━━━━━━━━━━━━━━━━
     요청: {요청 원문}
     출력: docs/plans/{slug}.md
     Mode: deep | Iterations: {N} | Critic: {PASS/FAIL→resolved/FAIL→unresolved}

     Explorer 결과:
       code-explorer    {완료/실패}
       risk-explorer    {완료/실패}
       option-explorer  {완료/실패}

     추가 섹션: Risk Map ({리스크 수}건) · Unknowns ({항목 수}건) · Verification Hooks ({항목 수}건)

     다음 단계:
       /nova:design "{요청 원문}"  — 기술 설계 작성
       /nova:auto   "{요청 원문}"  — 설계 → 구현 → 검증 자동 실행
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

---

## 에러 처리 요약

| 에러 | 대응 |
|------|------|
| slug 추출 실패 | 첫 단어 사용 + 경고 |
| Explorer 1~2개 실패 | 나머지로 진행 + 경고 |
| Explorer 3개 모두 실패 | 중단 + `/nova:plan` 폴백 안내 |
| Explorer 타임아웃 (10분) | 실패 처리 (위와 동일) |
| Critic FAIL + iteration 소진 | 최종 Plan 저장 + `⚠️ Critic Unresolved` 마커 + 사용자 검토 안내 |
| `--iterations` 범위 초과 | 3으로 clamp + 정보 로그: `[DeepPlan] --iterations={입력값} → 3으로 clamp` |

## 플래그

| 플래그 | 기본값 | 설명 |
|--------|--------|------|
| `--iterations=N` | 1 | Critic→Refiner 루프 최대 횟수. 1~3으로 clamp |
| `--jury` | false | Critic 단계에서 jury 스킬(Plan 모드) 호출 |

## Input

$ARGUMENTS
