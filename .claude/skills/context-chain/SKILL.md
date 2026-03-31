---
name: context-chain
description: Nova Context Chain — 세션 간 맥락 연속성 보장. NOVA-STATE.md 기반 상태 관리.
---

# Nova Context Chain

세션이 끊겨도 작업 맥락이 유지되도록 한다. `NOVA-STATE.md`를 단일 진입점으로 사용한다.

## 세션 시작 프로토콜

1. 프로젝트 루트에 `NOVA-STATE.md`가 있으면 읽고 현재 상태를 파악한다
   - Current → 지금 뭘 하고 있었는지
   - In Progress → 진행 중인 작업과 담당자
   - Blocker → 막혀 있는 것이 있는지
   - Refs → 관련 설계/검증 문서
2. `NOVA-STATE.md`가 없으면 다음을 스캔하여 상태를 추론한다:
   - `git log --oneline -10` — 최근 작업 방향
   - `docs/plans/`, `docs/designs/` — 진행 중인 설계
   - `docs/verifications/` — 최근 검증 결과
   - 추론 결과로 `NOVA-STATE.md`를 자동 생성한다

## 자동 갱신 트리거 (이벤트 기반)

세션 말기에 수동 기록하면 부실해진다. **성과 발생 시점**에 즉시 갱신한다.

| 이벤트 | NOVA-STATE.md 갱신 내용 |
|--------|------------------------|
| 작업 시작 | In Progress에 행 추가 |
| git commit | 관련 Task의 Status 업데이트 |
| `/nova:plan` 완료 | Current Goal/Phase 설정, Refs Plan 경로 기록 |
| `/nova:design` 완료 | Phase → building 전환, Refs Design 경로 기록 |
| `/nova:auto` 완료 | Recently Done에 추가 (Verdict + Ref) |
| `/nova:review` 완료 | Refs의 Last Verification 갱신 |
| `/nova:gap` 완료 | Refs의 Last Verification 갱신 |
| 작업 완료 | In Progress → Recently Done 이동 |

## 아카이빙 규칙

- Recently Done이 **3개 초과** 시 가장 오래된 항목 제거
- 상세 내용은 `docs/verifications/`에 보존됨 — 상태 파일에서 지워도 유실 없음
- **NOVA-STATE.md는 항상 50줄 이내 유지** — 초과하면 오래된 항목부터 정리

## 세션 종료 프로토콜

1. `NOVA-STATE.md`가 최신 상태인지 확인한다
2. 미완료 작업이 있으면 Blocker 필드에 사유를 기록한다
3. Next Actions를 다음 세션에서 바로 실행할 수 있는 수준으로 구체화한다

## Context Reset 전략

- 스프린트 간 새 서브에이전트로 컨텍스트 오염 방지
- `NOVA-STATE.md` + Design 문서로 새 세션에서 상태 복원
- `docs/auto-handoff.md`는 더 이상 사용하지 않는다 — `NOVA-STATE.md`가 대체
