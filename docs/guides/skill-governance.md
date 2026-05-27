# Skill Governance Guide

이 가이드는 Nova가 ship하는 13개 스킬(+16 커맨드)을 사용자가 어떻게 통제할 수 있는지 설명한다. Claude Code의 `skillOverrides` 설정을 활용해 자동 트리거를 끄거나, 명시 호출 전용으로 바꾸거나, 메타데이터를 숨길 수 있다.

한국어와 English를 모두 포함한다.

> 정확한 최신 카운트는 `docs/nova-meta.json`의 `stats.skills` / `stats.commands` 필드 참조. 본 가이드 작성 시점은 v5.30.3.

---

## 한국어

### 요약

Nova는 다음 11개 **스킬**을 ship한다 (커맨드와 별개):

| 카테고리 | 스킬 |
|----------|------|
| 품질 게이트 | `evaluator`, `jury` |
| 계획·설계 | `deepplan`, `orchestrator` |
| 운영 (세션·환경) | `context-chain`, `worktree-setup`, `repo-preflight`, `strategic-compact` |
| 메타 | `writing-nova-skill` |
| 도메인 | `claude-md`, `ux-audit`, `status-dashboard` |

> ⚠️ `scan`, `setup`, `next`, `auto`, `run`, `plan`, `design`, `review`, `check`, `ask`는 **커맨드(`/nova:*`)**이지 스킬이 아니다.
> ⚠️ `evolution`, `field-test`, `audit-self`는 Nova 개발자 전용으로 `dev/`에 격리됐다 (플러그인 배포 제외). 일반 사용자 환경에는 노출되지 않으므로 `skillOverrides`로 제어할 수 없다. `skillOverrides`로 제어할 수 없다. 커맨드는 사용자가 명시 호출(`/`) 시에만 동작하므로 별도 비활성화가 필요한 경우는 적다 — Nova plugin 자체를 settings에서 제외하면 커맨드도 함께 사라진다.

모두 활성화하면 컨텍스트 점유와 자동 트리거 빈도가 높아진다. Claude Code v2.1.126+가 제공하는 `skillOverrides` 설정으로 스킬을 선택적으로 끌 수 있다.

### 언제 사용하나

- 특정 도메인(예: 프론트엔드 전용 프로젝트에 backend-only 스킬, 또는 그 반대)에서 일부 Nova 스킬이 매번 자동 활성화돼서 컨텍스트가 무거울 때
- 메타-스킬(`evaluator`, `jury`)을 일시적으로 비활성화하고 빠르게 prototype을 만들고 싶을 때
- 특정 스킬은 모델이 자동 호출하지 않게 하고, 사용자가 `/스킬명`으로 명시 호출할 때만 쓰고 싶을 때

### 3가지 모드

`skillOverrides`는 `~/.claude/settings.json` 또는 프로젝트 `.claude/settings.json`에 작성한다.

| 모드 | 동작 | 권장 사용처 |
|------|------|-------------|
| `off` | 모델에서도, `/`에서도 완전히 숨김 | 본인 도메인과 무관한 스킬 (예: 모바일 전용 팀의 figma 스킬) |
| `user-invocable-only` | 모델 자동 트리거 차단, `/스킬명` 명시 호출만 허용 | 무거운 스킬을 명시 호출 시에만 쓰고 싶을 때 (`deepplan`, `ux-audit`) |
| `name-only` | 이름만 노출, description 숨김 (메타데이터 점유 ↓) | 스킬을 가끔 쓰지만 description이 매번 로드되는 게 부담일 때 |

### 설정 예시

```json
{
  "skillOverrides": {
    "nova:ux-audit": "off",
    "nova:writing-nova-skill": "user-invocable-only",
    "nova:strategic-compact": "name-only"
  }
}
```

> 키는 `<plugin>:<skill-name>` 형식. Nova 스킬은 모두 `nova:` 접두사를 갖는다. Nova가 ship하는 정확한 11개 스킬 외 이름을 적으면 사일런트로 무시된다 — 위 "요약" 표 참조.

### Nova 스킬 카테고리별 권장 설정

| 카테고리 | 스킬 (실제 ship 11개) | 권장 (대부분 사용자) | 권장 (가벼운 작업) |
|----------|----------------------|----------------------|---------------------|
| **품질 게이트 (핵심)** | `evaluator`, `jury` | 활성 (기본) | `evaluator`만 활성, `jury`는 `user-invocable-only` |
| **계획·설계** | `deepplan`, `orchestrator` | 활성 (자동 트리거 가치 큼) | `deepplan`은 `user-invocable-only` |
| **운영 (세션·환경)** | `context-chain`, `worktree-setup`, `repo-preflight`, `strategic-compact` | 활성 (기본) | 활성 — 환경 안전 직결 |
| **메타** | `writing-nova-skill` | `user-invocable-only` | `name-only` |
| **도메인** | `claude-md`, `ux-audit`, `status-dashboard` | 활성 (필요 도메인) | UX는 backend-only 프로젝트에서 `off` |

