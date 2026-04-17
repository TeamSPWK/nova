# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-5.3.0-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**출시 전에 검증한다. 매번.**

[English](README.md)

> AI가 코드를 빠르게 만들어줘도, 잘못된 판단 하나가 4주 뒤 전체 리팩토링으로 돌아온다.
> Nova는 AI가 만든 코드의 **품질 게이트** 역할을 하는 Claude Code 플러그인이다. 실행이 아닌 검증에 집중한다.

## 빠른 시작

```bash
# 설치 (30초)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# 시작
/nova:next   # 다음 할 일 확인
```

## Nova란?

Nova는 **AI 오케스트레이터 루프 안의 검문소**다. 코드를 생성하지 않고, 생성된 코드가 제대로 됐는지 검증한다. 또한 복잡한 멀티 프로젝트 작업을 자동으로 오케스트레이션한다.

```
┌─────────────────────────────────────────────────┐
│  사용자 요청                                      │
│       ↓                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │ Generator │───→│  Nova    │───→│ 완료/수정 │   │
│  │ (구현)    │    │ (검증)   │    │          │   │
│  └──────────┘    └──────────┘    └──────────┘   │
│                       ↑                          │
│               독립 서브에이전트                    │
│               적대적 자세로 검증                  │
└─────────────────────────────────────────────────┘
```

핵심은 **Generator-Evaluator 분리**: 코드를 만든 에이전트와 검증하는 에이전트가 항상 다르다. "자기가 쓴 코드를 자기가 리뷰"하는 함정을 방지한다.

## 아키텍처: 하네스 엔지니어링

Nova는 Claude Code의 **하네스 레이어** — 훅, 커맨드, 에이전트, 스킬 시스템 — 를 설계해서 품질 게이트를 구현한다. 모델이 아는 것을 바꾸는 게 아니라, **언제, 어떤 규칙으로, 어떤 도구로 실행하는지**를 제어한다.

```
┌─────────────────────────────────────────────────────┐
│  Claude Code 하네스                                   │
│                                                      │
│  ┌─────────────────┐   SessionStart 훅               │
│  │ session-start.sh │──→ 매 세션 시작 시               │
│  │                  │    10개 규칙을 LLM 컨텍스트로 주입 │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   슬래시 커맨드                   │
│  │ .claude-plugin/  │──→ /nova:plan, /nova:review,    │
│  │   *.md           │    /nova:check, /nova:run ... │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   전문 서브에이전트 5종           │
│  │ .claude-plugin/  │──→ architect, senior-dev,       │
│  │   agents/*.md    │    qa-engineer, security, devops │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   복합 스킬 5종                  │
│  │ skills/*/SKILL.md│──→ evaluator, jury,             │
│  │                  │    context-chain, field-test,   │
│  │                  │    orchestrator                 │
│  └─────────────────┘                                 │
└─────────────────────────────────────────────────────┘
```

| 레이어 | 파일 | 메커니즘 | 역할 |
|--------|------|---------|------|
| **규칙 주입** | `hooks/session-start.sh` | SessionStart 훅 | 매 세션 10개 자동 적용 규칙을 LLM 컨텍스트로 주입 |
| **커맨드** | `.claude-plugin/*.md` | 슬래시 커맨드 | 사용자가 호출하는 워크플로우 (`/nova:plan`, `/nova:review` 등) |
| **에이전트** | `.claude-plugin/agents/*.md` | 서브에이전트 타입 | 도메인별 체크리스트를 내장한 전문 에이전트 |
| **스킬** | `skills/*/SKILL.md` | 스킬 시스템 | 복합 다단계 작업 (평가, 배심원, 컨텍스트 체인, 오케스트레이션) |

**핵심 구분**: "자동 적용"이란 `session-start.sh`가 세션 시작 시 규칙 텍스트를 Claude 컨텍스트에 주입하는 것이다. Claude가 해당 규칙을 행동 지침으로 따르는 구조 — 코드 수준의 인터셉터가 아니라 하네스 수준의 프롬프트 거버넌스다.

## 워크플로우

### 자동 워크플로우 (자연어)

Nova를 설치하면 **커맨드 없이도** 모든 대화에서 Quality Gate가 자동 적용된다. 자연어로 작업을 요청하면 Nova가 알아서 판단한다.

```
"기능 만들어줘" ──→ 복잡도 자동 판단
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
       [간단]          [보통]          [복잡]
          │               │               │
       구현           Plan→승인        Plan→Design
          │               │            →스프린트 분할
          │            구현              →승인
          │               │               │
          ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │Evaluator │    │Evaluator │    │Evaluator │
    │  Lite    │    │ Standard │    │  Full    │
    └──────────┘    └──────────┘    └──────────┘
          │               │               │
       [PASS]          [PASS]          [PASS]
          ↓               ↓               ↓
        완료             완료            완료
```

