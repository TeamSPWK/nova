# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-3.2.0-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**출시 전에 검증한다. 매번.**

[English](README.md)

> AI가 코드를 빠르게 만들어줘도, 잘못된 판단 하나가 3주 뒤 전체 리팩토링으로 돌아온다.
> Nova는 AI가 만든 코드의 **품질 게이트** 역할을 하는 Claude Code 플러그인이다. 실행이 아닌 검증에 집중한다.

## 빠른 시작

```bash
# 설치 (30초)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# 시작
/nova:next   # 다음 할 일 확인
```

## 작동 방식

Nova를 설치하면 CLAUDE.md의 자동 적용 규칙에 따라 **모든 대화에서 Quality Gate 방법론이 자동 적용**된다. 커맨드를 몰라도 복잡도 판단 → 구현 → 독립 검증이 자동으로 실행된다.

### 핵심 원칙

| 원칙 | 의미 |
|------|------|
| **Structured** | CPS 프레임워크(Context → Problem → Solution)로 잘못된 것을 만드는 걸 방지 |
| **Consistent** | 누가 작업하든, 어떤 AI를 쓰든 같은 프로세스와 품질 기준선 |
| **X-Verification** | 설계 판단 시 여러 AI 모델에서 다관점 수집 |
| **Adaptive** | 규칙이 프로젝트와 함께 진화 — 좋은 패턴은 제안, 검토, 흡수 |

### Generator-Evaluator 분리

> "모델은 자기 결과물을 칭찬하는 경향이 있다."

코드를 구현하는 에이전트와 검증하는 에이전트는 **항상 분리**된다. 검증 에이전트는 적대적 자세: *통과시키지 마라, 문제를 찾아라*.

## 커맨드

모든 커맨드는 `nova:` 접두사로 사용한다.

| 커맨드 | 설명 |
|--------|------|
| `/nova:next` | 프로젝트 상태 기반 다음 액션 추천 |
| `/nova:plan 기능명` | CPS Plan 문서 작성 |
| `/nova:design 기능명` | CPS Design 문서 작성 |
| `/nova:auto 기능명` | 단발 종합 검증: 정적 분석 + 구조적 리뷰 + 설계 정합성 |
| `/nova:xv "질문"` | 멀티 AI 다관점 수집 (Claude + GPT + Gemini) |
| `/nova:gap 설계.md src/` | 설계-구현 간 갭 탐지 |
| `/nova:review src/` | 적대적 코드 리뷰 |
| `/nova:init 프로젝트명` | 새 프로젝트에 Nova 초기 설정 |
| `/nova:propose 패턴` | 반복 패턴을 규칙으로 제안 |
| `/nova:metrics` | Nova 도입 수준 측정 |

> **커맨드 없이도 작동한다.** 설치만 하면 CLAUDE.md 자동 적용 규칙에 따라 일상 대화에서도 복잡도 판단 → 구현 → 독립 검증이 자동 실행된다.

## 워크플로우

```
요청
  │
  ├── 간단 (버그 수정, 1-2 파일)
  │   └── 바로 구현 → 독립 Evaluator 검증 → 완료
  │
  ├── 보통 (새 기능, 3-7 파일)
  │   └── Plan → 승인 → 구현 → 독립 Evaluator 검증 → 완료
  │
  └── 복잡 (8+ 파일, 다중 모듈)
      └── Plan → Design → 스프린트 분할 → 승인
          → 스프린트별 (구현 → 검증) 반복
          → Independent Verifier → 완료
```

**수동 모드**: `/nova:plan` → `/nova:xv`(필요시) → `/nova:design` → 구현 → `/nova:gap` → `/nova:review`

**검증 모드**: `/nova:auto` → 단발 검증 → Quality Gate 판정

## 전문 에이전트

| 에이전트 | 전문 영역 |
|----------|----------|
| `architect` | 시스템 아키텍처 설계, 기술 선택, 확장성 |
| `senior-dev` | 코드 품질, 리팩토링, 기술 부채 |
| `qa-engineer` | 테스트 전략, 엣지 케이스, 품질 검증 |
| `security-engineer` | 취약점 점검, 위협 모델링, 인증/인가 |
| `devops-engineer` | CI/CD 파이프라인, 인프라, 배포 전략 |

## API 키 (선택)

`/nova:xv`(다관점 수집)만 API 키가 필요하다. 나머지는 전부 API 키 없이 동작한다.

```bash
cat > .env << 'EOF'
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF
```

## 설치 / 업데이트 / 삭제

```bash
# 설치
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# 업데이트
claude plugin update nova@nova-marketplace

# 삭제
claude plugin uninstall nova@nova-marketplace
claude plugin marketplace remove nova-marketplace
```

