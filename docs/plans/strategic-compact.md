# [Plan] Strategic Compact 스킬 (v5.21.0 minor)

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: jay-swk
> Design: (Plan 단독으로 충분 — Design 단계 생략, Sprint 단일)

---

## Context (배경)

### 현재 상태
- Nova v5.20.1 시점 — ECC 적대적 갭 분석 P0/P1 docs 흡수 완료 (P0-1 컨텍스트 로스트 진단 / P0-2 비용 가이드 / P1-2 MCP 룰 / P1-3 신뢰도 점수).
- NOVA-STATE 50줄 트림 룰은 v5.19.6에서 9 진입점 동기화로 강제됨. 그러나 **세션 자체** (Claude Code 컨텍스트 창)의 `/clear` `/compact` 사용 시점 가이드는 0줄.
- ECC `affaan-m/everything-claude-code` Strategic Compact 스킬 본문은 404 미확보. 사용자 LiveWiki 요약(영상 05:57~06:24) + Nova의 `docs/context-rot-diagnosis.md` "Nova 1차 대응" 표 기반 추론.
- 본 작업은 **이중 압축 체계**의 마지막 한 조각 — 상태-수준(NOVA-STATE 50줄 트림) ↔ 세션-수준(Strategic Compact)의 분리.

### 왜 필요한가
- **Generator 컨텍스트 보호**: 구현 sprint 도중 잘못된 `/compact` 발동 시 Plan-Design-Implement 응집형 정체성이 한 순간 무너진다 (이번 v5.20.x 세션에서 사용자가 명시 우려한 시나리오, 메모리 `feedback_evidence_first_identity` 인접).
- **마일스톤 압축 권장**: `/nova:plan`·`/nova:design`·`/nova:auto` 완료 직후가 자연스러운 압축 시점이지만 현재 Nova는 그 시점을 알리지 않는다.
- **무관 작업 전환 시 `/clear`**: ECC가 명시한 패턴 — 작업이 바뀌면 컨텍스트를 비워야 토큰 압박을 사전 차단.
- **컨텍스트 로스트 4원인 카탈로그(P0-1 흡수)의 실행 출구**: 진단까지는 v5.20.1에서 완료. 본 스킬이 진단 → 자동 안내까지 이어지는 출구 역할.

### 관련 자료
- `docs/proposals/2026-04-29-ecc-adversarial-gap.md` §P0-3 — 본 작업 출처
- `docs/context-rot-diagnosis.md` "Nova 1차 대응" 표 — 트리거 카탈로그 출처 (4원인별 대응)
- `docs/cost-optimization.md` AUTOCOMPACT 50% 권장 — Strategic Compact과 정합
- `skills/context-chain/SKILL.md` — NOVA-STATE 트림 룰 (역할 분리 명시 필요)
- `skills/writing-nova-skill/SKILL.md` — description = When-to-use only / 트리거 회귀 fixture 의무
- `tests/test-skill-triggering.sh` — 각 `skills/*/SKILL.md`에 positive fixture 자동 검증

---

## Problem (문제 정의)

### 핵심 문제
세션-수준 컨텍스트 압축(`/clear` `/compact`)의 발동 시점을 Nova가 0줄도 안내하지 않아, 사용자가 잘못된 시점에 압축하면 응집형 정체성(Plan-Design-Implement 컨텍스트)이 손실된다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 마일스톤 압축 미안내 | `/nova:plan` 완료 후 사용자는 압축 적기를 알지 못함. 토큰 누적 → 후속 작업 품질 저하 | 높음 |
| 2 | 구현 도중 `/compact` 위험 | Generator 컨텍스트 살아있는 sprint 중간 압축 시 의도 손실. 본 v5.20.x 세션에서 직접 우려된 시나리오 | 높음 |
| 3 | 무관 작업 전환 시 `/clear` 부재 | 한 세션에서 다른 프로젝트/주제로 전환 시 컨텍스트 누적 → 어텐션 희석 (P0-1 §1 원인) | 중간 |
| 4 | NOVA-STATE 트림과의 역할 혼동 | 사용자가 둘을 같은 것으로 오해 — STATE 트림으로 세션 압축이 해결된다고 착각하면 결국 토큰 압박 발생 | 중간 |
| 5 | Evaluator 검증 직전 압축 위험 | 적대적 검증은 *같은 컨텍스트* 재현 필요. 검증 직전 압축은 Generator-Evaluator 분리 원칙 훼손 | 높음 |

