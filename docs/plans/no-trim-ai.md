# [Plan] AI 트림 의무 면제 — events.jsonl 단일 진실원 + 자동 렌더

> Nova Engineering — CPS Framework
> 작성일: 2026-05-19
> 작성자: jay-swk
> 후속: v5.19.6 `docs/plans/state-prune-symmetry.md`의 결정 #2(갱신/정리 트리거 동기화) 회수

---

## Context (배경)

### 현재 상태

- 9개 커맨드(`plan/design/deepplan/run/auto/review/check/ux-audit/evolve`) + 4개 스킬(`context-chain/deepplan/orchestrator/ux-audit`)이 "갱신 후 정리 (필수): NOVA-STATE.md가 50줄 초과 시 가장 오래된 Last Activity / Recently Done부터 제거" 의무를 LLM에게 강제한다.
- `hooks/session-start.sh` 3 프로파일(lean/standard/strict) 모두 매 세션 "50줄, 초과 시 트림" 키워드를 컨텍스트에 주입한다.
- 사용자 보고(2026-05-19): "에이전트 작업하다 보면 `NOVA-STATE 64줄, 50줄 룰 초과. 트림 필요` 같은 메시지가 매번 나와서 토큰만 더 쓴다."
- v5.42.0+ 이미 `scripts/registry-render-state.sh` + v3 marker 인프라(`<!-- nova:registry-rendered:start ... end -->`) 구축됨. Active Tree / Recent Activity를 events.jsonl + work-items/index.json에서 **자동 렌더** 가능. 그러나 본 레포는 여전히 v2 schema라 자기 인프라를 자기에게 못 적용.

### 왜 필요한가

**임계값 상향(50→100) 같은 응급조치는 단조 증가의 구조를 못 막는다 — 결국 다시 같은 페인포인트로 회귀.** 사용자 지적이 정확:

| 응급조치 | 문제 |
|---------|------|
| 50→100줄 | 시점만 늦출 뿐 단조 증가 그대로 |
| advisory 무음화 | AI는 여전히 "갱신 후 정리(필수)" 텍스트를 읽고 매 커맨드 종료마다 Edit 호출 |
| Stop hook에 트림 스크립트 추가 | 트림 알고리즘이 결정론적이지 않음(어떤 항목 우선 제거?) — 정책을 코드에 박으면 사용자 편집 의도 손실 |

근본 원인은 **데이터 모델의 책임 혼선**:
- NOVA-STATE.md가 두 역할 — append-only 활동 로그(Recent Activity, Archive) + 현재 상태 스냅샷(Current/Risks/Refs)
- 두 역할 중 활동 로그 부분은 본질적으로 단조 증가
- 활동 진실원은 이미 `.nova/events.jsonl` (별도 파일, rotation 정책 있음)
- 즉 **NOVA-STATE.md의 활동 로그는 중복 데이터**다. AI가 매번 두 곳에 기록하느라 토큰 쓰고, 한쪽(STATE)은 트림까지 강제

### 관련 자료

- 사용자 보고: 2026-05-19 세션
- 인프라: `scripts/registry-render-state.sh` (v5.42.0+)
- 진실원: `.nova/events.jsonl` (work_item_* 이벤트 + rotation 10MB/5파일/30일)
- 이전 결정: v5.19.6 9 진입점 갱신/정리 동기화 (`state-prune-symmetry.md`) — 본 작업에서 회수
- 정책 충돌 회피: v5.41.0 Migration 자동화 회수 (`feedback_no_manual_setup` 메모리) — 자동 schema 변환 금지

---

## Problem (문제 정의)

### 핵심 문제

**AI에게 트림(텍스트 결정) 책임을 떠넘긴 게 비용의 본질.** 트림은 데이터 모델 분리로 구조적으로 차단해야 한다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **데이터 중복** | NOVA-STATE.md Recent Activity ↔ events.jsonl이 같은 정보 — AI가 두 곳 기록 | 높음 |
| 2 | **AI에게 트림 책임 부여** | 9개 커맨드 + 4개 스킬에서 "50줄 트림 필수" 텍스트 → 매 커맨드 종료 시 AI가 판단+Edit | 높음 |
| 3 | **자동 렌더 인프라 미적용** | v5.42.0+ `registry-render-state.sh` 있지만 v2 STATE는 marker 없어 작동 안 함. 본 레포조차 v2 | 중간 |
| 4 | **session-start 컨텍스트 낭비** | lean/standard/strict 3 프로파일 모두 "50줄" 키워드 노출 → 매 세션 인지 부담 | 중간 |
| 5 | **회귀 가드의 방향 잘못 가리킴** | `tests/test-scripts.sh`가 "50줄 트림 의무 텍스트 존재"를 강제 — 본 작업으로 의미 역전 | 낮음 |

### 제약 조건

