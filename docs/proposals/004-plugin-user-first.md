# [Rule Proposal] 플러그인 사용자 우선 검증

> Nova Engineering — Adaptive Rule Proposal
> 날짜: 2026-03-31
> 상태: 제안됨
> 제안자: AI

---

## 감지 (Detect)

### 발견된 패턴

**Nova 개발 시 "Nova 프로젝트 내부" 관점으로만 수정하고, "플러그인 사용자에게 실제로 전달되는가"를 검증하지 않는 패턴이 반복됨.**

이번 세션(v3.2.0~v3.3.2)에서 16개 커밋 중 6개가 이 패턴으로 인한 후속 수정이었다:

1. v3.2.0~v3.2.1: CLAUDE.md만 수정 → session-start.sh 동기화 누락 (사용자 미반영)
2. v3.2.4: hooks.json에서 session-start.sh 참조 누락 발견 (v3.1.1부터 회귀)
3. v3.3.0: 팀 전수 검사에서 /nova-update 유령 참조 6건 발견 (사용자가 없는 커맨드 호출)
4. v3.3.1: init-nova-state.sh가 docs/ 없는 신규 프로젝트에서 실패 (온보딩 불가)

### 발생 빈도
- 발견 횟수: 4회 (세션 내)
- 발견 위치: CLAUDE.md, hooks/hooks.json, hooks/session-start.sh, scripts/init-nova-state.sh, 6개 커맨드 파일

### 증거
```
v3.2.0: CLAUDE.md §2 변경 → session-start.sh 미동기화 → v3.2.2에서 수정
v3.2.4: hooks.json이 v3.1.1에서 session-start.sh 참조 삭제 → 자동 규칙 미주입
v3.3.1: init-nova-state.sh가 빈 프로젝트에서 exit 1 → 플러그인 온보딩 실패
```

### 근본 원인
Nova 개발자(AI 포함)가 **Nova 소스 코드를 수정하는 관점**과 **플러그인 사용자가 경험하는 관점**을 혼동한다. CLAUDE.md는 개발용이지 사용자에게 전달되지 않는데, 이 구분이 작업 중 잊혀진다.

---

## 제안 (Propose)

### 규칙 내용

**"플러그인 사용자 경로 검증" 규칙:**

모든 변경사항에 대해 커밋 전 다음을 확인한다:

1. **이 변경이 플러그인 사용자에게 전달되는가?**
   - commands/, agents/, skills/ → 자동 전달
   - hooks/session-start.sh → additionalContext로 자동 주입
   - CLAUDE.md → **전달 안 됨** (session-start.sh 동기화 필요)

2. **신규 프로젝트에서 동작하는가?**
   - docs/ 디렉토리 없음
   - NOVA-STATE.md 없음
   - 테스트/린트 설정 없음

3. **삭제된 기능을 참조하는 곳이 없는가?**
   - 커맨드/스킬 삭제 시 `grep -r "삭제된이름"` 전체 검색

### 적용 범위
- 적용 대상: Nova 프로젝트 전체 (모든 커밋)
- 강제 수준: **테스트 강제** (tests/test-scripts.sh에 검증 포함) + CLAUDE.md 가이드라인

### 기대 효과
- 사일런트 미반영 방지 (session-start.sh 동기화 누락 0건)
- 신규 프로젝트 온보딩 실패 방지
- 유령 참조 0건

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

- 반영 위치: CLAUDE.md "플러그인 배포 구조" 섹션 (이미 부분 반영됨), tests/test-scripts.sh 동기화 테스트 (이미 반영됨)
- 반영 커밋:

## 검증 (Verify)

- 기존 코드 충돌: 없음 — 이미 v3.2.3~v3.3.0에서 테스트 + 문서 반영 완료
- 적용 후 문제: 없음
- 비고: 이 규칙은 이번 세션에서 실질적으로 이미 적용됨. 제안서는 공식 기록 목적.
