# [Plan] Nova v4 — Self-Evolution + Command UX Overhaul

> Nova Engineering — CPS Framework
> 작성일: 2026-04-10
> 작성자: jay-swk + Claude
> Design: docs/designs/nova-v4-evolution.md (작성 예정)

---

## Context (배경)

### 현재 상태
- Nova v3.15.0 — 13개 커맨드, 5개 에이전트, 5개 스킬, 6개 MCP 도구
- 매 세션 session-start.sh로 10개 규칙 자동 주입
- pre-commit-reminder.sh로 커밋 전 리마인더 (advisory)
- 모든 업데이트는 사용자 수동 트리거

### 왜 필요한가
- **팀 피드백**: "xv가 뭔지 모르겠다", "Nova를 매번 호출해야 하나?", "커맨드가 너무 많다"
- **기술 환경**: Claude Code, 오픈소스 하네스 도구가 빠르게 진화 — 수동 추적 한계
- **Nova 철학**: Adaptive Pillar가 존재하지만 실제 자동 진화 메커니즘은 없음
- **UX**: `/nova:` 입력 시 xv가 먼저 노출, 커맨드 간 중복 존재 (gap ⊂ verify)

### 관련 자료
- 랜딩 페이지: https://jay-swk.github.io/nova-landing
- 팀 피드백: xv 명칭 불명확, always-on 요구, 커맨드 정리 요구

---

## Problem (문제 정의)

### 핵심 문제
Nova가 "좋은 것을 흡수해 발전한다"는 철학을 가지고 있지만, 실제로는 사람이 수동으로 업데이트해야 하고, 커맨드 UX가 팀 사용성을 저해한다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **자동 진화 부재** | 기술 동향 추적, 규칙 개선, 자기 업그레이드가 전부 수동 | 높음 |
| 2 | **커맨드 과잉 + 중복** | 13개 중 gap⊂verify, propose는 단독 사용 드묾, metrics도 init과 겹침 | 중간 |
| 3 | **xv 명칭 불명확** | 팀원이 의미를 모름 → 사용 안 함 → 핵심 기능 사장 | 중간 |
| 4 | **Always-On 부재** | 사용자가 `/nova:*` 명시적 호출 필요 → 습관 없으면 미사용 | 높음 |
| 5 | **커맨드 정렬** | `/nova:` 입력 시 xv가 먼저 노출, auto/review가 뒤에 밀림 | 낮음 |

