---
description: "구현→검증을 한 사이클로 실행한다 (Full Cycle). --verify-only로 검증만 수행 가능."
---

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

## Phase 3: Verify

검증 강도에 따라 순차 실행한다. 각 단계는 독립 서브에이전트로 실행한다.

### Step 1: 정적 분석 (모든 강도)

- 타입 에러, 린트 경고 확인
- 가능하면 실제 빌드/테스트 실행

### Step 2: 구조적 리뷰 (Standard 이상)

- /review의 Evaluation Criteria 전체 적용 (6개 구조적 문제 기준)
- 적대적 자세: "이 코드에는 반드시 문제가 있다"

### Step 3: 설계 정합성 (Full만)

- 설계 문서가 있으면 /gap과 동일한 관점으로 검증
- Sprint Contract 기준 충족 여부 확인

## Phase 4: Verdict

종합 판정을 내린다.

| 판정 | 기준 | 후속 행동 |
|------|------|----------|
| PASS | Critical 0개, HIGH 0개, Warning 3개 미만 | 완료. 머지/배포 가능 |
| CONDITIONAL | Critical 0개, HIGH 1개 이상 또는 Warning 3개 이상 | **사용자에게 판단 위임**. 이슈 목록과 권장 조치를 제시 |
| FAIL | Critical 1개 이상 | Full Cycle이면 → Phase 5(재시도). Verify Only면 → 중단, 수정 필요 |

> 판정 기준은 /review, /gap, /verify와 동일하다.

출력 형식:

```
━━━ Nova Quality Gate ━━━━━━━━━━━━━━━━━━━━━
  판정: {PASS | CONDITIONAL | FAIL}
  검증 강도: {Lite | Standard | Full}
  모드: {Full Cycle | Verify Only}

  Critical: {개수}
  Warning: {개수}
  Info: {개수}

  {이슈 목록}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Phase 5: Auto-Retry (Full Cycle + FAIL만)

**조건**: Full Cycle 모드이고, 판정이 FAIL이고, 재시도 횟수가 0회일 때만 실행한다.

1. Evaluator가 지적한 Critical 이슈 목록을 구조화한다
2. Generator 서브에이전트를 **새로** spawn한다 (이전 Generator의 컨텍스트 오염 방지)
3. 수정 범위를 **Evaluator가 지적한 항목에만** 한정한다 — 다른 부분은 건드리지 않는다
4. 수정 완료 후 Phase 3(Verify)를 재실행한다
5. 재시도 후 판정에 따라 분기한다:
   - **PASS** → 완료
   - **CONDITIONAL** → 사용자에게 에스컬레이션 (Warning 목록 포함). 자동 재시도 안 함.
   - **FAIL** → 즉시 중단, 사용자에게 에스컬레이션

> **재시도는 최대 1회.** 2번째 FAIL은 자동으로 해결할 수 없는 구조적 문제일 가능성이 높다.

## Phase 6: State Update

`NOVA-STATE.md`가 프로젝트 루트에 있으면 검증 결과를 자동 반영한다:
- Recently Done 테이블에 작업 추가 (판정 결과 + 검증 문서 링크)
- In Progress 테이블에서 해당 작업 제거
- Recently Done이 3개 초과 시 가장 오래된 항목 제거
- Phase를 검증 결과에 따라 갱신 (PASS → done, FAIL → building)

# Input

$ARGUMENTS
