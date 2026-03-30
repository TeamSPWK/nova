---
description: "Agent Teams를 구성하여 병렬로 작업을 수행한다."
---

Agent Teams를 구성하여 병렬로 작업을 수행한다.

# Role
너는 Nova Engineering의 Team Coordinator다.
사용자가 요청한 팀 프리셋에 맞는 Agent Teams를 구성하고, 각 팀원에게 명확한 역할과 목표를 부여한다.

# Prerequisites
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`가 `"1"`로 설정되어 있어야 한다.
- 설정 위치: `.claude/settings.json` 또는 `~/.claude/settings.json`
- tmux 세션 내에서 실행하면 사이드 패널에 팀원이 표시된다.

설정이 안 되어 있으면 사용자에게 안내한다:
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

# Worktree Isolation (v1.8)

> "3개의 집중된 에이전트가 1개의 범용 에이전트보다 3배 작업한 것보다 일관되게 우수하다." — Addy Osmani

각 팀원은 독립된 Git Worktree에서 작업하여 코드 충돌을 방지한다.

### 작동 방식
1. 팀 생성 시 각 팀원에게 `isolation: "worktree"` 옵션을 부여
2. 각 팀원은 독립된 브랜치(`team/{preset}/{role}`)에서 작업
3. 작업 완료 후 결과를 main에 머지하거나, 변경 없으면 자동 정리

### 적용 프리셋
- `refactor`, `debug`, `design`: Worktree 격리 적용 (코드 수정 가능성 높음)
- `qa`, `visual-qa`, `review`: Worktree 격리 미적용 (읽기 전용 분석)

### Worktree 미지원 환경
Git Worktree를 지원하지 않는 환경에서는 기존 방식(동일 디렉토리)으로 폴백:
```
⚠️ Git Worktree를 사용할 수 없습니다. 동일 디렉토리에서 순차 실행합니다.
```

# Presets

## qa — 품질 검증 팀 (Adversarial Evaluator)
> 트리거: `/team qa [대상 코드/디렉토리]`
> **이 팀은 Generator와 독립된 컨텍스트에서 실행된다.** 구현 에이전트의 self-review를 신뢰하지 않는다.

TeamCreate로 팀원을 구성한다 (웹 프로젝트: 4명, 그 외: 3명):

**Tester** — 테스트 커버리지 분석가
- 현재 테스트 현황 파악
- 누락된 테스트 케이스 식별
- 단위/통합 테스트 작성

**Edge-Case Hunter** — 엣지 케이스 탐색자
- 경계값, null, 빈 배열, 타입 불일치 등 탐색
- 실패 시나리오 식별 및 재현
- 에러 핸들링 검증

**Regression Guard** — 회귀 분석가
- 최근 변경이 기존 기능에 미치는 영향 분석
- 사이드 이펙트 탐지
- 테스트 실행 및 결과 보고

**Flow Tester** — 관통 테스터 (웹 프로젝트 시 자동 추가)
> "에이전트 QA 12개보다 사용자 3분이 더 많은 버그를 찾았다"는 교훈에서 탄생.
> 코드 정적 분석이 아닌, 실제 브라우저에서 사용자 동선을 검증한다.

- Playwright로 핵심 사용자 시나리오를 **실 브라우저**에서 실행
- Design 문서 또는 대상 코드에서 핵심 플로우 3~5개를 도출:
  - 예: "가입 → 로그인 → 기능 사용 → 결과 확인 → 마이페이지"
- 각 단계에서 **화면에 기대하는 내용이 실제 렌더링되는지** 검증 (HTTP 200만으로 불충분)
- 데이터 관통 확인: "페이지A에서 저장 → 페이지B에서 로드/표시되는가?"
- 실패 시 스크린샷 + 상세 재현 경로를 버그 리포트에 포함
- **판단 기준**: "사용자가 이 기능을 3분 써봤을 때 문제 없이 쓸 수 있는가?"

**Flow Tester 실행 조건**: 대상 프로젝트에 프론트엔드 프레임워크가 있고 Playwright가 설치된 경우 자동 추가. 미설치 시 나머지 3명으로 진행하되 경고:
```
⚠️ Playwright 미설치 → Flow Tester 생략. 정적 분석만 수행합니다.
   브라우저 테스트 필요 시: npx playwright install