### 수동 워크플로우 (커맨드)

```
/nova:plan → /nova:ask (필요시) → /nova:design → 구현 → /nova:check
```

## 작동 방식: 예시

### 예시: "로그인 API 만들어줘"

```
사용자: "로그인 API 만들어줘"
         ↓
Nova 자동 판단:
  1. 복잡도 판단 → "인증 도메인이라 한 단계 상향 → 보통"
  2. Plan 작성 → 사용자 승인 대기
  3. 승인 후 구현
  4. 독립 Evaluator 서브에이전트가 적대적 검증
     → "jwt_secret_key 하드코딩 → Hard-Block"
  5. Hard-Block 발견 → 사용자에게 즉시 보고
```

### 예시: "이 버그 수정해줘" (간단)

```
사용자: "NullPointerException 수정해줘"
         ↓
Nova 자동 판단:
  1. 복잡도 판단 → "1파일 수정, 명확한 버그 → 간단"
  2. 바로 수정
  3. 독립 Evaluator가 경량 검증 (Lite)
  4. PASS → 완료
```

### 예시: "전체 인증 시스템 리팩토링" (복잡)

```
사용자: "JWT에서 세션 기반으로 전환해줘"
         ↓
Nova 자동 판단:
  1. 복잡도 판단 → "8+ 파일, 인증 도메인 → 복잡"
  2. Plan → Design → 사용자 승인
  3. 스프린트 분할 (Sprint 1: 세션 모델, Sprint 2: 미들웨어, ...)
  4. 스프린트별 구현 → 검증 반복
  5. 전체 검증 → 완료
```

## 자동 적용 규칙 (10개)

설치 즉시 모든 대화에 적용되는 규칙이다. `session-start.sh` 훅이 매 세션 LLM 컨텍스트로 주입한다.

### 1. 복잡도 + 위험도 자동 판단

| 복잡도 | 기준 | 자동 행동 |
|--------|------|----------|
| **간단** | 1~2 파일, 명확한 버그 | 바로 구현 → Evaluator Lite |
| **보통** | 3~7 파일, 새 기능 | Plan → 승인 → 구현 → Evaluator Standard |
| **복잡** | 8+ 파일, 다중 모듈 | Plan → Design → 스프린트 분할 → Evaluator Full |

- 인증/DB/결제 등 고위험 영역은 파일 수와 무관하게 한 단계 상향
- 작업 중 파일이 초기 예상을 넘어서면 복잡도를 재판단

### 2. Generator-Evaluator 분리 + 커밋 전 게이트 (핵심)

- 구현(Generator)과 검증(Evaluator)은 **항상 별도 에이전트**
- 검증 에이전트는 적대적 자세: "통과시키지 마라, 문제를 찾아라"
- `--strict`를 명시하지 않으면 경량(Lite) 검증이 기본

**커밋 전 하드 게이트**: 구현 완료 → tsc/lint 통과 → Evaluator 실행 → PASS → 커밋 허용. Evaluator PASS 전 배포 금지 (예외: `--emergency`).

### 3. 검증 기준 (5가지)

| 기준 | 확인 사항 |
|------|----------|
| **기능** | 요구사항 원문과 대조하여 실제로 동작하는가? |
| **데이터 관통** | 입력 → 저장 → 로드 → 표시 → 사용자 전달까지 완전한가? |
| **설계 정합성** | 기존 코드/아키텍처와 일관되는가? |
| **크래프트** | 에러 핸들링, 엣지 케이스, 타입 안전성 |
| **경계값** | 0, 음수, 빈 문자열, 최대값에서 크래시 없이 동작하는가? |

### 4. 실행 검증 우선

- "코드가 존재한다" ≠ "동작한다"
- "테스트 통과" ≠ "검증 완료" — 경계값으로 크래시 여부를 추가 확인
- 환경 변경은 3단계: 현재값 확인 → 변경 → 반영 확인

### 5~10. 기타 규칙

| 규칙 | 설명 |
|------|------|
| **§5 검증 경량화** | 기본은 Lite. `--strict` 요청 시에만 풀 검증 |
| **§6 스프린트 분할** | 8+ 파일은 독립 검증 가능한 스프린트로 분할 |
| **§7 블로커 분류** | Auto-Resolve / Soft-Block / Hard-Block. 같은 실패 2회 반복 시 강제 분류 |
| **§8 NOVA-STATE.md** | 배포/테스트/스프린트/블로커/검증 결과 시 즉시 업데이트. Known Gaps 필수 기록 |
| **§9 긴급 모드** | `--emergency` 시 Plan/Design 생략, 즉시 수정. 검증은 사후 |
| **§10 환경 안전** | 설정 파일 직접 수정 금지. 환경변수/CLI 플래그 사용 |

