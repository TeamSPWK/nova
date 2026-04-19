# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-5.14.0-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**AI Agent Ops Framework for Claude Code.**
**Verify Before You Ship. Every Time.**

[한국어](README.ko.md)

> AI coding tools make you type faster — but the real bottleneck isn't typing.
> A single wrong decision in week 1 compounds into a full rewrite by week 4.
> Nova gives AI agents the **operating environment** they need to work reliably.

Nova is a [Claude Code](https://claude.ai/code) plugin that makes AI agents operate **dependably** in real projects. It started as a Quality Gate — and that's still the strongest pillar — but it now spans five:

| Pillar | Purpose |
|--------|---------|
| **Environment** | Worktree, secret-sharing, isolated agent workspaces — see [Worktree Setup guide](docs/guides/worktree-setup.md) |
| **Context** | Session-to-session state continuity (`NOVA-STATE.md`) |
| **Quality** | Generator-Evaluator separation, pre-commit hard gate |
| **Collaboration** | Design→build→verify orchestration, multi-AI consulting |
| **Evolution** | Self-diagnosis and auto-upgrade |

The Quality pillar remains load-bearing: independent evaluation, multi-AI cross-verification, and design-implementation gap detection are injected into every session automatically.

## Quick Start

```bash
# Install (30 seconds)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# Start
/nova:next   # Shows what to do next
```

## What Is Nova?

Nova is a **checkpoint inside the AI orchestrator loop**. It verifies that generated code is correct, and orchestrates complex multi-step workflows when needed.

```
┌─────────────────────────────────────────────────┐
│  User Request                                    │
│       ↓                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │ Generator │───→│  Nova    │───→│Done/Fix  │   │
│  │ (Build)   │    │ (Verify) │    │          │   │
│  └──────────┘    └──────────┘    └──────────┘   │
│                       ↑                          │
│              Independent subagent                │
│              Adversarial stance                  │
└─────────────────────────────────────────────────┘
```

The core principle is **Generator-Evaluator Separation**: the agent that writes code and the agent that verifies it are always different. This prevents the "reviewing your own homework" trap.

## Architecture: Harness Engineering

Nova works by engineering Claude Code's **harness layer** — the hooks, commands, agents, and skills system that wraps around the LLM. Instead of changing what the model knows, Nova controls **when, how, and under what rules** the model operates.

```
┌─────────────────────────────────────────────────────┐
│  Claude Code Harness                                 │
│                                                      │
│  ┌─────────────────┐   SessionStart hook             │
│  │ session-start.sh │──→ Injects 10 rules as         │
│  │                  │    LLM context every session    │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   slash commands                │
│  │ .claude-plugin/  │──→ /nova:plan, /nova:review,    │
│  │   *.md           │    /nova:check, /nova:run ... │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   5 specialist subagents        │
│  │ .claude-plugin/  │──→ architect, senior-dev,       │
│  │   agents/*.md    │    qa-engineer, security, devops │
│  └─────────────────┘                                 │
│                                                      │
│  ┌─────────────────┐   5 complex skills              │
│  │ skills/*/SKILL.md│──→ evaluator, jury,             │
│  │                  │    context-chain, field-test,   │
│  │                  │    orchestrator                 │
│  └─────────────────┘                                 │
└─────────────────────────────────────────────────────┘
```

| Layer | File | Mechanism | What It Does |
|-------|------|-----------|-------------|
| **Rules injection** | `hooks/session-start.sh` | SessionStart hook | Injects 10 auto-apply rules into every session as LLM context |
| **Commands** | `.claude-plugin/*.md` | Slash commands | User-invocable workflows (`/nova:plan`, `/nova:review`, `/nova:check`, etc.) |
| **Agents** | `.claude-plugin/agents/*.md` | Subagent types | Specialist agents with domain-specific checklists |
| **Skills** | `skills/*/SKILL.md` | Skill system | Complex multi-step operations (evaluation, jury, context chain, orchestration) |
| **MCP Server** | `mcp-server/` | stdio MCP | Exposes Nova rules, state, and tools to any Claude Code session |

**Key distinction**: "Auto-apply rules" means `session-start.sh` injects rule text into Claude's context at session start. Claude then follows these rules as behavioral guidelines — it's prompt-level governance via the harness, not a code-level interceptor.

## Workflow

### Auto Workflow (Natural Language)

Once installed, Nova's Quality Gate **automatically applies to every conversation** — no commands needed. Just describe your task in natural language.

```
"Build a feature" ──→ Auto complexity assessment
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
           [Simple]        [Medium]        [Complex]
              │               │               │
           Implement       Plan→Approve    Plan→Design
              │               │            →Sprint split
              │            Implement        →Approve
              │               │               │
              ▼               ▼               ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │Evaluator │    │Evaluator │    │Evaluator │
        │  Lite    │    │ Standard │    │  Full    │
        └──────────┘    └──────────┘    └──────────┘
              │               │               │
           [PASS]          [PASS]          [PASS]
              ↓               ↓               ↓
            Done             Done            Done
```

### Manual Workflow (Commands)

```
/nova:plan → /nova:ask (if needed) → /nova:design → Build → /nova:check
```

## How It Works: Examples

### Example: "Build a login API"

```
User: "Build a login API"
         ↓
Nova auto-judges:
  1. Complexity → "Auth domain, escalate → Medium"
  2. Writes Plan → Waits for user approval
  3. After approval → Implements
  4. Independent Evaluator subagent runs adversarial review
     → "jwt_secret_key hardcoded → Hard-Block"
  5. Hard-Block found → Reports to user immediately
```

### Example: "Fix this bug" (Simple)

```
User: "Fix the NullPointerException"
         ↓
Nova auto-judges:
  1. Complexity → "1 file, clear bug → Simple"
  2. Fixes immediately
  3. Independent Evaluator runs Lite verification
  4. PASS → Done
```

### Example: "Refactor entire auth system" (Complex)

```
User: "Switch from JWT to session-based auth"
         ↓
Nova auto-judges:
  1. Complexity → "8+ files, auth domain → Complex"
  2. Plan → Design → User approval
  3. Sprint split (Sprint 1: Session model, Sprint 2: Middleware, ...)
  4. Per-sprint: Implement → Evaluate loop
  5. Full verification → Done
```

## Auto-Apply Rules (10 Rules)

These rules apply to every conversation the moment Nova is installed. They are injected as LLM context via the `session-start.sh` hook.

### 1. Automatic Complexity Assessment

| Complexity | Criteria | Auto Behavior |
|-----------|----------|--------------|
| **Simple** | 1-2 files, clear bug | Implement → Evaluator Lite |
| **Medium** | 3-7 files, new feature | Plan → Approve → Implement → Evaluator Standard |
| **Complex** | 8+ files, multi-module | Plan → Design → Sprint split → Evaluator Full |

- Auth/DB/Payment domains escalate one level regardless of file count
- Re-assess if file count exceeds initial estimate during work

### 2. Generator-Evaluator Separation + Pre-Commit Gate (Core)

- Implementation (Generator) and verification (Evaluator) are **always separate agents**
- Evaluator takes an adversarial stance: "Find problems, don't rubber-stamp"
- Lite verification by default; full verification only with `--strict`

**Pre-commit gate**: Implementation complete → tsc/lint pass → Evaluator run → PASS → commit allowed. No deploy before Evaluator PASS (exception: `--emergency`).

### 3. Verification Criteria (5 Dimensions)

| Criterion | What It Checks |
|-----------|---------------|
| **Functionality** | Does it actually work? (compared against requirements) |
| **Data Flow** | Input → Store → Load → Display → Deliver to user — complete? |
| **Design Alignment** | Consistent with existing code/architecture? |
| **Craft** | Error handling, edge cases, type safety |
| **Boundary Values** | Does it survive 0, negative, empty string, max values without crashing? |

### 4. Execution Verification First

- "Code exists" ≠ "Code works"
- "Tests pass" ≠ "Verified" — boundary values must be checked separately
- Environment changes follow 3 steps: Check current → Change → Verify applied

### 5–10. Additional Rules

| Rule | Description |
|------|------------|
| **§5 Lightweight Verification** | Default is Lite. Full verification only with `--strict` |
| **§6 Sprint Split** | 8+ file changes split into independently verifiable sprints |
| **§7 Blocker Classification** | Auto-Resolve / Soft-Block / Hard-Block. Forced classification after 2 repeated failures |
| **§8 NOVA-STATE.md** | Immediate update on deploy/test/sprint/blocker/eval results. Known Gaps required |
| **§9 Emergency Mode** | `--emergency` skips Plan/Design. Fix now, verify after |
| **§10 Environment Safety** | Never edit config files directly. Use env vars or CLI flags |

## Commands

Commands provide **additional control** on top of auto-apply rules.

<!-- AUTO-GEN:commands -->
| Command | Description |
|---------|------------|
| `/nova:ask` | 멀티 AI 다관점 자문을 실행한다. Claude + GPT + Gemini 3개 AI에게 동시에 질의하고 합의 수준을 분석한다. |
| `/nova:auto` | 자연어 요청을 설계→구현→검증→수정 전체 사이클로 자동 실행한다. |
| `/nova:check` | 코드 품질 리뷰 + 설계-구현 정합성 검증을 한 번에 수행한다. |
| `/nova:deepplan` | Explorer→Synth→Critic→Refiner 4단 파이프라인으로 깊이 있는 Plan 문서를 생성한다. |
| `/nova:design` | CPS(Context-Problem-Solution) 프레임워크로 Design 문서를 작성한다. |
| `/nova:evolve` | 기술 동향을 스캔하고 Nova를 자동으로 진화시킨다. 사용자 대신 Nova 품질 게이트가 변경을 검증한다. |
| `/nova:next` | 현재 프로젝트 상태를 진단하고 다음에 실행할 Nova 커맨드를 추천한다. |
| `/nova:plan` | CPS(Context-Problem-Solution) 프레임워크로 Plan 문서를 작성한다. |
| `/nova:review` | 코드를 적대적 관점에서 리뷰하고, 숨겨진 문제를 찾아낸다. |
| `/nova:run` | 구현→검증을 한 사이클로 실행한다 (Full Cycle). --verify-only로 검증만 수행 가능. |
| `/nova:scan` | 새 프로젝트에 처음 투입됐을 때 코드베이스를 자동 분석하고 '어디부터 볼지' 브리핑한다. |
| `/nova:setup` | 새 프로젝트에 Nova Quality Gate를 초기 설정하거나, 기존 프로젝트의 갭을 자동 보완한다 (--upgrade). |
| `/nova:ux-audit` | 5인 적대적 평가자로 UI/UX를 다관점 심층 평가. 접근성(WCAG 2.2)·인지 부하·성능(Core Web Vitals)·다크 패턴(EU DSA)까지 코드 기반 분석. |
| `/nova:worktree-setup` | 현재 worktree에서 메인 레포의 .env·시크릿·설정 파일을 즉시 심볼릭 링크한다. SessionStart 자동 훅의 수동 재시도 버전. |
<!-- /AUTO-GEN:commands -->

## Self-Evolution

Nova evolves itself. `/nova:evolve` scans tech trends, filters by Nova relevance, and proposes or applies improvements automatically.

```bash
/nova:evolve              # Scan trends + generate proposals (default)
/nova:evolve --apply      # Implement proposals + quality gate
/nova:evolve --auto       # scan + apply + auto-merge within scope
```

### Autonomy Policy

| Level | Example | Automation |
|-------|---------|-----------|
| **patch** | Docs improvement, checklist updates | Auto-commit |
| **minor** | New verification criteria, hook improvements | PR creation |
| **major** | New commands, architecture changes | Proposal only |

### Automatic Schedule

Runs automatically via Claude Code remote agent **every Mon/Wed/Fri at 06:00 KST**.

Manage: https://claude.ai/code/scheduled

## MCP Server

Nova includes a local MCP (Model Context Protocol) server that exposes Nova's rules, state, and tools to any Claude Code session — even outside the Nova project.

### Setup

```bash
cd mcp-server && pnpm install && pnpm build
```

The `.mcp.json` at project root auto-registers the server with Claude Code.

### Available Tools

| Tool | Description |
|------|------------|
| `get_rules` | Returns Nova rules (full or by section §1-§9) |
| `get_commands` | Lists all slash commands with descriptions |
| `get_state` | Reads NOVA-STATE.md from any project path |
| `create_plan` | Generates CPS Plan template for a given topic |
| `orchestrate` | Returns agent formation guide by complexity |
| `verify` | Returns verification checklist by scope (lite/standard/full) |

### How It Works

```
Any Project ──→ Claude Code ──→ Nova MCP Server (localhost, stdio)
                                    │
                                    ├── get_rules()     → Full Nova ruleset
                                    ├── get_state()     → NOVA-STATE.md
                                    └── orchestrate()   → Agent team guide
```

The MCP server reads files directly from the Nova installation directory. No API calls, no external dependencies.

## Skills

Skills are multi-step operations that commands invoke internally. They can also be called directly.

<!-- AUTO-GEN:skills -->
| Skill | Description |
|-------|------------|
| **context-chain** | Nova Context Chain — 세션 간 맥락 연속성 보장. NOVA-STATE.md 기반 상태 관리. |
| **deepplan** | Nova DeepPlan — Explorer×3 병렬 탐색 → Synthesizer → Critic → Refiner 4단 파이프라인으로 깊이 있는 Plan 문서를 생성한다. |
| **evaluator** | Nova Adversarial Evaluator — Nova Quality Gate의 핵심 검증 엔진. 독립 서브에이전트로 코드를 적대적 관점에서 검증. |
| **evolution** | Nova Self-Evolution 엔진 — 기술 동향 스캔, 관련성 필터, 자율 범위 구현까지 전체 파이프라인 |
| **field-test** | 실제 프로젝트에서 Nova를 사용해보며 개선 포인트를 찾는 실전 테스트. 워크트리 격리로 흔적 없이 진행. |
| **jury** | Nova LLM Jury — 다중 관점 평가로 단일 Evaluator의 편향을 보정 |
| **orchestrator** | Nova Orchestrator — 자연어 요청을 CPS 설계→에이전트 편성→구현→검증→수정 전체 사이클로 자동 실행 |
| **ux-audit** | Nova UX Audit — 5인 적대적 평가자(Adversarial Jury)로 UI/UX를 다관점 심층 평가. 코드 기반 분석 + 선택적 화면 캡처. |
| **worktree-setup** | Nova Worktree Setup — git worktree 진입 시 메인 레포의 .env·시크릿·설정 파일을 자동 심볼릭 링크한다. 환경 기둥의 첫 시민. |
<!-- /AUTO-GEN:skills -->

## Specialist Agents (5 Types)

Each agent has a built-in Nova self-check checklist.

<!-- AUTO-GEN:agents -->
| Agent | Description |
|-------|------------|
| `architect` | 시스템 아키텍처 설계, 기술 선택, 확장성/유지보수성 검토가 필요할 때 사용 |
| `devops-engineer` | CI/CD 파이프라인, 인프라 설정, 배포 전략, 모니터링 구성이 필요할 때 사용 |
| `qa-engineer` | 테스트 전략 수립, 엣지 케이스 식별, 품질 검증이 필요할 때 사용 |
| `security-engineer` | 보안 취약점 점검, 위협 모델링, 인증/인가 검토가 필요할 때 사용 |
| `senior-dev` | 코드 품질 개선, 리팩토링, 구현 전략 수립, 기술 부채 식별이 필요할 때 사용 |
<!-- /AUTO-GEN:agents -->

## Session State (NOVA-STATE.md)

Nova maintains context across sessions via `NOVA-STATE.md`. If it doesn't exist, it is auto-generated at session start.

```markdown
# NOVA-STATE — project-name

## Current
- **Goal**: JWT → Session-based auth migration
- **Phase**: building
- **Blocker**: none

## Recently Done
| Task | Completed | Verdict |
|------|-----------|---------|
| Sprint 1: Session model | 2026-04-01 | PASS |

## Known Gaps
| Area | Uncovered | Priority |
|------|-----------|----------|
| Concurrent session limit | Not implemented | Medium |
```

- Located at project root (git root)
- Updated immediately on deploy/test/sprint/blocker/eval results
- "ALL PASS" alone is not enough — Known Gaps must be included

## Blocker Classification

Nova auto-classifies issue severity.

| Classification | Condition | Response |
|---------------|-----------|----------|
| **Auto-Resolve** | Reversible without external changes | Auto-fix |
| **Soft-Block** | May fail at runtime | Log and continue |
| **Hard-Block** | Data loss, security, user misjudgment | **Stop immediately**, ask user |

Code review additional criteria:
- Runtime crash → Hard-Block
- Data corruption / integrity violation → Hard-Block
- User misjudgment (wrong amount/status displayed) → Hard-Block
- Same failure repeated 2x → Forced blocker classification

## What Nova Catches

Our CI runs a [self-verification test](tests/test-self-verify.sh) against intentionally flawed code:

| Defect | Type | Detection Method |
|--------|------|-----------------|
| Missing `GET /api/auth/me` endpoint | Design-Implementation Gap | Design doc vs route handler diff |
| Plaintext password storage | Security | Design requires bcrypt, no hashing in code |
| No email duplicate check (missing 409) | Verification Contract Breach | Design specifies 409, no conflict handling |
| Hardcoded JWT secret key | Security Pattern | Static analysis: string literal |

## API Keys (Optional)

Only `/nova:ask` (multi-perspective collection) requires API keys. Everything else works without them.

```bash
cat > .env << 'EOF'
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF
```

## Install / Update / Remove

```bash
# Install
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# Update
claude plugin update nova@nova-marketplace

# Remove
claude plugin uninstall nova@nova-marketplace
claude plugin marketplace remove nova-marketplace
```

### Codex CLI (Beta)

Nova provides a separate manifest for [Codex CLI](https://github.com/openai/codex) users. Skills (7 types) and MCP are available in Phase 1.

```bash
# 1) Clone into Codex plugin directory
git clone https://github.com/TeamSPWK/nova.git ~/.agents/plugins/nova

# 2) Build the MCP server
cd ~/.agents/plugins/nova/mcp-server && pnpm install && pnpm build

# 3) Activate via Codex CLI `/plugins` command,
#    or register manually in ~/.agents/plugins/marketplace.json
```

> **Note**: The `session-start.sh` hook (10 auto-apply rules) is a Claude Code-only feature and **does not work with Codex CLI**. Slash commands (`/nova:*`) and specialist agents are also unavailable in Phase 1. Attach `docs/nova-rules.md` manually at session start to get the rules.

**MCP registration (fallback — if the bundled `.codex-plugin/.mcp.json` does not auto-load):**

```toml
# ~/.codex/config.toml
[mcp_servers.nova]
command = "node"
args = ["/absolute/path/to/nova/mcp-server/dist/index.js"]
```

## FAQ

### When should I NOT use Nova?

- **One-line fixes**: Typos, version bumps — no CPS needed
- **Clear bug fixes**: Stack trace points to cause? Just fix it
- **Throwaway prototypes**: Skip the process
- **Tasks under 30 minutes**: If the cycle takes longer than the task, it's overhead

**Rule of thumb**: If you can hold the entire change in your head, you don't need Nova.

### Can `/nova:ask` multi-AI consensus be wrong?

Yes. Claude, GPT, and Gemini share much training data. Even unanimous agreement may reflect a shared blind spot. The final call is always yours.

### How does Nova work with AI orchestrators?

Nova is a Quality Gate — it verifies, not orchestrates. The orchestrator builds, Nova checks. It's the checkpoint inside their loop, integrated via Claude Code's harness layer.

### What is the MCP server for?

The MCP server lets any Claude Code session access Nova's rules and orchestration guides — even in projects that don't have Nova installed as a plugin. It's a "Nova brain" that's always available locally.

### What is "harness engineering"?

Prompt engineering shapes *what* the model says. Harness engineering shapes *when, how, and under what rules* the model runs — using hooks, plugins, commands, and agents. Nova is a harness engineering tool: it governs AI behavior through Claude Code's plugin system rather than through prompt manipulation.

## Documentation

- [Usage Guide](docs/usage-guide.md) — Detailed command and agent reference
- [Nova Engineering](docs/nova-engineering.md) — Full methodology (4 Pillars, CPS, security)
- [Tutorial: Todo API](examples/tutorial-todo-api.md) — End-to-end workflow walkthrough

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- API keys: OpenAI + Google AI Studio (optional, for `/nova:ask` only)

## License

MIT — [Spacewalk Engineering](https://spacewalk.tech)
