---
name: strategic-compact
description: "세션 컨텍스트 압축(/clear · /compact) 시점을 판단해야 할 때. — MUST TRIGGER: /nova:plan·/nova:design·/nova:auto 마일스톤 직후, 토큰 사용량 70%+ 도달, 무관 작업 전환 직전."
description_en: "Use when you must decide whether to /clear or /compact the session context. — MUST TRIGGER: just after /nova:plan, /nova:design, or /nova:auto milestone, when token usage exceeds 70%, or before switching to an unrelated task."
user-invocable: false
---

# Nova Strategic Compact

세션-수준 컨텍스트 압축 시점을 판단한다. NOVA-STATE 50줄 트림이 *상태-수준* 압축이라면, 본 스킬은 *세션-수준* (Claude Code 컨텍스트 창 자체)의 `/clear`·`/compact` 적기를 안내한다. Nova 5기둥 중 **맥락 기둥**의 마지막 한 조각 — 진단(P0-1 컨텍스트 로스트 4원인 카탈로그)에서 자동 안내까지 잇는 출구.

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §8` 세션 상태 유지 — STATE 트림과 세션 압축의 분리
- `docs/nova-rules.md §10` 관찰성 계약 — events.jsonl로 후험 검증 가능

## 핵심 원칙

1. **상태-수준 ≠ 세션-수준.** NOVA-STATE.md 50줄 트림(`skills/context-chain/SKILL.md`)은 사람-읽는 인덱스 트림이지 Claude 컨텍스트 창 압축이 아니다. 둘은 **별도 트리거, 별도 효과**.
2. **`/clear` ≠ `/compact`.** `/clear`는 무관 작업 사이 즉시 비움(요약 없음), `/compact`는 마일스톤 사이 요약 압축. 잘못 쓰면 Generator 컨텍스트가 회복 불가능하게 손실된다.
3. **AI는 제안, 인간은 결정.** 본 스킬은 *시점 안내*만 한다 — `/compact`·`/clear`는 사용자가 직접 입력. 자동 실행 금지 (메모리 `feedback_evidence_first_identity` 정합).
4. **9 진입점 동결 유지.** 본 스킬은 NOVA-STATE 갱신 트리거를 추가하지 않는다 (v5.19.6 state-prune-symmetry 룰 보존).

## MUST TRIGGER (적기)

| 시점 | 권장 동작 | 사유 |
|------|----------|------|
| `/nova:plan` 완료 직후 | `/compact` 권장 | Plan 결과는 docs/plans/{slug}.md에 보존됨 — 컨텍스트는 요약해도 안전 |
| `/nova:design` 완료 직후 | `/compact` 권장 | Design 결과는 docs/designs/{slug}.md에 보존됨 |
| `/nova:auto` Phase 종료 시 | `/compact` 권장 | NOVA-STATE에 Recently Done 갱신됨 — 다음 Phase는 요약본만 있어도 충분 |
| 토큰 사용량 70%+ 도달 | `/compact` 또는 `/clear` | 80%+ AUTOCOMPACT 발동 전 사용자 통제 압축 (`docs/cost-optimization.md` 권장 50%와 정합) |
| 무관 작업 전환 직전 | `/clear` | 어텐션 희석 사전 차단 (`docs/context-rot-diagnosis.md` §1 원인 1) |
| 에이전트 spawn 직전 (메인 토큰 70%+) | `/compact` | 서브에이전트 spawn 시 메인 컨텍스트가 과적이면 핸드오프 품질 저하 |

## MUST NOT TRIGGER (금기)

| 시점 | 금지 사유 |
|------|----------|
| 구현 sprint 도중 | Generator 컨텍스트 살아있어야 — Plan-Design 의도가 요약으로 손실되면 sprint 중간 일관성 붕괴 |
| Evaluator 검증 직전 | 적대적 검증은 *같은 컨텍스트* 재현 필요 — 압축 후 검증은 Generator-Evaluator 분리 원칙 훼손 |
| 블로커 분석 도중 | 블로커는 컨텍스트 의존적 — 압축 시 원인 추적 불가능 |
| 회귀 테스트 디버깅 도중 | 실패 메시지·스택은 원본 보존 가치 높음 |

## 컨텍스트 로스트 4 원인 매핑

`docs/context-rot-diagnosis.md` 4 원인별 1차 대응:

| 원인 | 대응 |
|------|------|
| 어텐션 희석 (Attention Dilution) | 무관 작업 전환 시 `/clear` |
| 명령 충돌 (Instruction Conflict) | `/nova:check` 정합성 검증 우선 (`/compact`로 해결 X) |
| 토큰 예산 압박 (Token Budget Pressure) | 70%+ 도달 시 `/compact` + MCP 비활성화 (P1-2 ≤10/80) |
| 관련성 미스매치 (Relevance Mismatch) | `Explore` 서브에이전트 분리 (`/compact` 무관) |

> 4 원인 모두에 `/compact`가 답이 아니다. 본 스킬은 *해당 원인일 때만* 압축을 권장한다.

## ECC vs Nova 차이 (정체성 보존)

ECC `affaan-m/everything-claude-code` Strategic Compact는 *예방* 중심. Nova는:

- **예방**: 본 스킬 (세션-수준) + NOVA-STATE 50줄 트림 (상태-수준) 이중 압축
- **진단**: `docs/context-rot-diagnosis.md` 4 원인 카탈로그
- **측정**: `.nova/events.jsonl` 신뢰도(v5.20.0+) — 본 스킬 적용 전후 failures/CONDITIONAL 비율 비교 (v5.22.0+ 후험)

ECC 본문 미확보(404). 사용자 LiveWiki 요약(영상 05:57~06:24) + Nova `context-rot-diagnosis` "Nova 1차 대응" 표 기반 추론.

## 안티패턴

- 구현 도중 토큰이 부족하다고 `/compact` 발동 → Plan-Design 의도 손실. 정답: 작업 단위를 쪼개거나 Plan 분할.
- NOVA-STATE 트림과 세션 압축을 같은 것으로 혼동 → 둘 다 해야 토큰 압박 해소.
- `/compact` 마일스톤마다 자동 강제 → 사용자 결정권 박탈. 본 스킬은 안내만.
- Evaluator 검증 직전 압축 → 적대적 검증 무력화.

## Refs

- `docs/proposals/2026-04-29-ecc-adversarial-gap.md` §P0-3 — 본 스킬 출처
- `docs/context-rot-diagnosis.md` — 4 원인 진단 카탈로그
- `docs/cost-optimization.md` — AUTOCOMPACT 50% 권장
- `skills/context-chain/SKILL.md` — 상태-수준 트림 (역할 분리)
