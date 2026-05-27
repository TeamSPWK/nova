---
name: context-chain
description: "세션 간 맥락을 연결해야 할 때. — MUST TRIGGER: 세션 시작 시 NOVA-STATE.md 읽기, 커밋 후 상태 갱신, 스프린트 전환 시."
description_en: "Use when session-to-session context must carry over. — MUST TRIGGER: reading NOVA-STATE.md on session start, updating state after commit, or on sprint transitions."
user-invocable: false
---

# Nova Context Chain

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §8` 세션 상태 유지 (Known Gaps 필수, 즉시 업데이트 트리거, 커밋 전 일괄 갱신)
- `docs/nova-rules.md §10` 관찰성 계약 — NOVA-STATE(사람용) × JSONL(기계용) 역할 분담

세션이 끊겨도 작업 맥락이 유지되도록 한다. `NOVA-STATE.md`를 단일 진입점으로 사용한다.

> 외부 대안 비교: `docs/comparison/context-chain-vs-external.md` — Nova vs claude-mem(vector DB)·Continuous-Claude-v3(ledger+handoffs) 차별점 표.

## 역할 분담: NOVA-STATE(사람용) × `.nova/events.jsonl`(기계용) — v5.44.0+ 재정의

| 기록 | 용도 | 수명 | 손편집 책임 |
|------|------|------|-------------|
| `NOVA-STATE.md` 본문(Current/Goal/Phase/Risks/Refs) | **사람·AI가 읽는 현재 상태 스냅샷** | 프로젝트 생애 | AI/사용자 직접 편집 (작은 영역, 트림 불필요) |
| `NOVA-STATE.md` v3 marker 영역 | **자동 렌더 — Active Tree + 최근 work-item 활동** | 프로젝트 생애 | 손편집 금지 (`scripts/registry-render-state.sh` 자동 갱신) |
| `.nova/events.jsonl` | **활동 시계열 단일 진실원** — 11 타입 × timestamp | rotation (10MB/5 파일/30일) | `hooks/record-event.sh` 자동 (AI 호출 X) |

**핵심 원칙 (v5.44.0+)**:
- **시계열 진실원은 events.jsonl 하나.** NOVA-STATE.md의 Recent Activity 표 / Recently Done 표는 v3 marker가 있으면 자동 렌더, 없으면 사용자 손편집 영역(자연 안정화).
- **AI는 STATE 본문 스냅샷만 손편집** — Current/Goal/Phase/Refs/Risks. 시계열 표에 행 추가 X.
- **트림 의무 없음.** 본문 스냅샷은 본질적으로 작고, marker 영역은 스크립트가 상수 크기로 유지.

**KPI 집계**: `scripts/nova-metrics.sh`가 JSONL을 집계하여 `/nova:next`가 표시. NOVA-STATE.md는 수치 해석/맥락 역할.

## 세션 시작 프로토콜

1. 프로젝트 루트에 `NOVA-STATE.md`가 있으면 읽고 현재 상태를 파악한다
   - Current → 지금 뭘 하고 있었는지
   - Tasks → 진행 중/대기 중인 작업 (Status: todo/doing/done)
   - Blocker → 막혀 있는 것이 있는지
   - Refs → 관련 설계/검증 문서
2. `NOVA-STATE.md`가 없으면 다음을 스캔하여 상태를 추론한다:
   - `git log --oneline -10` — 최근 작업 방향
   - `docs/plans/`, `docs/designs/` — 진행 중인 설계
   - `docs/verifications/` — 최근 검증 결과
   - 추론 결과로 `NOVA-STATE.md`를 자동 생성한다

## 자동 갱신 트리거 (이벤트 기반) — v5.44.0+ 재정의

| 이벤트 | NOVA-STATE.md 손편집 (AI/사용자) | 자동 기록 |
|--------|--------------------------------|----------|
| 작업 시작 | Tasks에 행 추가 (Status: doing) | — |
| git commit | 관련 Task의 Status 업데이트 | `hooks/record-event.sh` (commit 이벤트) |
| `/nova:plan` 완료 | Current Goal/Phase, Refs Plan 경로 | events.jsonl + marker 자동 렌더 |
| `/nova:design` 완료 | Phase → building, Refs Design 경로 | events.jsonl + marker 자동 렌더 |
| `/nova:deepplan` 완료 | Phase → planning, Refs Plan 경로 | events.jsonl + marker 자동 렌더 |
| `/nova:run` 완료 | Phase 갱신 (PASS→done, FAIL→building), Tasks 제거 | events.jsonl + marker 자동 렌더 |
| `/nova:auto` 완료 | (필요 시) Current/Phase 정리 | events.jsonl + marker 자동 렌더 |
| `/nova:review` 완료 | Refs의 Last Verification | events.jsonl + marker 자동 렌더 |
| `/nova:check` 완료 | Refs의 Last Verification | events.jsonl + marker 자동 렌더 |
| `/nova:ux-audit` 완료 | (Critical 있으면) Known Risks 추가 | events.jsonl + marker 자동 렌더 |
| 작업 완료 | Tasks에서 제거 | events.jsonl (work_item_transitioned) |

**v5.44.0+ 단일 진실원 모델**: AI는 NOVA-STATE.md의 시계열 영역(Recent Activity 표, Recently Done 표)에 직접 행을 추가하지 않는다. 시계열은 `hooks/record-event.sh`가 `.nova/events.jsonl`에 자동 기록 + Stop hook이 `scripts/registry-render-state.sh`로 v3 marker 영역을 자동 갱신. 8개 진입점은 본문 스냅샷(Current/Phase/Refs/Risks)만 손편집한다.

**v3 marker 영역**: NOVA-STATE.md의 `<!-- nova:registry-rendered:start -->` ~ `<!-- nova:registry-rendered:end -->` 사이는 `scripts/registry-render-state.sh`가 자동 렌더한다. **손편집 금지**. work-item index는 `.nova/work-items/index.json`이 진실원. v2/v1 STATE(marker 부재)는 자동 렌더 silent skip — 시계열 영역이 빈 채로 유지되며 사용자가 활동을 보려면 `/nova:status` HTML 대시보드(events.jsonl 기반) 사용.

## Last Activity 포맷

NOVA-STATE.md의 Last Activity는 **반드시 1줄**로 기록한다:
```
## Last Activity
- /nova:review → PASS — src/api/ | 2026-04-02T15:30:00+09:00
```
4줄(커맨드/시각/결과/대상) 포맷은 사용하지 않는다.

## 아카이빙 규칙 — v5.44.0+ 재정의

- **시계열 아카이브는 events.jsonl rotation이 담당** (10MB/5 파일/30일). AI는 시계열 표를 트림하지 않는다.
- **본문 스냅샷 영역**(Current/Phase/Refs/Risks)은 본질적으로 작음 — 명시적 임계값 없음. 사용자가 가독성을 위해 필요 시 직접 정리.
- 검증 상세는 `docs/verifications/`에 보존됨 — STATE에서 지워도 유실 없음.

## Known Gaps 해결 표기 규칙 — v5.44.0+ 재정의

- 해결된 Known Gaps 항목은 **행을 삭제한다** (취소선 처리 금지)
- 해결 사실은 다음 진실원에 자동 보존됨 — STATE 시계열 표에 옮기지 않는다:
  - `git log` (해결 커밋 + 메시지)
  - `.nova/events.jsonl` (`work_item_transitioned` to=resolved, 자동 기록)
  - `.nova/work-items/index.json` (v3 registry — status 갱신)
- 규칙 목적: Known Gaps가 줄어들지 않으면 실제 해결 여부 판단 불가. 진실원은 분리, NOVA-STATE는 *현재 미해결만* 노출.

## 세션 종료 프로토콜

1. `NOVA-STATE.md`가 최신 상태인지 확인한다
2. 미완료 작업이 있으면 Blocker 필드에 사유를 기록한다
3. Tasks의 todo 항목을 다음 세션에서 바로 실행할 수 있는 수준으로 구체화한다

## Context Reset 전략

- 스프린트 간 새 서브에이전트로 컨텍스트 오염 방지
- `NOVA-STATE.md` + Design 문서로 새 세션에서 상태 복원
- `docs/auto-handoff.md`는 더 이상 사용하지 않는다 — `NOVA-STATE.md`가 대체

## 세션-수준 압축은 별도 스킬 (v5.21.0+, v5.44.0 갱신)

본 스킬은 *상태-수준* 데이터 모델(events.jsonl 단일 진실원 + NOVA-STATE 본문 스냅샷)을 다룬다. Claude Code 세션 컨텍스트 창 자체의 `/clear`·`/compact` 시점은 `skills/strategic-compact/SKILL.md`. 둘은 별도 트리거·별도 효과 — 토큰 압박은 `/clear`·`/compact`로 해소.
