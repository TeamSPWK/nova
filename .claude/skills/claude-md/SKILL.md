---
name: claude-md
description: "CLAUDE.md/AGENTS.md 등 에이전트 지침 파일을 신규 생성하거나 기존 프로젝트 기준으로 재구성해야 할 때. — MUST TRIGGER: 사용자가 /nova:claude-md 호출, CLAUDE.md·AGENTS.md 설계/정리 요청, 신규/기존 프로젝트의 에이전트 지침 중복·분산·드리프트 점검 필요 시."
description_en: "Use when CLAUDE.md, AGENTS.md, or other agent instruction files must be created or reorganized for a new or existing project. — MUST TRIGGER: user invokes /nova:claude-md, asks to design or clean up CLAUDE.md/AGENTS.md, or needs drift/duplication review across project instruction surfaces."
user-invocable: true
---

# Nova CLAUDE.md Architect

프로젝트의 에이전트 지침 표면을 설계·정리한다. Nova 5기둥 중 **맥락**(세션마다 필요한 지식), **환경**(시크릿/인프라 경계), **협업**(여러 에이전트가 같은 기준으로 일함)에 걸친 스킬이다.

## 핵심 원칙

1. **CLAUDE.md = 운영 헌법 + 라우터**  
   전체 매뉴얼이 아니라 매 세션 반드시 알아야 하는 불변 사실, 위험 경계, 진입점만 담는다. 상세 절차는 링크하거나 별도 표면으로 이동한다.

2. **분리 기준을 파일로 남긴다**  
   정리 결과만 만들지 않는다. 다음 에이전트가 새 지침을 추가할 때 같은 판단을 하도록 `Instruction Placement Contract`를 CLAUDE.md/AGENTS.md 또는 `.claude/rules/instruction-placement.md`에 남긴다.

3. **신규는 뼈대를 만들고, 기존은 이력을 보존한다**  
   신규 프로젝트는 빈칸을 솔직히 남기고 방향을 잡는다. 기존 프로젝트는 먼저 현재 파일을 감사한 뒤 `keep / move / enforce / local-only / remove`로 분류한다. 기존 규칙은 이동하더라도 잃지 않는다.

4. **강제와 조언을 분리한다**  
   CLAUDE.md의 "절대 금지"는 요청일 뿐이다. `.env` 읽기/쓰기 금지, 위험 명령 차단, 배포 전 검사처럼 반드시 지켜야 하는 것은 `.claude/settings.json`, hooks, CI, 스크립트로 강제한다.

