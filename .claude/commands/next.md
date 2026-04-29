---
description: "현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다."
description_en: "Diagnose current project state and recommend the next Nova command to run."
---

현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다.

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §8` 세션 상태 유지 (Known Gaps 필수, 즉시 트리거)
- `docs/nova-rules.md §10` 관찰성 계약 — 진단 결과 하단에 KPI 요약 1줄 포함

## KPI 요약 (v5.12.0+, 진단 결과 포함)

진단 결과 끝에 `scripts/nova-metrics.sh --since 30d` 출력을 1줄 요약으로 표시:

```
📊 KPI(30d): Process consistency: 78% (n=41) · Gap detection: 85% (n=13) · Rule evolution: N/A · Multi-perspective: 62% (n=8)
```

값이 모두 `N/A (insufficient data)`면 생략(경량). `scripts/nova-metrics.sh` 실행 실패도 생략(safe-default).

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

       ## Tasks
       | Task | Status | Verdict | Note |
       |------|--------|---------|------|
       | {추천 액션} | todo | - | - |

       ## Recently Done (최근 3개만)
       | Task | Completed | Verdict | Ref |
       |------|-----------|---------|-----|

       ## Refs
       - Plan: {docs/plans/xxx.md 또는 none}
       - Design: {docs/designs/xxx.md 또는 none}
       - Last Verification: {docs/verifications/xxx.md 또는 none}
       ```
     - 생성 후 사용자에게 "📋 NOVA-STATE.md를 자동 생성했습니다." 안내
   - **파일이 있으면**: 읽고 상태 기반 추천
     - Blocker가 있으면 → 블로커 해결을 최우선 추천
     - Tasks에 doing 작업이 있으면 → 해당 작업 이어가기 추천
     - Phase가 `verifying`이면 → `/check` 또는 `/review` 추천
     - Phase가 `done`이면 → "새 기능 시작 준비 완료" 표시

1. 다음 항목을 모두 확인한다:
   - `docs/plans/` 디렉토리의 .md 파일 목록과 개수
   - `docs/designs/` 디렉토리의 .md 파일 목록과 개수
   - `docs/verifications/` 디렉토리의 .md 파일 목록과 개수
   - `docs/decisions/` 디렉토리의 .md 파일 목록과 개수
   - `git log --oneline -10` — 최근 커밋 10개
   - `git status` — 커밋되지 않은 변경사항
   - `git diff --name-only HEAD~5..HEAD 2>/dev/null` — 최근 변경된 파일

