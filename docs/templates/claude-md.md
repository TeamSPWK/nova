# CLAUDE.md 템플릿

> **200줄 이하 유지.** Claude Code는 CLAUDE.md가 길수록 규칙 준수율이 떨어진다. 상세 규칙은 `.claude/rules/`로 분리한다.
> 프로젝트 특성에 맞게 수정해서 사용한다.

---

```markdown
# {프로젝트명}

{프로젝트 한 줄 설명}

## Language

- Claude는 사용자에게 항상 **{언어}**로 응답한다.

## Start Here

- Current state: `NOVA-STATE.md` 또는 {issue tracker}
- Architecture SOT: {docs/architecture.md 또는 TODO}
- Infra SOT: {docs/operations/infra-inventory.md 또는 TODO}
- Deploy workflow: {/.claude/skills/deploy 또는 TODO}

## Nova Engineering

> **Nova 플러그인 설치 시**: 복잡도·검증·실행 검증·블로커·환경 안전 5개 핵심 규칙은 `hooks/session-start.sh`가 매 세션 자동 주입한다. 이 파일에 중복 기재하지 않는다.
> **미설치 시**: `docs/nova-rules.md §1~§9` 핵심 요약을 이 섹션에 수동 병합한다 (폴백).
> 상세는 `/nova:next` 또는 `docs/nova-rules.md` 참조.

커맨드 진입점:

| 커맨드 | 사용 시점 |
|--------|----------|
| `/nova:next` | 다음 할 일 추천 |
| `/nova:plan` | 새 기능 시작 (복잡도 "보통" 이상) |
| `/nova:ask` | 설계 판단 불확실할 때 (멀티 AI 다관점 수집) |
| `/nova:design` | 기술 설계 (복잡도 "복잡") |
| `/nova:check` / `/nova:review` | 구현 완료 후 검증·리뷰 |
| `/nova:run` | 구현→검증 Full Cycle |
| `/nova:setup --check` | Nova 도입 수준 측정 (32항목) |
| `/nova:claude-md` | CLAUDE.md/AGENTS.md 지침 구조 감사·정리 |

## Tech Stack

- {프레임워크}: {버전}
- {언어}: {버전}
- {DB}: {버전}

## Build & Test

```bash
# 빌드
{빌드 명령}

# 테스트
{테스트 명령}

# 린트
{린트 명령}

# 개발 서버
{개발 서버 명령}
```

## Conventions

### Git

```
feat: 새 기능       | fix: 버그 수정
update: 기능 개선    | docs: 문서 변경
refactor: 리팩토링   | chore: 설정/기타
```

### Naming
- {파일명/변수명 규칙 — 필요 시}

## Credentials

- **절대 git 커밋 금지**: `.env`, `.secret/`, `*.pem`, `*accessKeys*`

## Agent Routing

- Always-on project facts: `CLAUDE.md` 또는 `AGENTS.md`
- Path-scoped rules: `.claude/rules/`
- Repeatable workflows: `.claude/skills/` 또는 `.claude/commands/`
- Hard enforcement: `.claude/settings.json`, hooks, CI
- Current status: `NOVA-STATE.md`
- Personal/local details: `CLAUDE.local.md`, `.claude/settings.local.json`

## Instruction Placement Contract

- 새 지침을 추가하기 전 `always-on / path-specific / workflow / hard guard / reference / state / local-only` 중 하나로 분류한다.
- 중요하다는 이유만으로 CLAUDE.md에 넣지 않는다. 반드시 매 세션 필요한 불변 사실만 남긴다.
- 반드시 지켜야 하는 규칙은 settings/hooks/CI/script 같은 enforcement owner를 가진다.

## Principles (선택)

<!-- 프로젝트 고유 개발 철학 — 인프라/복잡 프로젝트 권장.
     예: "정확도 > 속도", "파괴적 작업 전 사용자 확인 필수", "공유 리소스 변경은 승인 후". -->

## Coding Rules (선택)

<!-- 코드 스타일 강제 규칙 — 린터로 잡히지 않는 프로젝트 고유 규칙.
     예: "CSS Custom Properties 강제", "DB RLS 필수", "UI 텍스트 한/영 분리". -->

## Project Structure (선택)

<!-- 필요 시 추가. 코드에서 자명하면 생략 -->

## Human-AI Boundary (선택)

<!-- 프로젝트에 AI 협업 경계가 명시 필요한 경우에만 추가 -->

## Known Mistakes (선택)

<!-- 팀이 실제로 저지른 버그/설계 실수 기록. 재발 방지 목적.
     예: "배포 시 구 서버 혼동", "proxy 충돌", "simulate() 파라미터 불일치".
     코드·git log에서 추론 불가한 실전 교훈만. -->
```

