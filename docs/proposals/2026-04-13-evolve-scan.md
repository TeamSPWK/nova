# Evolution Scan Report (2026-04-13)

> 스캔 일시: 2026-04-13T10:30:00+09:00
> 소스: Anthropic 공식, Claude Code 생태계, 하네스 도구, AI 엔지니어링
> 이전 스캔: 2026-04-10 (6건 제안, 별도 파일)
> 발견: 32건 → 관련: 9건 (필터율: 72%)

---

## patch (3건)

### P1. Hook 조건부 필터링(`if` 필드) 활용

> 출처: https://code.claude.com/docs/en/hooks
> 수준: patch
> 자율 등급: Full Auto

#### 발견
Claude Code v2.1.85+에서 Hook에 `if` 필드가 추가되어, 도구 이름뿐 아니라 인자까지 매칭할 수 있다. 예: `"Bash(git *)"` → git 명령만, `"Edit(*.ts)"` → TypeScript 파일만 트리거.

#### Nova 적용 방안
Nova의 `pre-commit-reminder.sh` 훅은 현재 모든 Bash 호출에 트리거되고 내부에서 git commit 여부를 판별한다. `if` 필드로 `"Bash(git commit*)"`, `"Bash(git push*)"` 만 매칭하면 불필요한 훅 실행을 제거할 수 있다.

#### 영향 범위
- `hooks/hooks.json` (또는 plugin.json의 hooks 섹션) — `if` 조건 추가
- `hooks/pre-commit-reminder.sh` — 내부 git 명령 판별 로직 단순화

#### 리스크
낮음 — 기존 동작 범위를 좁히는 것이므로 안전. `if` 필드 미지원 버전에서는 무시됨.

---

### P2. `disallowedTools`로 Nova 에이전트 도구 거버넌스 명시화

> 출처: https://code.claude.com/docs/en/sub-agents
> 수준: patch
> 자율 등급: Full Auto

#### 발견
커스텀 에이전트 정의에 `disallowedTools` 필드가 추가되어 denylist 방식으로 도구 접근을 제한할 수 있다. 기존 `tools` allowlist보다 유연함.

#### Nova 적용 방안
Nova의 Evaluator 에이전트(`agents/nova:*`)에 `disallowedTools: ["Edit", "Write"]`를 명시하여 **검증자가 코드를 수정하지 못하도록** 아키텍처적으로 보장한다. 현재는 프롬프트로만 "수정하지 마라"고 지시하지만, `disallowedTools`로 하드 블록이 가능하다.

#### 영향 범위
- `agents/nova:security-engineer.md` — disallowedTools 추가
- `agents/nova:qa-engineer.md` — disallowedTools 추가
- 기타 검증 전용 에이전트

#### 리스크
낮음 — 기존 동작을 프롬프트 레벨에서 시스템 레벨로 강화하는 것.

---

### P3. `hookSpecificOutput.sessionTitle`로 Nova 세션 자동 타이틀

> 출처: https://github.com/anthropics/claude-code/releases (v2.1.94)
> 수준: patch
> 자율 등급: Full Auto

#### 발견
Claude Code v2.1.94에서 `UserPromptSubmit` 훅이 `hookSpecificOutput.sessionTitle`을 반환하면 세션 타이틀이 자동 설정된다.

#### Nova 적용 방안
Nova `session-start.sh`에서 NOVA-STATE.md의 현재 Goal을 읽어 세션 타이틀로 자동 설정. 예: `"Nova: Orchestrator Sprint 3"`. 사용자가 여러 세션을 열 때 구분이 용이해진다.

#### 영향 범위
- `hooks/session-start.sh` — sessionTitle 반환 로직 추가

#### 리스크
낮음 — 타이틀만 설정하므로 기존 동작에 영향 없음. sessionTitle 미지원 버전에서 무시됨.

---

## minor (4건)

### M1. Hook `if` 필드 + `agent_id` 컨텍스트로 Evaluator 격리 강화

> 출처: https://code.claude.com/docs/en/hooks, https://help.apiyi.com/en/claude-code-changelog-2026-april-updates-en.html
> 수준: minor
> 자율 등급: Semi Auto (PR)

#### 발견
Hook에 `agent_id`와 `agent_type` 컨텍스트가 추가되어, 특정 에이전트에서만 훅을 트리거하거나 제외할 수 있다. Evaluator 서브에이전트가 실행될 때만 특수 훅을 적용하는 것이 가능해졌다.