2. 아래 워크플로우 로직을 순서대로 적용하여 첫 번째 해당 항목을 추천한다:

   **환경 건전성 체크 (가장 먼저 수행):**
   - `git worktree list`를 실행하여 현재가 worktree인지 확인한다
   - worktree라면 `.env`, `.env.local`, `.secret/`, `.npmrc` 중 메인 레포에는 있지만 현재 worktree에는 **없거나 깨진 심링크**인 파일이 있는지 확인한다
   - 하나라도 해당하면 → `/nova:worktree-setup` 추천 (최우선)
     "환경 기둥 경고: worktree에서 {파일명}이(가) 연결되지 않았습니다. `/nova:worktree-setup`으로 메인 레포의 환경 파일을 링크하세요."
   - 문제 없으면 아래로 진행

   **복잡도 판단:**
   최근 커밋과 변경 파일을 분석하여 현재 작업의 복잡도를 판단한다.
   - 간단 (1~2 파일, 버그 수정, 명확한 변경) → "이 작업은 Plan 없이 바로 진행해도 됩니다." 라고 명시
   - 보통 이상 → 아래 워크플로우 로직 적용

   a. Plan이 하나도 없다 → 요청 성격에 따라 분기:
      - 요청이 "아키텍처 전환", "재구성", "마이그레이션", "인증 교체", "DB 스키마 변경", "외부 API 연동"처럼 실패 비용이 높은 판단이면 → `/nova:deepplan` 권장
        "아키텍처/마이그레이션 성격의 작업입니다. 대안 탐색·리스크 분석이 포함된 `/nova:deepplan`을 권장합니다."
      - 그 외 일반 기능 추가 → `/nova:plan` 추천
        "새 기능을 시작하려면 먼저 CPS Plan을 작성하세요."

   b. Plan은 있지만 Design이 없다 → `/design` 추천
      "Plan이 준비되었습니다. 기술 설계를 진행하세요."

   c. Design이 있고 최근 코드 커밋이 있지만 Verification이 없다 → `/check` 추천
      "구현이 진행되었습니다. 코드 품질과 설계 정합성을 확인하세요."

   d. Verification이 있고 이슈가 발견된 상태다 (verification 파일 내용에 FAIL/미완/TODO 등) → 수정 후 `/check` 재실행 추천
      "검증에서 이슈가 발견되었습니다. 수정 후 재검증하세요."

   e. Verification이 완료되고 이슈가 없다 → `/review` 추천
      "검증이 완료되었습니다. 코드 품질을 점검하세요."

   e-0. **Nova 플러그인 자기 코드 변경**이 감지되면 (커밋이 `commands/`, `agents/`, `hooks/`, `skills/`, `.claude-plugin/` 중 하나 포함) → `/nova:audit-self` 병행 추천
      "Nova 자기 코드가 변경되었습니다. `/nova:audit-self`로 정적 보안 진단을 권장합니다 (5 카테고리 30+ 룰)."
      이 추천은 e와 병행 표시한다 (e를 대체하지 않음).

   e-1. 최근 변경 파일에 프론트엔드 파일이 3개 이상 포함되어 있다 (*.tsx, *.jsx, *.vue, *.svelte, *.css, *.scss) → `/ux-audit` 병행 추천
      "UI 변경이 감지되었습니다. `/nova:ux-audit`로 접근성·인지 부하·성능·다크 패턴을 점검하세요."
      이 추천은 e 항목과 병행 표시한다 (e를 대체하지 않음).

   f. Review까지 완료된 흔적이 있다 (최근 커밋에 review/refactor 관련 메시지) → 완료 안내
      "리뷰가 완료되었습니다. 반복 패턴이 있으면 CLAUDE.md에 기록하세요."

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

# Quality Metrics 참조

NOVA-STATE.md에 `## Quality Metrics` 섹션이 있으면 추세를 분석하여 추천에 반영한다:

- **FAIL 빈도 높음** (최근 5회 중 2+ FAIL) → "품질 게이트 실패가 반복되고 있습니다. 근본 원인 분석을 권장합니다."
- **CONDITIONAL 누적** (3+ 미해결) → "미검증 항목이 누적되고 있습니다. Layer 3 실행 환경을 점검하세요."
- **Coverage 하락 추세** → "테스트 커버리지가 하락 중입니다. 테스트 보강을 권장합니다."
- **Learned Rules 현황**: `.claude/rules/` 파일 수를 진단에 표시한다.

# Notes
- 워크플로우 전체 흐름:
  - 수동 (일반): `/nova:plan` → `/ask` (필요시) → `/design` → 구현 → `/check` → `/review`
  - 수동 (고위험): `/nova:deepplan` → `/ask` (필요시) → `/design` → 구현 → `/check` → `/review`
  - 자동: `/nova:auto [--deep]` → (Plan→Design→구현→검증→완료)
  - 하네스: CLAUDE.md 자동 적용 규칙에 따라 복잡도별 자동 워크플로우 진입
- "이후 흐름"에는 추천 커맨드 이후 남은 단계를 보여준다
- 디렉토리가 존재하지 않으면 0개로 처리한다
- 판단이 애매할 때는 여러 선택지를 제시하고 사용자가 결정하게 한다

# Input
$ARGUMENTS
