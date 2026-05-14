# X-Verification: 
# NOVA-STATE.md 스키마 재설계 자문

## Context (Nova가 어떤 도구인지)
Nova는 Claude Code 플러그인. 

> 날짜: 2026-05-14
> 합의율: 95%
> 판정: auto_approve
> AI: claude, gpt, gemini

## 질문

# NOVA-STATE.md 스키마 재설계 자문

## Context (Nova가 어떤 도구인지)
Nova는 Claude Code 플러그인. 다중 에이전트 워크플로우(Architect → Generator → Evaluator 등)로 코드를 만들고 검증한다. NOVA-STATE.md는 프로젝트 루트에 1개 존재하는 단일 진실 원천(SoT)이며:
- session-start 시 자동 생성/주입
- /nova:next, /nova:status, 모든 에이전트가 진입 시 첫 번째로 읽음
- 에이전트가 작업 종료 시 갱신해야 함
- 50줄 soft / 노션 등 외부 도구 동기화는 사용자가 명시적으로 거부 (복잡도 폭발로 실패 경험)

## 현재 포맷 (실제 운영 중인 파일에서 발췌)
```md
# Nova State
- **Goal**: v5.37.0 minor — 셸 단독 자동 풍부 모드 도달
- **Phase**: in-progress — v5.37.0 릴리스
- **Blocker**: 없음
- **다음 세션 진입점**: (a) ... (b) ... (c) ...

## Tasks
| Task | Status | Verdict | Note |
| status-dashboard Phase 1 (S1~S4) | done | PASS | ... |
| status-dashboard Phase 2 (S5~S8) | done | PASS | ... |
| visual-intent-verify Sprint A3 (통합 + 가드) | done | PASS | ... |

## Recently Done (최근 3개)
## Known Risks / Known Gaps
## 규칙 우회 이력
## Last Activity (append-only 로그)
## Refs (Plan/Design/Verification 포인터)
```

## Problem (구체 문제)
1. **계층 표현 불가**: AO(자동 오케스트레이션) > Phase > Sprint > Agent 계층이 task 이름 문자열에 묵시 박힘 → 트리뷰 렌더링 불가, 부모-자식 추적 불가
2. **동시 진행 표현 불가**: `Goal/Phase/Blocker`는 단일 값 → 여러 작업 병렬 시 무용
3. **에이전트 핸드오프 누락**: 다음 에이전트가 받아야 할 컨텍스트(이전 산출물 포인터, 미해결 가정, 다음 목표)가 스키마에 없음 → 에이전트 간 컨텍스트 단절 발생
4. **시각화 어려움**: 평탄한 테이블 → `/nova:status` 대시보드도 트리로 못 그림
5. **50줄 룰 vs 정보량 충돌**: 트리/핸드오프 추가하면 즉시 넘침

## 사용자 핵심 요구 (재진술)
- 트리 구조로 한눈에 작업 흐름이 보여야 함 (AO → Phase → Sprint)
- 에이전트 핸드오프가 매끄럽게 (다음 에이전트가 STATE.md 한 파일로 자기 위치 파악)
- 단순함 유지 — 노션 같은 외부 동기화 절대 X, 복잡도 폭발 회피
- /nova:next, 에이전트 진입 등 기존 의존성 깨지면 안 됨

## 제약
- 마크다운 + git-friendly (diff 가능)
- 외부 도구/DB 의존 금지
- bash/python 파싱 가능해야 함 (이미 build-status/render-status가 의존)
- 50줄 soft 룰 유지하되 재해석 가능

## Solution 후보 (어떤 게 좋을지)
A. **들여쓰기 마크다운 트리** (`Active Tree` 섹션) + `Archive` 분리. 한 파일에 다 보임.
B. **JSON sidecar + Markdown render** — `.nova/state.json`이 정형 SoT, `NOVA-STATE.md`는 자동 렌더 결과 (사람이 보기). 사람이 편집해도 다음 갱신 때 덮어쓰임.
C. **Hybrid: Markdown frontmatter(YAML) + 본문 트리** — 정형 데이터는 frontmatter, 사람이 읽는 트리는 본문. 둘 다 같은 파일.