### 적용 후 확인

설정 후 새 Claude Code 세션을 시작하고 `/nova:` 자동완성에서 끈 스킬이 사라졌는지 확인한다. `off`로 설정한 스킬은 모델 자동 트리거에서도 호출되지 않는다.

`name-only` 모드의 경우, 스킬 이름은 보이지만 description은 빈 문자열이 된다 (모델은 description으로 트리거 판단을 하므로 자동 트리거 빈도가 ↓).

### 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `skillOverrides`를 설정했는데 스킬이 여전히 자동 트리거된다 | Claude Code 버전이 v2.1.126 미만 | `claude --version` 확인 후 업그레이드 |
| `off`인데 description이 로드되는 것 같다 | 같은 스킬이 다른 plugin에서도 ship됨 | plugin별로 키 형식 정확히 매칭 (`<plugin>:<skill>`) |
| 명시 호출(`/`)에서도 안 보인다 | `off`로 설정함 | `user-invocable-only`로 변경 |

### 참고

- `skillOverrides` 자체 정의: Claude Code v2.1.126~131 changelog
- Nova 스킬 전체 목록: `docs/nova-meta.json` (자동 생성됨, `bash scripts/generate-meta.sh`)
- Nova 스킬 추가 컨벤션: `.claude/skills/writing-nova-skill/SKILL.md`

---

## English

### TL;DR

Nova ships 11 **skills** (separate from commands) covering quality gates, planning, environment, meta, and domain helpers. If they all auto-trigger you may end up with heavy context usage. Claude Code v2.1.126+ exposes `skillOverrides` so you can selectively disable, restrict to manual `/` invocation, or hide descriptions of skills you don't need.

> Note: `scan`, `setup`, `next`, `auto`, `run`, `plan`, `design`, `review`, `check`, `ask` are **commands** (`/nova:*`), not skills — they cannot be controlled via `skillOverrides`. Commands only run on explicit `/` invocation, so disabling them is rarely needed; if you need to remove them entirely, exclude the Nova plugin from your settings.
> Note: `evolution`, `field-test`, `audit-self` are Nova-developer-only and isolated under `dev/` (excluded from plugin distribution). They never reach end-user environments, so `skillOverrides` does not apply.

### Three modes

Edit `~/.claude/settings.json` or project `.claude/settings.json`:

| Mode | Behavior | When to use |
|------|----------|-------------|
| `off` | Hidden from model and `/` | Skills outside your domain (e.g. figma skills on a backend-only project) |
| `user-invocable-only` | Model auto-trigger disabled, `/skill-name` still works | Heavy skills you only want on demand (`deepplan`, `ux-audit`) |
| `name-only` | Name visible, description hidden — reduces metadata footprint | Skills you use occasionally but the description load is heavy |

### Example

```json
{
  "skillOverrides": {
    "nova:ux-audit": "off",
    "nova:writing-nova-skill": "user-invocable-only",
    "nova:strategic-compact": "name-only"
  }
}
```

Keys follow `<plugin>:<skill-name>`. All Nova skills are namespaced under `nova:`. Skill names that don't match an actually-shipped skill are silently ignored — see the table above for the canonical 11.

### Recommended defaults

- **Quality gate skills** (`evaluator`, `jury`): keep active. Disabling these defeats Nova's core value.
- **Planning** (`deepplan`, `orchestrator`): active for most users; consider `user-invocable-only` for `deepplan` if your work is mostly small tasks.
- **Operations** (`context-chain`, `worktree-setup`, `repo-preflight`, `strategic-compact`): keep active — they protect against env/secret drift and session-state loss.
- **Meta** (`writing-nova-skill`): `user-invocable-only` or `name-only` for most teams.
- **Domain** (`claude-md`, `ux-audit`, `status-dashboard`): keep active where the domain applies; `off` for `ux-audit` on backend-only projects.

### Verification

After editing settings, start a new Claude Code session. Disabled skills should not appear in `/nova:` autocomplete (`off` mode), and `name-only` skills should show empty descriptions.

### References

- `skillOverrides` shipped in Claude Code v2.1.126~131 (May 2026 changelog)
- Full Nova skill catalog: `docs/nova-meta.json` (auto-generated by `bash scripts/generate-meta.sh`)
- Skill authoring conventions: `.claude/skills/writing-nova-skill/SKILL.md`
