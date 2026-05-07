# [Design] `/nova:auto` Plan 재사용 + `/nova:deepplan` 고성능 Plan 모드

> Nova Engineering — CPS Framework
> 작성일: 2026-04-19
> Plan: plans/auto-plan-reuse-and-deepplan.md
> Verification: (Gap 검증 후 경로 추가)

---

## Context (설계 배경)

### Plan 요약
- 핵심 문제: orchestrator가 기존 Plan/Design을 무시하고 새로 씀 + 기본 `/nova:plan`이 얕은 단일 패스라 중요 판단에 부족
- 선택한 방안: Sprint 3개로 분할한 통합 minor 릴리스 — (1) 재사용 로직 (2) deepplan 파이프라인 (3) auto 통합 + 동기화

### 설계 원칙
- **기존 체계 침범 금지**: 기본 `/nova:plan` 동작·출력 포맷 변경 X. deepplan은 추가 섹션만 주입하고 CPS 골격 유지 → `/nova:design`이 그대로 소비 가능
- **Claude 독립**: 외부 AI(GPT/Gemini) 의존 없음. jury는 Claude 서브에이전트 페르소나 기반
- **Escape hatch 보장**: `--fresh`로 재사용 무시, `--deep` 비선택 시 기존 동작
- **구조화된 핸드오프**: Explorer 3개의 출력 포맷을 사전 정의해서 Synthesizer가 예측 가능하게 통합
- **Adaptive thinking 우선**: 고정 thinking budget 노출 X, 모델 자율에 맡김

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | slug 추출 규칙 (한글/영문 요청 → kebab-case 파일명 매칭) | 중간 | 없음 |
| 2 | 여러 Plan 후보 매칭 시 사용자 확인 UX | 낮음 | 과제 1 |
| 3 | Explorer 3개 병렬 spawn + 구조화된 출력 수집 | 높음 | 없음 |
| 4 | Synthesizer가 CPS 골격에 3 탐색 결과를 매핑하는 로직 | 높음 | 과제 3 |
| 5 | Critic(evaluator 스킬)을 **Plan 대상**으로 호출 (기존은 코드 대상) | 중간 | 없음 |
| 6 | jury 스킬 Plan 모드 확장 (페르소나 재정의) | 중간 | 없음 |
| 7 | Refiner 루프 (최대 iteration 제어, 무한 루프 방지) | 중간 | 과제 5 |
| 8 | `--deep` + Plan 존재 충돌 처리 (Plan 존중 원칙) | 낮음 | 과제 1 |
| 9 | hooks/session-start.sh + tests/test-scripts.sh 동기화 자동 검증 | 낮음 | 없음 |

### 기존 시스템과의 접점
- **`skills/orchestrator/SKILL.md`**: Phase 1에 분기 로직 추가, 기존 Phase 2~7 유지
- **`skills/evaluator/SKILL.md`**: "Plan 검증 모드" 추가 (코드가 아닌 Plan 문서 대상)
- **`skills/jury/SKILL.md`**: "Plan 모드" 페르소나 3인(architect/security/qa) 추가. 기존 코드 리뷰 모드 유지
- **`commands/plan.md`**: deepplan 크로스 레퍼런스만 추가. 본체 로직 무변경
- **`commands/auto.md`**: `--deep` 플래그 문서화 + 사용 예시
- **`docs/nova-rules.md`**: deepplan 트리거 기준 삽입 (§복잡도 판단)
- **호환성**: v5.10.2 → v5.11.0 (minor). 기존 사용자는 `--deep`, `--fresh` 미사용 시 행동 변화 없음

---

## Solution (설계 상세)

### 아키텍처

