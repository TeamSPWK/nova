# AXIS Kit 사용법 가이드

> 9개 커맨드 + 3개 스크립트의 상세 사용법

---

## 목차

1. [시작하기](#시작하기)
2. [커맨드 상세](#커맨드-상세)
3. [CLI 스크립트 상세](#cli-스크립트-상세)
4. [전체 워크플로우 예시](#전체-워크플로우-예시)
5. [팁과 베스트 프랙티스](#팁과-베스트-프랙티스)

---

## 시작하기

### 설치

```bash
# 한 줄 설치
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 업데이트 (커맨드+스크립트만 갱신, 커스터마이징 보존)
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

교차검증(`/xv`)과 갭 체크(`/gap`) CLI를 사용하려면 3개 AI API 키가 필요합니다:

```bash
cat > .env << 'EOF'
ANTHROPIC_API_KEY="sk-ant-..."
OPENAI_API_KEY="sk-..."
GEMINI_API_KEY="AI..."
EOF
```

> 슬래시 커맨드(`/plan`, `/design`, `/review` 등)는 API 키 없이도 동작합니다.
> CLI 스크립트(`x-verify.sh`, `gap-check.sh`)만 API 키가 필요합니다.

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
🎯 추천: /gap docs/designs/auth.md src/

📊 프로젝트 진단:
  Plans:         2개 (최근: auth.md)
  Designs:       1개
  Verifications: 0개
  최근 커밋:     5개 (마지막: feat: 인증 모듈 구현)

💡 이유: 설계 문서가 있고 최근 구현 커밋이 있지만 검증이 없습니다.

⏭️ 이후 흐름: /gap → /review → /propose
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

Claude + GPT + Gemini 3개 AI에게 동시 질의하고 합의율을 자동 산출합니다.

```bash
/xv "Next.js에서 서버 액션 vs API 라우트, 기본으로 어떤 걸 쓸까?"
/xv "PostgreSQL vs MongoDB, 부동산 플랫폼에 적합한 건?"
```

**합의 프로토콜:**

| 합의율 | 판정 | 행동 |
|--------|------|------|
| 90%+ | AUTO APPROVE | 자동 채택 |
| 70~89% | HUMAN REVIEW | AI가 차이점 요약, 사람이 판단 |
| 70% 미만 | REDEFINE | 질문 재정의 필요 |

**산출물:** `docs/verifications/{date}-{slug}.md`

**CLI에서 직접 실행도 가능:**
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

### `install.sh` — 원격 설치 스크립트

GitHub에서 직접 다운로드하여 설치합니다.

```bash
# 신규 설치 — 모든 파일 다운로드
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 특정 디렉토리에 설치
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- ./my-project

# 업데이트 — 커맨드+스크립트만 갱신 (템플릿/가이드 보존)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

**설치되는 파일:**
- 커맨드 9개 (`.claude/commands/*.md`)
- 스크립트 3개 (`scripts/*.sh`)
- 템플릿 5개 (`docs/templates/*.md`) — 업데이트 모드에서 건너뜀
- 가이드 3개 (`docs/*.md`) — 업데이트 모드에서 건너뜀

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
   → 3개 AI 동시 질의
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
- **안 써도 되는 경우**: 단순 버그 수정, 스타일 결정, 이미 합의된 사항

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
- 프로젝트에 안 맞는 커맨드는 삭제해도 됩니다
- 새 커맨드를 만들어도 됩니다 (같은 .md 형식으로)
