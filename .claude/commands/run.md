---
description: "구현→검증을 한 사이클로 실행한다 (Full Cycle). --verify-only로 검증만 수행 가능."
description_en: "Run the implement → verify full cycle. Use --verify-only to run verification alone."
---

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §5` 검증 경량화 원칙 (기본 Lite, `--strict` Full)
- `docs/nova-rules.md §6` 복잡한 작업의 스프린트 분할 (8+ 파일 → 독립 검증 가능한 스프린트)
- `docs/nova-rules.md §7` 블로커 분류 (Auto/Soft/Hard, 2회 실패 시 강제 분류)
- `docs/nova-rules.md §10` 관찰성 계약 — 스프린트/블로커 이벤트 기록

## 관찰성 훅 (v5.12.0+)

- Sprint 착수: `bash hooks/record-event.sh sprint_started "$(jq -cn --arg n \"$SPRINT\" --argjson pf $PLANNED_FILES '{sprint_name:$n, planned_files:$pf}')" 2>/dev/null || true`
- Sprint 완료: `bash hooks/record-event.sh sprint_completed "$(jq -cn --arg n \"$SPRINT\" --arg v \"$VERDICT\" --argjson rt $REGRESSION_PASS '{sprint_name:$n, verdict:$v, regression_tests_pass:$rt}')" 2>/dev/null || true`
- 블로커 감지: `bash hooks/record-event.sh blocker_raised "$(jq -cn --arg t \"$BTYPE\" --arg c \"$CAUSE\" '{blocker_type:$t, cause:$c}')" 2>/dev/null || true`
- 블로커 해소: `bash hooks/record-event.sh blocker_resolved "$(jq -cn --arg t \"$BTYPE\" --arg r \"$RESOLUTION\" '{blocker_type:$t, resolution:$r}')" 2>/dev/null || true`

Safe-default: 기록 실패는 run 사이클 진행에 영향 없음.

# Role

너는 Nova Quality Gate의 종합 검증자다.
기본 모드에서는 구현 + 검증을 한 사이클로 수행한다.
`--verify-only` 모드에서는 검증만 수행한다 (외부 오케스트레이터 연동용).

# 핵심 원칙

- 검증은 반드시 독립 서브에이전트로 실행한다 (Generator-Evaluator 분리)
- 자동 재시도는 FAIL 판정에만, 최대 1회
- CONDITIONAL은 사용자에게 판단을 넘긴다
- 기본은 경량(--fast), 명시적 요청 시만 정밀(--strict)

# Execution

## Phase 0: Mode & Preflight

### 모드 판별

입력에서 모드를 판별한다:

| 플래그 | 모드 | 동작 |
|--------|------|------|
| (없음) | **Full Cycle** | Generator 서브에이전트 → Evaluator 서브에이전트 |
| `--verify-only` | **Verify Only** | Evaluator 서브에이전트만 (현행 동작) |
| `--with-refiner` | **GAN 3단** | Evaluator FAIL 시 refiner 서브에이전트 호출. 수정안 제시, 자동 적용 없음. |

### Preflight Check

1. 변경된 파일 목록 확인 (`git diff --name-only`)
2. 관련 설계 문서 탐색 (`docs/designs/`, `docs/plans/`)
3. 테스트 존재 여부 확인

## Phase 1: Risk Assessment

변경 규모와 위험도를 자동 판단하여 검증 강도를 결정한다.

| 규모 | 기준 | 검증 강도 |
|------|------|----------|
| Small | 1~2 파일, 단순 변경 | Lite: 정적 분석만 |
| Medium | 3~7 파일 | Standard: 정적 + 구조적 리뷰 |
| Large | 8+ 파일 또는 다중 모듈 | Full: 정적 + 구조적 + 설계 정합성 |

> **고위험 영역 상향**: 인증/DB/결제/보안 관련 변경은 파일 수와 무관하게 한 단계 상향한다.

`--fast` 옵션: 무조건 Lite 강제
`--strict` 옵션: 무조건 Full 강제

## Phase 2: Generate (Full Cycle 모드만)

**이 단계는 `--verify-only`이면 건너뛴다.**

독립 서브에이전트(Generator)를 spawn하여 구현을 수행한다.

Generator 서브에이전트에 전달할 컨텍스트:
- 작업 목표 (사용자 요청 원문)
- 관련 설계 문서 경로 (있는 경우)
- 수정 대상 파일 목록
- 기존 코드 패턴/컨벤션 요약

> Generator는 `senior-dev` 에이전트 타입을 사용한다.
> Generator에게 "구현만 하라, 검증은 별도 수행한다"고 명시한다.
> tmux 세션 내라면 별도 pane으로 spawn하여 사용자가 진행 상황을 볼 수 있게 한다.

### ✅ Checkpoint: Generate 완료
Generator 완료 후, 사용자에게 구현 요약을 보고하고 Verify 진행 여부를 확인받는다:
- 변경된 파일 목록
- 주요 변경 내용 요약 (3줄 이내)
- "검증을 진행합니다" — 사용자가 중단하거나 방향을 수정할 기회를 준다
- **복잡도 재판단**: 실제 변경 파일 수가 Phase 0 Risk Assessment 초기 판단을 초과했는가? 초과 시 사용자에게 알리고 (a) Plan 승격 또는 (b) 범위 축소 중 결정. 초기 판단 고수 금지.

## Phase 3: Verify

검증 강도에 따라 순차 실행한다. 각 단계는 독립 서브에이전트로 실행한다.

### Step 1: 정적 분석 (모든 강도)

- 타입 에러, 린트 경고 확인
- 가능하면 실제 빌드/테스트 실행

### Step 2: 구조적 리뷰 (Standard 이상)

- /review의 Evaluation Criteria 전체 적용 (6개 구조적 문제 기준)
- 적대적 자세: "이 코드에는 반드시 문제가 있다"

### Step 3: 설계 정합성 (Full만)

- 설계 문서가 있으면 /check의 설계-구현 정합성 검증과 동일한 관점으로 검증
- Sprint Contract 기준 충족 여부 확인

### ✅ Checkpoint: Verify 완료 — 배포 전 하드 게이트

**검증 결과가 PASS가 아니면 배포 금지.** 이 게이트는 우회 불가 (유일한 예외: `--emergency`).

배포가 포함된 작업이면, 배포 전 다음을 추가 확인한다:
- 로컬 빌드: 에러 없이 빌드 완료
- 로컬 테스트: 전수 테스트 통과
- 핵심 API: curl로 주요 엔드포인트 정상 응답 확인
- "로컬에서 curl 한 번이면 잡히는 버그"를 프로덕션에서 발견하는 것은 프로세스 실패

## Phase 4: Verdict

종합 판정을 내린다.

| 판정 | 기준 | 후속 행동 |
|------|------|----------|
| PASS | Critical 0개, HIGH 0개, Warning 3개 미만 | 완료. 머지/배포 가능 |
| CONDITIONAL | Critical 0개, HIGH 1개 이상 또는 Warning 3개 이상 | **사용자에게 판단 위임**. 이슈 목록과 권장 조치를 제시 |
| FAIL | Critical 1개 이상 | Full Cycle이면 → Phase 5(재시도). Verify Only면 → 중단, 수정 필요 |

> 판정 기준은 /review, /gap, /check와 동일하다.

출력 형식 (구조화된 마크다운 — 파싱 가능한 표준 포맷):

```markdown
## Nova Quality Gate — Verdict

