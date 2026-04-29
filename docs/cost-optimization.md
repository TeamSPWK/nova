# Cost Optimization (비용 최적화 가이드)

> Nova v5.20.1+ — ECC P0-2 흡수
> 출처: [Adversarial Gap Analysis (2026-04-29)](proposals/2026-04-29-ecc-adversarial-gap.md) + ECC `affaan-m/everything-claude-code` settings 패턴
> 목적: Nova evaluator/jury/orchestrator가 다중 서브에이전트를 spawn하면서 비용 폭발 방지. Multi-AI는 옵션 (메모리 `feedback_evidence_first_identity`).

---

## 핵심 원칙

1. **메인 ≠ 서브에이전트.** 메인은 의사결정, 서브에이전트는 실행/검색.
2. **모델 계층화.** 복잡도에 따라 Opus 4.7 / Sonnet 4.6 / Haiku 4.5 분기.
3. **Thinking 예산 제한.** 기본 10K, 복잡도 8+에서만 31999.
4. **AUTOCOMPACT 적극 활용.** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`으로 자동 압축 임계 낮춤 (NOVA-STATE 50줄 룰과 정합).

---

## 권장 settings (~/.claude/settings.json)

```json
{
  "model": "sonnet",
  "env": {
    "MAX_THINKING_TOKENS": "10000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50"
  }
}
```

> 출처: ECC `affaan-m/everything-claude-code` 측정 — 누적 ~80% 비용 절감. Nova 워크로드 검증은 v5.22.0+ 후험.

---

## 모델 선택 권장표

| 사용처 | 모델 | 사유 |
|--------|------|------|
| **메인 컨텍스트 (의사결정)** | **Opus 4.7** 또는 **Sonnet 4.6** | 사용자 워크플로 따름. 복잡도 8+ 작업은 Opus 권장 |
| **Evaluator 서브에이전트 (적대적 검증)** | **Sonnet 4.6** | 보수적 PASS 보류 + 비용 균형 |
| **Explore / 검색 서브에이전트** | **Haiku 4.5** | read-only, 결과만 메인에 반환 |
| **Jury (architect/security/qa)** | **Haiku 4.5** | 다관점이 본질, 깊이 X |
| **Orchestrator phase 전이 통제** | **Haiku 4.5** | 메타 작업 |
| **/nova:ask Multi-AI (Claude+GPT+Gemini)** | **옵션** | 항상 켜기 X — 큰 결정 시점에만. API 비용 3중 |

> Sub-agent 모델 환경변수: `CLAUDE_CODE_SUB_AGENT_MODEL=haiku` (Claude Code v2.1+ 지원)

---

## MAX_THINKING_TOKENS 가이드

| 작업 복잡도 | 권장 값 | 사유 |
|-------------|---------|------|
| 1~2 (간단 — 수정/단순 추가) | **10000** | 기본 31999는 과도 |
| 3~7 (보통 — Plan 단계) | 10000~20000 | 사용자 워크플로 따름 |
| 8+ (복잡 — 아키텍처 전환) | **31999** (또는 그 이상) | deepplan 4단 파이프라인 / 보안 결정 |

`set MAX_THINKING_TOKENS=10000` 로 설정 시 Nova 자동 규칙 적용 작업의 70%+ 가 충분히 처리됨 (CPS Plan/Design은 thinking 위주가 아닌 구조화 위주).

---

## CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50

Claude Code 자동 압축은 기본적으로 컨텍스트 80%+ 도달 시 발동. 50%로 낮추면:

- 빠른 압축 → 토큰 잠식 회피
- NOVA-STATE 50줄 룰과 정합 (Phase 1 압축 = STATE 트림과 같은 임계)
- *단점*: 압축 빈도 ↑ — Strategic Compact 스킬(v5.21.0)이 적절 시점 안내 필요

---

## Nova 작업별 예상 비용 (참고)

| Nova 명령 | 메인 모델 | 서브에이전트 spawn | 예상 토큰 (응답 1회) |
|-----------|----------|-------------------|--------------------|
| `/nova:plan` | Opus/Sonnet | 0~1 | ~5K |
| `/nova:deepplan` | Opus/Sonnet | **3** (Explorer) + 1 (Critic) + 1 (Refiner) | ~30K |
| `/nova:auto` (orchestrator) | Opus | 가변 (Phase별) | ~50K~ |
| `/nova:review --fast` | Sonnet | 1 (evaluator) | ~10K |
| `/nova:ask` Multi-AI | Opus + 외부 API 2종 | 0 | ~15K + GPT/Gemini API |
| `/nova:evolve --scan` | Sonnet | 0 | ~10K (+ WebSearch) |

> 위 수치는 Sprint 1 baseline (`docs/baselines/v5.20.0-baseline.md`) 기준 추정. 실측은 v5.22.0+에서 events.jsonl `duration_ms` 통계 (Sprint 2 v5.21.0 PostToolUse Spike 후) 가능.

---

## 비용 절감 체크리스트

- [ ] settings.json에 `model: "sonnet"` 또는 `opus` 명시 (default 자동 선택 회피)
- [ ] `MAX_THINKING_TOKENS=10000` (기본 31999)
- [ ] `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`
- [ ] `CLAUDE_CODE_SUB_AGENT_MODEL=haiku` (해당 시)
- [ ] MCP 서버 ≤10개, 활성 도구 ≤80개 (P1-2 룰)
- [ ] 무관 plugin disable (claude plugin prune)
- [ ] `/nova:ask` Multi-AI는 큰 결정 시점에만

---

## 측정

v5.20.0 baseline + v5.20.1 (본 가이드) 도입 이후의 비용 변화는:

- **events.jsonl `tool_call` 빈도** — 도구 호출 절약 효과
- **session 평균 길이** — AUTOCOMPACT 50% 효과
- **evaluator/jury 호출 빈도** — 서브에이전트 모델 분기 적용 후 비용 변화

측정 인프라 활용은 v5.22.0+ 에서 본 가이드 적용 사용자 vs 미적용 baseline 비교.

## Refs

- [ECC Adversarial Gap Analysis](proposals/2026-04-29-ecc-adversarial-gap.md) — P0-2 항목
- [Measurement Infrastructure Plan](plans/measurement-infrastructure.md) — 측정 인프라
- [Context Rot Diagnosis](context-rot-diagnosis.md) — P0-1 컨텍스트 로스트 진단 (토큰 압박 = 비용 압박)