### 제약 조건
- 본 스킬은 *판단을 권장*만 한다. `/compact` 자동 실행 X — "AI는 제안 인간은 결정" 원칙 (메모리 `feedback_evidence_first_identity` 정합).
- v5.19.6 NOVA-STATE 9 진입점 동결 유지 — 본 스킬이 새 진입점을 추가하지 않는다.
- ECC 본문 미확보(404) — 본문 직접 인용 금지, Nova 어휘로 변환.
- `skills/writing-nova-skill/SKILL.md` 규약 준수 — description = When-to-use only / `MUST TRIGGER:` 3개 이상 / 본문에 핵심 원칙 3~5개.
- 한국어 기본, description_en 병기.

---

## Solution (해결 방안)

### 선택한 방안
신규 user-invocable 비공개 스킬 `skills/strategic-compact/SKILL.md` 1개 + nova-rules.md §8 보강 1줄 + context-chain SKILL 분리 명시 1줄 + tests 회귀 가드 + skill-triggering positive fixture. 단일 sprint 6 파일.

### 대안 비교

| 기준 | 방안 A — 새 스킬 | 방안 B — context-chain 확장 | 방안 C — 새 커맨드 `/nova:compact-now` |
|------|------------------|------------------------------|----------------------------------------|
| 책임 분리 | STATE 트림 ↔ 세션 압축 분리 명확 | 한 스킬이 두 책임 — 비대해짐 | 사용자가 명령 입력해야 — 자동성 X |
| 발동 모델 | description 트리거(LLM 자동 발동) | description 모호 — 둘 중 무엇이 발동할지 흔들림 | 슬래시커맨드 — 사용자 인지 의존 |
| 9 진입점 영향 | 영향 없음 (새 스킬은 진입점 X) | context-chain 진입점 책임 모호 | EXPECTED_COMMANDS 추가 — 9 진입점 룰 재설계 위험 |
| 회귀 가드 비용 | description lint + skill-triggering positive 1개 + 키워드 3~4 assert | 기존 가드 수정 비용 + 책임 모호 | EXPECTED_COMMANDS + session-start.sh 동기화 + tests 추가 |
| ECC 패턴 정합 | ECC도 *스킬*로 구현 | 비대 스킬은 본문 스킵 유발 | 자동성 부재 — ECC 의도 훼손 |
| 선택 | **채택** | 기각 (책임 모호 + 본문 비대) | 기각 (자동성 부재 + 9 진입점 룰 충돌 위험) |

### 구현 범위 (단일 Sprint, 6 파일)

신규 (2):
- [ ] `skills/strategic-compact/SKILL.md` — user-invocable: false. description = When-to-use only + `MUST TRIGGER:` 3 트리거 + `MUST NOT TRIGGER:` 2 트리거. 본문: 핵심 원칙 3 + 적용 규칙(on-demand §8 §10) + ECC vs Nova 차이 + 안티패턴.
- [ ] `tests/skill-triggering/prompts/strategic-compact-positive.txt` — 트리거 회귀 fixture (예: "/nova:plan 끝났는데 다음 단계 시작 전에 컨텍스트 어떻게 하면 좋을까?").

수정 (4):
- [ ] `docs/nova-rules.md` §8 — Strategic Compact 1줄 보강 ("STATE 트림 ↔ 세션 압축은 별도 — `skills/strategic-compact/SKILL.md` 참조").
- [ ] `skills/context-chain/SKILL.md` — 1줄 cross-reference (NOVA-STATE는 상태-수준 / strategic-compact는 세션-수준 분리 명시).
- [ ] `tests/test-scripts.sh` — +3~4 assert (M20 트리거 카탈로그 키워드 / M21 §8 cross-ref / M22 context-chain cross-ref / M23 description lint 통과 — description lint는 기존 일반 룰이면 자동 통과 가능, 명시 가드만 추가).
- [ ] `NOVA-STATE.md` — Phase planning, Refs Plan 경로 추가, Last Activity, 50줄 트림.

