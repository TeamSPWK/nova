# [Plan] /nova:audit-self — Nova 자기 보안 진단

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1
> Design: docs/designs/audit-self.md
> Critic Round 1: FAIL (Critical 2건 + High 3건 + Medium 4건 = 9건 — Refiner 1회 적용)
> Critic Round 2: PASS (Critical 0건 — M#6 PARTIAL 1건은 Sprint 1.1 헤더 레벨 명시로 해소)

---

## Context (배경)

### 현재 상태

Nova는 v5.21.0 시점 ECC 적대적 갭 분석 P0 3건(컨텍스트 로스트 카탈로그·비용 가이드·Strategic Compact 스킬)을 모두 흡수했다. 잔여 P1 중 **자기 보안 진단**은 미적용 상태다.

- `agents/security-engineer.md` 는 **사용자 코드** OWASP/시크릿/위협모델링용으로만 사용 — Nova 자신의 plugin.json/hooks/agents/skills/commands는 검사 대상이 아니다.
- v5.18.3 PreToolUse `if` 사건(메모리 `feedback_spec_vs_runtime.md`)은 **hooks 자체가 공격 표면**임을 입증했다.
- 14개 커맨드 + 6 에이전트 + 11 스킬 + 9 hooks + plugin.json — 총 ~6900줄의 자기 코드는 **현재 0개 보안 룰**로 운영 중.
- ECC AgentShield는 102 정적 룰로 동일 구조를 검사하며 169K stars 시점 표준 패턴이 됨.

### 왜 필요한가

**기술적 동기.**

1. 플러그인 자체 권한 노출 표면이 사용자 코드보다 크다 — hooks가 사용자 환경에서 임의 셸을 실행하므로 plugin 보안 감사가 사용자 코드 감사보다 우선순위가 높아야 한다.
2. v5.18.3 사건 같은 hooks 회귀를 사후가 아닌 release 전 차단해야 한다.
3. ECC AgentShield 패턴은 검증된 메커니즘 — Nova 5기둥 중 "품질"의 자기 적용 (메타 품질 게이트).

**비즈니스 동기.**

- ECC 169K stars 격차 추격 X. **메서드론 차별화** — Nova는 "자기 자신을 자기 게이트로 검사하는 응집형 프레임워크"임을 증명.
- v5.22.0 minor 릴리스 1회로 P1-1 클로저.

### 관련 자료

| 카테고리 | 경로 | 역할 |
|----------|------|------|
| 출처 | `docs/proposals/2026-04-29-ecc-adversarial-gap.md:140-167` | P1-1 명세 (5 카테고리, --opus 3에이전트) |
| 패턴 참조 | `commands/review.md:1-413` | --jury, --strict, PASS/CONDITIONAL/FAIL 판정 패턴 |
| 패턴 참조 | `commands/ux-audit.md:1-310` | 5인 병렬 평가자 (run_in_background:true) |
| 패턴 참조 | `commands/check.md:1-223` | 정합성 검증 Phase 1~3 구조 |
| 의존성 | `agents/security-engineer.md:1-77` | OWASP/시크릿/위협모델링 (Read/Glob/Grep 전용) |
| 의존성 | `skills/evaluator/SKILL.md:1-393` | Layer 1~3 적대적 검증 + Coverage Gate |
| 의존성 | `skills/jury/SKILL.md:1-135` | architect/security/qa 3 페르소나 합의 프로토콜 |
| 의존성 | `hooks/record-event.sh:1-80` | evaluator_verdict / jury_verdict 이벤트 기록 |
| 동기화 대상 | `hooks/session-start.sh:1-99` | NOVA_PROFILE별 커맨드 카탈로그 |
| 동기화 대상 | `tests/test-scripts.sh` (EXPECTED_COMMANDS) | 신규 커맨드 자동 검증 |
| 동기화 대상 | `.claude-plugin/plugin.json:1-79` | tool_contract.per_agent (신규 에이전트 도입 시) |
| 메모리 | `feedback_evaluator_hallucination.md` | Evaluator 결과 메인 사실 검증 원칙 |
| 메모리 | `feedback_spec_vs_runtime.md` | v5.18.3 hooks 사건 — 정적 분석 한계 인지 |
| 메모리 | `feedback_no_manual_setup.md` | 플러그인 업데이트만으로 자동 적용 — 수동 설치 절차 금지 |

---

## Problem (문제 정의)

### 핵심 문제

Nova 자신의 코드(plugin.json + hooks + agents + skills + commands)에 대한 **선언적·정적 보안 진단 메커니즘이 0개**다. 사용자 코드용 security-engineer는 있으나 자기 적용 회로가 없으며, 자기 검사를 하더라도 **메타-루프 자가 합리화** 위험이 통제되지 않은 채 결과 신뢰도가 보장되지 않는다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|-----------|------|--------|
| 1 | **검사 대상 부재** | plugin.json·hooks·agents·skills·commands 5 카테고리에 대한 정의된 룰셋·진입점·결과 포맷이 모두 없다 | High |
| 2 | **검사 신뢰도 부재** | security-engineer 단독 호출 시 환각 가능성(메모리 `feedback_evaluator_hallucination`). 메인 사실 검증 회로 미정의 | High |
| 3 | **메타-루프 자가 합리화** | security-engineer가 자기 정의(agents/security-engineer.md)를 검사 → 통과 편향. 검사자 ⊆ 검사 대상 | High |
| 4 | **룰셋 자기 검증 부재** | 30~50 룰을 한 번에 작성 시 룰 자체의 모순·중복·스키마 호환성 검증 절차 부재 | Medium |
| 5 | **정적 분석 한계** | Read/Glob/Grep 전용 → 런타임 권한 상승·동적 hooks 체인 실패·MCP 네트워크 호출 미탐지 | Medium |
| 6 | **release 통합 미정의** | release.sh에 자동 호출할지·차단 규칙·--emergency 우회 조건 미정의 (메모리 `feedback_release_sh_staging_trap` 영향) | Medium |
| 7 | **유지보수 절차 부재** | hooks 스키마 변경(예: v5.18.3 inner-command 도입) 시 룰 폐기·갱신·버전 매핑 절차 부재 | Low |
| 8 | **인시던트 대응 흐름 부재** | audit-self가 Critical 시크릿/취약점 발견 시 즉시 대응 절차(에스컬레이션 경로·차단 시점·복구 책임) 미정의. security-engineer는 리포트만 → 발견 이후 후속 행동 공백 | High |
| 9 | **검사 도구 자체의 무결성** | `docs/security-rules.md` 룰 파일이 변조되면 검사 결과 조작 가능 — 공급망 리스크. 룰 스키마 정합성(R4)과 별개로 룰 **내용 무결성**(tamper detection) 영역 부재 | Medium |

### 제약 조건

**코드 구조 제약 (code-explorer 출력 기반).**

- session-start.sh ≤1200자 (lean profile) 제약 — 커맨드 카탈로그 1줄 추가 (12자) 영향 미미.
- EXPECTED_COMMANDS 배열 동기화 필수 — `tests/test-scripts.sh`가 자동 검증.
- agents/*.md frontmatter `tools:` ↔ plugin.json `tool_contract.per_agent` 동기화 필수 — `audit-agent-tools.sh` 강제.
- security-engineer는 Read/Glob/Grep 전용 (Edit/Write/Bash 불가) — **동적 검사 불가**, 정적 룰만.

**Nova 정체성 제약.**

- 응집형 프레임워크 — ECC 102 룰 양적 추격 X. **5 카테고리 × 6~10 룰 = 30~50** 보수적 룰셋만.
- 수동 설치 절차 금지 (메모리 `feedback_no_manual_setup`) — 플러그인 업데이트만으로 자동 동작.
- 자기 진단 결과는 메인이 사실 검증 후 사용자 보고 (메모리 `feedback_evaluator_hallucination`).

**구조적 리스크 제약 (risk-explorer 출력 기반).**

- 메타-루프 자가 합리화 (H/H) — 검사자/검사 대상 분리 원칙 깨지면 결과 무효.
- False Negative (H/H) — 정적 분석 한계로 ECC 102 룰의 ~30%만 적용 가능.
- Evaluator 환각 (M/H) — audit-self PASS는 "배포 차단 해제 조건"이 아닌 "수동 점검 체크리스트 시그널".

---

## Solution (해결 방안)

### 선택한 방안

**방안 B — 외부 `docs/security-rules.md` + security-engineer → evaluator 직렬 + 카테고리별 섹션 + Risk Map** (option-explorer ⭐ 권장)

채택 근거 (각 항목은 측정 가능한 결과로 검증):

1. **외부 룰 문서화로 diff 추적 유리** — `docs/security-rules.md`로 외부화 시 룰 추가/수정/삭제가 git diff로 1:1 추적 가능. 인라인(방안 A)은 커맨드 본문 변경과 룰 변경이 한 commit에 섞여 변경 이력 파악 어려움. **검증**: 6개월 운영 후 git log `docs/security-rules.md` 변경 횟수 ≥ commands/audit-self.md 본문 변경 횟수.
2. **메인 사실 검증 회로 구조화** — `feedback_evaluator_hallucination` 원칙(메인이 grep으로 사실 검증)을 security-engineer → evaluator 직렬 + 메인 1회 grep 검증으로 3단 구현. 방안 A는 단일 호출이라 환각 가능성을 구조로 막지 못함. **검증**: V11 Verification Hook으로 Evaluator PASS 확인 + 메인 grep 검증 로그.
3. **minor 1회 분량 적합** — 신규 2파일(commands/audit-self.md ~80줄 + docs/security-rules.md ~600~700줄) + 수정 6파일 ~80줄 = 약 ~750~850줄. 방안 C는 ~1500줄+ 으로 minor 초과. **검증**: Sprint 1+2 종료 후 `git diff --stat` 합계.
4. **release.sh 게이트 매핑 가능** — 방안 B의 카테고리별 섹션 + Risk Map(Critical/Warning/Info)이 release.sh 게이트 분류와 1:1. v5.22.0은 자동 호출 도입 안 하지만(R6 완화) 6개월 운영 후 patch에서 추가 시 어휘 그대로 사용 가능.
5. **메타-루프 가드 분리 가능** — 방안 B는 `docs/security-rules.md`에서 검사 대상 exclusion list를 선언적으로 명시 가능. 방안 A는 인라인 룰이라 exclusion이 룰 본문에 섞임 — 검사자/검사 대상 분리 원칙 텍스트 흔적이 약함.

방안 A 장점도 인정한다 (선택 시 후회 최소화):

- 단일 파일·구현 즉시·외부 파일 동기화 부채 없음 — minor 1회로 빠른 출시 가능
- 사용자가 audit-self 진입 시 1파일 Read만으로 전체 파악 가능 (인지 부하 낮음)

그러나 5 카테고리 × 6~10 룰 = 30~50 룰을 commands/audit-self.md 단일 파일에 인라인 시 ~800줄 단일 파일이 됨. Nova 기존 commands 평균 ~200줄(review.md 413줄이 최대)을 4배 초과 — 유지보수 시 diff 추적이 곤란하다.

### 대안 비교

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | 인라인 룰 + security-engineer 단독 + 단순 리스트 | 파일 1개·구현 신속 | 룰셋 분산·docs/nova-rules 동기 부재·--jury와 기본 모드 구별 모호 | |
| B | 외부 `docs/security-rules.md` + security-engineer → evaluator 직렬 + 카테고리별 섹션 + Risk Map 테이블 | Nova 정체성 정합·메인 검증 회로 구조화·릴리스 게이트 1:1 매핑 | 비용 2배(에이전트 직렬)·룰 검증 메타-스파이크 필요 | ⭐ |
| C | YAML 룰 + Red/Blue/Auditor 3에이전트 병렬 + JSON+MD dual 출력 | 머신 파싱·다관점 검증·CI 자동 차단 가능 | minor 분량 초과(v5.23.0 이전)·메타-루프 자동 판단 자체 실패 가능·비용 3배 | |

> v5.22.0 = 방안 B만. C 요소(3에이전트, JSON 출력)는 차후 P1-1 확장 분기로 보류.

### 구현 범위

> 수정 파일 8개 → **2 Sprint 분할** (수정 파일 8+이면 분할 룰).

#### Sprint 1 — 핵심 회로 구축 (5 파일)

- [ ] **신규** `commands/audit-self.md` — 메인 커맨드. Phase 1~3 (스캔→security-engineer→evaluator). `--jury` 옵션 stub (jury 페르소나는 P1-1 확장에서 구현, v5.22.0은 placeholder만).
- [ ] **신규** `docs/security-rules.md` — 5 카테고리 × 6~10 룰 = 30~50 룰셋. 각 룰: `[Rule ID][카테고리][심각도][검증조건][정상예시][위험예시][완화전략]`. ECC AgentShield 102룰 중 정적 분석으로 검증 가능한 부분만 선별 (예상 적용 가능 ~30%).
- [ ] **수정** `agents/security-engineer.md` — 자기 코드 감사 모드 추가 (frontmatter 또는 description 본문). 검사 대상에서 자기 정의(`agents/security-engineer.md`) 명시적 제외 (메타-루프 가드).
- [ ] **수정** `hooks/session-start.sh` — NOVA_PROFILE별 커맨드 카탈로그에 `/nova:audit-self` 1줄 추가. lean ≤1200자 제약 유지.
- [ ] **수정** `tests/test-scripts.sh` — EXPECTED_COMMANDS 배열에 `audit-self` 추가. 자동 검증.

#### Sprint 2 — 회귀·동기화·관찰성 (3~4 파일)

- [ ] **신규** `tests/test-audit-self.sh` — 회귀 가드. 룰셋 스키마(필수 필드 7개 존재) 검증 + Risk Map 테이블 헤더 정합 검증 + 5 카테고리 누락 감지.
- [ ] **수정** `docs/nova-rules.md` — §3 품질 또는 §5 환경안전에 `/nova:audit-self` 1줄 + 메타-루프 가드 원칙 1줄 추가.
- [ ] **수정** `commands/review.md` 크로스 레퍼런스 — 보안 스코프 시 audit-self 우선 안내.
- [ ] **수정** `commands/next.md` 워크플로우 — 릴리스 직전 audit-self 권장 추가.
- [ ] **(선택)** `hooks/record-event.sh` 호출 통합 — audit-self 종료 시 `audit_self_verdict` 이벤트 기록 (P1-3 신뢰도 점수 연동 씨앗).

#### 명시적 제외 (이번 minor에서 구현 안 함)

- ❌ `release.sh` 자동 차단 게이트 — risk-explorer R6 지적. False Positive 안정화 6개월 운영 후 별도 patch에서 추가.
- ❌ Red/Blue/Auditor 3에이전트 병렬 — 방안 C 요소, v5.23.0 이후 분기.
- ❌ JSON 출력 / 머신 파싱 / PreToolUse 자동 차단 — 동일.
- ❌ 룰셋 동적 마이그레이션 자동화 — 첫 릴리스는 수동 갱신 절차 명시만.

### 검증 기준

> Verification Hooks 섹션에서 구체화. 핵심 발췌:

- C1: `commands/audit-self.md` 존재 + frontmatter 유효 + Phase 1~3 섹션 헤더 일치
- C2: `docs/security-rules.md` 룰 30개 이상 + 5 카테고리 모두 커버 + 룰당 7 필수 필드 존재
- C3: `bash tests/test-scripts.sh` 169+개 → 169+신규 모두 PASS
- C4: 메타-루프 가드 동작 — `commands/audit-self.md` 본문 `exclusion_list` 컨텍스트에 `agents/security-engineer.md` 라인 단위로 존재 + Phase 1 스캔 단계가 exclusion_list 적용 텍스트 명시. 즉 텍스트 매칭이 아닌 **구조적 매칭** (exclusion_list 섹션 헤더 → 라인 항목 형태)
- C5: 메인 사실 검증 회로 — security-engineer Critical/Warning 보고 → evaluator 직렬 검증 → 메인이 보고된 `{파일}:{라인}` 각 항목에 대해 `grep -n {Rule 패턴} {파일}` 1회 실측. 매칭 실패 시 Evaluator 환각 경보 + 사용자에게 명시 보고. 일치 시 사용자 보고로 진행 (메모리 `feedback_evaluator_hallucination` 원칙 그대로)

---

## Sprints (스프린트 분할)

### Sprint 1 — 핵심 회로 구축

**목표**: `/nova:audit-self` 가 동작하는 최소 회로를 만들고 30~50 룰셋 초안을 외부화한다.

**Sprint 0 (Prerequisite) — Sprint 1 착수 전 필수**:

> 이 단계가 완료되지 않으면 Sprint 1.2 Done 조건(룰 30개 이상)이 차단될 수 있다. 별도 0.5일 분량.

| # | Done 조건 | 검증 방법 |
|---|-----------|----------|
| 0.1 | ECC AgentShield 102 룰을 3 분류로 분류한 `Source Mapping` 표 작성 — (a) Nova 정적 분석으로 검증 가능, (b) 동적 분석 필요 (Known Gap), (c) Nova 정체성 충돌 (채택 제외) | docs/security-rules.md 헤더에 `## Source Mapping` 섹션 + 102 룰 매핑 표 존재 |
| 0.2 | (a) 분류 흡수 결과로 Nova 룰 ≥ 30 보장 | (실제 룰 카운트로 검증) `grep -c "^### Rule " docs/security-rules.md` ≥ 30 |
| 0.3 | docs/proposals/2026-04-29-ecc-adversarial-gap.md §P1-1 갱신 — 룰 분류 결과 추적 가능하도록 본 분류 결과 링크 추가 | proposal 본문 grep "audit-self" 갱신 1줄 추가 |

**Sprint 1 Contract** (Sprint 0 PASS 후 진입):

| # | Done 조건 | 검증 방법 |
|---|-----------|----------|
| 1.1 | `commands/audit-self.md` 신규 생성, frontmatter `description:` 포함 + Phase 1 스캔 대상 파일 목록(scan_targets) + 명시적 제외 목록(exclusion_list) 정의. **두 섹션 모두 마크다운 H2 헤더 (`## scan_targets` / `## exclusion_list`) 로 작성하여 V4 awk 패턴과 정합** | `grep -q "^description:" commands/audit-self.md` AND `grep -q "^## exclusion_list$" commands/audit-self.md` AND `grep -q "^## scan_targets$" commands/audit-self.md` |
| 1.2 | `docs/security-rules.md` 신규 생성, 5 카테고리(plugin/hooks/agents/skills/commands) 섹션 모두 존재 + 총 룰 30개 이상 | `grep -c "^### Rule " docs/security-rules.md` ≥ 30 |
| 1.3 | `agents/security-engineer.md` 본문에 "자기 코드 감사 모드" 섹션 + 메타-루프 가드 명시 + commands/audit-self.md exclusion_list에 `agents/security-engineer.md` 명시 (텍스트 매칭으로는 부족 — 두 파일 동시 검증) | `grep -q "메타-루프\|self-audit" agents/security-engineer.md` AND `grep -q "agents/security-engineer.md" commands/audit-self.md` (exclusion_list 컨텍스트 내) |
| 1.4 | `hooks/session-start.sh` lean profile에 `/nova:audit-self` 1줄 추가, **lean ≤1200자(soft target) AND hard ≤2500자 양쪽 검증** | (1) `NOVA_PROFILE=lean bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c` ≤ 1200, (2) standard / strict 프로파일 모두 `wc -c` ≤ 2500 |
| 1.5 | `tests/test-scripts.sh` EXPECTED_COMMANDS에 `audit-self` 추가, 전체 테스트 PASS | `bash tests/test-scripts.sh` 종료 코드 0 |

**예상 변경 라인 수**: ~600~750줄 추가 (룰셋 본문이 가장 큼).

### Sprint 2 — 회귀·동기화·관찰성

**목표**: 룰셋 자체의 무결성·문서 동기화·이벤트 기록을 갖춰 v5.22.0 릴리스 가능 상태로 확정한다.

**Sprint Contract**:

| # | Done 조건 | 검증 방법 |
|---|-----------|----------|
| 2.1 | `tests/test-audit-self.sh` 신규, 룰셋 스키마 검증(필수 필드 7개) + 5 카테고리 누락 감지 | `bash tests/test-audit-self.sh` 종료 코드 0 |
| 2.2 | `docs/nova-rules.md` §품질 또는 §환경안전에 audit-self 1줄 + 메타-루프 가드 원칙 1줄 | `grep -c "audit-self" docs/nova-rules.md` ≥ 1 |
| 2.3 | `commands/review.md` 보안 스코프 → audit-self 우선 안내 추가 | `grep -q "audit-self" commands/review.md` |
| 2.4 | `commands/next.md` 워크플로우 추천 경로에 audit-self 추가 | `grep -q "audit-self" commands/next.md` |
| 2.5 | (선택) `hooks/record-event.sh` audit_self_verdict 이벤트 기록 hook 추가 | `grep -q "audit_self_verdict" hooks/record-event.sh` |
| 2.6 | commands/audit-self.md 본문에 "결과 해석 가이드" 섹션 + Critical 발견 시 권장 행동 표기 (R11 완화) | `grep -q "결과 해석 가이드\|Critical 발견 시" commands/audit-self.md` |
| 2.7 | commands/audit-self.md 토큰 비용 추정 + `--category` 옵션 정의 (R9 완화) | `grep -q -- "--category" commands/audit-self.md` AND `grep -q "토큰\|tokens" commands/audit-self.md` |
| 2.8 | docs/security-rules.md 헤더에 `version:` + Known Gap 섹션 (공급망 무결성 R10 명시) | `grep -q "^version:" docs/security-rules.md` AND `grep -q "Known Gap\|공급망" docs/security-rules.md` |
| 2.9 | Evaluator (별도 spawn) PASS — Sprint 0 + Sprint 1 + Sprint 2 모든 Done 조건 검증 + Verification Hooks V1~V15 검증 | Evaluator verdict = PASS |

**예상 변경 라인 수**: ~150~250줄 추가.

### 릴리스 절차 (Sprint 2 종료 후)

```
1. /nova:review --fast  (Always-On 4)
2. bash tests/test-scripts.sh  (회귀 PASS)
3. Evaluator 독립 서브에이전트 PASS
4. NOVA-STATE.md 갱신 (Phase=released)
5. bash scripts/release.sh minor "feat(v5.22.0): /nova:audit-self 신규 — Nova 자기 보안 진단"
```

---

## Risk Map

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| **R1 메타-루프 자가 합리화** — security-engineer가 자기 정의(agents/security-engineer.md) 검사 시 자가 통과 편향 | H | H | (1) 검사 대상에서 `agents/security-engineer.md` 명시 제외, (2) 다른 4 에이전트(architect/devops/qa/refiner) 정의만 검사, (3) security-engineer 자기 정의는 향후 --jury 다관점 (Red/Blue/Auditor) 위임으로 v5.23.0 분리, (4) commands/audit-self.md에 "검사자/검사 대상 분리 원칙 깨지면 결과 무효" 메타 노트 명시 |
| **R2 False Negative — 정적 분석 한계** | H | H | (1) 초기 30~50 룰은 보수적으로 의심 항목 모두 WARNING로 보고, (2) ECC 102 룰을 명시 매핑 후 Nova 미적용분을 `## Known Gaps` 섹션 문서화, (3) "audit-self는 정적 분석만 — 동적 권한 상승·세션 오염·MCP 네트워크는 e2e CI로 별도 검증" 명시, (4) `--mode static` (현재) vs `--mode dynamic` (향후 분기) 어휘만 도입 |
| **R3 False Positive 폭발** | M | M | (1) 첫 릴리스 직후 Nova 자신에 audit-self 실행 → False Positive rate 측정, (2) FP rate >10% 시 룰 재정의, (3) 각 룰에 `정상 케이스 예시` + `위험 케이스 예시` 강제 필드, (4) Critical/Warning/Info 3단 분류 — Critical만 차단 시그널, 나머지 정보성 |
| **R4 룰셋 자기 검증 부재** | M | M | (1) Sprint 2의 `tests/test-audit-self.sh` 가 룰 syntax + 중복 + 5 카테고리 커버리지 검사, (2) release.sh 게이트로 룰셋 무결성 검증 (수동·차단 X), (3) 룰셋 변경 시 `docs/security-rules.md` 헤더에 `version:` 필드 강제 |
| **R5 Evaluator 환각** | M | H | (1) audit-self PASS = "배포 차단 해제 조건 X / 수동 점검 체크리스트 시그널 O" 명시, (2) Critical 발견 시 "재현 가능성" 필드 강제, (3) 메인이 evaluator 결과 1회 grep 검증 후 사용자 보고 (메모리 원칙 그대로), (4) `--jury` 도입은 v5.23.0 분기 — v5.22.0은 메인 검증으로 충분 |
| **R6 release.sh 통합 함정** | M | M | (1) v5.22.0에서는 release.sh **자동 호출 도입 X** — 수동 호출만, (2) audit-self 6개월 운영 후 False Positive 안정화 시 patch에서 자동 호출 추가, (3) 도입 시 Critical만 차단 + `--skip-audit` 사용 시 NOVA-STATE.md "Skip Reason" 필수 기록, (4) `--emergency` 와 audit-skip 분리 |
| **R7 룰셋 유지보수 — 스키마 변경 대응** | M | M | (1) `docs/security-rules.md` 헤더에 호환 Nova 버전 명시, (2) hooks 스키마 변경 시 영향받는 룰을 release notes에 의무 기재, (3) 룰셋 changelog 별도 파일 생성은 v5.23.0+ 검토 |
| **R8 session-start lean 1200자 압박** | L | L | 신규 1줄 12자 추가만 — 영향 미미. Sprint 1.4 회귀가 lean ≤1200(soft) + hard ≤2500 양쪽 검증 |
| **R9 audit-self 실행 토큰 압박** | M | M | (1) Phase 1 스캔은 Glob으로 파일 목록만 로드 후 룰별 조건부 Read (필요 룰 매칭 시에만), (2) `--category {plugin\|hooks\|agents\|skills\|commands}` 옵션으로 부분 실행 지원, (3) Sprint 1 설계 시 1회 실행 토큰 비용 추정 + NOVA-STATE.md 기록, (4) 메모리 `feedback_session_start_lightweight` 원칙 적용 — 검사 대상 파일 1개당 평균 토큰 측정 후 룰셋 50개 × 6900줄 ≈ ~30K 토큰 추정치 갱신 |
| **R10 룰 파일 공급망 무결성** | M | M | (1) `docs/security-rules.md` 변경 시 release.sh가 git diff 라인 카운트 + 사용자 확인 프롬프트 (옵션, v5.23.0 검토), (2) v5.22.0은 Known Gap으로 명시 선언 — "OSS 기여자가 룰 파일을 변조해 검사 결과를 조작할 수 있는 공급망 리스크는 v5.22.0 범위 외", (3) 룰 파일 헤더에 `version:` + 마지막 검토 commit hash 기록 |
| **R11 인시던트 대응 흐름** | M | H | (1) commands/audit-self.md 출력에 Critical 발견 시 권장 행동 강제 표기 — "즉시 commit 차단 + 사용자 검토 후 수동 PASS 또는 fix", (2) NOVA-STATE.md "Known Risks" 자동 행 추가 (Critical 1건당 1행), (3) 본 v5.22.0은 자동 차단 도입 X — 정보성 권고만, (4) 사용자 학습 자료로 commands/audit-self.md 본문 하단에 "결과 해석 가이드" 섹션 의무 |

---

## Unknowns

> Phase C(Critic)가 본 항목을 검증한다. Refiner 단계에서 해소되지 않으면 ⚠️ 마커로 사용자 검토 위임.

- **U1 룰 30~50개 도출 소스 비율** — ECC AgentShield 102 룰을 직접 매핑 가능 비율이 ~30% 추정이지만 실측 미진행. **해소 절차**: Sprint 1 시작 전 ECC 룰 명시적 분류 (Nova 적용 가능 / 정적 분석으로 검증 불가 / 정체성 충돌). 결과를 `docs/security-rules.md` 헤더 `Source Mapping` 섹션에 기록.
- **U2 --jury Red/Blue/Auditor 인터페이스 정합성** — 현재 `skills/jury/SKILL.md` 페르소나는 "Correctness/Design/User"(코드 모드) 또는 "architect/security/qa"(Plan 모드). audit-self의 Red/Blue/Auditor는 신규 페르소나 — jury 내부 페르소나 추가 vs 별도 스킬 vs 인라인 페르소나 미결. **해소**: v5.22.0은 `--jury` placeholder만 (실제 동작은 v5.23.0). placeholder 어휘만 정의.
- **U3 메인 사실 검증의 무한 귀환** — "메인이 evaluator 결과 검증 → 메인도 LLM이라 환각 → 또 다른 메타 감사자 필요" 무한 귀환. **해소**: 본 Plan은 "메인 검증 = 일관성 체크(grep으로 파일 존재·라인 번호 일치)만 수행, 최종 보안 판정은 사용자 수동 결정에 위임"으로 현실화.
- **U4 security-engineer 자기 검사 시 제약 자기참조 테스트 가능성** — security-engineer가 refiner.md 도구 제약을 검사 가능하지만 자기 정의 검사는 논리 순환. **해소**: R1 완화의 검사 대상 제외로 회피.
- **U5 audit-self 결과 Evaluator 환각 가정과 메모리 모순** — 메모리 `feedback_evaluator_hallucination`이 존재하면 audit-self도 불신 대상. **해소**: 본 Plan은 "audit-self는 환각 가능성을 가정하고 설계 — 모든 Critical에 재현 가능성 필드 + 사용자 최종 판정"을 채택.

---

## Verification Hooks

> Sprint Contract 씨앗 — `/nova:design` 단계에서 구체화한다.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|-----------|-----------|----------|
| V1 | commands/audit-self.md 존재 + frontmatter 유효 | `test -f commands/audit-self.md && head -20 commands/audit-self.md \| grep -q "^description:"` | Critical |
| V2 | docs/security-rules.md 5 카테고리 모두 존재 | `for c in plugin hooks agents skills commands; do grep -q "## Category: $c" docs/security-rules.md \|\| exit 1; done` | Critical |
| V3 | docs/security-rules.md 룰 ≥30 개 | `grep -c "^### Rule " docs/security-rules.md` 가 ≥ 30 | Critical |
| V4 | 메타-루프 가드 — exclusion_list 구조적 매칭 | `awk '/^## exclusion_list/,/^---$/' commands/audit-self.md \| grep -q "agents/security-engineer.md"` (exclusion_list H2 헤더 ~ 다음 `---` 구분선까지 컨텍스트 내) | Critical |
| V5 | EXPECTED_COMMANDS audit-self 동기화 | `grep -A 5 "EXPECTED_COMMANDS=(" tests/test-scripts.sh \| grep -q audit-self` (배열 컨텍스트 내 매칭) | Critical |
| V6 | session-start **lean ≤1200(soft) AND hard ≤2500 양쪽** 검증 | `lean=$(NOVA_PROFILE=lean bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); std=$(NOVA_PROFILE=standard bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); strict=$(NOVA_PROFILE=strict bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); [ $lean -le 1200 ] && [ $std -le 2500 ] && [ $strict -le 2500 ]` | Critical |
| V7 | 전체 테스트 회귀 0 | `bash tests/test-scripts.sh` exit 0 | Critical |
| V8 | tests/test-audit-self.sh 신규 회귀 가드 동작 | `bash tests/test-audit-self.sh` exit 0 | Critical |
| V9 | docs/nova-rules.md audit-self 1줄 + 메타-루프 가드 1줄 | `grep -c "audit-self\|메타-루프" docs/nova-rules.md` ≥ 2 | High |
| V10 | commands/review.md / next.md 크로스 레퍼런스 | `for f in commands/review.md commands/next.md; do grep -q "audit-self" $f \|\| exit 1; done` | High |
| V11 | Evaluator 독립 서브에이전트 PASS + 메인 사실 검증 회로 동작 | (a) 별도 spawn evaluator verdict = PASS, (b) Critical/Warning 보고된 항목 각각에 `grep -n {Rule_pattern} {file}` 1회 실측 후 매칭 성공률 기록. 매칭 실패 1건 이상 시 V11 FAIL — Evaluator 환각 경보 | Critical |
| V12 | False Positive 측정 — 분모/분자 명시 | **분모**: audit-self 1회 실행에서 CRITICAL/WARNING 등급으로 보고된 룰 매칭 결과 수. **분자**: 분모 중 사용자가 "실제 문제 아님"으로 검토 판정한 수. **FP rate** = 분자/분모. 첫 릴리스 직후 수동 측정 + NOVA-STATE.md `Last Activity`에 `FP rate {percent}% (분자 N / 분모 M)` 1줄 기록. 목표 ≤10% (단 첫 측정은 베이스라인이므로 차단 X) | Nice-to-have |
| V13 | (Sprint 2 선택) hooks/record-event.sh audit_self_verdict 이벤트 기록 | `grep -q "audit_self_verdict" hooks/record-event.sh` | Nice-to-have |
| V14 | 토큰 압박 추정치 측정 (R9 완화) | `commands/audit-self.md` 본문에 1회 실행 평균 토큰 비용 추정치 명시 (예: "~30K 토큰 / 6900줄 검사 대상") + `--category` 옵션 정의 | High |
| V15 | 인시던트 대응 가이드 (R11) | `commands/audit-self.md` 본문 하단에 "결과 해석 가이드" 섹션 + Critical 발견 시 권장 행동 표기 | High |