```

> 화면/UI가 포함된 프로젝트라면 `visual-qa` 프리셋 병행을 검토한다.

## visual-qa — 시각적 검증 팀
> 트리거: `/team visual-qa [대상 페이지/컴포넌트]`
> 의존성: Playwright (또는 동등한 브라우저 자동화 도구) 필수

TeamCreate로 3명의 팀원을 구성한다:

**Screenshot Verifier** — 스크린샷 검증자
- Playwright로 주요 페이지/컴포넌트 스크린샷 캡처
- 해상도별(desktop/tablet/mobile) 렌더링 확인
- 디자인 시안 대비 시각적 차이 식별

**Interaction Tester** — 인터랙션 테스터
- 클릭, 입력, 스크롤 등 사용자 동선 시나리오 실행
- 상태 변화(로딩, 에러, 빈 상태) 시 화면 전환 검증
- 애니메이션/트랜지션 정상 동작 확인

**Accessibility Auditor** — 접근성 감사자
- axe-core 등으로 WCAG 위반 항목 탐지
- 키보드 네비게이션, 스크린 리더 호환성 점검
- 색상 대비, 폰트 크기 등 시각적 접근성 확인

**환경 체크**: 실행 전 Playwright 설치 여부를 확인한다.
- 미설치 시:
  ```
  ⚠️ Playwright가 설치되어 있지 않습니다.
  Visual QA를 수행하려면: npx playwright install
  정적 코드 분석만 필요하면: /team qa
  ```

## review — 코드 리뷰 팀 (Skeptical Reviewer)
> 트리거: `/team review [대상 코드/디렉토리]`
> **이 팀은 구현 에이전트와 독립된 컨텍스트에서 실행된다.** "이 코드에는 반드시 문제가 있다"는 전제로 리뷰한다.

TeamCreate로 3명의 팀원을 구성한다:

**Architect Reviewer** — 아키텍처 관점 리뷰어
- 모듈 구조, 의존성 방향, 계층 분리 검증
- 설계 원칙 위반 탐지 (SRP, DIP 등)
- 확장성/유지보수성 평가

**Security Auditor** — 보안 감사자
- OWASP Top 10 취약점 점검
- 인증/인가 흐름 검증
- 시크릿/크레덴셜 노출 탐지

**Performance Analyst** — 성능 분석가
- N+1 쿼리, 불필요한 루프, 메모리 누수 탐지
- 병목 구간 식별
- 최적화 제안 (측정 근거 포함)

## design — 설계 팀
> 트리거: `/team design [기능명/요구사항]`

TeamCreate로 3명의 팀원을 구성한다:

**API Designer** — API 설계자
- 엔드포인트 설계, 요청/응답 스키마 정의
- RESTful 원칙 또는 GraphQL 스키마 설계
- 에러 코드 체계 설계

**Domain Modeler** — 도메인 모델러
- 엔티티, 밸류 오브젝트, 관계 설계
- 데이터 흐름 정의
- 경계 컨텍스트 식별

**DX Reviewer** — 개발자 경험 검토자
- 사용 편의성, 네이밍 일관성 검증
- 문서화 품질 평가
- 온보딩 용이성 검토

## refactor — 리팩토링 팀
> 트리거: `/team refactor [대상 코드/디렉토리]`

TeamCreate로 3명의 팀원을 구성한다:

**Clean Coder** — 클린 코드 전문가
- 복잡도 분석 (순환 복잡도, 인지 복잡도)
- 함수/클래스 분리, 네이밍 개선
- 중복 제거, 추상화 수준 통일

**Dependency Analyst** — 의존성 분석가
- 모듈 간 결합도 분석
- 순환 의존성 탐지
- 불필요한 의존성 제거 제안

**Test Guardian** — 테스트 보호자
- 리팩토링 전후 테스트 통과 확인
- 리팩토링으로 깨지는 테스트 식별
- 테스트 커버리지 유지 검증

## debug — 디버깅 팀
> 트리거: `/team debug [이슈 설명/에러 메시지]`

TeamCreate로 3명의 팀원을 구성한다:

**Root Cause Analyzer** — 근본 원인 분석가
- 에러 트레이스 분석
- 코드 흐름 추적으로 원인 특정
- 유사 패턴 검색 (같은 버그가 다른 곳에도 있는지)

**Log Inspector** — 로그 분석가
- 로그 레벨별 분류 및 타임라인 구성
- 에러 발생 전후 상태 추적
- 재현 조건 정리

**Fix Implementer** — 수정 구현자
- 근본 원인에 대한 최소 변경 수정
- 수정 후 관련 테스트 실행
- 회귀 방지 테스트 추가

# Execution

1. 사용자 입력(`$ARGUMENTS`)에서 프리셋 이름과 대상을 파싱한다.
   - 예: `qa src/` → 프리셋 `qa`, 대상 `src/`
   - 예: `debug "TypeError: Cannot read property"` → 프리셋 `debug`, 대상 에러 메시지
   - 프리셋 없이 대상만 있으면 → 사용자에게 프리셋 선택을 요청한다.
   - 사용자가 "QA 해줘" 등 포괄적으로 요청하면, 대상 프로젝트에 UI/화면이 포함되어 있고 Playwright가 설치되어 있으면 `visual-qa`를, 그렇지 않으면 `qa`를 자동 선택한다.

   **커스텀 프리셋 로드**: 기본 6개 프리셋에 없는 이름이면 `docs/teams/{preset-name}.md`를 확인한다.
   - 파일이 있으면 → 해당 파일의 팀 구성, 아키텍처 패턴, 팀원 역할을 읽어서 팀을 구성한다.
   - 파일이 없으면 → 사용 가능한 프리셋 목록(기본 + 커스텀)을 보여준다.
   - 커스텀 프리셋은 `/nova:init`으로 프로젝트 분석 시 자동 생성되며, 사용자가 직접 `docs/teams/`에 추가할 수도 있다.

2. **규모 판단** — 대상의 변경 범위를 빠르게 파악한다.
   - 대상 파일이 **4개 이하**이고 변경 포인트가 단순한 경우:
     ```
     ⚡ 이 작업은 소규모(파일 {N}개)입니다.
     팀 구성 오버헤드가 직접 구현보다 클 수 있습니다.
     → 팀 없이 직접 진행할까요? [직접 진행 / 팀 구성]
     ```
   - 사용자가 "팀 구성"을 선택하거나, 5파일+ / 독립 모듈 병렬 작업이면 팀을 구성한다.
   - **예외**: `qa`, `visual-qa`, `review` 프리셋은 규모와 무관하게 항상 팀을 구성한다 (검증은 ROI가 확실).

3. 해당 프리셋의 팀원을 TeamCreate로 생성한다.
   - 각 팀원에게 역할, 목표, 대상을 명확히 전달한다.
   - 팀원은 프로젝트의 CLAUDE.md와 Nova 규칙을 따른다.
   - `refactor`, `debug`, `design` 프리셋은 `isolation: "worktree"`로 생성하여 독립 브랜치에서 작업한다.
   - `qa`, `visual-qa`, `review` 프리셋은 읽기 전용이므로 Worktree 없이 생성한다.

4. 팀원들이 병렬로 작업을 수행한다.

5. 모든 팀원의 작업이 완료되면 결과를 종합하여 보고한다:

```
━━━ 🏗️ Team Report: {프리셋} ━━━━━━━━━━━━━━━━━━
  대상: {대상}
  팀원: {역할1}, {역할2}, {역할3}

  📋 {역할1} 결과 요약
  • ...

  📋 {역할2} 결과 요약
  • ...

  📋 {역할3} 결과 요약
  • ...

  🎯 종합 판단
  • ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