### 검증 기준
- 신규 스킬 description이 `writing-nova-skill` 규약 통과 (description = When-to-use, `MUST TRIGGER:` 3개 이상, `→` `파이프라인` `4단` 등 금지어 0회).
- `bash tests/test-skill-triggering.sh` PASS — strategic-compact-positive.txt 존재 자동 검증.
- `bash tests/test-scripts.sh` 513 → 516+ 회귀 0.
- `bash hooks/session-start.sh | python3 -m json.tool` JSON 유효 (스킬 추가는 session-start 영향 없음 검증).
- `/nova:review --fast` PASS — 메인 컨텍스트가 Evaluator verdict를 git/grep 사실 검증 1회 후 사용자 보고 (메모리 `feedback_evaluator_hallucination`).
- NOVA-STATE.md 50줄 이내.
- v5.21.0 minor `release.sh` 체인 — `release.sh patch|minor|major "msg"` 한 명령 (메모리 `feedback_release_sh_staging_trap` 회피: staging 정리 후 release.sh 호출).
- `record-event.sh plan_created` 이벤트 기록 (safe-default).

### 리스크 맵

| 위험 | 영향도 | 완화 |
|------|--------|------|
| Strategic Compact 스킬 description이 LLM에 발동 신호 못 줌 (트리거 오인) | 높음 | `MUST TRIGGER:` 3개 이상 + `description_en` 병기 + skill-triggering positive fixture 사람-검수 |
| context-chain와 책임 혼동 (사용자가 STATE 트림으로 세션 압축 해결로 착각) | 중간 | 두 스킬 본문에 명시 cross-reference + nova-rules §8 1줄로 권위 부여 |
| ECC 본문 미확보(404) → 추론 패턴이 ECC 의도와 어긋남 | 중간 | 사용자 LiveWiki 요약 + Nova `context-rot-diagnosis` "Nova 1차 대응" 표를 1차 출처로 명시. 후험 검증은 v5.22.0+ events.jsonl 변화 |
| 9 진입점 동결 룰 위반 (새 스킬이 STATE 갱신 트리거 추가) | 높음 | 본 스킬은 *권장만* — STATE 갱신 X. 명시적으로 "9 진입점 동결 유지" 본문 기재 |
| description lint 룰이 새 키워드 차단 (예: "압축") | 낮음 | writing-nova-skill 금지어 목록 재확인 (`→` `파이프라인` `4단` `Explorer×3`만) — "압축"은 영향 없음 |

---

## X-Verification

> 본 작업은 ECC 적대적 갭 분석에서 사전 합의된 P0-3 항목. 추가 멀티 AI 자문 불필요.

합의 수준: Strong Consensus (P0-3 출처 + Nova 5기둥 협업 기둥과 정합)

---

## Sprint 분할

예상 수정 파일 6개 — 단일 sprint로 진행 (8개 미만).

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | Strategic Compact 스킬 흡수 | 6 (신규 2, 수정 4) | 없음 | 신규 스킬 description lint 통과 + skill-triggering positive 자동 검증 + tests 516+ 회귀 0 + /nova:review --fast PASS + v5.21.0 release.sh 체인 완료 |

---

## Verification Hooks

- `bash tests/test-skill-triggering.sh` — strategic-compact-positive.txt 존재 자동 검증
- `bash tests/test-scripts.sh` — 513 → 516+ 회귀 0
- `bash hooks/session-start.sh | python3 -m json.tool` — JSON 유효성
- `/nova:review --fast` — Evaluator 독립 서브에이전트 PASS
- `bash hooks/record-event.sh plan_created '...'` — Plan 작성 시점 이벤트 기록 (safe-default)
- `bash scripts/release.sh minor "feat(v5.21.0): Strategic Compact 스킬 흡수 (ECC P0-3)"` — 한 명령 릴리스 체인