```
사용자 진입점
  ├─ /nova:plan "X"          → (기존) 단일 패스 CPS
  ├─ /nova:deepplan "X"      → (신규) Explorer→Synth→Critic→Refiner 4단
  └─ /nova:auto [--deep] "X" → (수정) Phase 1에서 Plan/Design 재사용 분기
                                       ↓
                                  [분기 A] Plan 없음 + --deep
                                       → deepplan 호출 → Plan 생성 → 기존 파이프라인
                                  [분기 B] Design 있음
                                       → Phase 2·3 스킵, Generator 직행
                                  [분기 C] Plan만 있음
                                       → Architect가 Plan 기반 설계
                                  [분기 D] 둘 다 없음, --deep 없음
                                       → 기존 동작 (fresh Architect)
                                  [분기 E] --fresh
                                       → 강제 fresh Architect (escape hatch)

deepplan 내부
  ┌─────────────────────────────────────────────┐
  │ Phase A: Explorer ×3 병렬 (서브에이전트)       │
  │   code-explorer  : Read/Glob/Grep            │
  │   risk-explorer  : 실패 시나리오 브레인스토밍 │
  │   option-explorer: 대안 3개 (ToT식)          │
  │         ↓ (구조화된 핸드오프)                 │
  │ Phase B: Synthesizer (메인 컨텍스트)           │
  │   CPS 골격 + Risk Map/Unknowns/Hooks 3섹션   │
  │         ↓                                    │
  │ Phase C: Critic                              │
  │   기본: evaluator 스킬(Plan 대상)             │
  │   --jury: jury 스킬(architect/security/qa)   │
  │         ↓ PASS → 완료                        │
  │         ↓ FAIL → Refiner                     │
  │ Phase D: Refiner (최대 N회, 기본 1)           │
  │   Critic 이슈 반영 재작성                     │
  └─────────────────────────────────────────────┘
         ↓
  docs/plans/{slug}.md (헤더: > Mode: deep)
```

### 데이터 모델

**slug 추출 규칙**:
```
입력: "/nova:auto '건폐율 시각화 추가'"
  1. 따옴표 안 추출 → "건폐율 시각화 추가"
  2. 공백 → "-", 특수문자 제거 → "건폐율-시각화-추가"
  3. 한글 유지 (사용자가 이미 쓴 Plan 파일명과 일치해야 함)
  4. 최종 slug: "건폐율-시각화-추가"

후보 매칭:
  exact match  → docs/plans/건폐율-시각화-추가.md
  fuzzy match  → 요청 첫 단어 기준 startsWith
  다중 후보    → 사용자에게 숫자 선택 프롬프트
```

**Explorer 핸드오프 포맷** (각 Explorer가 반환):
```
code-explorer 출력:
  ## Code Survey
  - 관련 파일: [path:line, ...]
  - 주요 패턴: [...]
  - 의존성: [...]
  - 현재 제약: [...]

risk-explorer 출력:
  ## Risk Map
  | 리스크 | 가능성 | 영향 | 완화 |
  | ... | H/M/L | H/M/L | ... |

  ## Unknowns
  - [추가 조사 필요 항목, 선조치 없이 진행 시 위험]

option-explorer 출력:
  ## Alternatives
  | 방안 | 장점 | 단점 | 권장도 |
  | A | ... | ... | ⭐ |
  | B | ... | ... |  |
  | C | ... | ... |  |
```

**Plan 문서 최종 구조** (deepplan 출력물):
```
# [Plan] {기능명}
> ...
> Mode: deep            ← deepplan 마커
> Iterations: 1         ← Refiner 반복 횟수

## Context
## Problem (MECE)
## Solution
  ### 선택한 방안
  ### 대안 비교 (option-explorer 입력)
  ### 구현 범위
  ### 검증 기준
## Sprints                ← 기본 CPS
## Risk Map               ← deepplan 추가
## Unknowns               ← deepplan 추가
## Verification Hooks     ← deepplan 추가 (Sprint Contract 씨앗)
## X-Verification         ← 선택
```

### 데이터 계약 (Data Contract)

| 필드 | 타입 | 단위/포맷 | 변환 규칙 | 비고 |
|------|------|-----------|-----------|------|
| `slug` | string | kebab-case (한글 허용) | 공백 → `-`, 특수문자 제거 | 파일명과 1:1 매칭 |
| `Mode` (헤더) | string | `deep` | 없음 | deepplan 출력물 식별 마커 |
| `Iterations` (헤더) | number | 정수 ≥1 | 없음 | Refiner 실행 횟수 기록 |
| Explorer 출력 | markdown 섹션 | 고정 헤더 (`## Code Survey`, `## Risk Map`, `## Alternatives`) | Synthesizer가 정규식으로 추출 | 헤더 이름 변경 금지 |
| `--iterations` 플래그 | number | 1~3 | 초과 시 3으로 clamp | 무한 루프 방지 |
| `--deep` + Plan 존재 | 플래그 | boolean | Plan 존중, `--deep` 무시 | 경고 로그 필수 |
| Critic verdict | enum | `PASS` / `FAIL` | 구조화된 이슈 목록 필수 | FAIL 시 Refiner 진입 |

### 핵심 로직