## 자문 요청
1. A/B/C 중 어떤 방향이 "단순함 + 트리 표현 + 핸드오프 매끄러움" 3박자에 가장 맞는가? 다른 4번째 안이 있나?
2. 핸드오프 매니페스트는 어떤 필드가 최소로 필요한가? (4필드? 6필드?)
3. 50줄 룰을 어떻게 재해석해야 하는가? (활성 트리만 카운트? 깊이 제한? 자동 아카이브?)
4. 에이전트가 STATE.md 갱신을 빼먹는 갭(자동 갱신 강제)을 어떻게 풀어야 하는가? — MCP `orchestration_update`가 자동 patch? hook? 에이전트 프롬프트 의무?
5. 이 재설계에서 가장 큰 함정/리스크가 무엇인가?

각 AI는 자기 관점에서 답하고, 가능하면 구체 포맷 1개를 예시로 보여줘.


## claude
# NOVA-STATE.md 스키마 재설계 자문

## 1. 방향 권고: **C (Hybrid) + 부분 A 흡수**

B는 탈락. "사람이 편집해도 덮어쓰임"은 SoT 신뢰를 파괴한다. 에이전트가 md를 직접 패치하는 현재 모델과 충돌.

A는 파싱 취약. 들여쓰기 기반 트리는 bash/python regex로 파싱 시 엣지케이스 폭발.

**C가 최적**: YAML frontmatter = 정형 SoT (기계 파싱), 본문 = 사람 가독 트리 (A 스타일). 단일 파일, git diff 친화적, 외부 의존 없음.

```yaml
---
# NOVA-STATE frontmatter (기계 파싱 타깃)
goal: "v5.37.0 — 셸 단독 자동 풍부 모드"
active_ao: "AO-3"
blockers: []
handoff:
  from: "Evaluator"
  to: "Generator"
  outputs: ["dist/status-v2.js", "eval-report.md"]
  assumptions: ["Node 20 환경 확정"]
  next_objective: "Sprint B1 — 에러 렌더 통합"
---
```

```markdown
## Active Tree
- AO-3: v5.37.0 릴리스 [in-progress]
  - Phase 2: 통합 검증
    - ✅ Sprint A3: 통합+가드 (PASS)
    - 🔄 Sprint B1: 에러 렌더 [Generator 진행중]
    - ⬜ Sprint B2: E2E 검증

## Handoff
> **→ Generator**: Sprint B1 시작. 산출물: eval-report.md 참조.
> 미결 가정: 브라우저 폴백 범위 미확정.

## Last Activity (최근 5, append-only)
## Archive → .nova/archive-ao2.md
```

---

## 2. 핸드오프 최소 필드: **5필드**

4필드는 부족, 6필드는 과잉.

| 필드 | 이유 |
|------|------|
| `from` / `to` | 핸드오프 방향 |
| `outputs` | 이전 산출물 포인터 (파일 경로) |
| `assumptions` | 미검증 전제 — 가장 자주 누락되는 컨텍스트 |
| `next_objective` | 다음 에이전트의 첫 문장 |
| `blockers` | 이미 알려진 장애물 (없으면 `[]`) |

`confidence`, `deadline` 등은 필요 시 확장. 지금은 노이즈.

---

## 3. 50줄 룰 재해석: **"활성 트리 + Handoff만 카운트"**

- **카운트 대상**: frontmatter + Active Tree + Handoff 섹션
- **카운트 제외**: Last Activity 로그, Archive 포인터, Known Risks
- **깊이 제한**: AO → Phase → Sprint 3단계 고정. Task 단위는 Sprint 내 인라인 불가 → 별도 Sprint 파일로 분리
- **자동 아카이브 트리거**: Sprint `done` 상태 → 다음 갱신 시 `.nova/archive-aoN.md`로 이동, Active Tree에서 제거

결과적

## gpt
**권고: C(Frontmatter+본문 트리)**가 최적입니다.  
A는 파싱 취약, B는 SoT가 2개처럼 보여 “단순함” 훼손. C는 **단일 파일 SoT 유지 + 정형 파싱 + 사람이 읽는 트리**를 동시에 만족합니다.

**최소 핸드오프 필드(6개)**  
`id, owner(agent), status, next, refs, assumptions`  
권장 추가: `updated_at, blocker`.  
핵심은 “다음 에이전트가 뭘 이어받아 뭘 해야 하는지”가 즉시 보여야 합니다.

**50줄 룰 재해석**  
- **활성 영역만 50줄** 카운트  
- 완료 항목은 `Archive`로 접기/요약  
- 트리 깊이 **AO > Phase > Sprint**까지만, Agent는 leaf 메타로 표현  
- append-only 로그는 최근 N개만 노출

