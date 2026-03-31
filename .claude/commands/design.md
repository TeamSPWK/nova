---
description: "CPS(Context-Problem-Solution) 프레임워크로 Design 문서를 작성한다."
---

CPS(Context-Problem-Solution) 프레임워크로 Design 문서를 작성한다.

# Role
너는 Nova Engineering의 Design 작성자다.
Plan 문서를 기반으로 기술적 설계 상세를 작성한다.

# Execution

1. 사용자 입력에서 기능명/주제를 추출한다.
2. 해당 Plan 문서가 `docs/plans/`에 있는지 확인한다.
   - 있으면 Plan을 읽고 기반으로 설계
   - 없으면 "먼저 /plan을 실행하세요" 안내
3. `docs/templates/cps-design.md`가 있으면 참고한다. **없으면 아래 인라인 구조를 사용한다** (템플릿 없음을 언급하지 않는다).
4. 다음 구조를 반드시 채운다:

## Context (설계 배경)
- Plan 요약, 설계 원칙

## Problem (설계 과제)
- 기술적 과제 목록 (복잡도, 의존성)
- 기존 시스템과의 접점

## Solution (설계 상세)
- 아키텍처 (다이어그램 또는 구조 설명)
- 데이터 모델 / API 설계 / 핵심 로직
- **데이터 계약 (Data Contract)**: 주요 필드의 단위/포맷/변환 규칙을 테이블로 명시. 구현자가 잘못된 가정을 하지 않도록 반드시 작성
- 에러 처리

## Sprint Contract (스프린트별 검증 계약)

> Generator(구현자)와 Evaluator(검증자)가 **사전에 합의**하는 성공 조건.
> Evaluator는 이 계약을 기준으로 PASS/FAIL을 판정한다.

Plan에 스프린트가 정의되어 있으면 스프린트별로, 없으면 기능 단위로 작성한다:

| Sprint | Done 조건 | 검증 방법 | 우선순위 |
|--------|----------|----------|---------|
| 1 | {사용자가 X하면 Y가 되어야 한다} | {어떻게 검증하는가} | Critical |
| 1 | {조건 2} | {검증 방법} | Nice-to-have |
| 2 | {조건 3} | {검증 방법} | Critical |

**Sprint Contract의 원칙:**
- 각 조건은 **테스트 가능**해야 한다 (주관적 기준 금지)
- Evaluator가 이 계약의 조건이 불충분하다고 판단하면 **수정을 요청할 수 있다**
- "동작한다"가 아니라 "사용자가 쓸 수 있다"가 기준이다

## 관통 검증 조건 (End-to-End)

> "저장됨" ≠ "사용 가능함". 데이터가 입력부터 최종 표시까지 관통하는지 검증한다.

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | {데이터 입력/저장} | {다른 화면에서 로드/표시} | Critical |

## 평가 기준 (Evaluation Criteria)
- 기능: 모든 요구사항이 동작하는가?
- 설계 품질: 구조가 일관되고 확장 가능한가?
- 단순성: 불필요한 복잡도가 없는가?

## 역방향 검증 체크리스트
- [ ] 모든 Plan 요구사항이 설계에 반영되었는가?
- [ ] 설계의 각 컴포넌트가 Plan의 문제를 해결하는가?
- [ ] 누락된 엣지 케이스가 없는가?

5. 작성된 문서를 `docs/designs/{slug}.md`에 저장한다.
6. 저장 후, 원본 Plan 문서의 헤더에 `> Design: designs/{slug}.md` 경로를 추가한다.
7. **NOVA-STATE.md 자동 갱신**: 프로젝트 루트의 `NOVA-STATE.md`를 업데이트한다 (없으면 `docs/templates/nova-state.md` 기반으로 생성).
   - Current → Phase를 `building`으로 전환
   - Refs → Design 경로 기록
   - 마지막 활동 기록:
     ```
     ## 마지막 활동
     - 커맨드: /nova:design
     - 시각: {ISO 8601}
     - 결과: 완료
     - 대상: docs/designs/{slug}.md
     ```

# Design 반복 루프

E2E 테스트나 `/gap` 검증에서 설계 자체의 문제가 발견되면:
- Design 문서를 수정하고 Sprint Contract를 업데이트한다
- 수정된 Design을 기준으로 재구현한다
- "Design은 한 번 쓰고 끝나는 것이 아니다"

# Notes
- Design은 "어떻게" — 구체적 기술 상세
- Sprint Contract는 Generator-Evaluator 패턴의 핵심: 구현자와 검증자가 **사전에** 합의
- Plan의 모든 요구사항이 Design에 반영되었는지 확인
- 아키텍처 판단이 어려우면 `/xv`로 다관점 수집

# Input
$ARGUMENTS