## 커맨드

커맨드는 자동 적용 규칙 위에 **추가 제어**가 필요할 때 사용한다.

<!-- AUTO-GEN:commands -->
| Command | Description |
|---------|------------|
| `/nova:ask` | 멀티 AI 다관점 자문을 실행한다. Claude + GPT + Gemini 3개 AI에게 동시에 질의하고 합의 수준을 분석한다. |
| `/nova:auto` | 자연어 요청을 설계→구현→검증→수정 전체 사이클로 자동 실행한다. |
| `/nova:check` | 코드 품질 리뷰 + 설계-구현 정합성 검증을 한 번에 수행한다. |
| `/nova:design` | CPS(Context-Problem-Solution) 프레임워크로 Design 문서를 작성한다. |
| `/nova:evolve` | 기술 동향을 스캔하고 Nova를 자동으로 진화시킨다. 사용자 대신 Nova 품질 게이트가 변경을 검증한다. |
| `/nova:next` | 현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다. |
| `/nova:plan` | CPS(Context-Problem-Solution) 프레임워크로 Plan 문서를 작성한다. |
| `/nova:review` | 코드를 적대적 관점에서 리뷰하고, 숨겨진 문제를 찾아낸다. |
| `/nova:run` | 구현→검증을 한 사이클로 실행한다 (Full Cycle). --verify-only로 검증만 수행 가능. |
| `/nova:scan` | 새 프로젝트에 처음 투입됐을 때 코드베이스를 자동 분석하고 '어디부터 볼지' 브리핑한다. |
| `/nova:setup` | 새 프로젝트에 Nova Quality Gate를 초기 설정하거나, 기존 프로젝트의 갭을 자동 보완한다 (--upgrade). |
| `/nova:ux-audit` | 5인 적대적 평가자로 UI/UX를 다관점 심층 평가. 접근성(WCAG 2.2)·인지 부하·성능(Core Web Vitals)·다크 패턴(EU DSA)까지 코드 기반 분석. |
<!-- /AUTO-GEN:commands -->

## Self-Evolution (자동 진화)

Nova는 스스로 진화한다. `/nova:evolve`가 기술 동향을 스캔하고, Nova에 적용할 개선점을 찾아 제안하거나 직접 구현한다.

```bash
/nova:evolve              # 기술 동향 스캔 + 제안서 생성 (기본)
/nova:evolve --apply      # 제안서 기반 구현 + 품질 게이트
/nova:evolve --auto       # scan + apply + 자율 범위 자동 머지
```

### 자율 범위 정책

| 수준 | 예시 | 자동화 |
|------|------|--------|
| **patch** | 문서 개선, 체크리스트 보완 | 자동 커밋 |
| **minor** | 검증 기준 추가, 훅 개선 | PR 생성 |
| **major** | 새 커맨드, 아키텍처 변경 | 제안서만 |

### 자동 스케줄

Claude Code 원격 에이전트로 **매주 월/수/금 06:00 KST**에 자동 실행된다.

관리: https://claude.ai/code/scheduled

## MCP 서버

Nova는 로컬 MCP (Model Context Protocol) 서버를 포함한다. Nova의 규칙, 상태, 도구를 어느 Claude Code 세션에서든 접근할 수 있게 한다 — Nova 프로젝트 밖에서도.

### 설정

```bash
cd mcp-server && pnpm install && pnpm build
```

프로젝트 루트의 `.mcp.json`이 Claude Code에 자동 등록한다.

### 제공 도구

| 도구 | 설명 |
|------|------|
| `get_rules` | Nova 규칙 반환 (전체 또는 섹션별 §1~§9) |
| `get_commands` | 전체 슬래시 커맨드 목록과 설명 |
| `get_state` | 지정 프로젝트의 NOVA-STATE.md 읽기 |
| `create_plan` | 주제에 대한 CPS Plan 템플릿 생성 |
| `orchestrate` | 복잡도별 에이전트 편성 가이드 반환 |
| `verify` | 검증 강도별 체크리스트 반환 (lite/standard/full) |

### 동작 방식

