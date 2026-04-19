---
description: "CPS(Context-Problem-Solution) 프레임워크로 Plan 문서를 작성한다."
---

CPS(Context-Problem-Solution) 프레임워크로 Plan 문서를 작성한다.

# Role
너는 Nova Engineering의 Plan 작성자다.
사용자의 요구사항을 CPS 구조로 분석하고 구조화된 Plan 문서를 생성한다.

# Execution

1. 사용자 입력에서 기능명/주제를 추출한다.
2. `docs/templates/cps-plan.md`가 있으면 참고한다. **없으면 아래 인라인 구조를 사용한다** (템플릿 없음을 언급하지 않는다).
3. 다음 구조를 반드시 채운다:

```markdown
# [Plan] {기능명}

> Nova Engineering — CPS Framework
> 작성일: {YYYY-MM-DD}
> 작성자: {이름}
> Design: {designs/slug.md — Design 작성 후 경로 추가}

---

## Context (배경)

### 현재 상태
- {현재 시스템/프로세스의 상태 설명}

### 왜 필요한가
- {비즈니스/기술적 동기}

### 관련 자료
- {링크, 이슈 번호, 참고 문서}

---

## Problem (문제 정의)

### 핵심 문제
{한 문장으로 요약}

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | {영역} | {구체적 설명} | 높음/중간/낮음 |

### 제약 조건
- {기술적 제약}
- {시간/리소스 제약}
- {비즈니스 제약}

---

## Solution (해결 방안)

### 선택한 방안
{방안 요약}

### 대안 비교

| 기준 | 방안 A | 방안 B |
|------|--------|--------|
| {기준} | | |
| 선택 | **채택** | 기각 (사유) |

### 구현 범위
- [ ] {태스크 1}
- [ ] {태스크 2}

### 검증 기준
- {성공 조건 1}
- {성공 조건 2}

---

## X-Verification (다관점 수집)

> 필요 시 기록. 불필요하면 이 섹션 삭제.

| AI | 의견 요약 | 합의 |
|----|----------|------|
| Claude | | O/X |
| GPT | | O/X |
| Gemini | | O/X |

합의 수준: {Strong Consensus | Partial Consensus | Divergent}
```

## Sprints (스프린트 분할)

예상 수정 파일이 8개 이상이면 독립 검증 가능한 스프린트로 분할한다:

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | {기능A} | {파일 목록} | 없음 | {검증 가능한 완료 기준} |
| 2 | {기능B} | {파일 목록} | Sprint 1 | {검증 가능한 완료 기준} |

- 각 스프린트는 독립적으로 검증 가능해야 한다
- 의존성이 있으면 의존 순서대로 배치
- Done 조건은 Evaluator가 검증할 수 있는 구체적 기준

예상 수정 파일이 7개 이하면 스프린트 분할 없이 단일 구현으로 진행한다.

4. 작성된 문서를 `docs/plans/{slug}.md`에 저장한다.
5. 다관점 수집이 필요한 설계 판단이 있으면 `/ask` 사용을 제안한다.
6. Plan 헤더의 `Design:` 필드는 비워둔다. `/design` 실행 시 자동으로 채워진다.
# CRITICAL: NOVA-STATE.md 갱신 (이 단계를 건너뛰지 마라)

**Plan 작성이 끝나면 반드시 NOVA-STATE.md를 업데이트한다.** 이 단계 없이 커맨드를 종료하면 안 된다.

- 프로젝트 루트에 `NOVA-STATE.md`가 없으면 `docs/templates/nova-state.md` 기반으로 생성
- Current → Goal을 Plan 제목으로, Phase를 `planning`으로 설정
- Refs → Plan 경로 기록
- Last Activity 갱신:
  ```
  ## Last Activity
  - /nova:plan → 완료 — docs/plans/{slug}.md | {ISO 8601}
  ```

# Related: `/nova:deepplan`과 `/ultraplan`

## `/nova:deepplan` — 로컬 강화 플래닝

아키텍처 전환·대형 마이그레이션·실패 비용이 높은 판단에는 `/nova:deepplan`을 사용한다.
Explorer×3 병렬 탐색 → Synthesizer → Critic → Refiner 4단계로 기본 `/nova:plan`보다 깊이 있는 Plan을 생성한다.

| | `/nova:plan` | `/nova:deepplan` | `/ultraplan` |
|---|---|---|---|
| 실행 | 로컬 동기 (터미널) | 로컬 동기 (터미널) | 클라우드 비동기 (브라우저 리뷰) |
| 플래닝 깊이 | CPS 단일 패스 | Explorer×3 + Critic + Refiner | 전용 컴퓨트 + 인라인 피드백 |
| 적합 | 일반 기능 추가, 버그 수정 | 아키텍처 전환, 대형 마이그레이션, 보안 경계 변경 | 대형 팀 공유 문서, 브라우저 인라인 피드백 |
| 토큰/시간 | 기본 | 3~5×, 10~20분 추가 | 별도 클라우드 컴퓨트 |
| Nova 체인 | Plan → Design → 구현 체인 | Plan → Design → 구현 체인 (동일) | 독립 실행 (결과를 Nova에 수동 흡수) |

**언제 `/nova:deepplan`을 쓰나**:
- 기존 시스템 다수를 재구성하는 아키텍처 전환
- DB 스키마·인증 구조·외부 API 연동처럼 실패 비용이 높은 판단
- 대안을 충분히 탐색하고 싶을 때
- 단순 기능 추가에는 `/nova:plan`이 더 빠름

## `/ultraplan`과의 역할 분리

Claude Code `/ultraplan`은 클라우드 CCR에서 최대 30분 전용 컴퓨트로 플래닝 세션을 돌리고 브라우저에서 인라인 코멘트로 반복 편집한다. `/nova:plan`과 **실행 모델이 달라 체인 통합하지 않는다.** 보완재로 병용한다.

| | `/nova:plan` | `/ultraplan` |
|---|---|---|
| 실행 | 로컬 동기 (터미널) | 클라우드 비동기 (브라우저 리뷰) |
| 프레임 | CPS(Context-Problem-Solution) + 스프린트 분할 | 자유 형식 + 인라인 피드백 루프 |
| 적합 | 매 기능 단위, Design으로 이어지는 플래닝 | 대형 마이그레이션·아키텍처 전환·팀 공유 문서 |
| 통합 | Plan → Design → 구현 체인 | 독립 실행 (결과를 Nova에 수동 흡수) |

> 위 비교는 2026-04-17 시점 공개 문서 기준이며, Claude Code 업데이트에 따라 변경될 수 있다. 실제 연동 전 [Claude Code Docs](https://code.claude.com/docs)에서 최신 동작을 확인하라.

**언제 `/ultraplan`을 병용하나**
- 대형 마이그레이션(예: 스키마 전환, 프레임워크 교체)에서 **팀 리뷰가 필요**할 때
- 터미널을 해방하고 플래닝을 병렬로 돌리고 싶을 때
- 결과를 `/nova:plan`에 **수동으로 옮겨** Nova 체인에 진입시킨다 — 자동 연동 없음

Nova 자체는 `/ultraplan`을 자동 호출하지 않는다. 사용자가 판단하여 독립 실행한다.

# Notes
- Plan은 "무엇을, 왜" — Design은 "어떻게"
- Plan 없이 바로 코딩하지 않는다
- 간단한 버그 수정에는 불필요 (기능 추가/변경에 사용)
- 스프린트의 Done 조건은 이후 Sprint Contract의 기초가 된다

# Input
$ARGUMENTS
