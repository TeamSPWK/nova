# [Plan] Opus 4.7 Self-Verification 흡수

> Nova Engineering — CPS Framework
> 작성일: 2026-04-17
> 작성자: jay-swk (via Nova)
> Design: (미작성 — `/nova:design self-verify-absorption`으로 후속)

---

## Context (배경)

### 현재 상태
- Opus 4.7이 2026-04-16 출시됨. 공식 홍보 문구: *"devises ways to verify its own outputs before reporting back"*
- Nova v5.2.3에서 기본 Opus 모델 ID를 `claude-opus-4-7`로 업데이트 완료, Evaluator SKILL.md에 "Generator-Evaluator 분리는 유지된다" 방어선 문구 추가 완료
- 그러나 이는 **방어적 조치**에 그침. Generator가 내부적으로 수행하는 self-verification 신호는 현재 **버려지고** Evaluator가 처음부터 전체 검증 수행
- Nova에 이미 "구조화된 핸드오프 프로토콜"이 존재 (evaluator SKILL.md §구조화된 핸드오프 입력) — 의도/주요결정/알려진제한 필드. self-verify 필드는 없음

### 왜 필요한가
- **공식 기능 낭비**: Anthropic이 넣은 self-verify 능력을 0으로 취급하면 비용 낭비이자 품질 기회 손실
- **Evaluator 자원 비효율**: Generator가 이미 자신 있는 영역까지 Evaluator가 동일 깊이로 검증 → 불필요한 Layer 3 실행
- **Self-preference bias 방어**: 동시에 *LLM Evaluators Recognize and Favor Their Own Generations* (arXiv 2404.13076) 연구 결과에 따라, self-verify를 무비판적으로 신뢰하면 동일 blind spot 전파
- **Nova 차별화**: Anthropic은 "모델 내부 self-verify", Nova는 "모델 간 + 프로세스 간 교차검증" — 두 계층을 결합하면 Nova만의 포지셔닝 강화