- **하위 호환**: v2 사용자 STATE를 자동 변환하지 않음 (v5.41.0 정책). 단 본 변경 후 AI가 시계열에 추가하지 않으므로 자연 안정화.
- **session-start 예산**: soft 1200자 / hard 2500자 유지.
- **자동 렌더 hook 안전성**: Stop hook의 `registry-render-state.sh` 호출은 silent — 실패해도 hook exit 0.
- **dogfooding**: 본 작업에서 nova 레포 자체를 v3로 전환(`/nova:migrate-state`)해 자기 인프라를 실증.

---

## Solution (해결책)

### 결정 사항

**책임 분리**:
- `events.jsonl` = 활동 시계열 **단일 진실원** (rotation으로 자체 관리)
- `NOVA-STATE.md` 본문(Current/Risks/Refs) = **AI/사람 손편집 스냅샷** (본질적으로 작음 — 트림 불필요)
- `NOVA-STATE.md` marker 영역 (v3) = **`registry-render-state.sh` 자동 렌더** (top 7d × top 7 항목, 상수 크기)

**AI 의무 재정의**:
- 9개 커맨드/4개 스킬에서 NOVA-STATE.md의 **Recent Activity / Recently Done 갱신 의무 제거**.
- AI는 Current/Goal/Phase/Refs/Risks 등 **본문 스냅샷만** 갱신.
- 시계열 기록은 events.jsonl(이미 `hooks/record-event.sh`가 9 커맨드 종료 시 호출) — AI 의식 불필요.

**자동 렌더 통합**:
- `hooks/stop-event.sh`에 `registry-render-state.sh` silent 호출 추가.
- marker 있는 STATE(v3): 매 세션 종료 시 marker 영역 갱신 → AI 손 안 댐.
- marker 없는 STATE(v2/v1): silent skip → 변경 없음, 자연 안정화.

### 접근 방법

| 단계 | 작업 | 산출물 |
|------|------|--------|
| 1 | Plan(본 문서) | `docs/plans/no-trim-ai.md` |
| 2 | nova 레포 v3 전환 | `NOVA-STATE.md` (marker 삽입), `.nova/work-items/` 생성 |
| 3 | 9개 커맨드 정리 의무 텍스트 제거 | `.claude/commands/{plan,design,deepplan,run,auto,review,check,ux-audit,evolve}.md` |
| 4 | 4개 스킬 정리 | `.claude/skills/{context-chain,deepplan,orchestrator,ux-audit}/SKILL.md` |
| 5 | session-start.sh 3 프로파일 키워드 정리 | `hooks/session-start.sh` |
| 6 | Stop hook에 registry-render 자동 호출 | `hooks/stop-event.sh` |
| 7 | nova-rules 동기화 | `docs/nova-rules.md` §8 |
| 8 | 테스트 가드 교체 | `tests/test-scripts.sh` |
| 9 | /nova:review + Evaluator 독립 검증 | (보고서) |
| 10 | release.sh minor v5.44.0 | git tag + GitHub Release |

### 영향 분석

**모든 사용자 즉시 효과 (③④⑤)**:
- AI가 "50줄 트림" 텍스트를 더 이상 읽지 않음 → 매 커맨드 종료 시 토큰 0
- session-start 매 세션 약 80자 절감(3 프로파일 평균)

**v3 사용자 (마이그레이션 완료)**: Recent Activity 자동 렌더 → 완전 해결
**v2/v1 사용자**: AI가 시계열 추가도 안 함 → 단조 증가 자연 정지. 활동 보고 싶으면 `/nova:status` HTML 대시보드(events.jsonl 기반).

### 트레이드오프

| 선택 | 장점 | 단점 |
|------|------|------|
| **(채택) events.jsonl 단일 진실원** | AI 토큰 0, 단조 증가 구조적 차단, 인프라 재활용 | v2 사용자는 NOVA-STATE.md의 Recent Activity 표가 비어보일 수 있음 — `/nova:status`로 보완 |
| 임계값 상향(50→100) | 변경 작음 | 단조 증가 그대로, 회귀 보장 |
| 자동 트림 스크립트 | AI 토큰 0 | 트림 정책 결정론화 어려움, 사용자 편집 의도 손실 위험 |
| v2 STATE 자동 marker 삽입 | 모든 사용자 즉시 v3 혜택 | v5.41.0 자동화 회수 정책 위배 |

### 성공 기준

1. `bash tests/test-scripts.sh` 통과 (신규 가드 포함)
2. `hooks/session-start.sh | python3 -m json.tool` 유효
3. `NOVA_PROFILE=strict bash hooks/session-start.sh` 출력에 "50줄 트림" 없음
4. 9개 커맨드 + 4개 스킬에서 "갱신 후 정리 (필수)" 블록 0건 (`grep -c`)
5. 본 레포 NOVA-STATE.md v3 schema (`<!-- nova:registry-rendered:start -->` 존재)
6. `bash hooks/stop-event.sh` 실행 시 marker 영역 갱신 (수동 시뮬레이션)
7. `/nova:review --fast` PASS + Evaluator 독립 서브에이전트 PASS
8. v2 STATE 시뮬레이션(marker 부재)에서 stop hook 실패 없이 exit 0