**Sprint 1 — orchestrator Phase 1 개정**:
```
function phase1_request_analysis(request, flags):
    slug = extract_slug(request)
    plan_path = "docs/plans/{slug}.md"
    design_path = "docs/designs/{slug}.md"

    # 1) fresh + deep 복합: fresh 우선 적용 + deepplan으로 새 Plan 생성
    if flags.fresh and flags.deep:
        log("[Orchestrator] fresh+deep 모드 — deepplan 호출 후 파이프라인 진입")
        run_deepplan(request)
        return PlanReuseFlow(plan_path)

    # 2) fresh 단독: 기존 Plan/Design 무시
    if flags.fresh:
        log("[Orchestrator] fresh 모드 — 기존 Plan/Design 무시")
        return FreshFlow()

    # 3) Design 존재: --deep 포함 여부와 무관하게 Design 우선 (Phase 2·3 스킵)
    if exists(design_path):
        log(f"[Orchestrator] Design 재사용: {design_path} — Phase 2·3 스킵")
        return DesignReuseFlow(design_path)

    # 4) Plan + --deep 조합: Plan 존중, --deep 무시 (경고)
    if exists(plan_path) and flags.deep:
        warn("[Orchestrator] --deep 무시 — 기존 Plan 존중. 재실행하려면 --fresh --deep")
        return PlanReuseFlow(plan_path)

    # 5) Plan 단독: Architect가 Plan 기반 설계
    if exists(plan_path):
        log(f"[Orchestrator] Plan 재사용: {plan_path} — Architect가 Plan 기반 설계")
        return PlanReuseFlow(plan_path)

    # 6) --deep 단독: deepplan 호출 → Plan 생성 → 재사용
    if flags.deep:
        log("[Orchestrator] deepplan 호출 — Plan 생성 후 파이프라인 진입")
        run_deepplan(request)
        return PlanReuseFlow(plan_path)

    # 7) 기본: fresh Architect
    return FreshFlow()
```

**Sprint 2 — deepplan 파이프라인**:
```
function deepplan(request, flags):
    slug = extract_slug(request)

    # Phase A: Explorer 3개 병렬
    explorers = spawn_parallel([
        ("code-explorer",   CODE_EXPLORER_PROMPT),
        ("risk-explorer",   RISK_EXPLORER_PROMPT),
        ("option-explorer", OPTION_EXPLORER_PROMPT),
    ])
    results = await_all(explorers, timeout=10min)

    # Phase B: Synthesizer (메인)
    plan_draft = synthesize(request, results)  # CPS + 3 추가 섹션

    # Phase C~D: Critic + Refiner 루프
    iterations = min(flags.iterations or 1, 3)
    for i in range(iterations + 1):
        critic_fn = jury_plan_mode if flags.jury else evaluator_plan_mode
        verdict = critic_fn(plan_draft)
        if verdict.pass or i == iterations:
            break
        plan_draft = refine(plan_draft, verdict.issues)

    plan_draft.header["Mode"] = "deep"
    plan_draft.header["Iterations"] = i
    save(f"docs/plans/{slug}.md", plan_draft)
    update_nova_state("planning", plan_path)
    return plan_path
```

**Sprint 3 — `/nova:auto --deep` 통합**:
```
# commands/auto.md가 orchestrator 스킬에 플래그 전달
# skills/orchestrator/SKILL.md Phase 1에서 flags.deep 처리 (위 Sprint 1 로직에 포함됨)
# 핵심: deepplan은 Plan이 없을 때만 호출. 있으면 --deep 무시 + 경고.
```

### 에러 처리

| 예상 에러 | 대응 방안 |
|----------|----------|
| slug 추출 실패 (빈 문자열) | 요청 첫 단어를 slug로 사용 + 경고 로그 |
| 여러 Plan 후보 매칭 | 사용자에게 숫자 선택 프롬프트 (1/2/3/fresh) |
| Explorer 서브에이전트 1개 실패 | 나머지 2개 결과로 Synthesizer 진행 + 경고. 3개 모두 실패 시 중단 + `/nova:plan` 폴백 안내 |
| Explorer 타임아웃 (10분 초과) | 실패 처리 (위와 동일) |
| Critic FAIL 후 Refiner도 FAIL (iteration 소진) | 최종 Plan 저장하되 헤더에 `⚠️ Critic Unresolved Issues` 마커. 사용자 검토 안내 |
| `--deep` + Plan 존재 | `--deep` 무시 + 경고: "기존 Plan 존중. 재실행하려면 `--fresh --deep`" |
| jury 스킬 Plan 모드 미구현 상태에서 `--jury` 호출 | evaluator 폴백 + 경고 |
| Refiner 무한 루프 방지 | `--iterations` 최대 3으로 clamp |

