# [Rule Proposal] 릴리스 전 /review 필수

> Nova Engineering — Adaptive Rule Proposal
> 날짜: 2026-03-31
> 상태: 제안됨
> 제안자: AI

---

## 감지 (Detect)

### 발견된 패턴

**릴리스 후 /review에서 Critical이 발견되어 즉시 핫픽스가 필요한 패턴이 반복됨.**

이번 세션에서 v3.3.0을 릴리스한 직후 /review에서 Critical 3건이 발견되어 v3.3.1 핫픽스가 필요했다. 특히 C-1(init-nova-state.sh 신규 프로젝트 실패)은 플러그인의 핵심 온보딩 기능이 완전히 불동작하는 심각한 문제였다.

### 발생 빈도
- 발견 횟수: 1회 (이번 세션)
- 하지만 릴리스 워크플로우에 /review가 포함되지 않아 매번 잠재적으로 발생 가능

### 증거
```
v3.3.0 릴리스 → /review 실행 → FAIL (Critical 3건) → v3.3.1 핫픽스
릴리스 워크플로우(CLAUDE.md):
  1. 구현 + 테스트 통과 확인
  2. git add + git commit
  3. bump-version.sh → commit → tag → push → release

→ /review 단계가 없음
```

### 근본 원인
Release Workflow에 "테스트 통과"만 요구하고 "/review 통과"를 요구하지 않는다. tests/test-scripts.sh는 구조적 존재 확인(grep 수준)이지 실행 검증이 아니다. init-nova-state.sh의 실제 동작 실패는 테스트가 잡지 못했다.

---

## 제안 (Propose)

### 규칙 내용

**Release Workflow에 `/review --fast` 단계 추가:**

```
1. 구현 + 테스트 통과 확인
2. /review --fast (Lite 검증 — 정적 분석 + 실행 검증)  ← 추가
3. git add + git commit
4. bump-version.sh → commit → tag → push → release
```

- patch 릴리스: `--fast` (Lite)
- minor 릴리스: 기본 모드 (Standard)
- major 릴리스: `--strict` (Full)

### 적용 범위
- 적용 대상: CLAUDE.md Release Workflow 섹션
- 강제 수준: **가이드라인** (AI가 릴리스 시 자동으로 /review를 먼저 실행하도록 유도)

### 기대 효과
- 릴리스 후 즉시 핫픽스 필요한 상황 방지
- 실행 검증(Step 3)으로 테스트가 잡지 못하는 런타임 문제 조기 발견

---

## 승인 (Approve)

> 아래는 사람이 작성

- [x] 승인
- [ ] 수정 후 승인 (수정 내용: )
- [ ] 기각 (사유: )

승인자: jay
승인일: 2026-03-31

---

## 적용 (Apply)

> 승인 후 작성

- 반영 위치: CLAUDE.md "Release Workflow" 섹션
- 반영 커밋:

## 검증 (Verify)

- 기존 코드 충돌: 없음
- 적용 후 문제: 릴리스 속도가 약간 느려질 수 있으나, 핫픽스 비용 대비 이득
