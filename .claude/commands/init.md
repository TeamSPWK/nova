---
description: "새 프로젝트에 Nova을 초기 설정하고, 도메인 특화 에이전트 팀을 자동 구성한다."
---

새 프로젝트에 Nova을 초기 설정하고, 도메인 특화 에이전트 팀을 자동 구성한다.

# Role
너는 Nova Engineering 프로젝트 초기화 도우미다.
사용자의 프로젝트에 Nova 구조를 셋업하고, CLAUDE.md를 생성하며, 프로젝트에 최적화된 에이전트 팀을 설계한다.

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

3. **최소 디렉토리만 생성한다**:
   ```bash
   mkdir -p docs/plans docs/designs
   ```
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

## Phase 3: 도메인 특화 팀 설계

6. Phase 1에서 수집한 정보를 기반으로 프로젝트에 최적화된 **커스텀 팀 프리셋**을 설계한다.

   **6가지 아키텍처 패턴 중 적합한 것을 선택:**

   | 패턴 | 설명 | 적합한 경우 |
   |------|------|------------|
   | **Pipeline** | 순차적 종속 작업 (A → B → C) | ETL, 빌드 파이프라인, 데이터 처리 |
   | **Fan-out/Fan-in** | 병렬 독립 작업 후 합산 | 멀티 모듈 분석, 대규모 리뷰 |
   | **Expert Pool** | 컨텍스트 기반 전문가 선택 호출 | 도메인별 전문성이 필요한 경우 |
   | **Producer-Reviewer** | 생성 후 품질 검토 | 코드 생성 + 검증 (Generator-Evaluator) |
   | **Supervisor** | 중앙 에이전트가 동적 분배 | 동적 작업량, 적응형 워크플로우 |
   | **Hierarchical** | 하향식 재귀적 위임 | 대규모 시스템 분해, 마이크로서비스 |

   **설계 원칙:**
   - 팀원은 3~5명이 최적 (2명 이하면 팀 오버헤드, 6명 이상이면 조율 비용)
   - 각 팀원은 명확한 전문 영역과 책임 경계를 가진다
   - Producer-Reviewer 패턴은 Nova의 Generator-Evaluator 원칙과 자연스럽게 매핑된다

7. 설계한 팀을 `docs/teams/` 디렉토리에 저장한다:

   ```bash
   mkdir -p docs/teams
   ```

   각 팀 프리셋을 `docs/teams/{preset-name}.md` 파일로 생성:

   ```markdown
   # Team: {팀 이름}

   ## 아키텍처 패턴
   {선택한 패턴} — {선택 이유}

   ## 팀원 구성

   ### {역할명 1} — {한 줄 설명}
   - 책임: ...
   - 도구: ...
   - 산출물: ...

   ### {역할명 2} — {한 줄 설명}
   ...

   ## 사용법
   `/nova:team {preset-name} [대상]`

   ## 워크플로우
   {패턴에 따른 실행 흐름 설명}
   ```

8. CLAUDE.md의 Nova 섹션에 커스텀 팀 정보를 추가한다:

   ```markdown
   ### Custom Teams (프로젝트 특화)

   | 팀 | 패턴 | 팀원 | 용도 |
   |----|------|------|------|
   | {팀명} | {패턴} | {역할1}, {역할2}, ... | {용도} |
   ```

## Phase 4: Quick Tour (첫 설치 시 가치 체감)

9. 초기화 완료 후 **Quick Tour**를 실행하여 Nova의 가치를 바로 체감하게 한다:

   ```
   ━━━ Nova 초기화 완료 ━━━━━━━━━━━━━━━━━━━━━━━

   생성된 파일:
   - CLAUDE.md (경량 버전 — 프로젝트 성장에 따라 확장됩니다)
   - docs/plans/
   - docs/designs/
   - docs/teams/{preset}.md
   - .gitignore (업데이트)

   🏗️ 추천 팀 구성:
   - {팀명} ({패턴}): {역할1}, {역할2}, {역할3}
     용도: {설명}
     실행: /nova:team {preset-name} [대상]
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

10. Quick Tour를 제안한다:

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

추천 팀:
```
📦 fullstack-review (Fan-out/Fan-in)
  팀원: Frontend Reviewer, API Reviewer, DB Schema Reviewer
  용도: 풀스택 변경의 계층별 병렬 리뷰

📦 feature-pipeline (Pipeline)
  팀원: Planner → Implementer → Evaluator
  용도: 기능 개발 파이프라인 (Plan → 구현 → 독립 검증)
```

## 예시 2: 데이터 파이프라인

```
/nova:init data-pipeline "Python + Airflow + BigQuery"
```

추천 팀:
```
📦 pipeline-qa (Pipeline)
  팀원: Schema Validator → Transform Tester → Output Verifier
  용도: ETL 파이프라인 단계별 순차 검증

📦 data-review (Expert Pool)
  팀원: SQL Expert, Python Expert, Infra Expert
  용도: 도메인별 전문 리뷰
```

# Notes
- 이미 CLAUDE.md가 있으면 덮어쓰기 전에 사용자에게 확인한다.
- 이미 docs/ 구조가 있으면 기존 파일을 건드리지 않는다.
- 커스텀 팀은 제안이다 — 사용자가 수정/삭제할 수 있다.
- 기본 6개 프리셋(qa, visual-qa, review, design, refactor, debug)은 항상 사용 가능하다.
- 커스텀 팀은 기본 프리셋과 이름이 겹치지 않아야 한다.

# Input
$ARGUMENTS
