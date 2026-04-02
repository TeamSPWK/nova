---
description: "새 프로젝트에 Nova Quality Gate를 초기 설정하거나, 기존 프로젝트의 갭을 자동 보완한다 (--upgrade)."
---

새 프로젝트에 Nova Quality Gate를 초기 설정하거나, 기존 프로젝트의 갭을 자동 보완한다.

# Role
너는 Nova Quality Gate 프로젝트 초기화 및 업그레이드 도우미다.
새 프로젝트에는 Nova 구조를 셋업하고, 기존 프로젝트에는 갭을 진단하여 보완한다.

# Mode 판별

| 조건 | 모드 | 동작 |
|------|------|------|
| `--upgrade` 플래그 | **Upgrade** | `/metrics` 실행 → 미충족 항목만 보완 |
| CLAUDE.md + NOVA-STATE.md 이미 존재 | **Upgrade** (자동 전환) | 초기화 건너뛰고 갭 보완 |
| 위 해당 없음 | **Init** (기본) | 처음부터 셋업 |

> `--upgrade`는 "이미 Nova를 쓰고 있지만 빠진 부분을 채우고 싶을 때" 사용한다.
> 기존 프로젝트에서 `/init`을 실행하면 자동으로 Upgrade 모드로 전환된다.

## Upgrade 모드 실행 흐름

1. `/metrics`와 동일한 17개 항목을 점검한다
2. **미충족 항목만** 목록으로 표시한다:
   ```
   ━━━ Nova Upgrade — 갭 진단 ━━━━━━━━━━━━━━━━
     현재: 12/20 (Level 3)

     보완 가능 항목:
     [ ] S3 — Design 문서 없음 → /design 실행 필요
     [ ] I3 — 컨텍스트 체인 없음 → 자동 생성 가능
     [ ] I4 — 의사결정 기록 없음 → docs/decisions/ 생성 가능
     [ ] X2 — 다관점 수집 결과 없음 → /xv 실행 필요

     자동 보완 가능: 2건 (I3, I4)
     수동 작업 필요: 2건 (S3, X2)

     자동 보완을 진행할까요? (all / 선택: I3,I4 / skip)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
3. 사용자 승인 시 자동 보완 가능한 항목만 즉시 실행한다:
   - 디렉토리/파일 생성 (docs/decisions/, docs/templates/ 등)
   - CLAUDE.md 누락 섹션 추가
   - 컨텍스트 체인 파일 생성
4. 수동 작업 항목은 실행 가능한 커맨드를 안내한다
5. 보완 후 점수를 재계산하여 개선 결과를 표시한다:
   ```
   ━━━ Upgrade 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━
     12/20 (Level 3) → 14/20 (Level 3)
     +2점: I3 컨텍스트 체인, I4 의사결정 디렉토리
     남은 갭: S3 Design, X2 다관점 수집 결과
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

---

# Init 모드 실행 흐름 (새 프로젝트)

## Phase 1: 프로젝트 정보 수집

1. 사용자에게 기본 정보를 확인한다 (인자가 없으면 질문):
   - **프로젝트명**: 프로젝트 이름 (예: my-app)
   - **기술 스택**: 프레임워크와 언어 (예: Next.js + TypeScript)
   - **응답 언어**: Claude 응답 언어 (기본: 한국어)

2. 기존 프로젝트인 경우(`--adopt`) 코드베이스를 자동 분석한다:
   - `package.json`, `requirements.txt`, `go.mod`, `Cargo.toml` 등에서 기술 스택 탐지
   - 디렉토리 구조에서 도메인 영역 파악 (예: `src/auth/`, `src/payment/` → 인증, 결제 도메인)
   - 테스트 프레임워크 존재 여부 확인
   - CI/CD 설정 확인 (`.github/workflows/`, `Dockerfile` 등)

## Phase 2: Nova 구조 셋업 (Progressive Disclosure — 최소 시작)

> **원칙**: 처음부터 완벽한 구조를 강제하지 않는다. 최소한의 CLAUDE.md만 생성하고, 나머지는 프로젝트가 성장하며 필요할 때 제안한다.

3. **최소 디렉토리와 상태 파일을 생성한다**:
   ```bash
   mkdir -p docs/plans docs/designs
   ```
   - `NOVA-STATE.md`를 **프로젝트 루트(git root)**에 생성한다 (`docs/templates/nova-state.md` 템플릿 사용)
   - 이 파일이 세션 간 컨텍스트 연속성의 핵심 진입점이 된다
   - **모노레포 가드**: 생성 전 `git rev-parse --show-toplevel`로 루트를 확인하고, 루트에 이미 NOVA-STATE.md가 있으면 하위 디렉토리에 중복 생성하지 않는다. 하위 앱 디렉토리에서 실행해도 루트 기준으로 동작한다.
   > `docs/decisions`, `docs/verifications`, `docs/templates`는 처음에 생성하지 않는다.
   > 이후 `/nova:gap` 실행 시 → "검증 결과를 저장할 `docs/verifications/`를 생성할까요?"
   > `/nova:propose` 실행 시 → "의사결정 기록을 위한 `docs/decisions/`를 생성할까요?"
   > 이런 식으로 **필요 시점에 제안**한다.

