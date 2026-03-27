# AXIS Kit

[![CI](https://github.com/TeamSPWK/axis-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/axis-kit/actions/workflows/ci.yml)

**처음부터 제대로. 매번 더 빠르게.**
Build Right the First Time. Faster Every Time.

---

## AI 도구는 넘쳐나는데, 왜 재작업은 줄지 않는가?

AI 코딩 도구는 **타이핑 속도**를 높여줬다. 하지만 진짜 병목은 거기에 없다.

> 잘못된 설계 판단 하나가 3주 뒤 전체 리팩토링으로 돌아온다.
> "빠르게 만들었다"가 "빠르게 다시 만들었다"로 바뀐다.
> 팀원이 바뀌면 맥락이 증발하고, 같은 실수가 반복된다.

**재작업의 근본 원인은 속도가 아니라 판단이다.** 잘못된 판단은 복리로 비용이 쌓인다. 1주차의 잘못된 결정이 4주차에 10배의 재작업으로 돌아온다.

AXIS Kit은 AI 시대의 소프트웨어 개발에서 **처음부터 제대로 만들게 하여 재작업을 제거한다.**

## AXIS가 하는 일

AXIS Kit은 5가지 자산으로 개발 과정의 핵심 병목을 제거한다.

| 자산 | 제거하는 병목 | 결과 |
|------|-------------|------|
| **CPS 문서 체계** | "뭘 만들지 합의 안 됨" | 기획-설계-구현이 하나의 구조로 연결 |
| **교차검증 (/xv)** | "AI 한 마리 말만 믿음" | 3개 AI 합의로 잘못된 판단 사전 차단 |
| **역방향 검증 (/gap)** | "설계와 코드가 따로 놂" | 설계-구현 갭 자동 탐지, 누락 제로 |
| **컨텍스트 체인** | "세션 끊기면 맥락 증발" | CLAUDE.md + git + 의사결정 기록으로 영속 복원 |
| **적응형 규칙** | "규칙이 낡아서 무시됨" | 프로젝트와 함께 진화하는 살아있는 규칙 |

## 철학

AXIS는 세 가지 원칙 위에 서 있다.

**일관성** -- 누가 작업하든, 어떤 AI를 쓰든 같은 품질이 나온다. 구조가 품질을 만든다.

**생산성** -- 재작업을 제거하는 것이 가장 빠른 길이다. 처음부터 제대로 만들면 두 번 만들 필요가 없다.

**혁신 흡수** -- 규칙은 고정이 아니다. 좋은 패턴이 발견되면 제안하고, 검증하고, 흡수한다.

```
A — Adaptive    : 규칙이 프로젝트와 함께 진화한다
X — X-Verify    : 멀티 AI 교차검증으로 단일 판단을 맹신하지 않는다
I — Idempotent  : 누가, 어떤 AI로, 언제 해도 같은 품질이 나온다
S — Structured  : CPS + MECE + 린터로 구조가 품질을 만든다
```

## 빠른 시작

### 최소 설치 (권장 -- 핵심 3개 커맨드부터)

![설치 데모](assets/install-demo.gif)

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal
```

### 전체 설치

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash
```

### 업데이트 (커스터마이징 보존)

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

### 프로젝트 초기화

```bash
# 기존 프로젝트에 AXIS 도입 (CLAUDE.md 기존 내용 유지)
bash scripts/init.sh --adopt my-project

# 신규 프로젝트 생성
bash scripts/init.sh my-project "Next.js + TypeScript"
```

### 바로 시작

```bash
/next   # 다음 할 일 확인 — 여기서부터 시작
```

### API 키 설정 (교차검증용, 선택)

```bash
cat > .env << 'EOF'
ANTHROPIC_API_KEY="your-key"
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF
```

> `/xv`(교차검증)만 API 키가 필요합니다. 나머지 커맨드는 모두 API 키 없이 동작합니다.

## 커맨드

| 커맨드 | 설명 | 사용 시점 |
|--------|------|----------|
| `/next` | 다음 할 일 자동 추천 | 뭘 해야 할지 모를 때 |
| `/init 프로젝트명` | 프로젝트에 AXIS 초기 설정 | 신규 프로젝트 시작 시 |
| `/plan 기능명` | CPS Plan 문서 작성 | 새 기능 기획 시 |
| `/xv "질문"` | 멀티 AI 교차검증 (Claude+GPT+Gemini) | 설계 판단, 아키텍처 선택 |
| `/design 기능명` | CPS Design 문서 작성 | Plan 이후 기술 설계 시 |
| `/gap 설계.md 코드/` | 설계↔구현 역방향 검증 | 구현 완료 후 누락 확인 |
| `/review 코드` | 단순성 원칙 코드 리뷰 | 코드 품질 점검 |
| `/propose 패턴` | 규칙 제안 (Adaptive) | 반복 패턴 발견 시 |
| `/metrics` | AXIS 도입 수준 자동 측정 | 정기 평가, 현황 파악 |

## 에이전트

특화된 관점이 필요할 때, 전문 에이전트를 호출한다.

| 에이전트 | 전문 영역 |
|----------|----------|
| `architect` | 시스템 아키텍처 설계, 기술 선택, 확장성/유지보수성 검토 |
| `senior-dev` | 코드 품질 개선, 리팩토링, 기술 부채 식별 |
| `qa-engineer` | 테스트 전략, 엣지 케이스 식별, 품질 검증 |
| `security-engineer` | 보안 취약점 점검, 위협 모델링, 인증/인가 검토 |
| `devops-engineer` | CI/CD 파이프라인, 인프라 설정, 배포 전략 |

## 워크플로우

```
/next ─── 뭘 해야 하지?
  │
  ▼
/plan ─── 기능 기획 (CPS)
  │
  ├── /xv ─── 설계 판단이 필요하면 교차검증
  │
  ▼
/design ─ 기술 설계 (CPS)
  │
  ▼
  구현
  │
  ├── /gap ──── 설계 vs 구현 갭 검증
  ├── /review ─ 코드 리뷰
  │
  ▼
  완료
  │
  └── 패턴 발견 → /propose → 승인 → 규칙 진화
```

![X-Verification 데모](assets/xv-demo.gif)
![Gap Check 데모](assets/gap-demo.gif)

## 문서

| 문서 | 설명 |
|------|------|
| **[사용법 가이드](docs/usage-guide.md)** | 커맨드, 스크립트, 에이전트 상세 사용법 |
| **[Todo API 튜토리얼](examples/tutorial-todo-api.md)** | Plan - Design - 구현 - Gap 전체 워크플로우 체험 |
| **[도입 가이드](docs/adoption-guide.md)** | 신규/기존 프로젝트별 단계적 도입 전략 |
| **[방법론 상세](docs/axis-engineering.md)** | AXIS 4 Pillars, CPS, MECE, 보안 체계 |

## 파일 구조

```
axis-kit/
├── install.sh                  # 한 줄 설치 스크립트
├── CONTRIBUTING.md             # 기여 가이드
├── .claude/
│   ├── commands/               # 슬래시 커맨드
│   │   ├── next.md             #   /next — 다음 할 일 추천
│   │   ├── init.md             #   /init — 프로젝트 초기 설정
│   │   ├── plan.md             #   /plan — CPS Plan 작성
│   │   ├── xv.md               #   /xv — 멀티 AI 교차검증
│   │   ├── design.md           #   /design — CPS Design 작성
│   │   ├── gap.md              #   /gap — 역방향 검증
│   │   ├── review.md           #   /review — 코드 리뷰
│   │   ├── propose.md          #   /propose — 규칙 제안
│   │   └── metrics.md          #   /metrics — 도입 수준 측정
│   └── agents/                 # 전문 에이전트
│       ├── architect.md
│       ├── senior-dev.md
│       ├── qa-engineer.md
│       ├── security-engineer.md
│       └── devops-engineer.md
├── scripts/
│   ├── .axis-version           # 현재 버전
│   ├── x-verify.sh             # 교차검증 CLI
│   ├── gap-check.sh            # 갭 체크 CLI
│   ├── init.sh                 # 초기화 CLI
│   └── lib/
│       └── common.sh           # 공통 함수 라이브러리
├── docs/
│   ├── usage-guide.md          # 사용법 가이드
│   ├── adoption-guide.md       # 도입 가이드
│   ├── axis-engineering.md     # 방법론 상세
│   ├── context-chain.md        # 컨텍스트 유지 체계
│   ├── eval-checklist.md       # 도입 수준 자가 평가
│   ├── rules-changelog.md      # 규칙 변경 이력
│   ├── proposals/              # 규칙 제안서
│   ├── plans/                  # CPS Plan 문서
│   ├── decisions/              # 의사결정 기록 (ADR)
│   ├── verifications/          # 교차검증 결과
│   └── templates/              # 문서 템플릿
│       ├── cps-plan.md
│       ├── cps-design.md
│       ├── claude-md.md
│       ├── decision-record.md
│       └── rule-proposal.md
├── tests/
│   └── test-scripts.sh         # 스크립트 테스트
└── examples/                   # 사용 예시 + 튜토리얼
    ├── tutorial-todo-api.md
    ├── sample-plan.md
    ├── sample-design.md
    ├── sample-decision.md
    └── sample-xv-result.md
```

## 치트시트

### 설치 & 업데이트

```bash
# 최소 설치 (핵심 3개: /next, /plan, /review)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal

# 전체 설치
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 업데이트 (커맨드+스크립트만 갱신, 커스터마이징 보존)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update

# 초기화
bash scripts/init.sh my-project "Next.js + TypeScript"     # 신규
bash scripts/init.sh --adopt my-project                     # 기존 프로젝트
```

### 커맨드 요약

```bash
/next                              # 다음 할 일 추천
/plan 기능명                        # CPS Plan 작성
/xv "질문"                          # 멀티 AI 교차검증
/design 기능명                      # CPS Design 작성
/gap docs/designs/x.md src/        # 설계↔구현 갭 검증
/review src/                       # 코드 리뷰
/propose 패턴명                     # 규칙 제안
/metrics                           # AXIS 도입 수준 측정
/init 프로젝트명                    # 프로젝트 초기 설정
```

### CLI 스크립트

```bash
./scripts/x-verify.sh "질문"                    # 교차검증 (기본: Sonnet)
./scripts/x-verify.sh --model opus "질문"       # Opus 모델 사용
./scripts/x-verify.sh --no-save "질문"          # 결과 저장 안 함
./scripts/gap-check.sh design.md src/           # 갭 체크
```

### 워크플로우

```
기능 요청 → /plan → /xv(필요시) → /design → 구현 → /gap → /review → /propose(패턴 발견시)
```

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- `jq`, `curl` (스크립트 실행용)
- API 키: Anthropic + OpenAI + Google AI Studio (교차검증 사용 시, 선택)

## 라이선스

MIT

---

Spacewalk Engineering
