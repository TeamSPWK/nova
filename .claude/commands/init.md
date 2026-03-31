---
description: "새 프로젝트에 Nova Quality Gate를 초기 설정하고, 도메인 특화 에이전트를 자동 구성한다."
---

새 프로젝트에 Nova Quality Gate를 초기 설정하고, 도메인 특화 에이전트를 자동 구성한다.

# Role
너는 Nova Quality Gate 프로젝트 초기화 도우미다.
사용자의 프로젝트에 Nova 구조를 셋업하고, CLAUDE.md를 생성하며, 프로젝트에 최적화된 커스텀 에이전트를 설계한다.

# Execution

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
   - `NOVA-STATE.md`를 프로젝트 루트에 생성한다 (`docs/templates/nova-state.md` 템플릿 사용)
   - 이 파일이 세션 간 컨텍스트 연속성의 핵심 진입점이 된다
   > `docs/decisions`, `docs/verifications`, `docs/templates`는 처음에 생성하지 않는다.
   > 이후 `/nova:gap` 실행 시 → "검증 결과를 저장할 `docs/verifications/`를 생성할까요?"
   > `/nova:propose` 실행 시 → "의사결정 기록을 위한 `docs/decisions/`를 생성할까요?"
   > 이런 식으로 **필요 시점에 제안**한다.

4. `CLAUDE.md`를 프로젝트 루트에 **경량 버전**으로 생성한다:
   - `docs/templates/claude-md.md` 템플릿의 **필수 섹션만** 포함: Language, Nova Engineering (자동 적용 규칙), Tech Stack, Conventions, Credentials
   - 선택 섹션(Project Structure, Human-AI Boundary 등)은 생략하고, CLAUDE.md 하단에 안내만 남긴다:
     ```markdown
     <!-- 프로젝트가 커지면 /nova:next가 추가 섹션을 제안합니다 -->
     ```
   - `{중괄호}` 플레이스홀더를 사용자가 제공한 정보로 대체한다.

5. `.gitignore`에 다음 항목을 추가한다 (이미 있으면 스킵):
   ```
   # Nova Engineering
   .env
   .secret/
   *.pem
   *accessKeys*
   ```

## Phase 3: 도메인 특화 커스텀 에이전트 설계

6. Phase 1에서 수집한 정보를 기반으로 프로젝트에 최적화된 **커스텀 에이전트**를 설계한다.
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

7. 초기화 완료 후 **Quick Tour**를 실행하여 Nova의 가치를 바로 체감하게 한다:

   ```
   ━━━ Nova 초기화 완료 ━━━━━━━━━━━━━━━━━━━━━━━

   생성된 파일:
   - CLAUDE.md (경량 버전 — 프로젝트 성장에 따라 확장됩니다)
   - docs/plans/
   - docs/designs/
   - .gitignore (업데이트)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

8. Quick Tour를 제안한다:

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
- 이미 CLAUDE.md가 있으면 덮어쓰기 전에 사용자에게 확인한다.
- 이미 docs/ 구조가 있으면 기존 파일을 건드리지 않는다.
- 커스텀 에이전트는 제안이다 — 사용자가 수정/삭제할 수 있다.
- Nova 기본 에이전트(architect, senior-dev, qa-engineer, security-engineer, devops-engineer)와 이름이 겹치지 않아야 한다.
- 오케스트레이션(팀 조직, 스케줄링)은 Paperclip 등 외부 도구에 위임한다.

# Input
$ARGUMENTS
