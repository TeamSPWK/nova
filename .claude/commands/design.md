CPS(Context-Problem-Solution) 프레임워크로 Design 문서를 작성한다.

# Role
너는 AXIS Engineering의 Design 작성자다.
Plan 문서를 기반으로 기술적 설계 상세를 작성한다.

# Execution

0. (버전 체크) `scripts/.axis-version` 파일이 있으면 `curl -fsSL --max-time 3 https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/scripts/.axis-version 2>/dev/null`로 최신 버전을 확인한다. 버전이 다르면 출력 마지막에 한 줄 안내한다: `🔄 AXIS Kit 업데이트 가능 (현재 → 최신) — curl -fsSL .../install.sh | bash -s -- --update`. 실패 시 조용히 건너뛴다.

1. 사용자 입력에서 기능명/주제를 추출한다.
2. 해당 Plan 문서가 `docs/plans/`에 있는지 확인한다.
   - 있으면 Plan을 읽고 기반으로 설계
   - 없으면 "먼저 /plan을 실행하세요" 안내
3. `docs/templates/cps-design.md` 템플릿을 기반으로 작성한다.
4. 다음 구조를 반드시 채운다:

## Context (설계 배경)
- Plan 요약, 설계 원칙

## Problem (설계 과제)
- 기술적 과제 목록 (복잡도, 의존성)
- 기존 시스템과의 접점

## Solution (설계 상세)
- 아키텍처 (다이어그램 또는 구조 설명)
- 데이터 모델 / API 설계 / 핵심 로직
- 에러 처리

## 검증 계약 (Verification Contract)
- 기능별 **테스트 가능한 성공 조건** 목록
  - 형식: "사용자가 X하면 Y가 되어야 한다"
  - 각 조건이 `/gap`에서 검증 가능해야 함
- 검증 우선순위 (Critical / Nice-to-have)

## 평가 기준 (Evaluation Criteria)
- 기능: 모든 요구사항이 동작하는가?
- 설계 품질: 구조가 일관되고 확장 가능한가?
- 단순성: 불필요한 복잡도가 없는가?

5. 작성된 문서를 `docs/designs/{slug}.md`에 저장한다.

# Notes
- Design은 "어떻게" — 구체적 기술 상세
- 검증 계약은 Generator-Evaluator 패턴의 핵심: 구현자와 검증자가 사전에 합의
- Plan의 모든 요구사항이 Design에 반영되었는지 확인
- 아키텍처 판단이 어려우면 `/xv`로 교차검증

# Input
$ARGUMENTS