### 관련 자료
- [Introducing Claude Opus 4.7](https://www.anthropic.com/news/claude-opus-4-7)
- [LLM Evaluators Recognize and Favor Their Own Generations (arXiv 2404.13076)](https://arxiv.org/abs/2404.13076)
- Nova v5.2.3 릴리스: https://github.com/TeamSPWK/nova/releases/tag/v5.2.3
- `docs/proposals/2026-04-17-opus-4-7-evolution.md` (원 제안서)
- `.claude/skills/evaluator/SKILL.md` (현재 핸드오프 프로토콜 정의 위치)

---

## Problem (문제 정의)

### 핵심 문제
Opus 4.7의 self-verification 신호를 **버리지도 맹신하지도 않고** Nova Evaluator 프로세스에 통합하되, self-preference bias를 구조적으로 방어하는 메커니즘이 필요하다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | Generator self-verify 결과 유실 | 4.7 Generator가 내부 수행한 자기 검증 결과가 Evaluator에 전달되지 않음 → 신호 낭비 | 중간 |
| 2 | Evaluator Layer 배분 획일화 | 모든 파일/함수를 동일 깊이로 검증. Generator 확신 영역 vs 불확실 영역 구분 없음 → Layer 3 자원 비효율 | 중간 |
| 3 | Self-preference bias 탐지 부재 | Generator OK + Evaluator FAIL 패턴이 누적돼도 Nova가 학습하지 않음 → Adaptive 원칙 미준수 | 높음 |
| 4 | Jury 다관점에 Generator 본인 제외 | `/nova:ask` Jury(Claude+GPT+Gemini)에 Generator의 self-verify 관점이 반영 채널 없음 | 낮음 |

### 제약 조건
- **철학 제약**: Generator-Evaluator 분리 원칙 훼손 금지. Evaluator의 독립 spawn + `disallowedTools: Edit,Write` 구조는 그대로 유지
- **하위호환 제약**: self-verify 필드가 없는(=구 Generator 에이전트 또는 4.6 이하 모델) 핸드오프도 정상 동작해야 함
- **환경 제약**: 사용자 맥은 현재 Claude Code 2.1.92에 고정. 4.7을 완전히 체감하려면 2.1.111+ 업그레이드 선결 (brew cask는 아직 최신이 2.1.92, npm은 2.1.112)
- **측정 제약**: Sprint 2의 "Layer 3 시간 감소" 같은 효과를 검증하려면 벤치마크 기준 필요 — 현재 Nova에 시간 측정 인프라 없음

---

## Solution (해결 방안)

### 선택한 방안
**단계적 흡수** — 신호 수집부터 시작해서 점진적으로 Layer 배분 최적화, 충돌 학습, Jury 통합까지 4개 Sprint로 분할.

### 대안 비교

| 기준 | A. 흡수 안 함 (현 v5.2.3 상태) | B. 전면 채택 | **C. 단계적 흡수 (채택)** |
|------|-----------------------------|------------|--------------------------|
| 4.7 self-verify 활용 | ❌ 0% | ✅ 100% | ✅ 필드 기반 수집 + 가중치 |
| Self-preference bias 방어 | ✅ 구조적 차단 | ❌ 무방비 | ✅ 충돌 탐지 + 가중치 패널티 |
| Evaluator 자원 효율 | ❌ 획일적 | ✅ 편중 (bias 위험) | ✅ 신호 기반 적응 |
| 철학 정합성 | ✅ 완전 정합 | ⚠️ 분리 원칙 훼손 위험 | ✅ 독립성 유지하며 신호만 수용 |
| 리스크 | 공식 기능 낭비 | Critical blind spot 전파 | 복잡도 상승 (설계 비용) |
| 선택 | 기각 (기회 손실) | 기각 (self-preference bias 방치) | **채택** |

### 구현 범위 (Sprint 분할)

예상 수정 파일이 4개 Sprint 전체 8개 이상이므로 스프린트 분할 필수.

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | 핸드오프 `self_verify` 필드 정의 + 수신 | `.claude/skills/orchestrator/SKILL.md`, `.claude/skills/evaluator/SKILL.md`, `.claude/agents/*-dev.md` (Generator 에이전트 2~3개) | 없음 | Generator 에이전트가 핸드오프에 `self_verify` 필드를 포함하고, Evaluator가 이를 읽어 Layer 판정에 언급 (end-to-end 수동 테스트로 확인) |
| 2 | 신호 기반 Layer 배분 최적화 | `.claude/skills/evaluator/SKILL.md` (§복잡도별 검증 강도 확장) | Sprint 1 | `confident` 영역은 Layer 1~2, `uncertain`/`not_tested` 영역은 Layer 3 강제 — Evaluator 출력에 배분 결정 근거 명시 |
| 3 | Generator-Evaluator 충돌 탐지 + Adaptive 축적 | `.claude/skills/evaluator/SKILL.md`, `.claude/skills/context-chain/SKILL.md` (NOVA-STATE.md 갱신 규칙), `docs/templates/nova-state.md` | Sprint 1 | Generator OK + Evaluator FAIL 케이스 발생 시 NOVA-STATE.md Known Risks에 자동 기록, 2회 누적 시 해당 도메인 `--strict` 자동 승격 |
| 4 | Jury에 self-verify 참여 (가중치 패널티) | `.claude/skills/jury/SKILL.md`, `mcp-server/src/tools/x-verify.ts`, `scripts/x-verify.sh` | Sprint 1 (신호 정의 재사용) | Jury 결과에 self-verify가 "Generator 관점" 한 표로 포함되되, 합의율 산출 시 가중치 패널티(예: 0.5) 적용. 문서에 근거(arXiv 2404.13076) 링크 |

### 검증 기준

**Sprint 1**:
- 기존 핸드오프 방식(필드 없음)이 여전히 동작 — 하위호환 확인
- 새 필드 포함 시 Evaluator가 3개 서브필드(`confident`/`uncertain`/`not_tested`)를 각각 읽어 판정 report에 반영
- `tests/test-scripts.sh` 통과

**Sprint 2**:
- 동일 변경을 Sprint 1 적용 전/후로 Evaluator 실행 → 판정 report의 Layer 3 실행 대상 목록이 `confident` 영역을 제외하는 것을 관찰
- 측정 방식: Evaluator report에서 "Layer 3 대상 파일/함수 목록"을 명시적으로 출력하도록 SKILL.md 보강

**Sprint 3**:
- 시뮬레이션: 의도적으로 Generator가 OK를 뱉고 Evaluator가 FAIL 내는 상황을 2회 만들어, NOVA-STATE.md에 기록되는지 확인
- Adaptive 승격: 3회째 동일 도메인 변경 시 `/nova:review --strict`가 자동 호출되는지

**Sprint 4**:
- Jury 결과에 4번째 관점(self-verify)이 포함되는지
- 합의율 산출 로직이 self-verify에 가중치 0.5 적용하는지 (다른 AI는 1.0)
- 문서에 bias 근거 링크 및 패널티 사유 명시

### 블로커

| 블로커 | 심각도 | 해소 조건 |
|-------|--------|----------|
| Claude Code 2.1.111+ 미설치 | 높음 (Sprint 1 체감 검증 불가) | brew cask bump 대기 or npm 전역 설치로 전환 |
| 4.7 self-verify 실제 출력 포맷 미관찰 | 중간 (Sprint 1 필드 스키마 설계 부정확 가능) | 업그레이드 후 `/model opus` + `/effort xhigh`로 몇 번 돌려 실제 아티팩트 샘플 확보 |
| Sprint 3 측정 인프라 부재 | 중간 | Adaptive 축적을 NOVA-STATE.md 기반 수동 관찰로 시작, 자동화는 후속 |

---

## X-Verification (다관점 수집)

> 필요 시 기록. Sprint 1 설계 finalize 이전에 `/nova:ask`로 Generator-Evaluator 모델 분리 전략에 대한 다관점 수집 권장.

| AI | 의견 요약 | 합의 |
|----|----------|------|
| Claude | (후속 /nova:ask 시 채움) | - |
| GPT | (후속) | - |
| Gemini | (후속) | - |

합의 수준: (측정 전)

---

## 다음 단계

1. **블로커 해소**: Claude Code 업그레이드 (사용자 결정 필요 — 방법은 본 세션 말미 제안)
2. **Opus 4.7 체감**: 업그레이드 후 실제 self-verify 출력 포맷 샘플 확보 (최소 3건)
3. **`/nova:design self-verify-absorption`**: 이 Plan 기반으로 Sprint 1 상세 설계 (핸드오프 스키마 finalize)
4. **`/nova:ask`**: Sprint 4의 "가중치 패널티 0.5" 값이 합리적인지 다관점 검증 (선택)
5. **Sprint 1 착수**: Design 승인 후 구현

> Plan은 "무엇을·왜", Design에서 "어떻게"를 정의. Sprint 1이 먼저 돌아가야 2~4가 의미 있으므로 순차 진행.
