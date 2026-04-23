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

## 역할 분담: NOVA-STATE(사람용) × `.nova/events.jsonl`(기계용) — v5.12.0+

Sprint 1부터 Nova는 두 기록 체계를 **병행**한다(이중화 아님):

| 기록 | 용도 | 수명 | 형태 |
|------|------|------|------|
| `NOVA-STATE.md` | **사람이 읽는 상위 요약** — Current/Tasks/Blockers/Last Activity | 프로젝트 생애 | Markdown, 50줄 이내 |
| `.nova/events.jsonl` | **기계가 집계하는 원자 이벤트** — 11 타입 × timestamp | rotation (10MB/5 파일/30일) | JSONL |

**동시 기록 원칙**: 검증 결과, Phase 전이, 블로커 발생/해소는 **NOVA-STATE.md 갱신 + `hooks/record-event.sh` 호출을 동시** 수행한다. 하나만 빠지면 사람/기계 중 한쪽이 맹목이 된다.

**KPI 집계**: `scripts/nova-metrics.sh`가 JSONL을 집계하여 `/nova:next`가 표시한다. NOVA-STATE.md는 그 수치의 해석/맥락 역할.

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

## 자동 갱신 트리거 (이벤트 기반)

세션 말기에 수동 기록하면 부실해진다. **성과 발생 시점**에 즉시 갱신한다.

| 이벤트 | NOVA-STATE.md 갱신 내용 |
|--------|------------------------|
| 작업 시작 | Tasks에 행 추가 (Status: doing) |
| git commit | 관련 Task의 Status 업데이트 |
| `/nova:plan` 완료 | Current Goal/Phase 설정, Refs Plan 경로 기록 |
| `/nova:design` 완료 | Phase → building 전환, Refs Design 경로 기록 |
| `/nova:auto` 완료 | Recently Done에 추가 (Verdict + Ref) |
| `/nova:review` 완료 | Refs의 Last Verification 갱신 |
| `/nova:check` 완료 | Refs의 Last Verification 갱신 |
| 작업 완료 | Tasks에서 제거 → Recently Done 이동 |

## Last Activity 포맷

NOVA-STATE.md의 Last Activity는 **반드시 1줄**로 기록한다:
```
## Last Activity
- /nova:review → PASS — src/api/ | 2026-04-02T15:30:00+09:00
```
4줄(커맨드/시각/결과/대상) 포맷은 사용하지 않는다.

## 아카이빙 규칙

- Recently Done이 **3개 초과** 시 가장 오래된 항목 제거
- 상세 내용은 `docs/verifications/`에 보존됨 — 상태 파일에서 지워도 유실 없음
- **NOVA-STATE.md는 항상 50줄 이내 유지** — 초과하면 오래된 항목부터 정리

## Known Gaps 해결 표기 규칙

- 해결된 Known Gaps 항목은 **행을 삭제한다** (취소선 처리 금지)
- 삭제 전에 해당 항목을 "Recently Done" 테이블에 이동하여 해결 기록을 남긴다:
  ```
  | {갭 내용 요약} | {해결 날짜} | RESOLVED | {관련 커밋/PR} |
  ```
- 이 규칙의 목적: Known Gaps가 줄어들지 않으면 실제 해결 여부를 판단할 수 없다

## 세션 종료 프로토콜

1. `NOVA-STATE.md`가 최신 상태인지 확인한다
2. 미완료 작업이 있으면 Blocker 필드에 사유를 기록한다
3. Tasks의 todo 항목을 다음 세션에서 바로 실행할 수 있는 수준으로 구체화한다

## Context Reset 전략

- 스프린트 간 새 서브에이전트로 컨텍스트 오염 방지
- `NOVA-STATE.md` + Design 문서로 새 세션에서 상태 복원
- `docs/auto-handoff.md`는 더 이상 사용하지 않는다 — `NOVA-STATE.md`가 대체