5. **크로스 에이전트 호환성을 설계한다**  
   Claude Code는 `CLAUDE.md`, Codex 및 여러 에이전트는 `AGENTS.md`를 본다. 신규 프로젝트는 가능하면 `AGENTS.md`를 공통 계약으로 두고 `CLAUDE.md`가 `@AGENTS.md`를 import한다. 기존 CLAUDE 중심 프로젝트는 얇은 AGENTS 브리지로 시작하고, 필요할 때만 canonical 전환한다.

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §1` 작업 전 복잡도 + 위험도 판단
- `docs/nova-rules.md §3` 검증 기준 — 요청 범위, 데이터 관통, 경계값
- `docs/nova-rules.md §8` NOVA-STATE.md 세션 상태 유지
- `docs/nova-rules.md §11` 도구 제약 계약 — 하드 가드는 settings/hooks로 강제

## 모드 판별

| 조건 | 모드 | 동작 |
|------|------|------|
| `--check` | Audit | 파일 수정 없이 현황, 중복, 과밀, 미강제 규칙을 보고 |
| `--apply` | Apply | 사용자가 승인한 분리안을 파일에 반영 |
| `--new` 또는 CLAUDE.md/AGENTS.md 없음 | New Project | 최소 지침 구조와 빈칸을 생성 |
| 기존 CLAUDE.md/AGENTS.md 있음 | Adopt Existing | 현재 지침을 감사한 뒤 재구성 제안 |
| 모노레포/하위 패키지 | Nested | 루트 공통 지침과 패키지별 지침을 분리 |
| `--global-karpathy` 또는 사용자가 전역 Karpathy 설정 요청 | Global Karpathy | 개인 전역 지침에 Karpathy 압축 원칙 추가/갱신 |

기본은 안전하게 **Audit → 제안 → 승인 후 Apply**다. 사용자가 명시적으로 "바로 적용" 또는 `--apply`를 주면 적용까지 진행한다.

## Global Karpathy 옵션

Karpathy 원칙은 프로젝트 지식이 아니라 개인의 보편적 코딩 태도다. 따라서 프로젝트별 CLAUDE.md에 복붙하지 말고, 사용자가 원할 때 개인 전역 지침에만 짧게 설치한다.

### 대상 파일

| 도구 | 파일 | 처리 |
|------|------|------|
| Claude Code | `~/.claude/CLAUDE.md` | 기존 내용 유지 + `AI Coding Discipline (Karpathy)` 섹션 추가/갱신 |
| Codex | `~/.codex/AGENTS.md` | 기존 내용 유지 + 같은 원칙 추가/갱신 |

### 실행 규칙

1. 전역 파일을 수정하기 전에 반드시 yes/no로 확인한다.
2. 이미 동일 섹션이 있으면 중복 추가하지 말고 갱신 여부를 묻는다.
3. 긴 전문을 넣지 않는다. 4개 원칙을 4~6줄로 압축한다.
4. 프로젝트 CLAUDE.md/AGENTS.md에는 Karpathy 전문을 추가하지 않는다. 필요한 경우 "global discipline applies" 정도만 언급한다.
5. 사용자가 no를 선택하면 전역 변경 없이 프로젝트 지침 정리만 계속한다.

확인 문구:

```text
개인 전역 지침에 Karpathy 압축 원칙을 추가/갱신할까요?
대상: ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md
프로젝트 파일에는 복붙하지 않습니다. (yes/no)
```

설치할 압축본:

```markdown
## AI Coding Discipline (Karpathy)
- 코딩 전 가정·모호성·트레이드오프를 먼저 드러내고, 불확실하면 묻기
- 요청한 문제를 푸는 최소 코드만 작성하고, 미요청 기능·추상화·설정화를 추가하지 않기
- 변경은 surgical 하게: 요청과 직접 연결된 라인만 건드리고, 주변 리팩터링/포맷 정리는 하지 않기
- 성공 기준을 테스트·빌드·스크린샷·curl 등으로 검증 가능하게 정의하고, 검증될 때까지 반복하기
```

## 조사 절차

1. git root와 현재 작업 디렉토리를 확인한다.
2. 다음 파일을 존재 여부와 크기 기준으로 조사한다:
   - `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`
   - `AGENTS.md`, `AGENTS.override.md`
   - nested `CLAUDE.md`/`AGENTS.md`
   - `.claude/rules/**`, `.claude/skills/**/SKILL.md`, `.claude/commands/**`
   - `.claude/settings.json`, `.claude/settings.local.json`, hooks
   - `NOVA-STATE.md`, README, package/build files, `.github/workflows/**`, `.env.example`
3. 기존 CLAUDE.md/AGENTS.md는 섹션별로 다음 표에 분류한다:

| 분류 | 기준 | 목적지 |
|------|------|--------|
| KEEP | 매 세션 필요한 불변 사실, 빌드/검증 명령, 위험 경계 | `CLAUDE.md` 또는 `AGENTS.md` |
| MOVE_RULE | 특정 경로/파일 타입에만 필요한 규칙 | `.claude/rules/*.md` with `paths` |
| MOVE_SKILL | 배포, 릴리스, DB 마이그레이션 등 다단계 절차 | `.claude/skills/*/SKILL.md` 또는 `.claude/commands/*.md` |
| ENFORCE | 반드시 차단/검사해야 하는 규칙 | `.claude/settings.json`, hooks, CI |
| MOVE_DOC | 긴 설명, 인프라 inventory, API 문서, runbook | `docs/**` |
| MOVE_STATE | 현재 phase, todo, 최근 검증, blocker | `NOVA-STATE.md` |
| LOCAL_ONLY | 개인 경로, sandbox URL, 로컬 토큰 위치 | `CLAUDE.local.md` 또는 settings.local |
| REMOVE | 코드/README에서 자명하거나 오래된 중복 | 삭제 제안 |

## 신규 프로젝트 생성안

신규 프로젝트에는 완벽한 문서를 만들려고 하지 않는다. 모르는 정보는 추측하지 않고 `TODO(owner)`로 남긴다.

### 추천 파일

| 파일 | 생성 조건 | 역할 |
|------|----------|------|
| `AGENTS.md` | cross-agent 사용 가능성이 있으면 기본 생성 | 공통 에이전트 계약 |
| `CLAUDE.md` | Claude Code 사용 시 생성 | `@AGENTS.md` import + Claude/Nova 특화 |
| `.claude/rules/instruction-placement.md` | Claude Code 프로젝트면 생성 | 지침 추가 시 분리 기준 자동 로드 |
| `NOVA-STATE.md` | Nova 프로젝트면 생성 또는 확인 | 현재 상태/진입점 |
| `.claude/settings.json` | 사용자가 hard guard 적용 승인 시 | 시크릿/위험 명령 차단 |

### 신규 AGENTS.md 골격

````markdown
# {Project Name}

## Role
{이 프로젝트가 무엇인지 한 문단}

## Start Here
- Current state: `NOVA-STATE.md` 또는 `{issue tracker}`
- Architecture SOT: `{docs/architecture.md 또는 TODO}`
- Infra SOT: `{docs/operations/infra-inventory.md 또는 TODO}`
- Deploy workflow: `{/.claude/skills/deploy 또는 TODO}`

## Build & Verify
```bash
{install command}
{lint command}
{test command}
{build command}
```

## Non-Negotiables
- {사고 방지 규칙 1}
- {사고 방지 규칙 2}

## Secrets & Infra
- Never commit `.env`, `.secret/`, `*.pem`, or access keys.
- Secret values live outside this file. Reference only the secret system or env template.
- Production mutations require explicit human approval.

## Agent Routing
- Path-scoped rules: `.claude/rules/`
- Repeatable workflows: `.claude/skills/` or `.claude/commands/`
- Hard enforcement: `.claude/settings.json`, hooks, CI
- Current status: `NOVA-STATE.md`

## Instruction Placement Contract
- Put always-on project facts here.
- Put path-specific guidance in `.claude/rules/`.
- Put multi-step procedures in skills/commands.
- Put hard blocks in settings/hooks/CI.
- Put volatile status in `NOVA-STATE.md`.
- Put personal/local details in gitignored local files.
````

### 신규 CLAUDE.md 골격

```markdown
@AGENTS.md

## Claude Code
- Use `/memory` to verify loaded instruction files when behavior seems stale.
- Nova commands: `/nova:next`, `/nova:plan`, `/nova:check`, `/nova:review`, `/nova:claude-md`.
- Keep this file as a Claude-specific supplement. Shared project instructions belong in `AGENTS.md`.
```

## 기존 프로젝트 재구성안

기존 프로젝트는 "정답 템플릿으로 덮어쓰기"가 아니라 현재 지식의 보존과 재배치를 우선한다.

1. 파일 크기와 중복을 측정한다:
   - 150줄 이하: 정상
   - 151~200줄: 주의
   - 200줄 초과: 분리 권고
2. 섹션별 이동 제안을 만든다.
3. 위험 규칙마다 강제 소유자를 붙인다:
   - `advisory`: CLAUDE.md/AGENTS.md에만 있음
   - `enforced`: settings/hooks/CI/script가 있음
   - `missing-enforcement`: 반드시 보강 추천
4. 기존 레포가 CLAUDE 중심이면 기본은 유지한다:
   - `CLAUDE.md`: 정리된 운영 헌법 + 라우터
   - `AGENTS.md`: "Before repository work, run Nova repo-preflight if available. Otherwise read CLAUDE.md and NOVA-STATE.md manually. Project-specific instructions live in CLAUDE.md." 브리지
5. cross-agent 신뢰성이 중요하면 canonical 전환을 제안한다:
   - `AGENTS.md`: 공통 계약
   - `CLAUDE.md`: `@AGENTS.md` + Claude 특화

## Instruction Placement Rule 템플릿

Claude Code 프로젝트에는 아래 path-scoped rule을 생성한다. 이 파일은 지침 파일을 편집할 때만 로드되어 CLAUDE.md 비대화를 막는다.

```markdown
---
paths:
  - "CLAUDE.md"
  - "AGENTS.md"
  - ".claude/CLAUDE.md"
  - ".claude/rules/**"
  - ".claude/skills/**"
  - ".claude/commands/**"
  - ".claude/settings*.json"
  - "docs/operations/**"
  - "docs/guides/**"
---
# Instruction Placement Contract

Before adding or changing agent instructions, classify the content:

| Content | Destination |
|---------|-------------|
| Always-on project facts, build/test commands, non-negotiable risk boundaries | `CLAUDE.md` or `AGENTS.md` |
| File/path-specific guidance | `.claude/rules/*.md` with `paths` |
| Multi-step procedures such as deploy/release/migration | `.claude/skills/*/SKILL.md` or `.claude/commands/*.md` |
| Hard blocks and deterministic checks | `.claude/settings.json`, hooks, CI, scripts |
| Long reference docs, infra inventory, runbooks | `docs/**` |
| Current phase, TODO, blockers, recent verification | `NOVA-STATE.md` or issue tracker |
| Personal paths, local URLs, private preferences | `CLAUDE.local.md` or `.claude/settings.local.json` |

Do not put a rule in CLAUDE.md just because it is important. If it is important and must always hold, add enforcement or point to the enforcement owner.
```

## 출력 형식

Audit/Adopt 모드:

```text
━━━ Agent Instructions Audit ━━━━━━━━━━━━━
Mode: Existing / New / Nested
Loaded: CLAUDE.md N lines, AGENTS.md N lines, rules N, skills N, settings yes/no

Verdict:
- Size: PASS/WARN/FAIL
- Duplication: PASS/WARN/FAIL
- Enforcement gaps: N
- Cross-agent bridge: PASS/WARN/FAIL

Placement Plan:
| Source section | Classification | Destination | Reason |

Proposed files:
| File | Action | Notes |

Questions:
- {추측하면 안 되는 정보}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Apply 모드:

```text
━━━ Applied ━━━━━━━━━━━━━━━━━━━━━━━━━
Changed:
- CLAUDE.md — condensed to N lines
- AGENTS.md — bridge/canonical updated
- .claude/rules/instruction-placement.md — added

Verification:
- no literal secret values
- CLAUDE.md line count <= 150 target / <= 200 limit
- every hard rule has advisory/enforced/missing-enforcement label
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 안티패턴

- Karpathy나 Nova 같은 보편 규칙 전문을 모든 프로젝트 CLAUDE.md에 복붙한다.
- 배포 runbook 전체를 CLAUDE.md에 넣고 `/deploy` 진입점 없이 방치한다.
- `.env` 금지를 CLAUDE.md에만 쓰고 settings/hooks로 막지 않는다.
- 현재 phase와 todo를 CLAUDE.md에 넣어 오래된 지시로 만든다.
- 기존 프로젝트에서 이력을 지우고 새 템플릿으로 덮어쓴다.
- `@docs/large-file.md` import로 CLAUDE.md를 짧아 보이게만 만든다. import도 launch context를 소비한다.

## 검증 체크리스트

- [ ] CLAUDE.md 또는 AGENTS.md가 200줄 이하인가? 150줄 이하이면 더 좋다.
- [ ] 신규 프로젝트의 모르는 정보가 추측되지 않고 TODO/질문으로 남았는가?
- [ ] 기존 프로젝트의 중요한 규칙이 삭제되지 않고 이동/유지/강제 분류되었는가?
- [ ] hard guard가 advisory인지 enforced인지 표시되었는가?
- [ ] 배포/릴리스/마이그레이션 절차가 skill/command로 분리되었는가?
- [ ] path-specific 지침이 `.claude/rules/`로 분리되었는가?
- [ ] cross-agent 구조가 명시되었는가? (`AGENTS.md` canonical 또는 bridge)
- [ ] 다음 에이전트가 분리 기준을 볼 수 있는가?
