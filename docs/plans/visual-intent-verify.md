---
title: Visual Intent Verify (G1+G3 페어 게이트)
sprint: A2 (Plan)
created: 2026-04-29
related:
  - docs/designs/visual-intent-verify.md
  - docs/guides/ui-quality-gate.md
  - scripts/capture-visual-intent.sh
  - scripts/visual-self-verify.sh
  - scripts/detect-ui-change.sh
---
# [Plan] Visual Intent Verify (G1+G3 페어 게이트)
> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> Design: docs/designs/visual-intent-verify.md
> Visual Intent: docs/plans/visual-intent-verify-intent.json (선택)
---
## Context
visual-intent-verify는 UI 작업에서 "의도 캡처"와 "시각 자가 검증"을 묶어
완료 선언의 신뢰도를 높이기 위한 프로젝트다.
도입 배경:
- 기존 체인은 코드 정합성 중심이라 시각 의도 회귀를 직접 차단하지 못함
- 사용자 워크플로우(`/nova:plan`, `/nova:run`, `/nova:check`)에 자연스럽게 삽입 필요
- 모든 사용자 보장을 위해 키/MCP 비의존 폴백 설계 필요
근거:
- `docs/research/2026-04-29-ui-ux-gap-rescan.md:45`
- `docs/guides/ui-quality-gate.md:12-19`
---
## Problem
핵심 문제:
UI 검증에서 시각 의도 계약이 빠져 회귀가 발생해도 PASS로 흘러갈 수 있다.
문제 분해:
| # | 영역 | 설명 | 영향도 |
|---|---|---|---|
| 1 | 의도 기준 부재 | intent.json 없으면 판정 기준 없음 | 높음 |
| 2 | 시각 검증 부재 | 구현 후 시각 불일치 차단 불가 | 높음 |
| 3 | 환경 편차 | Playwright MCP/키 유무에 따라 동작 불균형 | 중간 |
| 4 | 재검증 비용 | 동일 변경 반복 검증 비용 증가 | 중간 |
---
## Solution Overview
해결 방식은 G1+G3 페어 게이트다.
1. G1 Intent Capture
- `capture-visual-intent.sh`로 intent.json v1.0 freeze
- vocabulary/scope/design_system/references 등 구조화
2. G3 Self-Verify
- `visual-self-verify.sh`가 ready_for_judge JSON 생성
- Agent judge가 intent와 결과를 비교
3. 안정성 장치
- 폴백 체인 4단계
- 캐시 hit 시 재검증 생략
- opt-out/비-UI 경로 허용
---
## Sprint 분할
### Sprint A1 — G1 시각 의도 캡처
범위:
- `scripts/capture-visual-intent.sh`
- `.claude/commands/plan.md` G1 호출부
- intent.json 스키마(v1.0) 확정
Done Criteria:
- capture 스크립트 동작
- intent.json freeze 완료
- plan.md에서 UI 감지 시 G1 자동 호출
### Sprint A2 — G3 시각 자가 검증
범위:
- `scripts/visual-self-verify.sh`
- `.claude/commands/run.md` Phase 5.5b
- `.claude/commands/check.md` Phase 3.5
- 폴백 체인 4단계
Done Criteria:
- verify 스크립트 동작
- 폴백 체인 4단계 명세/구현 정합
- run/check 호출부 연결 완료
### Sprint A3 — 통합 + 회귀 가드
범위:
- `tests/test-scripts.sh` A2/A3 회귀
- `hooks/session-start.sh` 문맥 동기화
- fixture 3종 + 가이드 동기화
Done Criteria:
- 회귀 테스트 통과
- 가이드 정합
- fixture 시나리오 PASS
---
## Sprint Done Criteria 요약
| Sprint | 완료 조건 |
|---|---|
| A1 | capture 스크립트 + intent.json freeze + plan.md G1 호출 |
| A2 | verify 스크립트 + 폴백 체인 4단계 + run/check 호출 |
| A3 | 회귀 테스트 통과 + 가이드 + fixture |
---
## Design
세부 계약(데이터/출력/캐시/판정)은 아래 문서를 단일 진실원으로 사용한다.
- `docs/designs/visual-intent-verify.md`
---
## Risk
### 1) false positive (비-UI 발화)
위험:
- 백엔드 변경에도 게이트 발화 가능
완화:
- `detect-ui-change.sh --planning/--post-impl` UI 키워드 정규식 기반 필터 사용 (v5.26.1+: 임계치 제거 — UI 1파일/소규모 변경도 발화하되 키워드 미매칭이면 logic-only로 분류)
### 2) privacy (raw user phrase)
위험:
- 사용자 원문이 intent.json에 저장됨
완화:
- 목적을 evaluator 해석 기준으로 제한
- 외부 API 직접 호출 경로를 만들지 않음
### 3) 환경 차이 (Playwright MCP 유무)
위험:
- 캡처 인프라 부재 시 검증 중단 가능성
완화:
- `playwright-mcp -> user-manual -> code-only-fallback -> degraded report`
- API 키 의존성 0 유지
---
## 검증 포인트
1. 문서 키워드:
- `playwright-mcp`, `user-manual`, `code-only-fallback`
- `키 의존성 0`, `키 불필요`, `NOT REQUIRED`
2. 회귀 테스트:
- `tests/test-scripts.sh` A2/A3 PASS
3. 계약 정합:
- Design 문서와 스크립트 라인 근거 일치