**갱신 누락 방지**  
프롬프트 의무만으론 부족.  
`orchestration_update`를 **작업 종료 hook의 필수 단계**로 넣고, 미갱신 시 종료 실패 처리. 사람이 수정 가능하되, 구조화 영역은 자동 patch.

**최대 리스크**  
본문 트리와 frontmatter 간 **불일치**. 해결은 “frontmatter가 권위, 본문은 렌더 가능 영역” 원칙.

예시:
```md
---
goal: v5.37.0
active:
  - id: AO-1/P2/S3
    owner: generator
    status: in-progress
    next: evaluator
    refs: [plan.md#L10, verify.md#L3]
    assumptions: ["shell-only 유지"]
    blocker: null
---
# Active Tree
- AO-1 자동 풍부 모드
  - P2 릴리스
    - S3 통합 검증 [in-progress → evaluator]
```

## gemini
소프트웨어 아키텍처 전문가로서 **Hybrid(C) 모델**을 기반으로 한 재설계안을 제안합니다.

### 1. 설계 방향: Hybrid (C) - YAML Frontmatter + Markdown Tree
단순함과 정형 데이터의 균형을 위해 **Option C**가 최적입니다. Bash/Python은 YAML만 파싱하고, 에이전트와 사람은 본문 트리를 읽습니다.

### 2. 핸드오프 매니페스트 (최소 4필드)
- `source_agent`: 현재 작업을 마친 에이전트
- `target_agent`: 다음 바통을 받을 에이전트 (또는 `any`)
- `context_bridge`: 미해결 가정이나 주의사항 (Short string)
- `output_pointers`: 이전 단계 산출물 경로 (List)

### 3. 50줄 룰 재해석
**'Active Window'** 개념을 도입하십시오. 완료된 Task는 `[Done]` 상태로 1개 레이어만 남기고 상세 내역은 즉시 아카이브(또는 삭제)하여, 현재 진행 중인 노드의 하위 트리만 상세히 기술합니다.

### 4. 갱신 누락 방지 (Gap Closure)
에이전트 종료 시 `finish_task` MCP 도구 호출을 의무화하고, 이 도구가 `NOVA-STATE.md` 업데이트를 트랜잭션처럼 처리하게 강제하십시오. (Prompt에 "상태 업데이트 없이는 종료 불가" 명시)

### 5. 가장 큰 리스크
**'State Drift'**입니다. 에이전트가 실제 코드 수정 사항과 STATE를 다르게 기록할 경우 전체 오케스트레이션이 붕괴됩니다. 이를 방지하기 위해 `Evaluator` 단계에서 STATE와 실제 파일의 동기화 여부를 검증해야 합니다.

### [포맷 예시]
```md
---
current: { agent: Architect, task_id: T2, status: handoff }
handoff: { to: Generator, bridge: "API spec updated", refs: ["/docs/api.md"] }
---
# Nova State
- [Done] AO: V5.37 Release
  - [Done] Phase 1: Dashboard
- [/] Phase 2: Visual Intent (Active)
  - [ ] Sprint A3: Integration [In-Progress] <-- @Generator
    - [ ] Task 1: Hook setup
    - [ ] Task 2: Refactoring
```

## 합의 분석
- **합의율**: 95%
- **판정**: auto_approve
- **요약**: 모든 AI가 하이브리드(YAML+트리) 구조와 MCP 기반 자동 갱신, 활성 영역 중심의 50줄 관리에 완벽히 합의함.

### 공통점
- 솔루션 C(YAML Frontmatter + Markdown Tree)를 최적의 아키텍처로 선정
- 50줄 룰을 '활성 작업(Active Window)' 중심으로 재해석하고 완료된 작업은 아카이브 처리
- 핸드오프 필드에 이전/다음 에이전트, 산출물 포인터, 미결 가정(Assumptions) 포함 필수
- 에이전트의 상태 갱신 누락을 방지하기 위해 MCP 도구(hook) 호출 의무화 필요
- 기계 파싱(YAML)과 인간 가독성(Tree)의 분리 및 동기화 유지 강조

### 차이점
- 핸드오프 최소 필드 개수에 대한 미세한 차이 (4개 vs 5개 vs 6개)
- 아카이브 방식의 구체성 (별도 파일로 분리 vs 본문 내 요약/삭제)
- 가장 큰 리스크에 대한 관점 차이 (파싱 예외 vs 데이터 불일치 vs 실제 코드와의 괴리)