---

## Sprint Contract (스프린트별 검증 계약)

> Generator(구현자)와 Evaluator(검증자)가 **사전에 합의**하는 성공 조건.
> Evaluator는 이 계약을 기준으로 PASS/FAIL을 판정한다.
> **Evaluator는 이 계약의 조건이 불충분하다고 판단하면 수정을 요청할 수 있다.**

### Sprint 1: orchestrator Plan/Design 재사용

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 1 | `docs/plans/{slug}.md` 존재 시 `/nova:auto` 실행하면 "Plan 재사용" 로그 출력 + Phase 2(Architect) 스킵 | 로그 확인 | 수동 시나리오 — Plan 있는 프로젝트에서 auto 실행 후 로그 grep | **Critical** |
| 1 | `docs/designs/{slug}.md` 존재 시 Phase 2·3 모두 스킵, Generator 직행 | 로그 확인 | 수동 시나리오 — Design 있는 프로젝트 | **Critical** |
| 1 | Plan/Design 없을 때 기존 동작 유지 (fresh Architect) | 회귀 테스트 | `bash tests/test-scripts.sh` — 기존 테스트 전부 통과 | **Critical** |
| 1 | 여러 Plan 후보 매칭 시 사용자 선택 프롬프트 | 수동 시나리오 | 동일 prefix 파일 2개 만들고 auto 실행 | Nice-to-have |
| 1 | `--fresh` 플래그로 재사용 무시 가능 | 수동 시나리오 | Plan 있는 상태에서 `/nova:auto --fresh` | **Critical** |
| 1 | slug 추출 로직이 한글/영문 둘 다 지원 | 단위 시나리오 | 요청 2종(한글/영문) 입력 후 slug 추출 결과 검증 | **Critical** |

### Sprint 2: `/nova:deepplan` 단독 파이프라인

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 2 | `/nova:deepplan "X"` 실행 시 `docs/plans/X.md` 생성 | 파일 존재 확인 | `test -f docs/plans/X.md && echo OK` | **Critical** |
| 2 | 출력 Plan에 Risk Map · Unknowns · Verification Hooks 3섹션 포함 | grep | `grep -c "^## Risk Map\|^## Unknowns\|^## Verification Hooks" docs/plans/X.md` → 3 | **Critical** |
| 2 | Plan 헤더에 `> Mode: deep` 마커 존재 | grep | `grep "^> Mode: deep" docs/plans/X.md` | **Critical** |
| 2 | Explorer 3개 병렬 실행 (code/risk/option) | 로그 확인 | 실행 로그에 3 서브에이전트 spawn 흔적 | **Critical** |
| 2 | Critic이 evaluator 스킬을 **Plan 대상**으로 호출 | 로그 + evaluator 프롬프트 검증 | 로그에 "evaluator (target: plan)" 표기 | **Critical** |
| 2 | Critic FAIL → Refiner 1회 실행 | 로그 | `Iterations` 헤더 값 확인 | **Critical** |
| 2 | `--iterations=N` 옵션 동작 (1~3 clamp) | 수동 시나리오 | `/nova:deepplan --iterations=5 "X"` → Iterations=3 | Nice-to-have |
| 2 | `--jury` 플래그 시 jury 스킬 호출 (architect/security/qa 페르소나) | 로그 | 3 페르소나 spawn 확인 | Nice-to-have |
| 2 | Explorer 1개 실패해도 나머지 2개로 진행 | 수동 시나리오 | Explorer 의도적 실패 주입 | Nice-to-have |
| 2 | NOVA-STATE.md Phase가 `deep-planning` → `planning` 전환 | 파일 diff | `grep "Phase" NOVA-STATE.md` 전후 비교 | Nice-to-have |

