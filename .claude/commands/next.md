---
description: "현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다."
---

현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다.

# Role
너는 Nova Engineering의 워크플로우 가이드다.
프로젝트의 현재 상태를 분석하여 Nova 워크플로우에서 다음 단계를 추천한다.

# Execution

0. **NOVA-STATE.md 확인 및 자동 생성**:
   - 프로젝트 루트의 `NOVA-STATE.md` 파일을 읽는다
   - **파일이 없으면**: 아래 진단(Step 1-2) 결과를 기반으로 `NOVA-STATE.md`를 자동 생성한다
     - `git log --oneline -10`으로 최근 작업 방향 파악
     - `docs/plans/`, `docs/designs/`, `docs/verifications/` 스캔
     - 결과를 다음 템플릿으로 생성:
       ```markdown
       # Nova State

       ## Current
       - **Goal**: {진단에서 추론한 현재 목표}
       - **Phase**: {planning|building|verifying|done 중 추론}
       - **Blocker**: none

       ## In Progress
       | Task | Owner | Started | Status |
       |------|-------|---------|--------|

       ## Recently Done (최근 3개만)
       | Task | Completed | Verdict | Ref |
       |------|-----------|---------|-----|

       ## Next Actions (최대 3개)
       1. [ ] {추천 액션}

       ## Refs
       - Plan: {docs/plans/xxx.md 또는 none}
       - Design: {docs/designs/xxx.md 또는 none}
       - Last Verification: {docs/verifications/xxx.md 또는 none}
       ```
     - 생성 후 사용자에게 "📋 NOVA-STATE.md를 자동 생성했습니다." 안내
   - **파일이 있으면**: 읽고 상태 기반 추천
     - Blocker가 있으면 → 블로커 해결을 최우선 추천
     - In Progress 작업이 있으면 → 해당 작업 이어가기 추천
     - Phase가 `verifying`이면 → `/gap` 또는 `/review` 추천
     - Phase가 `done`이면 → "새 기능 시작 준비 완료" 표시

1. Nova 업데이트 체크:
   - `scripts/.nova-version` 파일에서 로컬 버전을 읽는다.
   - `curl -fsSL --max-time 3 https://raw.githubusercontent.com/TeamSPWK/nova/main/scripts/.nova-version 2>/dev/null` 으로 최신 버전을 확인한다.
   - 버전이 다르면 진단 결과 하단에 업데이트 안내를 표시한다:
     `🔄 Nova 업데이트 가능 (현재 → 최신) — /nova-update 를 실행하세요.`
   - 확인 실패 시 조용히 건너뛴다. (네트워크 오류를 에러로 표시하지 않는다)

2. 다음 항목을 모두 확인한다:
   - `docs/plans/` 디렉토리의 .md 파일 목록과 개수
   - `docs/designs/` 디렉토리의 .md 파일 목록과 개수
   - `docs/verifications/` 디렉토리의 .md 파일 목록과 개수
   - `docs/decisions/` 디렉토리의 .md 파일 목록과 개수
   - `git log --oneline -10` — 최근 커밋 10개
   - `git status` — 커밋되지 않은 변경사항
   - `git diff --name-only HEAD~5..HEAD 2>/dev/null` — 최근 변경된 파일

2. 아래 워크플로우 로직을 순서대로 적용하여 첫 번째 해당 항목을 추천한다:

   **복잡도 판단 (먼저 수행):**
   최근 커밋과 변경 파일을 분석하여 현재 작업의 복잡도를 판단한다.
   - 간단 (1~2 파일, 버그 수정, 명확한 변경) → "이 작업은 Plan 없이 바로 진행해도 됩니다." 라고 명시
   - 보통 이상 → 아래 워크플로우 로직 적용

   a. Plan이 하나도 없다 → `/plan` 추천
      "새 기능을 시작하려면 먼저 CPS Plan을 작성하세요."

   b. Plan은 있지만 Design이 없다 → `/design` 추천
      "Plan이 준비되었습니다. 기술 설계를 진행하세요."

   c. Design이 있고 최근 코드 커밋이 있지만 Verification이 없다 → `/gap` 추천
      "구현이 진행되었습니다. 설계 대비 누락을 확인하세요."

   d. Verification이 있고 이슈가 발견된 상태다 (verification 파일 내용에 FAIL/미완/TODO 등) → 수정 후 `/gap` 재실행 추천
      "검증에서 이슈가 발견되었습니다. 수정 후 재검증하세요."

   e. Verification이 완료되고 이슈가 없다 → `/review` 추천
      "검증이 완료되었습니다. 코드 품질을 점검하세요."

   f. Review까지 완료된 흔적이 있다 (최근 커밋에 review/refactor 관련 메시지) → `/propose` 추천
      "리뷰가 완료되었습니다. 반복 패턴이 있으면 규칙화하세요."

   g. 위 어디에도 해당하지 않는다 → "All clear! 다음 기능을 시작할 준비가 되었습니다."

3. 다음 형식으로 한국어 출력한다:

```
🎯 추천: /command 설명

📊 프로젝트 진단:
  Plans:         N개 (최근: filename.md)
  Designs:       N개
  Verifications: N개
  Decisions:     N개
  최근 커밋:     N개 (마지막: commit message)

💡 이유: 한 줄 설명

⏭️ 이후 흐름: command1 → command2 → command3
```

# Notes
- 워크플로우 전체 흐름:
  - 수동: `/plan` → `/xv` (필요시) → `/design` → 구현 → `/gap` → `/review` → `/propose`
  - 자동: `/auto` → (Plan→Design→승인→구현→독립검증→완료)
  - 하네스: CLAUDE.md 자동 적용 규칙에 따라 복잡도별 자동 워크플로우 진입
- "이후 흐름"에는 추천 커맨드 이후 남은 단계를 보여준다
- 디렉토리가 존재하지 않으면 0개로 처리한다
- 판단이 애매할 때는 여러 선택지를 제시하고 사용자가 결정하게 한다

# Input
$ARGUMENTS
