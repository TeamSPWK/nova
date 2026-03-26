# AXIS Kit

> **A**daptive · **X**-Verification · **I**dempotent · **S**tructured

AI 시대의 소프트웨어 개발 방법론 도구 키트.
어떤 AI를 쓰든, 누가 쓰든, 언제 쓰든 — 같은 구조에서 같은 품질이 나온다.

## 왜 AXIS인가?

### 하네스 엔지니어링에서 출발

AXIS는 하네스 엔지니어링의 핵심 철학을 계승합니다.
하네스 엔지니어링은 AI 모델에 관계없이 **멱등성 있는 결과물**을 만들기 위한 구조화 기법으로, CPS 프레임워크, MECE 분석, 린터 강제화, 구조화된 문서화를 통해 일관된 품질을 보장합니다.

AXIS는 여기에 **실전에서 부족했던 3가지**를 추가합니다:

| | 하네스 엔지니어링 | AXIS Kit |
|---|---|---|
| 규칙 체계 | 정적 (한번 정하면 고정) | **Adaptive** — 프로젝트와 함께 진화 |
| 검증 방식 | 단일 AI 결과 신뢰 | **X-Verify** — 멀티 AI 교차검증 + 합의율 자동 산출 |
| 설계↔구현 | 정방향만 (설계→구현) | **양방향** — 역방향 검증으로 갭 자동 탐지 |
| 문서 구조 | CPS + MECE | CPS + MECE (동일하게 계승) |
| 코드 강제 | 린터 | 린터 (동일하게 계승) |

### 범용 플러그인(bkit 등)과의 차이

bkit, Cursor Rules 같은 범용 AI 코딩 플러그인과 비교:

| | 범용 플러그인 | AXIS Kit |
|---|---|---|
| 철학 | 가능한 많은 기능을 제공 | **필요한 것만, 가볍게** |
| 커맨드 | 30개+ 스킬, 11개+ 에이전트 | **6개 커맨드** |
| 컨텍스트 비용 | 매 대화마다 수천 토큰 로드 | 호출할 때만 로드 |
| 커스터마이징 | 설정 파일 수정 | **코드 자체를 수정** (내 것) |
| AI 검증 | 단일 AI 의존 | **멀티 AI 교차검증** |
| 방법론 | 범용 PDCA | **CPS + MECE + 합의 프로토콜** |

AXIS는 플러그인이 아닙니다. **내 프로젝트에 복사해서 내 것으로 만드는 도구 키트**입니다.

## 핵심 원칙

```
A — Adaptive    : 규칙이 프로젝트와 함께 진화한다
X — X-Verify    : 멀티 AI 교차검증으로 단일 판단을 맹신하지 않는다
I — Idempotent  : 누가, 어떤 AI로, 언제 해도 같은 품질이 나온다
S — Structured  : CPS + MECE + 린터로 구조가 품질을 만든다
```

## 빠른 시작

### 1. 설치

```bash
# 프로젝트 루트에 복사
cp -r axis-kit/.claude/commands/ your-project/.claude/commands/
cp -r axis-kit/scripts/ your-project/scripts/
cp -r axis-kit/docs/templates/ your-project/docs/templates/
```

### 2. API 키 설정

```bash
# 프로젝트 루트에 .env 생성
cat > .env << 'EOF'
ANTHROPIC_API_KEY="your-key"
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF
```

### 3. 사용

```bash
# Claude Code에서 슬래시 커맨드로 사용
/xv "Next.js에서 서버 액션 vs API 라우트, 어떤 걸 기본으로?"
/plan 아파트 비교 기능
/design 아파트 비교 기능
/gap docs/designs/compare.md src/
/review src/components/CompareTable.tsx
```

## 커맨드

| 커맨드 | 설명 | 사용 시점 |
|--------|------|----------|
| `/xv "질문"` | 멀티 AI 교차검증 (Claude+GPT+Gemini) | 설계 판단, 아키텍처 선택 |
| `/plan 기능명` | CPS Plan 문서 작성 | 새 기능 기획 시 |
| `/design 기능명` | CPS Design 문서 작성 | Plan 이후 기술 설계 시 |
| `/gap 설계.md 코드/` | 설계↔구현 역방향 검증 | 구현 완료 후 누락 확인 |
| `/review 코드` | 단순성 원칙 코드 리뷰 | 코드 품질 점검 |
| `/propose 패턴` | 규칙 제안 (Adaptive) | 반복 패턴 발견 시 |

### 워크플로우

```
기능 요청 → /plan → /xv (필요시) → /design → 구현 → /gap → /review
            └── 패턴 발견 시 → /propose → 승인 → 규칙 반영
```

## 컨텍스트 체인 (Context Chain)

세션이 끊겨도, 팀원이 바뀌어도 맥락은 살아있습니다.

**3계층 메모리 아키텍처:**

| 계층 | 저장 위치 | 수명 |
|------|----------|------|
| Ephemeral | 현재 대화 | 세션 내 |
| Persistent | CLAUDE.md, docs/decisions/ | 프로젝트 전체 |
| Structural | 설계 문서, git history, 린터 | 영구 |