---

## 사용법

1. 위 코드펜스 안의 내용을 프로젝트 루트 `CLAUDE.md`로 복사
2. `{중괄호}` 부분을 프로젝트에 맞게 수정
3. Tech Stack, Build & Test, Conventions를 실제에 맞게 채움
4. 선택 섹션(Project Structure, Human-AI Boundary)은 필요 시에만 추가

## 필수 섹션 vs 선택 섹션

| 섹션 | 필수 | 이유 |
|------|------|------|
| Language | O | AI 응답 언어 통일 |
| Start Here | O | 현재 상태와 SOT 진입점 |
| Nova Engineering (참조) | O | 플러그인 자동 주입 + 미설치 폴백 가이드 |
| Tech Stack + Build & Test | O | Claude가 코드에서 추론 불가한 명령 |
| Conventions (git) | O | 일관성 유지 |
| Credentials | O | 보안 사고 방지 |
| Agent Routing + Instruction Placement | O | CLAUDE.md 비대화와 규칙 산재 방지 |
| Principles | 선택 | 개발 철학 (정확도>속도 등) — 인프라/복잡 프로젝트 권장 |
| Coding Rules | 선택 | 강제 규칙 (CSS, DB RLS 등) — 린터로 잡히지 않는 프로젝트 고유 규칙 |
| Project Structure | 선택 | 복잡한 프로젝트에서 유용 |
| Human-AI Boundary | 선택 | AI 협업 경계 명시 필요 시 |
| Known Mistakes | 선택 | 실전 교훈 (재발 방지) — 코드·git log에서 추론 불가한 내용 |

## Nova 자동 적용의 원리

Nova 플러그인이 설치되면 `hooks/session-start.sh`가 매 세션 시작 시 자동 규칙을 주입한다. 따라서 CLAUDE.md에는 **프로젝트 고유 맥락**(Tech Stack, Build/Test, Conventions, Credentials)만 담으면 된다.

- 사용자가 `/nova:run`을 쓰면 → 커맨드 파일의 상세 절차
- 사용자가 "기능 만들어줘"라고 하면 → session-start 주입 규칙 적용
- **두 경로 모두 같은 Nova 원칙을 따른다**

## 작성 베스트 프랙티스

| 원칙 | 설명 |
|------|------|
| **200줄 이내** | 초과 시 규칙 준수율 하락. 150줄 이하가 이상적 |
| **컨텍스트지 강제가 아님** | 보안·크레덴셜 등 필수 강제는 hooks로 |
| **빌드/테스트 명령 필수** | Claude가 코드에서 추론 불가한 핵심 정보 |
| **코드 추론 가능한 것 제외** | 스타일(린터), API 문서(코드), 상세 경로(탐색) |
| **`.claude/rules/` 분리** | 특정 파일/디렉토리 스코프 규칙은 rules/로 모듈화 |
| **계층 구조 활용** | 모노레포는 루트에 공통, 패키지별 CLAUDE.md |

## 플러그인 미설치 시 폴백 (선택 복붙)

Nova 플러그인을 설치하지 않은 환경에서는 `session-start.sh` 자동 주입이 없다. 아래 4개 최소 규칙을 CLAUDE.md의 `## Nova Engineering` 섹션에 **그대로 복붙**해 사용한다. (상세는 `docs/nova-rules.md` §1~§9)

```markdown
### 자동 적용 규칙 (미설치 폴백 — 핵심 4개)

1. **복잡도 판단**: 간단(1~2파일)→바로 구현. 보통(3~7)→Plan 승인 후 구현. 복잡(8+)→Plan→Design→스프린트 분할. 인증/DB/결제는 +1 단계. 파일 수 초과 시 즉시 Plan 승격, 자가 완화 금지.
2. **Generator-Evaluator 분리**: 구현과 검증은 **반드시 다른 서브에이전트**로 실행한다. 검증 에이전트는 적대적 자세("통과시키지 마라, 문제를 찾아라"). 메인이 자기 코드 재확인하는 것은 독립 검증이 아니다.
3. **검증 기준**: 기능(요구사항 대조) · 데이터 관통(입력→저장→로드→표시) · 설계 정합성 · **요청 범위**(drive-by 리팩토링·포맷 교정 금지, Karpathy Surgical Changes) · 크래프트 · 경계값(0/음수/빈 값/최대값) · Coverage Gate.
4. **블로커 분류**: Auto-Resolve(자동 해결) · Soft-Block(기록 후 계속) · Hard-Block(데이터 손실/보안 → 즉시 중단, 사용자 판단). 불확실=Hard. 같은 원인 실패 2회 반복 시 강제 분류.
```
