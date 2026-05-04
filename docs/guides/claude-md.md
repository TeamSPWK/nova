# /nova:claude-md Guide

This guide explains why `/nova:claude-md` exists and how to decide whether an instruction belongs in `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, `.claude/settings.json`, hooks, CI, or another project artifact.

한국어와 English를 모두 포함한다.

---

## 한국어

### 요약

`/nova:claude-md`는 `CLAUDE.md`를 예쁘게 다시 쓰는 커맨드가 아니다. 에이전트가 매 세션 읽는 지침 표면을 정리해서, 프로젝트 맥락은 잘 보이게 두고 강제해야 하는 규칙은 설정/훅/CI로 옮기기 위한 커맨드다.

### 왜 필요한가

AI 에이전트가 레포 규칙을 따르는 품질은 `CLAUDE.md`와 주변 설정 구조에 점점 더 크게 의존한다. 그런데 모든 내용을 `CLAUDE.md`에 넣으면 세 가지 문제가 생긴다.

1. 중요한 규칙과 긴 설명이 섞여 에이전트가 핵심을 놓친다.
2. 프로젝트마다 구조가 달라 팀원이 같은 규칙을 반복해서 설명해야 한다.
3. 보안, 포맷팅, 보호 파일 차단처럼 강제해야 할 일을 문장으로만 남기게 된다.

따라서 목표는 `CLAUDE.md`를 키우는 것이 아니라, 역할을 나누는 것이다. `CLAUDE.md`는 매 세션 필요한 운영 맥락과 라우터로 유지하고, 더 좁거나 더 강한 지침은 적절한 위치로 분리한다.

### 지침 배치 원칙

| 내용 | 권장 위치 | 이유 |
|------|-----------|------|
| 프로젝트 개요, 아키텍처, 빌드/테스트 명령, 공통 위험 경계 | `CLAUDE.md` 또는 `AGENTS.md` | 모든 세션에서 필요한 불변 맥락 |
| Claude 전용 보충 지침 | `CLAUDE.md` 또는 `.claude/CLAUDE.md` | Claude Code가 직접 읽는 프로젝트 메모리 |
| Codex/다른 에이전트까지 공유할 공통 계약 | `AGENTS.md` | 여러 에이전트가 같은 시작점을 공유 |
| 특정 디렉토리나 파일 타입에만 적용되는 규칙 | `.claude/rules/*.md` | 필요할 때만 로드해서 `CLAUDE.md` 비대화 방지 |
| 반복 가능한 배포, 마이그레이션, 리뷰 절차 | `.claude/skills/` 또는 `.claude/commands/` | 절차를 실행 단위로 분리 |
| 위험 명령 차단, 권한, 환경변수, 도구 동작 | `.claude/settings.json` | 설정으로 관리해야 하는 정책 |
| 포맷팅, 보호 파일 차단, 세션 시작 컨텍스트 주입 | hooks, CI, scripts | 문장이 아니라 자동 실행/강제로 보장 |
| 현재 phase, TODO, blocker, 최근 검증 | `NOVA-STATE.md` 또는 이슈 트래커 | 변하는 상태를 지침 파일에서 분리 |
| 개인 경로, 로컬 URL, private preference | `CLAUDE.local.md`, `.claude/settings.local.json` | 공유 레포에 커밋하지 않을 정보 |

### 사용 방법

```bash
/nova:claude-md --check   # 현재 지침 표면 감사만 수행
/nova:claude-md --adopt   # 기존 CLAUDE.md/AGENTS.md 재구성안 생성
/nova:claude-md --new     # 신규 프로젝트용 지침 골격 생성
/nova:claude-md --apply   # 승인된 재구성안 적용
```

기존 레포에서는 먼저 `--check`로 시작한다. 결과를 보고 각 섹션을 `keep / move / enforce / local-only / remove`로 분류한 뒤, 팀이 동의한 항목만 적용한다.

### 팀 공유 문구

```md
@core Nova 최신으로 업데이트하신 뒤 `/nova:claude-md`를 한번 사용해보시면 좋겠습니다.

이 커맨드는 `CLAUDE.md`를 더 길게 만드는 목적이 아니라, 에이전트가 실제 작업 중 안정적으로 참조할 수 있도록 지침의 역할을 나누는 목적입니다.

- `CLAUDE.md`/`AGENTS.md`: 프로젝트 맥락, 빌드/테스트, 공통 작업 규칙
- `.claude/rules`: 특정 경로나 파일 타입에만 적용되는 규칙
- `.claude/settings.json`: 권한, 환경변수, 도구 동작
- hooks/CI/scripts: 포맷팅, 보호 파일 차단, 위험 작업 차단처럼 자동화나 강제가 필요한 항목
- `NOVA-STATE.md`: 현재 phase, blocker, 최근 검증처럼 계속 변하는 상태

각 레포에서 `/nova:claude-md --check`를 먼저 실행해보고, 에이전트가 자주 헷갈리는 부분이나 settings/hooks/rules로 분리하는 게 나은 항목이 있으면 같이 정리해보면 좋겠습니다.
```

---

## English

### Summary

`/nova:claude-md` is not a formatter for `CLAUDE.md`. It is a command for designing the project instruction surface that AI agents read before they work. The goal is to keep project context visible while moving narrow, volatile, or enforceable rules to the right artifact.

### Why this exists

Agent reliability increasingly depends on the quality of project instructions. If every note goes into `CLAUDE.md`, three problems show up quickly.

1. Critical rules get buried inside long reference text.
2. Different repositories teach agents with different structures, so teams repeat the same corrections.
3. Things that should be enforced, such as secret access, formatting, protected files, or risky commands, remain as advisory prose.

The goal is not to make `CLAUDE.md` larger. The goal is to make instruction placement explicit. Keep `CLAUDE.md` as the always-on operating context and router, then move narrower or stronger rules to the surface that can actually own them.

### Instruction placement contract

| Content | Recommended home | Why |
|---------|------------------|-----|
| Project overview, architecture, build/test commands, shared risk boundaries | `CLAUDE.md` or `AGENTS.md` | Stable context every agent needs |
| Claude-specific supplement | `CLAUDE.md` or `.claude/CLAUDE.md` | Claude Code project memory |
| Shared contract for Codex and other agents | `AGENTS.md` | Common entrypoint across agent tools |
| Rules for specific paths or file types | `.claude/rules/*.md` | Loaded only when relevant, keeping core memory small |
| Repeatable workflows such as deploy, migration, review | `.claude/skills/` or `.claude/commands/` | Procedures belong in executable workflows |
| Permissions, environment variables, tool behavior | `.claude/settings.json` | Policy belongs in settings |
| Formatting, protected-file checks, session-start context injection | hooks, CI, scripts | Deterministic behavior should be automated or enforced |
| Current phase, TODOs, blockers, recent verification | `NOVA-STATE.md` or issue tracker | Volatile state should not live in instruction memory |
| Personal paths, local URLs, private preferences | `CLAUDE.local.md`, `.claude/settings.local.json` | Local details should stay out of source control |

### How to use it

```bash
/nova:claude-md --check   # Audit the current instruction surface
/nova:claude-md --adopt   # Propose a reorganization for an existing repo
/nova:claude-md --new     # Create a new-project instruction skeleton
/nova:claude-md --apply   # Apply an approved reorganization
```

For existing repositories, start with `--check`. Review the proposed `keep / move / enforce / local-only / remove` classification, then apply only the changes your team agrees with.

### Announcement copy

```md
@core Please update Nova and try `/nova:claude-md`.

This command is not meant to make `CLAUDE.md` longer. It helps split agent instructions by role so Claude/Codex can read the right context and teams can enforce the rules that should not remain as prose.

- `CLAUDE.md`/`AGENTS.md`: project context, build/test commands, shared operating rules
- `.claude/rules`: path-specific or file-type-specific rules
- `.claude/settings.json`: permissions, environment variables, tool behavior
- hooks/CI/scripts: formatting, protected-file checks, risky-operation blocks, and other enforceable behavior
- `NOVA-STATE.md`: changing state such as phase, blockers, and recent verification

Please run `/nova:claude-md --check` in each repo and share anything agents repeatedly misunderstand, or anything that should move from prose into settings/hooks/rules.
```

## References

- [Claude Code `.claude` directory](https://code.claude.com/docs/en/claude-directory)
- [Claude Code memory and rules](https://code.claude.com/docs/en/memory)
- [Claude Code settings](https://code.claude.com/docs/en/configuration)
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)