| 항목 | 값 |
|------|-----|
| 판정 | **{PASS / CONDITIONAL / FAIL}** |
| 검증 강도 | {Lite / Standard / Full} |
| 모드 | {Full Cycle / Verify Only} |
| 대상 | {변경 파일 수}개 파일 |

### 이슈 요약

| # | 심각도 | 파일 | 이슈 | 권장 조치 |
|---|--------|------|------|----------|
| 1 | Critical | path/to/file.py:42 | 설명 | 조치 |
| 2 | HIGH | path/to/file.py:87 | 설명 | 조치 |
| 3 | Warning | path/to/file.py:15 | 설명 | 조치 |

### Known Gaps (미커버 영역)
- {검증하지 못한 경로/경계값/환경}

### 다음 단계
- {PASS: "배포 가능" / CONDITIONAL: 사용자 판단 항목 / FAIL: 수정 필요 항목}
```

> **왜 구조화된 마크다운인가**: JSON 로그는 파싱에 수작업이 필요하다. 마크다운 테이블은 사람이 바로 읽을 수 있고, 필요 시 파싱도 쉽다.

## Phase 5: Auto-Fix (FAIL 자동 수정)

**진입 조건: FAIL 판정만.** CONDITIONAL은 자동 수정하지 않는다 — 이슈 목록과 권장 조치를 사용자에게 보고하고 판단을 위임한다.

FAIL 판정 시, Evaluator의 이슈 목록을 기반으로 자동 수정을 시도한다.

### 자동 수정 흐름

```
Evaluator 이슈 목록
  ↓
