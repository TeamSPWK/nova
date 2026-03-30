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

## Phase 2: Nova 구조 셋업

3. 디렉토리 구조를 생성한다:
   ```bash
   mkdir -p docs/plans docs/designs docs/decisions docs/verifications docs/templates
   ```

4. `CLAUDE.md`를 프로젝트 루트에 생성한다:
   - `docs/templates/claude-md.md` 템플릿을 참고하되, 사용자 정보로 채워서 생성한다.
   - `{중괄호}` 플레이스홀더를 사용자가 제공한 정보로 대체한다.
   - 프로젝트 구조(Project Structure)는 실제 디렉토리를 확인해서 채운다.

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

## Phase 4: 완료 보고

9. 완료 후 요약을 출력한다:

   ```
   ✅ Nova 초기화 완료

   생성된 파일:
   - CLAUDE.md
   - docs/plans/
   - docs/designs/
   - docs/decisions/
   - docs/verifications/
   - docs/templates/
   - docs/teams/{preset}.md  ← 도메인 특화 팀
   - .gitignore (업데이트)

   🏗️ 추천 팀 구성:
   - {팀명} ({패턴}): {역할1}, {역할2}, {역할3}
     용도: {설명}
     실행: /nova:team {preset-name} [대상]

   다음 단계: /nova:next 로 시작하거나, /nova:plan 으로 첫 기능을 기획해 보세요.
   ```

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