### 제약 조건
- Nova는 Claude Code 플러그인 → commands/*.md 파일명이 곧 정렬 순서 (알파벳)
- 기존 사용자 호환: 갑자기 커맨드를 없애면 혼란
- 169개 기존 테스트를 깨뜨리면 안 됨
- Self-evolution이 Nova 자체 품질을 깨뜨리면 안 됨

---

## Solution (해결 방안)

### 방안 요약

4개 워크스트림으로 분리 실행:

**WS-1. 커맨드 정리** — 13개 → 10개 + 리네이밍
**WS-2. Always-On** — 사용자 호출 없이 Nova 자동 작동
**WS-3. Self-Evolution** — `/nova:evolve` 커맨드 + 자동 스케줄
**WS-4. 테스트 + 릴리스** — 169개 테스트 업데이트 + v4.0 릴리스

---

### WS-1. 커맨드 정리

#### 삭제 (3개)

| 커맨드 | 사유 | 흡수처 |
|--------|------|--------|
| `/nova:gap` | verify = review + gap 이미 통합 | `/nova:verify` |
| `/nova:propose` | 단독 사용 드묾, evolve에 포함 | `/nova:evolve` |
| `/nova:metrics` | init --check로 대체 가능 | `/nova:init --check` |

#### 리네이밍 (1개)

| 현재 | 변경 | 사유 |
|------|------|------|
| `/nova:xv` | `/nova:consult` | "xv"는 의미 불명. "consult"는 "전문가 자문"으로 직관적. 멀티 AI에게 의견을 "묻는다"는 의미가 명확 |

**대안 검토:**

| 후보 | 의미 | 판정 |
|------|------|------|
| `consult` | 전문가 자문 | **채택** — 직관적, 동사로 자연스러움 |
| `council` | 위원회 | 기각 — 명사형, 커맨드로 어색 |
| `cross` | 교차검증 | 기각 — xv와 비슷하게 모호 |
| `debate` | 토론 | 기각 — AI끼리 토론하는 느낌, 목적 불명확 |
| `ask-all` | 다 물어보기 | 기각 — 하이픈 포함, 비격식적 |

#### 신규 (1개)

| 커맨드 | 목적 |
|--------|------|
| `/nova:evolve` | 기술 동향 스캔 → 변경 제안 → 자동 구현 → 품질 게이트 → 머지/PR |

#### 정렬 최적화

Claude Code 플러그인은 commands/ 파일명 알파벳 순으로 표시.
사용 빈도 높은 커맨드가 위에 오도록 파일명 앞에 숫자 프리픽스 또는 파일명 자체를 조정:

**최종 커맨드 목록 (10개, 알파벳 순):**

```
1. auto        ← 가장 많이 쓰임 (a로 시작)
2. consult     ← xv 대체 (c로 시작)
3. design      ← CPS 설계
4. evolve      ← 신규 (e로 시작)
5. explore     ← 온보딩
6. init        ← 프로젝트 셋업
7. next        ← 다음 단계 추천
8. orchestrate ← 전체 파이프라인
9. plan        ← CPS 계획
10. review     ← 적대적 리뷰
11. verify     ← 통합 검증
```

> auto, consult, design이 상단에 오고, xv는 사라짐. review/verify도 하단이지만 가장 자주 쓰이는 auto가 맨 위.

> **참고**: 11개지만, 현재 13개 대비 2개 순감. gap/propose/metrics 삭제(3), evolve 추가(1), xv→consult 리네이밍(±0).

---

### WS-2. Always-On Nova

#### 현재 상태
- `session-start.sh`: 규칙 주입 (advisory) ✅
- `pre-commit-reminder.sh`: 커밋 전 리마인더 (advisory) ✅
- 문제: 둘 다 advisory — AI가 무시할 수 있음

#### 목표
사용자가 `/nova:*`를 명시적으로 호출하지 않아도 Nova가 자동 작동하는 상태.

#### 구현 방안

**A. session-start.sh 강화 — "강제 행동" 추가**

현재 `additionalContext`에 규칙만 주입. 여기에 **행동 지시**를 추가:

```
## 필수 행동 (MUST)

1. 모든 코드 변경 작업에 Nova 규칙을 적용한다 (사용자가 Nova를 언급하지 않아도).
2. 3파일 이상 변경 시 반드시 Plan을 먼저 제시한다.
3. 커밋 전 /nova:review --fast를 자동 실행한다.
4. 구현 완료 시 Evaluator를 독립 서브에이전트로 실행한다.
5. 블로커 발생 시 즉시 사용자에게 알린다.
```

> "advisory"에서 "MUST"로 격상. AI는 지시(instruction)를 따르므로, 명확한 MUST 표현이 핵심.

**B. pre-commit hook 강화 — "차단" 모드 옵션**

현재: 리마인더만 (advisory)
변경: `--strict` 모드 시 실제 차단 (hookResult: "block")

```json
{
  "decision": "block",
  "reason": "3파일 이상 변경이지만 /nova:verify 미실행. 먼저 실행해주세요."
}
```

**C. 자동 행동 트리거 추가**

| 트리거 | 자동 행동 |
|--------|----------|
| 세션 시작 | NOVA-STATE.md 읽기 + 상태 요약 |
| 3+ 파일 변경 감지 | Plan 제시 권고 → MUST |
| `git commit` 감지 | verify --fast 자동 실행 (현재: 리마인더) |
| 에러/실패 2회 반복 | 블로커 자동 분류 |
| 구현 완료 선언 | Evaluator 자동 실행 |

---

### WS-3. Self-Evolution (`/nova:evolve`)

#### 아키텍처

```
/nova:evolve [--scan | --apply | --auto]

--scan   : 기술 동향 스캔 + 제안서만 생성 (기본)
--apply  : 제안서 기반 구현 + 품질 게이트
--auto   : scan + apply + 자율 범위 내 자동 머지
```

#### 파이프라인

```
┌─ Scanner ─────────────────────────────────────────┐
│ 1. 소스 스캔                                       │
│    - Anthropic 공식 문서/블로그/changelog           │
│    - Claude Code 릴리스 노트                       │
│    - 주요 오픈소스 하네스 도구 (aider, cursor 등)   │
│    - Claude Code 플러그인 생태계                   │
│                                                    │
│ 2. Nova 관련성 필터                                │
│    - Nova 4대 Pillar과 관련된 변화인가?            │
│    - 기존 커맨드/스킬/규칙에 영향이 있는가?         │
│    - 새로운 기능 기회인가?                         │
│                                                    │
│ 3. 제안서 생성 → docs/proposals/YYYY-MM-DD-*.md    │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌─ Planner ─────────────────────────────────────────┐
│ 4. 제안서 → CPS Plan 자동 생성                     │
│ 5. 변경 범위 분류 (patch / minor / major)          │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌─ Builder ─────────────────────────────────────────┐
│ 6. Plan 기반 코드 변경 구현                        │
│    - commands/*.md 수정                            │
│    - skills/*/SKILL.md 수정                        │
│    - hooks/*.sh 수정                               │
│    - docs/nova-rules.md 수정                       │
│    - session-start.sh 동기화                       │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌─ Quality Gate Chain ──────────────────────────────┐
│ 7. bash tests/test-scripts.sh  → FAIL이면 폐기    │
│ 8. /nova:review (Evaluator)    → FAIL이면 수정    │
│ 9. /nova:consult (Jury/멀티AI) → FAIL이면 폐기    │
│    (major 변경만)                                  │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌─ Merge Policy ────────────────────────────────────┐
│ patch → 게이트 통과 시 자동 커밋                   │
│ minor → PR 생성 + 사용자 알림                      │
│ major → 제안서만 생성 + 사용자 결정                │
└───────────────────────────────────────────────────┘
```

#### 자율 범위 정책

| 수준 | 예시 | 자동화 등급 |
|------|------|------------|
| **patch** | 문서 개선, 규칙 문구 다듬기, 체크리스트 항목 추가 | **Full Auto** — 게이트 통과 시 자동 커밋 |
| **minor** | 새 체크리스트 섹션, 검증 기준 추가, 훅 로직 개선 | **Semi Auto** — PR 생성, 사용자 알림 |
| **major** | 새 커맨드/스킬, 아키텍처 변경, 호환성 영향 | **Manual** — 제안서만, 사용자 결정 |

#### 스케줄

- **수동**: `/nova:evolve` → 즉시 실행
- **자동**: Schedule (cron) → 화/목/토 06:00 KST

#### 필요 파일

| 파일 | 용도 |
|------|------|
| `commands/evolve.md` | 커맨드 정의 |
| `skills/evolution/SKILL.md` | Scanner → Planner → Builder → Gate 파이프라인 |
| Schedule cron 설정 | 자동 실행 등록 |

---

### WS-4. 테스트 + 릴리스

#### 테스트 영향

| 변경 | 테스트 영향 |
|------|------------|
| gap 삭제 | gap 관련 테스트 삭제/수정 |
| xv → consult 리네이밍 | xv 관련 테스트 전체 리네이밍 |
| propose 삭제 | propose 관련 테스트 삭제 |
| metrics 삭제 | metrics 관련 테스트 삭제/init으로 이동 |
| evolve 추가 | 새 테스트 추가 |
| session-start.sh 변경 | 동기화 테스트 업데이트 |
| hooks 변경 | 훅 테스트 업데이트 |

#### 버전

이 변경은 **major** 수준 — 커맨드 삭제는 호환성이 깨지는 변경.

**v4.0.0**으로 릴리스.

---

## 구현 범위 (Sprint 분할)

### Sprint 1: 커맨드 정리 (WS-1)
- [ ] gap.md 삭제, verify.md에 gap 기능 완전 흡수 확인
- [ ] propose.md 삭제
- [ ] metrics.md 삭제, init.md에 --check 플래그 추가
- [ ] xv.md → consult.md 리네이밍 + 내용 수정
- [ ] session-start.sh 커맨드 목록 동기화
- [ ] 테스트 업데이트

### Sprint 2: Always-On (WS-2)
- [ ] session-start.sh에 "필수 행동" 섹션 추가
- [ ] pre-commit-reminder.sh 강화 (차단 모드 옵션)
- [ ] hooks.json 업데이트
- [ ] 테스트 업데이트

### Sprint 3: Self-Evolution (WS-3)
- [ ] commands/evolve.md 작성
- [ ] skills/evolution/SKILL.md 작성
- [ ] docs/nova-rules.md에 Self-Evolution 규칙 추가
- [ ] 테스트 추가

### Sprint 4: 통합 + 릴리스 (WS-4)
- [ ] 전체 테스트 통과 확인
- [ ] /nova:review --strict 실행
- [ ] 랜딩 페이지 업데이트 내용 정리
- [ ] v4.0.0 버전 범프 + 릴리스

---

## 검증 기준

1. `bash tests/test-scripts.sh` 전체 통과
2. `/nova:verify --strict` PASS
3. 삭제된 커맨드(gap, propose, metrics)가 더 이상 노출되지 않음
4. `/nova:consult`가 기존 xv와 동일하게 동작
5. 사용자가 `/nova:*`를 호출하지 않아도 Nova 규칙이 자동 적용됨
6. `/nova:evolve --scan`이 기술 동향 제안서를 생성
7. session-start.sh JSON 유효성 통과