이슈별 수정 작업 생성 (Task)
  ↓
Generator 서브에이전트 spawn (이슈 목록 + 수정 범위 전달)
  ↓
수정 완료 → Phase 3(Verify) 재실행
  ↓
판정에 따라 분기
```

### 자동 수정 규칙

1. Evaluator가 지적한 **Critical/HIGH 이슈**를 구조화된 수정 작업으로 변환한다:
   ```
   ━━━ Auto-Fix Plan ━━━━━━━━━━━━━━━━━━━━━━━
     수정 대상: {N}건 (Critical {N} / HIGH {N})

     [1] {파일:라인} — {이슈 설명} → {수정 방향}
     [2] {파일:라인} — {이슈 설명} → {수정 방향}

     수정을 진행합니다. (중단: Ctrl+C)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
2. Generator 서브에이전트를 **새로** spawn한다 (이전 Generator의 컨텍스트 오염 방지)
3. 수정 범위를 **Evaluator가 지적한 항목에만** 한정한다 — 다른 부분은 건드리지 않는다
4. 수정 완료 후 Phase 3(Verify)를 재실행한다
5. 재시도 후 판정에 따라 분기한다:
   - **PASS** → 완료
   - **CONDITIONAL** → 사용자에게 에스컬레이션 (Warning 목록 포함). 자동 재시도 안 함.
   - **FAIL** → 즉시 중단, 사용자에게 에스컬레이션

> **자동 수정은 최대 1회.** 2번째 FAIL은 자동으로 해결할 수 없는 구조적 문제일 가능성이 높다.

### Verify Only 모드에서 --fix

`--verify-only --fix` 조합 시: 검증만 수행 → FAIL이면 수정 작업 생성 → Generator spawn → 재검증.
"구현은 이미 했는데 검증에서 떨어졌을 때" 자동 수정을 원할 때 사용한다.

```
/run --verify-only --fix    # 검증 + 실패 시 자동 수정
/run --verify-only           # 검증만 (기존 동작)
```

### ✅ Checkpoint: 전체 사이클 완료
사이클 완료 후, 배포 포함 작업이면 반드시 사용자에게 최종 확인을 받는다:
- Verdict 결과 요약 (이슈 테이블)
- 배포 대상 환경
- "배포를 진행할까요?" — 사용자 명시적 승인 없이 배포하지 않는다

> **대형 PR 전 2차 감사**: 8+파일 또는 인증/DB/결제 변경이면 인간 리뷰 직전에 Claude Code `/ultrareview`(클라우드 멀티 에이전트 + 재현 검증)를 병용할 수 있다. Nova 체인에 자동 포함되지 않으며, 정책·비용 판단은 사용자. 상세는 `commands/review.md` "Related" 참조.

## Phase 6: State Update

`NOVA-STATE.md`가 프로젝트 루트에 있으면 검증 결과를 자동 반영한다:
- Recently Done 테이블에 작업 추가 (판정 결과 + 검증 문서 링크)
- Tasks 테이블에서 해당 작업 제거
- Recently Done이 3개 초과 시 가장 오래된 항목 제거
- Phase를 검증 결과에 따라 갱신 (PASS → done, FAIL → building)

# Input

$ARGUMENTS