4. `CLAUDE.md`를 프로젝트 루트에 **경량 버전**으로 생성한다:
   - `docs/templates/claude-md.md` 템플릿의 **필수 섹션만** 포함
   - `{중괄호}` 플레이스홀더를 사용자가 제공한 정보로 대체한다.

   **CLAUDE.md 작성 베스트 프랙티스 (2026.04 기준):**

   | 원칙 | 설명 |
   |------|------|
   | **200줄 이내** | 초과 시 규칙 준수율이 떨어짐. 150줄 이하가 이상적 |
   | **강제가 아닌 컨텍스트** | CLAUDE.md는 LLM 특성상 100% 보장 불가. 보안/크레덴셜 등 필수 사항은 hooks로 강제 |
   | **빌드/테스트 명령 필수** | Claude가 코드에서 추론 불가한 핵심 명령을 반드시 포함 |
   | **코드 추론 가능한 것 제외** | 코드 스타일(린터가 처리), API 문서(코드에 있음), 파일 경로 상세(탐색 가능) |
   | **`.claude/rules/` 분리** | 특정 파일/디렉토리에만 적용되는 규칙은 rules/로 모듈화. paths frontmatter로 스코프 지정 |
   | **계층 구조 활용** | 부모 CLAUDE.md는 자동 로드, 서브디렉토리는 온디맨드. 모노레포는 루트에 공통 규칙, 패키지별 CLAUDE.md |

   **3계층 문서 구조 (권장):**

   | 계층 | 역할 | 크기 목표 | 로드 시점 |
   |------|------|----------|----------|
   | **CLAUDE.md** | 불변 원칙 + Build & Test + Credentials | 80~150줄 | 매 세션 자동 |
   | **docs/ 참조 문서** | 상세 규칙, Plan, Design, ADR | 무제한 | 자동 로드 아님 — Claude가 판단해서 읽거나 사용자가 언급 시 |
   | **.claude/rules/** | 파일/디렉토리 스코프 규칙 | 각 30줄 | 해당 파일 작업 시 |

   > "CLAUDE.md는 짧게 유지하되, 반드시 지켜야 할 규칙은 CLAUDE.md에 직접 유지한다."
   > 보충 문서는 CLAUDE.md에 "상세: docs/X.md 참조"로 링크. 단, Claude가 자동으로 읽는 것은 보장 안 됨.

   **필수 섹션:**
   - Language, Build & Test (빌드/테스트/린트 명령), Conventions (git), Credentials
   - Nova Engineering (자동 적용 규칙 — session-start.sh가 주입하므로 CLAUDE.md에서는 참조만)

   **선택 섹션 (필요 시 추가):**
   - Tech Stack, Project Structure, Human-AI Boundary → 프로젝트 성장에 따라 `/nova:next`가 제안
     ```markdown
     <!-- 프로젝트가 커지면 /nova:next가 추가 섹션을 제안합니다 -->
     ```

5. `.gitignore`에 다음 항목을 추가한다 (이미 있으면 스킵):
   ```
   # Nova Engineering
   .env
   .secret/
   *.pem
   *accessKeys*
   ```

## Phase 2.5: Agent Teams 환경 확인

6. 에이전트를 설계하기 전에 **Agent Teams 설정**을 확인한다.
   Nova의 에이전트가 tmux split-pane으로 가시화되려면 다음 설정이 필요하다:

   `.claude/settings.json` (프로젝트 또는 글로벌)에서 확인:
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     },
     "teammateMode": "tmux",
     "agentTeams": {
       "display": "split-panes"
     }
   }
   ```

   - 설정이 없으면 사용자에게 안내한다:
     ```
     ⚠️ Agent Teams 설정이 감지되지 않았습니다.
     Nova 에이전트를 tmux split-pane으로 실시간 확인하려면 위 설정이 필요합니다.
     글로벌 설정(~/.claude/settings.json)에 추가할까요?
     ```
   - 사용자가 동의하면 설정을 추가한다. 거부하면 스킵하되, 에이전트는 백그라운드로 동작함을 안내한다.
   - tmux 환경이 아니면(e.g. VS Code 터미널) 이 단계를 스킵한다.

## Phase 3: 도메인 특화 커스텀 에이전트 설계

7. Phase 1에서 수집한 정보를 기반으로 프로젝트에 최적화된 **커스텀 에이전트**를 설계한다.
   에이전트는 `.claude/agents/` 디렉토리에 마크다운 파일로 생성된다.

   **설계 원칙:**
   - 프로젝트의 주요 도메인/계층별로 1개 에이전트 (예: backend-dev, frontend-dev, worker-dev)
   - 각 에이전트는 명확한 전문 영역과 책임 경계를 가진다
   - 반드시 **qa-reviewer** 에이전트를 포함한다 — Nova Quality Gate의 검증 역할
   - 에이전트는 3~5개가 최적
   - 오케스트레이션(팀 조직, 병렬 실행)은 외부 오케스트레이터(Paperclip 등)에 위임한다

   각 에이전트 파일에는 다음을 포함한다:
   ```markdown
   ---
   name: {에이전트명}
   description: {한줄 설명}
   model: sonnet  # 또는 haiku (qa-reviewer는 비용 효율을 위해 haiku 권장)
   ---
   # Role
   {역할 설명}
   # Scope
   {담당 디렉토리/파일 범위}
   # Rules
   {도메인 특화 규칙}
   ```

## Phase 4: Quick Tour (첫 설치 시 가치 체감)

8. 초기화 완료 후 **Quick Tour**를 실행하여 Nova의 가치를 바로 체감하게 한다:

   ```
   ━━━ Nova 초기화 완료 ━━━━━━━━━━━━━━━━━━━━━━━

   생성된 파일:
   - CLAUDE.md (경량 버전 — 프로젝트 성장에 따라 확장됩니다)
   - docs/plans/
   - docs/designs/
   - .gitignore (업데이트)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

9. Quick Tour를 제안한다:

    ```
    🚀 Quick Tour — Nova가 뭘 하는지 30초 안에 보여드립니다.

    1️⃣ /nova:next  → 프로젝트 상태를 분석하고 다음 할 일을 추천합니다
    2️⃣ /nova:review src/  → 기존 코드에서 숨겨진 문제를 찾아냅니다
    3️⃣ /nova:plan 기능명  → 첫 기능의 CPS Plan을 작성합니다

    → 어떤 걸 먼저 해볼까요? (또는 그냥 작업을 시작하셔도 됩니다 — Nova가 자동으로 따라갑니다)
    ```

    > 사용자가 투어를 건너뛰면 강제하지 않는다. "그냥 작업을 시작하셔도 됩니다"가 핵심.

# Examples

## 예시 1: Next.js SaaS 프로젝트

```
/nova:init --adopt my-saas "Next.js + Supabase"
```

분석 결과:
- 프론트엔드(React) + 백엔드(API Routes) + DB(Supabase) 3계층 구조
- 인증, 결제, 대시보드 3개 도메인

추천 에이전트:
```
📁 .claude/agents/
  ├── frontend-dev.md   — React/Next.js UI 개발 (apps/web/)
  ├── api-dev.md        — API Routes + Supabase 연동 (apps/api/)
  ├── qa-reviewer.md    — 풀스택 품질 검증 (전체)
  └── infra-dev.md      — 배포/인프라 관리
```

## 예시 2: 데이터 파이프라인

```
/nova:init data-pipeline "Python + Airflow + BigQuery"
```

추천 에이전트:
```
📁 .claude/agents/
  ├── pipeline-dev.md   — Airflow DAG + Transform 로직
  ├── sql-dev.md        — BigQuery 스키마 + 쿼리 최적화
  ├── qa-reviewer.md    — 데이터 품질 + 파이프라인 검증
  └── infra-dev.md      — GCP 인프라 + Docker 관리
```

# Notes
- 이미 `.claude/rules/`가 존재하는 경우, Nova 규칙과의 관계를 안내한다:
  ```
  ℹ️ 기존 .claude/rules/가 감지되었습니다.
  프로젝트 규칙(.claude/rules/)이 Nova 규칙보다 우선 적용됩니다.
  Nova는 프로젝트 규칙에 없는 품질 게이트(검증 분리, 복잡도 판단 등)를 보완합니다.
  충돌하는 규칙이 있으면 .claude/rules/ 쪽을 따릅니다.
  ```
- **모노레포**: NOVA-STATE.md와 CLAUDE.md는 항상 git root에 생성한다. `apps/`, `packages/` 등 하위 디렉토리에서 실행해도 루트 기준으로 동작하며, 하위에 중복 생성하지 않는다.
- 이미 CLAUDE.md가 있으면 덮어쓰기 전에 사용자에게 확인한다.
- 이미 docs/ 구조가 있으면 기존 파일을 건드리지 않는다.
- 커스텀 에이전트는 제안이다 — 사용자가 수정/삭제할 수 있다.
- Nova 기본 에이전트(architect, senior-dev, qa-engineer, security-engineer, devops-engineer)와 이름이 겹치지 않아야 한다.
- 오케스트레이션(팀 조직, 스케줄링)은 Paperclip 등 외부 도구에 위임한다.

# Input
$ARGUMENTS