```
어느 프로젝트든 ──→ Claude Code ──→ Nova MCP 서버 (로컬, stdio)
                                        │
                                        ├── get_rules()     → Nova 규칙 전문
                                        ├── get_state()     → NOVA-STATE.md
                                        └── orchestrate()   → 에이전트 편성 가이드
```

MCP 서버는 Nova 설치 디렉토리에서 파일을 직접 읽는다. API 호출 없음, 외부 의존성 없음.

## 스킬

스킬은 커맨드가 내부적으로 호출하는 복합 작업이다. 직접 호출도 가능하다.

<!-- AUTO-GEN:skills -->
| Skill | Description |
|-------|------------|
| **context-chain** | Nova Context Chain — 세션 간 맥락 연속성 보장. NOVA-STATE.md 기반 상태 관리. |
| **evaluator** | Nova Adversarial Evaluator — Nova Quality Gate의 핵심 검증 엔진. 독립 서브에이전트로 코드를 적대적 관점에서 검증. |
| **evolution** | Nova Self-Evolution 엔진 — 기술 동향 스캔, 관련성 필터, 자율 범위 구현까지 전체 파이프라인 |
| **field-test** | 실제 프로젝트에서 Nova를 사용해보며 개선 포인트를 찾는 실전 테스트. 워크트리 격리로 흔적 없이 진행. |
| **jury** | Nova LLM Jury — 다중 관점 평가로 단일 Evaluator의 편향을 보정 |
| **orchestrator** | Nova Orchestrator — 자연어 요청을 CPS 설계→에이전트 편성→구현→검증→수정 전체 사이클로 자동 실행 |
| **ux-audit** | Nova UX Audit — 5인 적대적 평가자(Adversarial Jury)로 UI/UX를 다관점 심층 평가. 코드 기반 분석 + 선택적 화면 캡처. |
<!-- /AUTO-GEN:skills -->

## 전문 에이전트 (5종)

각 에이전트는 역할별 Nova 자가 점검 체크리스트를 내장하고 있다.

<!-- AUTO-GEN:agents -->
| Agent | Description |
|-------|------------|
| `architect` | 시스템 아키텍처 설계, 기술 선택, 확장성/유지보수성 검토가 필요할 때 사용 |
| `devops-engineer` | CI/CD 파이프라인, 인프라 설정, 배포 전략, 모니터링 구성이 필요할 때 사용 |
| `qa-engineer` | 테스트 전략 수립, 엣지 케이스 식별, 품질 검증이 필요할 때 사용 |
| `security-engineer` | 보안 취약점 점검, 위협 모델링, 인증/인가 검토가 필요할 때 사용 |
| `senior-dev` | 코드 품질 개선, 리팩토링, 구현 전략 수립, 기술 부채 식별이 필요할 때 사용 |
<!-- /AUTO-GEN:agents -->

## 세션 상태 관리 (NOVA-STATE.md)

Nova는 `NOVA-STATE.md`로 세션 간 맥락을 유지한다. 없으면 세션 시작 시 자동 생성된다.

```markdown
# NOVA-STATE — 프로젝트명

## Current
- **Goal**: JWT → 세션 기반 전환
- **Phase**: building
- **Blocker**: none

## Recently Done
| Task | Completed | Verdict |
|------|-----------|---------|
| Sprint 1: 세션 모델 | 2026-04-01 | PASS |

## Known Gaps (미커버 영역)
| 영역 | 미커버 내용 | 우선순위 |
|------|-----------|---------|
| 동시 세션 제한 | 미구현 | Medium |
```

- 프로젝트 루트(git root)에 위치
- 배포/테스트/스프린트/블로커/검증 결과마다 즉시 업데이트
- "ALL PASS"만 기록하지 않는다 — Known Gaps를 반드시 포함

## 블로커 분류

Nova는 문제 발견 시 심각도를 자동 분류한다.

| 분류 | 조건 | 대응 |
|------|------|------|
| **Auto-Resolve** | 되돌리기 가능 | 자동 해결 |
| **Soft-Block** | 런타임 실패 가능성 | 기록 후 계속 |
| **Hard-Block** | 데이터 손실, 보안, 사용자 오판단 유발 | **즉시 중단**, 사용자 판단 요청 |

코드 리뷰 시 추가 기준:
- 런타임 크래시 유발 → Hard-Block
- 데이터 손상/무결성 위반 → Hard-Block
- 사용자 오판단 유발 (잘못된 금액/상태 표시) → Hard-Block
- 같은 실패 2회 반복 → 블로커 분류 강제

## Nova가 잡아내는 것

CI에서 의도적 결함이 주입된 코드를 대상으로 [자가 검증 테스트](tests/test-self-verify.sh)를 실행한다:

