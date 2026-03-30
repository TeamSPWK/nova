# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.2.0-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**처음부터 제대로. 매번 더 빠르게.**

[English](README.md)

> AI가 코드를 빠르게 만들어줘도, 잘못된 판단 하나가 3주 뒤 전체 리팩토링으로 돌아온다.
> Nova는 **설계 판단을 구조화**하여 재작업을 제거하는 Claude Code 플러그인이다.

## 빠른 시작

```bash
# 설치 (30초)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# 시작
/nova:next   # 다음 할 일 확인
```

## 작동 방식

Nova를 설치하면 CLAUDE.md의 자동 적용 규칙에 따라 **모든 대화에서 방법론이 자동 적용**된다. 커맨드를 몰라도 복잡도 판단 → 구현 → 독립 검증이 자동으로 실행된다.

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
| `/nova:auto 기능명` | Plan → Design → 구현 → 검증 자율 실행 |
| `/nova:xv "질문"` | 멀티 AI 다관점 수집 (Claude + GPT + Gemini) |
| `/nova:gap 설계.md src/` | 설계-구현 간 갭 탐지 |
| `/nova:review src/` | 적대적 코드 리뷰 |
| `/nova:team 프리셋` | 병렬 Agent Teams 구성 (QA, 리뷰, 디버그 등) |
| `/nova:init 프로젝트명` | 새 프로젝트에 Nova 초기 설정 |
| `/nova:propose 패턴` | 반복 패턴을 규칙으로 제안 |
| `/nova:metrics` | Nova 도입 수준 측정 |

> **커맨드 없이도 작동한다.** 설치만 하면 CLAUDE.md 자동 적용 규칙에 따라 일상 대화에서도 복잡도 판단 → 구현 → 독립 검증이 자동 실행된다.

## Agent Teams

`/nova:team`으로 목적별 에이전트 팀을 병렬 구성한다. tmux 사이드 패널에 팀원 활동이 표시된다.

| 프리셋 | 팀 구성 | 사용 시점 |
|--------|---------|----------|
| `qa` | 테스터 + 엣지케이스 + 회귀분석 | PR 전 품질 검증 |
| `visual-qa` | 스크린샷 + 인터랙션 + 접근성 | UI/UX 시각적 검증 |
| `review` | 아키텍트 + 보안 + 성능 | 코드 리뷰 |
| `design` | API설계 + 도메인모델 + DX | 신규 기능 설계 |
| `refactor` | 클린코드 + 의존성 + 테스트 | 기술부채 해소 |
| `debug` | 근본원인 + 로그분석 + 수정 | 프로덕션 이슈 |

> Agent Teams는 실험적 기능이다. 활성화: `.claude/settings.json`에 `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"` 추가

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

**자동 모드**: `/nova:auto 기능명` → 승인 한 번 → 자율 실행 → 완료

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

## 문서

- [사용법 가이드](docs/usage-guide.md) — 커맨드, 에이전트 상세 사용법
- [Nova Engineering](docs/nova-engineering.md) — 방법론 상세 (4 Pillars, CPS, 보안)
- [튜토리얼: Todo API](examples/tutorial-todo-api.md) — 전체 워크플로우 체험

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- API 키: OpenAI + Google AI Studio (선택, `/nova:xv`만 필요)

## 라이선스

MIT — [Spacewalk Engineering](https://spacewalk.tech)