## Nova가 잡아내는 것

CI에서 의도적 결함이 주입된 코드를 대상으로 [자가 검증 테스트](tests/test-self-verify.sh)를 실행한다. 간단한 인증 모듈에서 탐지되는 갭 목록:

| 결함 | 유형 | 탐지 방법 |
|------|------|----------|
| `GET /api/auth/me` 엔드포인트 누락 | 설계-구현 갭 | 설계 문서 vs 라우트 핸들러 엔드포인트 diff |
| 비밀번호 평문 저장 | 보안 | 설계는 bcrypt 요구, 코드에 해싱 import 없음 |
| 이메일 중복 체크 누락 (409 미구현) | 검증 계약 불이행 | 설계에 409 응답 명시, 코드에 충돌 처리 없음 |
| 비밀번호 최소 길이 검증 누락 | 검증 계약 불이행 | 설계에 8자 이상 명시, 코드에 길이 검사 없음 |
| JWT 토큰에 userId 누락 | 데이터 계약 불일치 | 설계에 userId 포함 명시, 코드는 email만 포함 |
| JWT 시크릿 키 하드코딩 | 보안 패턴 | 정적 분석: `jwt.sign()`에 문자열 리터럴 |

> 위는 AI 모델 없이 실행되는 **구조적 검사**다. Nova의 AI 에이전트(`/nova:gap`, `/nova:review`)는 이 구조적 패턴 위에 더 깊은 의미론적 분석을 수행한다.

## FAQ

### Nova를 쓰지 말아야 할 때는?

Nova는 설계 판단이 중요할 때 가치를 발휘한다. 다음 경우엔 그냥 코딩하면 된다:

- **한 줄 수정**: 오타, 버전 범프, 설정 변경 — CPS 불필요.
- **원인이 명확한 버그**: 스택 트레이스가 원인을 가리키면 바로 고치면 된다. Plan을 쓸 필요 없다.
- **버릴 프로토타입**: 어차피 버릴 거라면 프로세스를 건너뛰자.
- **30분 이내 작업**: Plan → Design → Gap 전체 사이클이 작업 자체보다 오래 걸리면 그건 도움이 아니라 오버헤드다.

**기준**: 변경 사항 전체를 머릿속에 담을 수 있으면 Nova가 필요 없다.

### KPI는 실측 결과인가?

아니다. 방법론 문서의 KPI는 **도입 목표**이지 측정된 결과가 아니다. Nova는 아직 젊은 프로젝트이며, 통계적으로 유의미한 before/after 데이터가 없다. 실제 프로젝트에서 Nova를 적용하고 결과를 측정하셨다면 공유해주시면 감사하겠다.

### `/nova:xv` 다관점 합의가 틀릴 수 있나?

그렇다. 알려진 한계:

- **공유된 학습 편향**: Claude, GPT, Gemini는 학습 데이터의 상당 부분을 공유한다. Strong Consensus가 정확성을 보장하지 않는다 — 공유된 맹점일 수 있다.
- **정성적 판단**: 합의 수준(Strong/Partial/Divergent)은 AI의 정성적 평가이며, 정량 메트릭이 아니다.
- **전문성을 대체하지 않는다**: `/nova:xv`는 판단 재료를 풍부하게 할 뿐이다. 최종 결정은 항상 사람의 몫 — 특히 모든 LLM이 깊이가 부족한 영역(니치 프레임워크, 내부 시스템, 신규 아키텍처)에서는 더욱 그렇다.

세 모델이 모두 동의할 때 스스로에게 물어보자: *"이건 셋 다 틀릴 수 있는 주제인가?"* 그렇다면 인간 전문가를 찾아라.

### Paperclip 같은 오케스트레이터와 어떻게 함께 쓰나?

Nova는 Quality Gate — 검증만 한다. 외부 오케스트레이터(Paperclip 등)가 에이전트 스케줄링, 예산, 팀 조율을 담당한다. Nova는 그 루프 안에서 검증 검문소 역할을 한다: 오케스트레이터가 만들고, Nova가 검증한다.

## 문서

- [사용법 가이드](docs/usage-guide.md) — 커맨드, 에이전트 상세 사용법
- [Nova Engineering](docs/nova-engineering.md) — 방법론 상세 (4 Pillars, CPS, 보안)
- [튜토리얼: Todo API](examples/tutorial-todo-api.md) — 전체 워크플로우 체험

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- API 키: OpenAI + Google AI Studio (선택, `/nova:xv`만 필요)

## 라이선스

MIT — [Spacewalk Engineering](https://spacewalk.tech)
