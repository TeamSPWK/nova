---
name: jury
description: "단일 Evaluator의 편향이 우려되는 중요 판단일 때 여러 관점으로 재검토한다. — MUST TRIGGER: 아키텍처 결정, 릴리스 게이트 의심 케이스, 사용자가 /nova:ask 또는 다관점 평가를 요청할 때."
description_en: "Use when single-Evaluator bias is a concern and an important judgment needs a multi-perspective re-review. — MUST TRIGGER: architectural decisions, suspicious release-gate cases, or when the user invokes /nova:ask or requests multi-perspective evaluation."
user-invocable: false
---

# Nova LLM Jury

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §10` 관찰성 계약 — 최종 합의 판정 직후 `jury_verdict` 이벤트 기록

## 관찰성 훅 (v5.12.0+)

합의 판정 후 반드시:
```bash
bash hooks/record-event.sh jury_verdict "$(jq -cn \
  --arg cl "$CONSENSUS" \
  --argjson cd "$CHANGED" \
  '{consensus_level:$cl, changed_direction:$cd}')" 2>/dev/null || true
```
Safe-default: 기록 실패는 판정 반환에 영향 없음.

> 단일 LLM 심판은 위치 편향(position bias)과 장황함 편향(verbosity bias)이 있다.
> 다중 관점으로 평가하면 이 편향을 구조적으로 상쇄할 수 있다.

이 스킬은 **3가지 모드**로 호출된다:

| 모드 | 호출처 | 페르소나 |
|------|--------|---------|
| **코드 리뷰** | `/nova:review --jury` | Correctness / Design / User |
| **Plan 리뷰** | `skills/deepplan` Phase C (`--jury` 옵션) | architect / security / qa |
| **보안 진단** | `/nova:audit-self --jury` (v5.23.0+) | Red(공격자) / Blue(방어자) / Auditor(중재자) |

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

---

## 모드 3: 보안 진단 (v5.23.0+, ECC §P2-3 흡수)

`/nova:audit-self --jury`에서 호출된다. 호출 컨텍스트에 `mode: audit`, `target: nova-self-codebase`, `rules_doc: docs/security-rules.md`, `scan_targets`, `exclusion_list`가 포함된다.

> 단일 security-engineer는 **자기 합리화 편향**(self-justification bias)이 있다 — 자기 룰셋의 false negative를 잘 못 본다.
> Red(공격자)/Blue(방어자)의 적대적 검증으로 이 편향을 구조적으로 상쇄하고, Auditor가 최종 중재한다.

### Jury 구성 (3인)

각 Jury는 독립 서브에이전트로 실행한다 — Generator-Evaluator 분리 원칙(§2).

| Jury | 관점 | 핵심 질문 |
|------|------|----------|
| **Red (공격자)** | 우회·약점 탐색 | 이 룰을 우회하는 방법은? 의도적으로 false negative를 만들 수 있는가? |
| **Blue (방어자)** | 보수적 보고 | 매칭된 위반이 실제 보안 이슈인가? false positive를 최소화하라 |
| **Auditor (중재자)** | 최종 중재 | Red의 우회 케이스 + Blue의 검증 결과를 통합. Critical/Warning/Info 최종 분류 |

### 보안 진단 페르소나 프롬프트

#### Red (공격자)

```
역할: 적대적 보안 연구자(Red Team).
대상: docs/security-rules.md 30 룰셋 + Nova 자기 코드베이스
컨텍스트: mode=audit, scan_targets=<plugin/hooks/agents/skills/commands>, exclusion_list=<메타-루프 가드>

이 룰셋의 약점을 공격자 관점에서 발굴하라:
1. 각 룰의 grep/jq pattern을 우회하는 코드 패턴은? (false negative)
2. 룰셋이 cover하지 못하는 카테고리의 보안 위협은? (Known Gap 외)
3. exclusion_list가 합리적인가? 메타-루프 가드를 악용한 자기 면제 가능성은?

우선 false negative 후보 5개 이내로 보고. 형식:
- {룰 ID 또는 새 룰 후보}: {우회 시나리오 1줄 + 예시 코드}
판정: PASS(룰셋 견고) 또는 FAIL(우회 케이스 발견). FAIL 시 위 5개 이내 목록 필수.
```

#### Blue (방어자)

```
역할: 보수적 보안 엔지니어(Blue Team).
대상: security-engineer가 보고한 위반 항목 + docs/security-rules.md
컨텍스트: mode=audit, security_engineer_report=<Phase 2 결과>

각 보고된 위반을 검증하라 — false positive를 최소화하는 게 목표:
1. {file:line} 매칭이 실제 보안 이슈인가? normal_example과 대조하라
2. Critical 분류가 적절한가? Warning 또는 Info로 강등 가능한가?
3. 룰의 risk_example과 본 매칭이 동질한 리스크인가?

판정: PASS(모든 보고 정확) 또는 CONDITIONAL(N건 강등 권고). 형식:
- {Rule ID, file:line}: {KEEP|DEMOTE_TO_WARNING|DEMOTE_TO_INFO|DROP_AS_FP} — {1줄 사유}
```

#### Auditor (중재자)

```
역할: 보안 감사관(Auditor) — 최종 중재.
대상: Red 보고 + Blue 보고 + security-engineer 원본 보고
컨텍스트: mode=audit, red_report, blue_report, original_report

세 보고를 통합하여 최종 보안 진단을 산출하라:
1. Red가 발견한 false negative 후보 → 신규 룰 제안 또는 룰 수정 권고로 변환
2. Blue가 강등 권고한 항목 → 원본 분류와 비교, 최종 등급 결정
3. 원본 security-engineer 보고 중 Red/Blue 모두 합의한 항목 → KEEP

최종 출력 (audit-self Phase 5에 직접 입력):
- ## Critical (N건): {Rule ID, file:line, 1줄}
- ## Warning (N건): 동일
- ## Info (N건): 동일
- ## Red 발견 — 룰셋 보강 권고 (N건): {새 룰 후보}
- ## Blue 강등 — FP 의심 (N건): {강등 사유}
- ## 합의 프로토콜 결과: 3/3 PASS | 2/1 split | etc

판정: PASS(Critical 0) | FAIL(Critical ≥1) | INCONCLUSIVE(3-way split). audit-self가 본 결과를 NOVA-STATE/Last Activity 1줄로 기록.
```

### 보안 진단 합의 프로토콜

코드/Plan 리뷰와 다른 **3-way 통합** 형태:

| Red 판정 | Blue 판정 | Auditor 최종 |
|----------|-----------|-------------|
| PASS (룰셋 견고) | PASS (보고 정확) | **PASS** — 진단 종결 |
| PASS | CONDITIONAL (강등 권고) | **PASS with demotion** — Blue 권고 반영 |
| FAIL (우회 케이스 발견) | PASS | **CONDITIONAL** — Red 권고 v5.x.y+ 룰 보강 백로그 |
| FAIL | CONDITIONAL | **FAIL** — Red+Blue 양측 이슈, 즉시 검토 |

**Generator-Evaluator 분리 강화**: Red/Blue/Auditor 모두 독립 서브에이전트로 spawn (Read/Glob/Grep만). 메인 컨텍스트는 Auditor 결과를 grep으로 1회 사실 검증 (feedback_evaluator_hallucination 메모리 원칙).

**관찰성 훅**: 모드 3 합의 후 `jury_verdict` 이벤트 기록 — `mode=audit` 필드 포함. 차후 KPI(`audit-self FP rate`, `Red 발견 룰 보강율`) 산출 가능.