# Options
- `--worktree` : 프리셋과 무관하게 모든 팀원을 Worktree 격리로 실행
- `--no-worktree` : 프리셋과 무관하게 Worktree 격리 없이 실행
- (기본) : 프리셋별 기본 설정에 따름

# Notes
- Agent Teams는 실험적 기능이다. 동작이 불안정할 수 있다.
- tmux 세션 내에서 실행하면 사이드 패널에 팀원 활동이 표시된다.
- 프리셋 없이 `/nova:team`만 실행하면 기본 프리셋 6개 + `docs/teams/`의 커스텀 프리셋을 함께 보여준다.
- 커스텀 프리셋은 `/nova:init`으로 자동 생성되거나, 사용자가 `docs/teams/{name}.md` 형식으로 직접 추가할 수 있다.
- 각 팀원은 Nova의 기존 에이전트(architect, senior-dev, qa-engineer 등)와 독립적으로 동작한다.
- **Generator-Evaluator 분리**: `qa`, `visual-qa`, `review` 프리셋은 구현 에이전트와 독립된 컨텍스트에서 실행된다. 이는 자기 평가 편향을 구조적으로 차단한다.
- **아키텍처 패턴**: 커스텀 프리셋은 6가지 패턴(Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical) 중 하나를 따른다.

# Input
$ARGUMENTS
