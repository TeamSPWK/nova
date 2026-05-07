# [Plan] Phase 5: Optimization — Eval 지표 및 도구 키트 완성

> AXIS Engineering — CPS Framework
> 작성일: 2026-03-26
> 작성자: Spacewalk Engineering

---

## Context (배경)

### 현재 상태
- Phase 1~4 완성: 구조(Structured), 검증(X-Verify), 맥락(Context Chain), 진화(Adaptive)
- AXIS 4 Pillars의 도구가 모두 갖춰짐
- 하지만 "잘 쓰고 있는지" 측정할 방법이 없음

### 왜 필요한가
- 방법론의 효과를 정량화해야 개선 방향을 잡을 수 있음
- 도구 키트로서 설치/사용의 완결성 필요
- README, 파일 구조 등 최종 정리

---

## Problem (문제 정의)

### 핵심 문제
AXIS를 도입한 프로젝트가 **방법론을 얼마나 잘 따르고 있는지** 측정할 수 없다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 측정 기준 없음 | 어떤 지표로 효과를 판단할지 모름 | 높음 |
| 2 | 도입 가이드 미흡 | axis-kit 설치 후 뭘 해야 하는지 불명확 | 중간 |
| 3 | README 최신화 필요 | Phase 3~4 산출물이 반영 안 됨 | 중간 |

### 제약 조건
- 자동 측정 대시보드는 범위 밖 (경량 원칙)
- 체크리스트 기반 자가 평가로 충분

---

## Solution (해결 방안)

### 구현 범위
- [ ] `docs/eval-checklist.md` — AXIS 도입 자가 평가 체크리스트
- [ ] `docs/axis-engineering.md` 로드맵 체크리스트 업데이트
- [ ] README.md 최종 업데이트 (Phase 3~5 반영)

### 검증 기준
- 체크리스트로 프로젝트의 AXIS 도입 수준 평가 가능
- README가 전체 도구 키트를 정확히 설명
- `/gap`으로 역방향 검증 시 90% 이상 매칭