새 세션 시작 시: CLAUDE.md 로드 → git log 확인 → 의사결정 기록 참조 → 이어서 작업

상세: `docs/context-chain.md`

## 규칙 진화 (Adaptive Rules)

규칙은 고정이 아닙니다. 프로젝트와 함께 성장합니다.

```
감지(Detect) → 제안(/propose) → 승인(사람) → 적용 → 검증
```

- 반복 패턴 3회 이상 → 규칙 제안 고려
- AI가 제안, **사람이 승인** (AI 독단 변경 불가)
- 변경 이력: `docs/rules-changelog.md`

## 자가 평가 (Eval Checklist)

프로젝트의 AXIS 도입 수준을 측정합니다.

| Pillar | 평가 항목 |
|--------|----------|
| Structured | CLAUDE.md, CPS 문서, 린터, 커밋 컨벤션 |
| Idempotent | AI 독립성, 컨텍스트 복원, 의사결정 추적 |
| X-Verification | 교차검증, 합의 프로토콜, 역방향 검증 |
| Adaptive | 규칙 제안, 변경 관리, 이력 추적 |

상세: `docs/eval-checklist.md`

## 교차검증 (X-Verification)

3개 AI(Claude, GPT, Gemini)에게 동시에 질의하고 합의율을 자동 산출합니다.

![X-Verification 데모](assets/xv-demo.gif)

```bash
# CLI에서 직접 실행
./scripts/x-verify.sh "기술적 질문"

# 결과 저장 없이 실행
./scripts/x-verify.sh --no-save "빠른 질문"

# 파일에서 질문 읽기
./scripts/x-verify.sh -f question.txt
```

**합의 프로토콜:**
- 90%+ 합의 → 자동 채택
- 70~89% → AI가 차이점 요약, 사람이 판단
- 70% 미만 → 사람 필수 개입, 질문 재정의 검토

검증 결과는 `docs/verifications/`에 자동 저장됩니다.

## 역방향 검증 (Gap Check)

설계 문서와 구현 코드의 갭을 자동 탐지합니다.

![Gap Check 데모](assets/gap-demo.gif)

```bash
./scripts/gap-check.sh docs/designs/feature.md src/
```

**판정 기준:**
- 매칭률 90%+ → PASS
- 매칭률 70~89% → REVIEW NEEDED
- 매칭률 70% 미만 → SIGNIFICANT GAPS

## 튜토리얼

하나의 기능을 Plan → Design → 구현 → Gap Check까지 따라가는 실전 예시:

**[Todo API 튜토리얼](examples/tutorial-todo-api.md)** — 30분 안에 AXIS 전체 워크플로우를 체험

## CPS 프레임워크

모든 설계/분석 문서는 CPS 구조를 따릅니다:

```
Context  — 왜 이 작업이 필요한가? 배경과 현재 상태
Problem  — 구체적으로 무엇이 문제인가? MECE로 분해
Solution — 어떻게 해결하는가? 트레이드오프와 결정 근거 포함
```

템플릿: `docs/templates/cps-plan.md`, `docs/templates/cps-design.md`

## 파일 구조

```
axis-kit/
├── .claude/commands/       # Claude Code 슬래시 커맨드 (6개)
│   ├── xv.md               # /xv — 멀티 AI 교차검증
│   ├── plan.md             # /plan — CPS Plan 작성
│   ├── design.md           # /design — CPS Design 작성
│   ├── gap.md              # /gap — 역방향 검증
│   ├── review.md           # /review — 코드 리뷰
│   └── propose.md          # /propose — 규칙 제안 (Adaptive)
├── scripts/
│   ├── x-verify.sh         # 교차검증 CLI
│   └── gap-check.sh        # 갭 체크 CLI
├── docs/
│   ├── axis-engineering.md  # 방법론 상세
│   ├── context-chain.md     # 컨텍스트 유지 체계
│   ├── eval-checklist.md    # 도입 수준 자가 평가
│   ├── rules-changelog.md   # 규칙 변경 이력
│   ├── plans/               # CPS Plan 문서
│   ├── templates/           # 문서 템플릿
│   │   ├── cps-plan.md
│   │   ├── cps-design.md
│   │   ├── claude-md.md     # CLAUDE.md 작성 가이드
│   │   ├── decision-record.md # 의사결정 기록
│   │   └── rule-proposal.md  # 규칙 제안서
│   └── verifications/       # 교차검증 결과 (자동 생성)
└── examples/                # 사용 예시
```

## CLAUDE.md 설정

프로젝트에 AXIS를 도입할 때, `docs/templates/claude-md.md` 템플릿을 참고하여 CLAUDE.md를 작성합니다.

핵심 포인트:
- CLAUDE.md가 모든 맥락의 **입구** — 여기서부터 추적 가능해야 함
- AI 응답 언어, 커맨드, 컨벤션, Human-AI Boundary 필수 포함
- 상세 가이드: `docs/templates/claude-md.md`

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- API 키: Anthropic + OpenAI + Google AI Studio
- `jq`, `curl` (스크립트 실행용)

## 라이선스

MIT

## 만든 사람

Spacewalk Engineering
