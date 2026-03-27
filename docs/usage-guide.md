# AXIS Kit 사용법 가이드

> 처음부터 제대로. 매번 더 빠르게.
>
> 9개 커맨드 + 5개 전문가 에이전트 + 3개 스크립트의 상세 사용법

---

## 목차

1. [시작하기](#시작하기)
2. [설치 모드](#설치-모드)
3. [커맨드 상세](#커맨드-상세)
4. [전문가 에이전트](#전문가-에이전트)
5. [CLI 스크립트 상세](#cli-스크립트-상세)
6. [공통 유틸리티](#공통-유틸리티)
7. [버전 관리](#버전-관리)
8. [전체 워크플로우 예시](#전체-워크플로우-예시)
9. [팁과 베스트 프랙티스](#팁과-베스트-프랙티스)

---

## 시작하기

### 설치

```bash
# 전체 설치 (커맨드 9개 + 에이전트 5개 + 스크립트 + 템플릿 + 가이드)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 최소 설치 (핵심 커맨드 3개만)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal

# 업데이트 (커맨드+스크립트+에이전트만 갱신, 템플릿/가이드 보존)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

### 초기 설정

```bash
# 신규 프로젝트
bash scripts/init.sh my-project "Next.js + TypeScript"

# 기존 프로젝트 (CLAUDE.md 비파괴적 도입)
bash scripts/init.sh --adopt my-project "React + TypeScript"
```

### API 키 설정

교차검증(`/xv` Mode A)과 갭 체크(`/gap`) CLI를 사용하려면 AI API 키가 필요합니다:

```bash
cat > .env << 'EOF'
ANTHROPIC_API_KEY="sk-ant-..."
OPENAI_API_KEY="sk-..."
GEMINI_API_KEY="AI..."
EOF
```

> **API 키 없이도 교차검증 가능!** `/xv`는 API 키 없이 에이전트 모드(Mode B)로 자동 전환됩니다.
> 슬래시 커맨드(`/plan`, `/design`, `/review` 등)는 API 키 없이도 동작합니다.

---

## 설치 모드

`install.sh`는 3가지 모드를 지원합니다:

### Full 모드 (기본)

모든 구성 요소를 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash
```

**설치되는 파일:**

| 구분 | 수량 | 내용 |
|------|------|------|
| 커맨드 | 9개 | `.claude/commands/*.md` |
| 에이전트 | 5개 | `.claude/agents/*.md` |
| 스크립트 | 5개 | `scripts/*.sh`, `scripts/lib/common.sh`, `scripts/.axis-version` |
| 템플릿 | 5개 | `docs/templates/*.md` |
| 가이드 | 3개 | `docs/*.md` |

### Minimal 모드 (`--minimal`)

빠르게 시작하고 싶을 때. 핵심 커맨드 3개와 기본 스크립트만 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal
```

**설치되는 것:**
- 커맨드 3개: `/next`, `/plan`, `/review`
- 스크립트: `init.sh`, `lib/common.sh`, `.axis-version`
- 에이전트, 템플릿, 가이드: 설치하지 않음

> 나중에 전체 설치(`bash install.sh`)로 업그레이드할 수 있습니다.

### Update 모드 (`--update`)

이미 설치된 AXIS Kit을 최신 버전으로 갱신합니다. 사용자가 커스터마이징한 템플릿과 가이드 문서는 건드리지 않습니다.

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

**갱신 대상:** 커맨드 9개, 에이전트 5개, 스크립트 5개
**보존 대상:** 템플릿, 가이드 문서 (사용자 커스터마이징 보호)

### Uninstall (`--uninstall`)

AXIS Kit이 설치한 파일만 제거합니다. 사용자 문서(`docs/plans/` 등)와 설정(`CLAUDE.md`, `.env`)은 보존됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --uninstall
```

---

## 커맨드 상세

### `/next` — 다음 할 일 추천

프로젝트 상태를 자동 진단하고, AXIS 워크플로우에서 다음에 실행할 커맨드를 추천합니다.

```bash
/next
```

**동작 원리:**
- `docs/plans/`, `docs/designs/`, `docs/verifications/` 스캔
- `git log`, `git status` 확인
- 워크플로우 규칙에 따라 추천:

| 상태 | 추천 |
|------|------|
| Plan 없음 | `/plan` |
| Plan 있고 Design 없음 | `/design` |
| Design 있고 코드 커밋 있지만 검증 없음 | `/gap` |
| 검증 완료 | `/review` |
| 리뷰 완료 | `/propose` |
| 모두 완료 | "다음 기능 시작 준비 완료" |

**출력 예시:**
```
추천: /gap docs/designs/auth.md src/

프로젝트 진단:
  Plans:         2개 (최근: auth.md)
  Designs:       1개
  Verifications: 0개
  최근 커밋:     5개 (마지막: feat: 인증 모듈 구현)

이유: 설계 문서가 있고 최근 구현 커밋이 있지만 검증이 없습니다.

이후 흐름: /gap → /review → /propose
```

---

### `/init` — 프로젝트 초기 설정

AXIS Kit 디렉토리 구조와 CLAUDE.md를 자동 생성합니다.

```bash
/init my-project            # 기본 (프로젝트명만)
/init                       # 대화형 — 정보를 물어봄
```

**생성되는 것:**
- `CLAUDE.md` — 프로젝트 맥락 + AXIS 커맨드 + 컨벤션
- `docs/plans/`, `docs/designs/`, `docs/decisions/`, `docs/verifications/`
- `.gitignore` 업데이트

**기존 프로젝트에 도입할 때:**
```bash
/init --adopt my-project
```
→ 기존 CLAUDE.md를 수정하지 않고, 끝에 AXIS 섹션만 추가합니다.

---

### `/plan 기능명` — CPS Plan 작성

CPS(Context → Problem → Solution) 구조로 기능 계획서를 작성합니다.

```bash
/plan 사용자 인증
/plan 아파트 비교 기능
/plan 결제 시스템 도입
```

**포함 내용:**
- **Context**: 왜 필요한가? 현재 상태
- **Problem**: 핵심 문제 + MECE 분해 (겹침 없이, 빠짐 없이)
- **Solution**: 선택한 방안, 대안 비교, 구현 범위, 검증 기준

**산출물:** `docs/plans/{slug}.md`

> Plan은 "무엇을, 왜" — Design은 "어떻게"

**예시:** [examples/sample-plan.md](../examples/sample-plan.md)

---

### `/xv "질문"` — 멀티 AI 교차검증

3개 이상의 독립 관점에서 동시 질의하고 합의율을 자동 산출합니다.

```bash
/xv "Next.js에서 서버 액션 vs API 라우트, 기본으로 어떤 걸 쓸까?"
/xv "PostgreSQL vs MongoDB, 부동산 플랫폼에 적합한 건?"
/xv --agent "API 키 없이 에이전트로 교차검증"
```

#### Mode A: API 교차검증

`.env`에 API 키가 1개 이상 있으면 자동 선택됩니다. Claude + GPT + Gemini 3개 AI에게 동시 질의합니다.

```bash
/xv "기술적 질문"           # API 키가 있으면 자동으로 Mode A
```

#### Mode B: 에이전트 교차검증

API 키 없이도 교차검증을 수행합니다. 3개 병렬 에이전트를 서로 다른 전문가 관점(아키텍트, 시니어 개발자, QA/보안)으로 **동시에** 실행합니다.

```bash
/xv --agent "질문"          # 명시적으로 에이전트 모드 사용
/xv "질문"                  # API 키가 없으면 자동으로 Mode B
```

**모드 자동 판별:**

| 조건 | 선택 모드 |
|------|-----------|
| `--agent` 옵션 사용 | Mode B (에이전트) |
| `.env`에 API 키 없음 | Mode B (에이전트) |
| `.env`에 API 키 있음 | Mode A (API) |

**합의 프로토콜 (양쪽 모드 공통):**

| 합의율 | 판정 | 행동 |
|--------|------|------|
| 90%+ | AUTO APPROVE | 자동 채택 |
| 70~89% | HUMAN REVIEW | AI가 차이점 요약, 사람이 판단 |
| 70% 미만 | REDEFINE | 질문 재정의 필요 |

**산출물:** `docs/verifications/{date}-{slug}.md`

**CLI에서 직접 실행도 가능 (Mode A만):**
```bash
./scripts/x-verify.sh "질문"
./scripts/x-verify.sh --model opus "중요한 질문"    # Claude 모델 선택
./scripts/x-verify.sh --no-save "빠른 질문"         # 결과 저장 안 함
./scripts/x-verify.sh -f question.txt               # 파일에서 질문 읽기
```

**예시:** [examples/sample-xv-result.md](../examples/sample-xv-result.md)

---

### `/design 기능명` — CPS Design 작성

Plan을 기반으로 기술 설계 상세를 작성합니다.

```bash
/design 사용자 인증     # docs/plans/에서 관련 Plan을 자동 참조
```

**포함 내용:**
- **Context**: Plan 요약, 설계 원칙
- **Problem**: 기술적 과제, 기존 시스템 접점
- **Solution**: 아키텍처, 데이터 모델, API 설계, 에러 처리
- **검증 계약**: `/gap`에서 검증할 테스트 가능한 성공 조건 목록

**산출물:** `docs/designs/{slug}.md`

> 검증 계약은 Generator-Evaluator 패턴의 핵심입니다.
> 구현자(AI)와 검증자(AI/사람)가 "이것이 성공 조건"이라고 사전에 합의합니다.

**예시:** [examples/sample-design.md](../examples/sample-design.md)

---

### `/gap 설계.md 코드/` — 역방향 검증

설계 문서와 실제 구현 코드를 비교하여 갭을 자동 탐지합니다.

```bash
/gap docs/designs/auth.md src/
/gap docs/designs/auth.md         # 코드 경로 자동 추론
/gap                              # 최근 설계 문서 자동 선택
```

**판정 기준:**

| 매칭률 | 판정 | 행동 |
|--------|------|------|
| 90%+ | PASS | 설계-구현 일치 |
| 70~89% | REVIEW NEEDED | 미구현 항목 정리 → 보완 |
| 70% 미만 | SIGNIFICANT GAPS | 설계 재검토 또는 대규모 보완 |

**CLI에서 직접 실행도 가능:**
```bash
./scripts/gap-check.sh docs/designs/feature.md src/
```

**핵심 원칙:** Generator-Evaluator 분리 — 구현한 AI와 검증하는 AI가 독립적으로 동작하여 자기 평가 편향을 제거합니다.

---

### `/review 코드` — 코드 리뷰

단순성 원칙(Rob Pike)과 AXIS 구조 원칙으로 코드를 진단합니다.

```bash
/review src/auth/
/review src/components/CompareTable.tsx
```

**평가 기준:**
- **Over_Abstraction**: 1-2회 사용을 위한 불필요한 레이어?
- **Control_Flow_Bloat**: 데이터 구조로 제거 가능한 조건문?
- **Side_Effect_Scatter**: 부수효과가 여러 계층에 분산?
- **Premature_Optimization**: 측정 없이 성능 가정?
- **Missing_Lookup**: 런타임 계산을 정적 Map으로 치환 가능?
- **Design_Drift**: 설계 문서와 구현의 괴리? (AXIS 고유)

**출력 형식:**
1. Rule Violation Report — 기준별 True/False + 사유
2. Complexity Analysis — 문제 함수 + 간소화 방향
3. Refactoring Suggestion — Before/After 코드
4. AXIS Alignment — 설계 문서와의 정합성

---

### `/propose 패턴` — 규칙 제안

반복되는 코드/프로세스 패턴을 규칙으로 승격시키는 제안서를 작성합니다.

```bash
/propose 에러 핸들링 패턴
/propose API 응답 구조 통일
```

**Adaptive 사이클:**
```
감지(Detect) → 제안(/propose) → 승인(사람) → 적용 → 검증
```

**산출물:** `docs/proposals/{slug}.md`

> AI는 제안만 합니다. 승인은 반드시 사람이 합니다.
> 패턴 3회 이상 반복 시 규칙 제안을 고려하세요.

---

### `/metrics` — AXIS 도입 수준 측정

프로젝트의 AXIS 4대 Pillar별 점수를 자동 산출합니다.

```bash
/metrics
```

**측정 항목 (17점 만점):**

| Pillar | 항목 수 | 측정 내용 |
|--------|---------|----------|
| Structured | 5점 | CLAUDE.md, Plan/Design 문서, 린터, 커밋 컨벤션 |
| Idempotent | 4점 | 템플릿, Tech Stack, 컨텍스트 체인, 의사결정 기록 |
| X-Verification | 4점 | 교차검증 도구/결과, 갭 체크 도구/결과 |
| Adaptive | 4점 | /propose, 규칙 변경 이력, 제안 템플릿/기록 |

**등급:**

| 등급 | 점수 |
|------|------|
| Level 5 | 17점 — AXIS 완전 적용 |
| Level 4 | 14~16점 — 높은 수준 |
| Level 3 | 10~13점 — 중간 |
| Level 2 | 6~9점 — 초기 |
| Level 1 | 0~5점 — 시작 단계 |

---

## 전문가 에이전트

AXIS Kit은 5종의 전문가 에이전트를 제공합니다. `.claude/agents/` 디렉토리에 위치하며, Claude Code의 에이전트 기능으로 자동 활용됩니다.

### 에이전트 개요

| 에이전트 | 파일 | 핵심 역할 | 활용 시점 |
|----------|------|----------|----------|
| Architect | `architect.md` | 시스템 구조 설계, 기술 선택, 확장성 검토 | 아키텍처 결정, 모듈 분리, ADR 작성 |
| Senior Dev | `senior-dev.md` | 코드 품질, 리팩토링, 최소 변경 구현 | 코드 리뷰, 기술 부채 해소, 디자인 패턴 적용 |
| QA Engineer | `qa-engineer.md` | 테스트 전략, 엣지 케이스, 품질 검증 | 테스트 시나리오 설계, 버그 재현, 경계값 분석 |
| Security Engineer | `security-engineer.md` | 보안 취약점, 위협 모델링, 인증/인가 검토 | 보안 감사, 시크릿 노출 탐지, OWASP 기반 분석 |
| DevOps Engineer | `devops-engineer.md` | CI/CD, 인프라, 배포 전략, 모니터링 | Dockerfile, GitHub Actions, IaC 검토/작성 |

### 에이전트 상세

#### Architect (아키텍트)

시스템 아키텍처 전문가. 확장성, 유지보수성, 모듈 간 결합도를 최우선으로 판단합니다.

**판단 우선순위:** 단순성 → 확장성 → 유지보수성 → 성능
**도구:** Read, Glob, Grep, Agent, WebSearch

- 설계 판단 시 최소 2개 대안을 비교하고 트레이드오프를 명시
- 코드를 직접 수정하지 않음 — 구조와 방향만 제시
- 불확실한 기술 선택은 `/xv` 교차검증을 제안

#### Senior Dev (시니어 개발자)

10년차 시니어 개발자. 코드 품질, DX(개발자 경험), 최소 변경 원칙을 최우선으로 판단합니다.

**판단 우선순위:** 정확성 → 가독성 → 최소 변경 → 테스트 용이성
**도구:** Read, Glob, Grep, Edit, Write, Bash, Agent

- 구현 전 영향 범위를 먼저 분석하고 계획을 제시
- 3개 이상 파일 수정 시 계획 승인 후 진행
- 불필요한 추상화, 과도한 설정, 미래 대비 코드를 만들지 않음

#### QA Engineer (QA 엔지니어)

QA 엔지니어. 테스트 커버리지, 엣지 케이스, 실패 시나리오를 최우선으로 판단합니다.

**판단 우선순위:** 재현 가능성 → 커버리지 → 자동화 가능성 → 유지보수성
**도구:** Read, Glob, Grep, Bash

- 정상 경로보다 실패 경로를 먼저 확인
- 입력 경계값(0, -1, 빈 문자열, null, 최대값)을 항상 검증
- 코드를 직접 수정하지 않음 — 테스트와 이슈 리포트만 작성

#### Security Engineer (보안 엔지니어)

보안 엔지니어. OWASP Top 10 기준으로 취약점을 식별하고, 최소 권한 원칙과 심층 방어를 적용합니다.

**판단 우선순위:** 악용 가능성 → 영향 범위 → 수정 용이성 → 심층 방어
**도구:** Read, Glob, Grep

- 분석 전 공격 표면(입력 경로, 인증 경계, 외부 API)을 먼저 매핑
- 시크릿 패턴(.env, API 키, 토큰, 비밀번호)을 항상 탐지
- 코드를 직접 수정하지 않음 — 취약점 리포트와 수정 가이드만 제공

#### DevOps Engineer (데브옵스 엔지니어)

DevOps 엔지니어. 배포 안정성, 관측성(Observability), 자동화를 최우선으로 판단합니다.

**판단 우선순위:** 롤백 가능성 → 재현 가능성 → 관측성 → 자동화
**도구:** Read, Glob, Grep, Edit, Write, Bash

- 인프라 변경 전 롤백 계획을 먼저 수립
- 시크릿은 환경변수 또는 시크릿 매니저로만 관리
- 클라우드 리소스 변경 전 반드시 사용자 확인

### 에이전트와 `/xv`의 관계

`/xv` 에이전트 모드(Mode B)에서는 Architect, Senior Dev, QA/Security 3개 관점을 병렬로 실행하여 교차검증합니다. 이는 전문가 에이전트의 핵심 활용 사례입니다.

---

## CLI 스크립트 상세

### `scripts/x-verify.sh` — 교차검증 CLI

터미널에서 직접 멀티 AI 교차검증을 실행합니다.

```bash
# 기본 사용
./scripts/x-verify.sh "기술적 질문"

# Claude 모델 선택
./scripts/x-verify.sh --model opus "중요한 아키텍처 판단"   # Opus (고품질)
./scripts/x-verify.sh --model sonnet "일반 질문"            # Sonnet (기본값)
./scripts/x-verify.sh --model haiku "빠른 질문"             # Haiku (빠름)

# 결과 저장 안 함
./scripts/x-verify.sh --no-save "일회성 질문"

# 파일에서 질문 읽기
./scripts/x-verify.sh -f question.txt

# 옵션 조합 (순서 무관)
./scripts/x-verify.sh --no-save --model opus "질문"
./scripts/x-verify.sh --model haiku --no-save "질문"
```

**필요 조건:**
- `.env`에 `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`
- `jq`, `curl` 설치
- 일부 API 키가 없어도 있는 것만으로 부분 실행 가능

**실행 흐름:**
1. Phase 1: 3개 AI에 질문 병렬 전송 (10~20초)
2. Phase 2: Gemini Flash로 합의율 자동 분석 (5초)
3. 결과 출력 + `docs/verifications/`에 자동 저장

---

### `scripts/gap-check.sh` — 갭 체크 CLI

설계 문서와 구현 코드의 갭을 AI로 분석합니다.

```bash
./scripts/gap-check.sh docs/designs/feature.md src/
./scripts/gap-check.sh docs/designs/auth.md apps/backend/
```

**필요 조건:**
- `.env`에 `GEMINI_API_KEY`
- `jq`, `curl` 설치

**출력 정보:**
- 분석 대상 파일 수 + 총 줄 수
- 매칭률 (0~100%)
- 구현 완료 항목
- 미구현 항목
- 설계 외 구현 항목
- 위험 사항

---

### `scripts/init.sh` — 초기화 CLI

프로젝트에 AXIS Kit 구조를 셋업합니다.

```bash
# 신규 프로젝트
bash scripts/init.sh my-app "Next.js + TypeScript" "한국어"

# 인자 생략 시 기본값 적용
bash scripts/init.sh my-app                  # 기술 스택: 미지정, 언어: 한국어

# 기존 프로젝트 (CLAUDE.md 비파괴적 도입)
bash scripts/init.sh --adopt my-app
```

**`--adopt` 모드:**
- 기존 CLAUDE.md가 있으면 교체하지 않고 끝에 AXIS 섹션만 추가
- 이미 AXIS 섹션이 있으면 중복 추가 방지
- 기존 디렉토리/파일을 건드리지 않음

---

## 공통 유틸리티

### `scripts/lib/common.sh`

모든 CLI 스크립트가 공유하는 유틸리티 라이브러리입니다. 스크립트에서 다음과 같이 불러옵니다:

```bash
source "$(dirname "$0")/lib/common.sh"
```

**제공 함수:**

| 함수 | 설명 | 사용 예시 |
|------|------|----------|
| `load_env` | `.env` 파일을 읽어 환경변수로 로드 | `load_env` 또는 `load_env .env.local` |
| `require_commands` | 필수 명령어 설치 여부 검사. 없으면 설치 안내와 함께 종료 | `require_commands jq curl` |
| `banner` | 구분선으로 감싼 제목 배너 출력 | `banner "AXIS Kit X-Verify"` |
| `divider` | 구분선만 출력 | `divider` |
| `check_update` | 버전 업데이트 체크 (하루 1회, 백그라운드) | `check_update` |

**색상 변수:** `BOLD`, `RED`, `GREEN`, `YELLOW`, `BLUE`, `MAGENTA`, `CYAN`, `NC` (No Color)

> 커스텀 스크립트를 만들 때 `common.sh`를 활용하면 일관된 UI와 에러 처리를 손쉽게 적용할 수 있습니다.

---

## 버전 관리

### `scripts/.axis-version`

AXIS Kit의 현재 설치 버전을 기록하는 파일입니다. 현재 버전: **1.1.0**

### 자동 업데이트 안내

`common.sh`의 `check_update()` 함수가 CLI 스크립트 실행 시 자동으로 버전을 체크합니다:

- **하루 1회**, 백그라운드에서 GitHub의 최신 버전과 비교
- 새 버전이 있으면 업데이트 명령어를 안내
- 스크립트 실행을 차단하지 않음 (비동기)
- 체크 실패 시 무시 (오프라인에서도 정상 동작)

**업데이트 안내 예시:**
```
  AXIS Kit 업데이트 가능 (1.0.0 → 1.1.0)
     curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

---

## 전체 워크플로우 예시

### 시나리오: "사용자 인증 기능 추가"

```
1. /next
   → "Plan 없음. /plan으로 시작하세요."

2. /plan 사용자 인증
   → docs/plans/user-auth.md 생성
   → Context: 로그인 기능 필요
   → Problem: MECE로 5개 영역 분해
   → Solution: JWT 이중 토큰 방식 채택

3. /xv "JWT vs 세션 기반 인증, SPA에 적합한 건?"
   → 3개 AI 동시 질의 (또는 에이전트 모드로 3개 관점 병렬 분석)
   → 합의율 95% → AUTO APPROVE → JWT 채택

4. /design 사용자 인증
   → docs/designs/user-auth.md 생성
   → 아키텍처, API 7개, 데이터 모델, 검증 계약 11개

5. [구현]
   → 설계에 따라 코드 작성

6. /gap docs/designs/user-auth.md src/
   → 매칭률 85% → REVIEW NEEDED
   → 미구현: "비밀번호 재설정 API"
   → 보완 후 재실행 → 매칭률 95% → PASS

7. /review src/auth/
   → Over_Abstraction: False
   → Design_Drift: False (Gap 통과)
   → Refactoring: TokenService 분리 제안

8. /propose JWT 토큰 갱신 패턴
   → 3번 이상 반복된 토큰 갱신 로직을 규칙으로 제안
   → 사람 승인 → CLAUDE.md에 반영

9. /metrics
   → Structured: 5/5, Idempotent: 4/4, X-Verify: 4/4, Adaptive: 3/4
   → 총점: 16/17 → Level 4
```

---

## 팁과 베스트 프랙티스

### 언제 `/xv`를 쓸까?
- 기술 스택 선택 (DB, 프레임워크, 라이브러리)
- 아키텍처 패턴 결정 (모노리스 vs 마이크로서비스)
- 설계 방향 갈림길 (REST vs GraphQL)
- **API 키 없을 때**: `--agent` 옵션으로 에이전트 모드 사용 — 프로젝트 코드를 직접 참조하여 더 구체적인 답변 가능
- **안 써도 되는 경우**: 단순 버그 수정, 스타일 결정, 이미 합의된 사항

### 전문가 에이전트 활용 시나리오
- **Architect**: "이 모듈을 어떻게 분리해야 할까?", "마이크로서비스로 전환할 시점인가?"
- **Senior Dev**: "이 코드를 리팩토링해줘", "기술 부채를 정리하고 싶어"
- **QA Engineer**: "이 기능의 테스트 시나리오를 설계해줘", "엣지 케이스를 찾아줘"
- **Security Engineer**: "이 API의 보안을 점검해줘", "시크릿 노출이 없는지 확인해줘"
- **DevOps Engineer**: "CI/CD 파이프라인을 구성해줘", "Dockerfile을 최적화해줘"

### `/gap`을 최대한 활용하려면
- `/design`에서 검증 계약을 상세하게 작성하세요
- "사용자가 X하면 Y가 되어야 한다" 형식이 가장 효과적
- 매칭률이 올라가는 추세면 계속, 정체되면 접근 전환

### `/propose`를 쓸 타이밍
- "이거 전에도 이렇게 했는데..." 싶을 때
- 같은 패턴이 3번 이상 반복될 때
- 코드 리뷰에서 같은 피드백이 반복될 때

### 경량 원칙 지키기
- 모든 커맨드를 매번 쓸 필요 없음
- 단순 버그 수정 → Plan/Design 스킵, 바로 구현 → /review
- 확신 있는 판단 → /xv 스킵
- **`/next`가 항상 적절한 다음 단계를 알려줍니다**

### 커스터마이징
- `.claude/commands/*.md`를 직접 수정하세요 — 그게 AXIS의 철학
- `.claude/agents/*.md`도 프로젝트 도메인에 맞게 수정 가능
- 프로젝트에 안 맞는 커맨드/에이전트는 삭제해도 됩니다
- 새 커맨드나 에이전트를 만들어도 됩니다 (같은 .md 형식으로)
- `scripts/lib/common.sh`를 활용하면 커스텀 스크립트도 일관된 UI로 만들 수 있습니다