| 결함 | 유형 | 탐지 방법 |
|------|------|----------|
| `GET /api/auth/me` 엔드포인트 누락 | 설계-구현 갭 | 설계 문서 vs 라우트 핸들러 diff |
| 비밀번호 평문 저장 | 보안 | 설계는 bcrypt 요구, 코드에 해싱 없음 |
| 이메일 중복 체크 누락 (409) | 검증 계약 불이행 | 설계에 409 명시, 코드에 처리 없음 |
| JWT 시크릿 키 하드코딩 | 보안 패턴 | 정적 분석: 문자열 리터럴 |

## API 키 (선택)

`/nova:ask`(다관점 수집)만 API 키가 필요하다. 나머지는 전부 API 키 없이 동작한다.

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

### Codex CLI (Beta)

Nova는 [Codex CLI](https://github.com/openai/codex) 사용자를 위한 별도 매니페스트를 제공한다. Phase 1에서는 스킬(7종)과 MCP를 사용할 수 있다.

```bash
# 1) Codex 플러그인 디렉토리에 클론
git clone https://github.com/TeamSPWK/nova.git ~/.agents/plugins/nova

# 2) MCP 서버 빌드
cd ~/.agents/plugins/nova/mcp-server && pnpm install && pnpm build

# 3) Codex CLI의 `/plugins` 커맨드로 활성화하거나,
#    `~/.agents/plugins/marketplace.json`에 Nova 엔트리를 수동 등록
```

> **주의**: `session-start.sh` 훅(10개 자동 적용 규칙)은 Claude Code 전용 기능으로 **Codex CLI에서는 동작하지 않는다**. 슬래시 커맨드(`/nova:*`)와 전문 에이전트도 Phase 1에서는 사용 불가. 세션 시작 시 `docs/nova-rules.md`를 수동으로 첨부해 규칙을 적용한다.

**MCP 수동 등록 (폴백 — 번들된 `.codex-plugin/.mcp.json`이 자동 로드되지 않을 경우):**

```toml
# ~/.codex/config.toml
[mcp_servers.nova]
command = "node"
args = ["/절대경로/nova/mcp-server/dist/index.js"]
```

## FAQ

### Nova를 쓰지 말아야 할 때는?

- **한 줄 수정**: 오타, 버전 범프 — CPS 불필요
- **원인이 명확한 버그**: 스택 트레이스가 원인을 가리키면 바로 수정
- **버릴 프로토타입**: 검증 프로세스 스킵
- **30분 이내 작업**: 사이클이 작업보다 오래 걸리면 오버헤드

**기준**: 변경 사항 전체를 머릿속에 담을 수 있으면 Nova가 필요 없다.

### `/nova:ask` 다관점 합의가 틀릴 수 있나?

그렇다. Claude, GPT, Gemini는 학습 데이터를 상당 부분 공유한다. 세 모델이 동의해도 공유된 맹점일 수 있다. 최종 결정은 항상 사람의 몫이다.

### AI 오케스트레이터와 어떻게 함께 쓰나?

Nova는 Quality Gate — 검증만 한다. 오케스트레이터가 만들고, Nova가 검증한다. Claude Code의 하네스 레이어를 통해 그 루프 안의 검문소 역할을 한다.

### MCP 서버는 뭔가?

MCP 서버는 어느 Claude Code 세션에서든 Nova의 규칙과 오케스트레이션 가이드에 접근할 수 있게 한다 — Nova가 플러그인으로 설치되지 않은 프로젝트에서도. 로컬에서 항상 사용 가능한 "Nova의 두뇌"다.

### "하네스 엔지니어링"이란?

프롬프트 엔지니어링이 모델이 *무엇을 말하는지*를 다룬다면, 하네스 엔지니어링은 모델이 *언제, 어떤 규칙으로, 어떤 도구로 실행되는지*를 다룬다 — 훅, 플러그인, 커맨드, 에이전트를 활용해서. Nova는 하네스 엔지니어링 도구다: 프롬프트 조작이 아니라 Claude Code의 플러그인 시스템을 통해 AI 행동을 통제한다.

## 문서

- [사용법 가이드](docs/usage-guide.md) — 커맨드, 에이전트 상세 사용법
- [Nova Engineering](docs/nova-engineering.md) — 방법론 상세 (4 Pillars, CPS, 보안)
- [튜토리얼: Todo API](examples/tutorial-todo-api.md) — 전체 워크플로우 체험

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- API 키: OpenAI + Google AI Studio (선택, `/nova:ask`만 필요)

## 라이선스

MIT — [Spacewalk Engineering](https://spacewalk.tech)