### Sprint 3: `/nova:auto --deep` 통합 + 동기화

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 3 | `/nova:auto --deep "X"` 실행 시 Plan 없으면 deepplan 호출 → orchestrator 파이프라인 진입 | 로그 + 파일 | Plan 없는 fixture에서 실행, 로그 "deepplan 호출" + Plan 파일 생성 확인 | **Critical** |
| 3 | Plan 있음 + `--deep` → `--deep` 무시 + 경고 + Plan 재사용 | 로그 | Plan 있는 상태에서 실행, 경고 메시지 grep | **Critical** |
| 3 | `--fresh --deep` 조합 시 기존 Plan 무시하고 deepplan 재실행 | 수동 시나리오 | 로그 "Plan 재사용 무시" + "deepplan 호출" 동시 | **Critical** |
| 3 | `tests/test-scripts.sh` EXPECTED_COMMANDS에 `deepplan` 추가 | 테스트 | `bash tests/test-scripts.sh` 통과 | **Critical** |
| 3 | `hooks/session-start.sh` 커맨드 목록에 `/nova:deepplan` 추가, JSON 유효 | 파싱 | `bash hooks/session-start.sh \| python3 -m json.tool` | **Critical** |
| 3 | `commands/next.md` 워크플로우 추천에 deepplan 진입 조건 포함 | 수동 확인 | 파일 읽기 | Nice-to-have |
| 3 | `commands/plan.md`에 deepplan 크로스 레퍼런스 추가 | 수동 확인 | grep "deepplan" commands/plan.md | Nice-to-have |
| 3 | `docs/nova-rules.md`에 deepplan 트리거 기준 (아키텍처 전환/마이그레이션) 추가 | 수동 확인 | grep "deepplan" docs/nova-rules.md | Nice-to-have |
| 3 | 플러그인 설치 후 `/nova:deepplan` 자동 등록 (수동 파일 복사 없음) | fixture 테스트 | fixture 프로젝트에 설치 → 커맨드 호출 | **Critical** |

### 관통 검증 조건 (End-to-End)

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | `/nova:plan "기능X"` → `/nova:design "기능X"` → `/nova:auto "기능X"` | Phase 2·3 스킵 로그 + Generator가 Design 기반 Dev 프롬프트 수신 + 구현 산출물 생성 | **Critical** |
| 2 | `/nova:deepplan "기능Y"` 단독 실행 | `docs/plans/기능Y.md` 생성 + 3 추가 섹션 + Mode:deep 마커 + Critic 결과 로그 | **Critical** |
| 3 | `/nova:auto --deep "기능Z"` (Plan 없음) | deepplan 호출 → Plan 저장 → orchestrator 파이프라인 진입 → Dev → QA → 완료 보고 | **Critical** |
| 4 | `/nova:auto --deep "기능W"` (Plan 이미 있음) | `--deep` 무시 경고 + 기존 Plan 기반 Architect → Dev → QA 진행 | **Critical** |
| 5 | `/nova:auto --fresh "기능V"` (Plan 있음) | Plan 재사용 무시 + fresh Architect로 처음부터 진행 | **Critical** |

### 역방향 검증 체크리스트

- [ ] Plan의 모든 요구사항(문제 영역 1~5)이 설계에 반영되었는가?
- [ ] Sprint Contract의 각 Done 조건이 Plan의 구현 범위 체크리스트와 1:1 매핑되는가?
- [ ] `--fresh` escape hatch가 모든 재사용 분기에 적용되는가?
- [ ] 외부 AI 의존이 완전히 제거되었는가? (jury는 Claude 서브에이전트만)
- [ ] 동기화 누락(session-start.sh, test-scripts.sh, nova-rules.md)이 없는가?
- [ ] deepplan이 기존 `/nova:plan` 출력물을 **소비 가능한** 형태로 남기는가? (CPS 골격 유지)
- [ ] Refiner 무한 루프가 구조적으로 방지되는가? (iteration clamp)

### 평가 기준

- **기능**: 관통 검증 조건 5개 모두 동작하는가?
- **설계 품질**: Phase 1 분기 로직이 MECE인가? 엣지 케이스가 빠지지 않았는가?
- **단순성**: Explorer 3개가 각자 고유 역할을 갖는가? 중복 없이 Synthesizer가 단순 merge 가능한가?

---

## Notes
- deepplan 파이프라인의 Explorer 프롬프트 본문은 Sprint 2 구현 시 확정한다. Design에는 역할 정의와 출력 포맷만 명시.
- jury 스킬 Plan 모드 페르소나는 Sprint 2에서 정의. 기존 jury 구성(Correctness/Design/User)은 유지하고 **모드 분기**로 추가.
- `/ultraplan`(Claude Code 클라우드)과의 역할 분리는 `commands/deepplan.md` 본문에 명시 예정.
- Sprint 2~3 구현 중 Explorer 개수 조정(3→4, 예: `docs-explorer` 추가)이 필요하다고 판단되면 Design 갱신 후 재진입.
