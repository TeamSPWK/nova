---
name: jury
description: Nova LLM Jury — 다중 관점 평가로 단일 Evaluator의 편향을 보정
user-invocable: false
---

# Nova LLM Jury

> 단일 LLM 심판은 위치 편향(position bias)과 장황함 편향(verbosity bias)이 있다.
> 다중 관점으로 평가하면 이 편향을 구조적으로 상쇄할 수 있다.

이 스킬은 **2가지 모드**로 호출된다:

| 모드 | 호출처 | 페르소나 |
|------|--------|---------|
| **코드 리뷰** | `/nova:review --jury` | Correctness / Design / User |
| **Plan 리뷰** | `skills/deepplan` Phase C (`--jury` 옵션) | architect / security / qa |

---

## 모드 1: 코드 리뷰

`/nova:review --jury` 옵션으로 활성화한다.

### Jury 구성 (3인)

각 Jury는 독립 서브에이전트로 실행한다:

| Jury | 관점 | 핵심 질문 |
|------|------|----------|
| **Correctness** | 정확성 | 코드가 요구사항대로 동작하는가? |
| **Design** | 설계 | 아키텍처 원칙과 일관되는가? |
| **User** | 사용자 | 사용자가 문제 없이 쓸 수 있는가? |

### 합의 프로토콜

| Jury 합의 | 최종 판정 |
|-----------|----------|
| 3/3 PASS | **PASS** |
| 2/3 PASS + 1 CONDITIONAL | **PASS with notes** — 소수 의견 기록 |
| 2/3 PASS + 1 FAIL | **CONDITIONAL** — FAIL 사유 검토 필요 |
| 2/3 FAIL 이상 | **FAIL** |

합의와 다른 판정을 낸 Jury의 의견은 반드시 기록한다.

---

## 모드 2: Plan 리뷰

`skills/deepplan` Phase C에서 `--jury` 옵션이 지정될 때 호출된다.
호출 컨텍스트에 `mode: plan` 및 `file: docs/plans/{slug}.md`가 포함된다.

### Jury 구성 (3인)

Plan 리뷰 전용 페르소나. 코드 리뷰 페르소나와 독립적이다.

| Jury | 관점 | 핵심 질문 |
|------|------|----------|
| **architect** | 아키텍처 타당성 | Plan의 Solution이 기존 시스템과 자연스럽게 연결되는가? 확장성과 유지보수성이 고려되었는가? |
| **security** | 보안 경계 | 보안 경계, 권한 모델, 데이터 누출 시나리오가 Risk Map에 충분히 반영되었는가? |
| **qa** | 검증 가능성 | Verification Hooks의 Done 조건이 측정 가능한가? Sprint Contract 품질이 충분한가? 엣지 케이스가 누락되지 않았는가? |

### Plan 리뷰 페르소나 프롬프트

#### architect

```
역할: 시니어 아키텍트.
대상: docs/plans/{slug}.md

이 Plan의 아키텍처 타당성을 검토하라:
1. Solution이 기존 시스템 구조와 자연스럽게 연결되는가?
2. 확장성 문제(트래픽 증가, 데이터 증가)가 고려되었는가?
3. 다른 시스템 컴포넌트에 미치는 영향이 누락되지 않았는가?

판정: PASS 또는 FAIL. FAIL이면 구체적 이슈를 Critic Issues 포맷으로 반환하라.
```

#### security

```
역할: 보안 엔지니어.
대상: docs/plans/{slug}.md

이 Plan의 보안 관점을 검토하라:
1. 인증·인가 경계가 명확히 정의되었는가?
2. 데이터 누출 또는 권한 상승 시나리오가 Risk Map에 있는가?
3. 외부 의존성(API, 라이브러리)에서 공급망 리스크가 다루어졌는가?

판정: PASS 또는 FAIL. FAIL이면 구체적 이슈를 Critic Issues 포맷으로 반환하라.
```

#### qa

```
역할: QA 엔지니어.
대상: docs/plans/{slug}.md

이 Plan의 검증 가능성을 검토하라:
1. Verification Hooks의 각 항목이 실제로 측정 가능한가? ("성능 향상" 같은 모호한 조건은 FAIL)
2. 경계값·예외 케이스·실패 경로가 테스트 계획에 포함되었는가?
3. Sprint Done 조건이 Evaluator가 독립적으로 검증할 수 있는 형태인가?

판정: PASS 또는 FAIL. FAIL이면 구체적 이슈를 Critic Issues 포맷으로 반환하라.
```

### Plan 리뷰 합의 프로토콜

코드 리뷰와 동일한 합의 프로토콜을 적용한다:

| Jury 합의 | 최종 판정 |
|-----------|----------|
| 3/3 PASS | **PASS** |
| 2/3 PASS + 1 CONDITIONAL | **PASS with notes** — 소수 의견 기록 |
| 2/3 PASS + 1 FAIL | **CONDITIONAL** — FAIL 사유 검토 필요 |
| 2/3 FAIL 이상 | **FAIL** |

합의와 다른 판정을 낸 Jury의 의견은 반드시 기록한다.
FAIL 시 각 Jury의 이슈를 통합하여 단일 `## Critic Issues` 테이블로 반환한다 (deepplan Refiner가 소비).