#### Nova 적용 방안
1. **Evaluator 전용 훅**: Evaluator 에이전트가 실행될 때 자동으로 `--readonly` 모드를 강제하는 PreToolUse 훅 추가.
2. **Generator 전용 훅**: 구현 에이전트에서만 pre-commit reminder를 트리거하도록 `agent_type` 조건 추가.
3. Generator-Evaluator 분리를 프롬프트가 아닌 **시스템 레벨**에서 보장.

#### 영향 범위
- `hooks/hooks.json` — agent_id/agent_type 기반 조건 추가
- `docs/nova-rules.md` — Generator-Evaluator 분리 규칙에 시스템 레벨 보장 언급

#### 리스크
중간 — agent_id 매칭 패턴이 Nova 에이전트 네이밍과 일치해야 함. 테스트 필요.

---

### M2. Multi-Agent 오케스트레이션 패턴 적용 (파일 잠금 + 의존성 추적)

> 출처: https://addyosmani.com/blog/code-agent-orchestra/
> 수준: minor
> 자율 등급: Semi Auto (PR)

#### 발견
Addy Osmani의 "Code Agent Orchestra" (O'Reilly CodeCon 2026)에서 multi-agent 코딩 패턴을 체계화:
- **파일 잠금**: 에이전트 간 동일 파일 수정 충돌 방지
- **의존성 추적**: 태스크 간 선후 관계를 명시하여 병렬 실행 최적화
- **3개 집중 에이전트 > 1개 범용 에이전트**: 전문화된 에이전트가 일관되게 더 나은 결과

#### Nova 적용 방안
Nova Orchestrator(`/nova:orchestrate`)에 다음을 반영:
1. **스프린트 분할 시 파일 잠금 힌트**: 에이전트에게 "이 파일은 다른 에이전트가 수정 중"이라는 컨텍스트 제공.
2. **태스크 의존성 DAG**: 스프린트 내 태스크 간 의존성을 명시하여 병렬 실행 가능한 태스크를 자동 식별.
3. Orchestrator 프롬프트에 "3개 전문 에이전트 > 1개 범용" 원칙 명시.

#### 영향 범위
- `skills/orchestrator/SKILL.md` — 파일 잠금 힌트, 의존성 DAG 섹션 추가
- `commands/orchestrate.md` — 크로스 레퍼런스

#### 리스크
중간 — 파일 잠금은 Claude Code의 native file locking과의 통합이 필요. 현재 Nova MCP 서버에서는 직접 구현 불가, 프롬프트 레벨 가이드로 시작.

---

### M3. Cursor Bugbot Learned Rules 패턴 — 리뷰 피드백 → 규칙 자동 생성

> 출처: https://cursor.com/blog/bugbot-learning
> 수준: minor
> 자율 등급: Semi Auto (PR)

#### 발견
Cursor Bugbot이 자기개선형 리뷰 도입. PR 리뷰에서 개발자 반응(다운보트, 답글), 인간 리뷰어 코멘트 3가지 시그널로 candidate rule 생성 → 자동 승격/비활성화. 해결율 52% → 80%. 110,000+ 저장소에서 44,000+ 커스텀 룰 생성.

#### Nova 적용 방안
Nova의 Adaptive(A) 원칙의 구체적 구현:
1. `/nova:review`가 지적한 항목 중 사용자가 "무시" 또는 "동의"한 피드백을 프로젝트별 `.claude/rules/`에 learned rule로 축적.
2. 반복 패턴 감지 → 규칙 후보 제안 → 사용자 승인 후 자동 활성화.
3. N회 이상 무시된 규칙은 자동 비활성화 제안.

#### 영향 범위
- `skills/evaluator/SKILL.md` — learned rules 참조 섹션 추가
- `commands/review.md` — 피드백 수집 + 규칙 제안 로직
- 새 파일: `docs/learned-rules-spec.md` (설계 문서)

#### 리스크
중간 — 규칙의 품질 관리가 핵심. 노이즈 규칙이 쌓이면 오히려 리뷰 품질 저하. 사용자 승인 게이트 필수.

---

### M4. TeammateIdle/TaskCompleted 훅으로 Orchestrator 상태 추적

> 출처: https://code.claude.com/docs/en/changelog (v2.1.94+)
> 수준: minor
> 자율 등급: Semi Auto (PR)

#### 발견
Claude Code에 `TeammateIdle`과 `TaskCompleted` 훅 이벤트가 추가. Agent Teams에서 팀원 에이전트의 유휴/완료 상태를 감지하여 자동으로 다음 작업을 할당할 수 있다.

#### Nova 적용 방안
Nova Orchestrator가 스프린트를 실행할 때:
1. `TaskCompleted` 훅에서 완료된 에이전트의 결과를 자동 수집.
2. `TeammateIdle` 훅에서 유휴 에이전트에게 다음 태스크를 자동 할당.
3. 스프린트 진행률을 NOVA-STATE.md에 실시간 반영.

#### 영향 범위
- `hooks/hooks.json` — TeammateIdle/TaskCompleted 핸들러 추가
- `skills/orchestrator/SKILL.md` — 훅 연동 섹션

#### 리스크
중간 — Agent Teams 기능이 안정화된 후 적용 권장. 훅 오류가 오케스트레이션 루프를 중단시킬 수 있음.

---

## major (2건)

### X1. Two-Gate Quality System (Code Health + Coverage Gate)

> 출처: https://codescene.com/blog/agentic-ai-coding-best-practice-patterns-for-speed-with-quality
> 수준: major
> 자율 등급: Manual (제안만)

#### 발견
CodeScene의 연구에서 AI 에이전트 코딩에 Two-Gate 시스템이 효과적:
1. **Code Health Gate**: 코드 가독성, 유지보수성, 기술 부채 점수 (9.4+ 필요)
2. **Coverage Gate**: 테스트 커버리지를 회귀 시그널로 활용 (vanity metric이 아닌 behavioral check)

현재 Nova의 품질 게이트는 `tsc/lint → Evaluator → PASS` 단일 체인이다. Coverage Gate가 없다.

#### Nova 적용 방안
Nova Evaluator의 검증 체크리스트에 **Coverage 관점**을 공식 추가:
1. Evaluator가 "이 변경에 대한 테스트가 존재하는가?"를 필수 체크 항목으로 확인.
2. `--strict` 모드에서 `jest --coverage` 또는 프로젝트별 커버리지 도구 실행.
3. 커버리지 하락 시 FAIL 판정 (현재는 Evaluator 재량).

#### 영향 범위
- `skills/evaluator/SKILL.md` — Coverage Gate 체크리스트 항목 추가
- `docs/nova-rules.md` — 검증 기준에 Coverage Gate 언급
- `hooks/session-start.sh` — 규칙 동기화

#### 리스크
높음 — 프로젝트별 테스트 도구/커버리지 기준이 다름. `/nova:init`에서 프로젝트별 설정이 필요. 테스트가 아예 없는 프로젝트에서는 게이트가 항상 FAIL → 실용성 저하.

---

### X2. Learned Rules 자동화 + Adaptive 측정 (M3의 full 구현)

> 출처: https://cursor.com/blog/bugbot-learning, https://www.anthropic.com/engineering/harness-design-long-running-apps
> 수준: major
> 자율 등급: Manual (제안만)

#### 발견
Bugbot의 44,000+ learned rules 성공 사례와 Anthropic의 "하네스 복잡도는 태스크 난이도에 비례" 원칙을 결합하면, Nova의 Adaptive(A) 원칙을 정량적으로 측정·개선하는 시스템이 가능하다.

#### Nova 적용 방안
1. **규칙 효과 측정**: 각 규칙이 얼마나 자주 트리거되고, 사용자가 수용/거부했는지 추적.
2. **프로젝트별 프로파일**: `/nova:init`에서 프로젝트 특성(언어, 프레임워크, 테스트 도구)을 감지하여 기본 규칙 세트를 조정.
3. **Adaptive 대시보드**: 규칙 효과 통계를 `/nova:next`에서 표시.

#### 영향 범위
- 새 시스템: 규칙 효과 추적 메커니즘
- `commands/init.md`, `commands/next.md`, `skills/evaluator/SKILL.md`
- MCP 서버 확장 또는 파일 기반 로컬 저장소

#### 리스크
높음 — 아키텍처 레벨 변경. 데이터 저장/조회 메커니즘 설계 필요. 프라이버시 고려(프로젝트 코드 패턴 저장 범위).

---

## 시장 컨텍스트

> "AI가 전체 커밋 코드의 42%를 기여하며, 병목이 코드 작성에서 **코드 검증으로 이동**했다." — [AI Code Review Benchmark 2026](https://byteiota.com/ai-code-review-benchmark-2026-first-real-results/)

> "에이전트는 자기 결과물을 자신있게 칭찬한다 — 명백히 품질이 낮을 때도. Generator-Evaluator 분리는 선택이 아닌 필수." — [Anthropic Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)

> "Harness Engineering: 솔루션 공간을 제약할수록 출력이 예측 가능해진다." — [Red Hat Developer](https://developers.redhat.com/articles/2026/04/07/harness-engineering-structured-workflows-ai-assisted-development)

Nova의 Generator-Evaluator 분리, CPS 구조, 단계별 품질 게이트가 업계 표준으로 수렴하고 있음을 확인.
