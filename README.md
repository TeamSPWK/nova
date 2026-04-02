# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-3.10.2-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Verify Before You Ship. Every Time.**

[한국어](README.ko.md)

> AI coding tools make you type faster — but the real bottleneck isn't typing.
> A single wrong decision in week 1 compounds into a full rewrite by week 4.
> Nova **structures design decisions** to eliminate rework.

Nova is a [Claude Code](https://claude.ai/code) plugin that acts as a **Quality Gate** for AI-assisted development. It doesn't orchestrate — it verifies. Independent evaluation, multi-AI cross-verification, and design-implementation gap detection.

## Quick Start

```bash
# Install (30 seconds)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# Start
/nova:next   # Shows what to do next
```

## What Is Nova?

Nova is a **checkpoint inside the AI orchestrator loop**. It doesn't generate code — it verifies that generated code is correct.

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

## How It Works: Natural Language Is Enough

Once installed, Nova's Quality Gate **automatically applies to every conversation** — no commands needed. Just describe your task in natural language.

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

These rules apply to every conversation the moment Nova is installed.

### 1. Automatic Complexity Assessment

| Complexity | Criteria | Auto Behavior |
|-----------|----------|--------------|
| **Simple** | 1-2 files, clear bug | Implement → Evaluator Lite |
| **Medium** | 3-7 files, new feature | Plan → Approve → Implement → Evaluator Standard |
| **Complex** | 8+ files, multi-module | Plan → Design → Sprint split → Evaluator Full |

- Auth/DB/Payment domains escalate one level regardless of file count
- Re-assess if file count exceeds initial estimate during work

### 2. Generator-Evaluator Separation (Core)

- Implementation (Generator) and verification (Evaluator) are **always separate agents**
- Evaluator takes an adversarial stance: "Find problems, don't rubber-stamp"
- Lite verification by default; full verification only with `--strict`

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

| Command | Description | When To Use |
|---------|------------|-------------|
| `/nova:next` | Diagnose project state + recommend next action | Session start, unsure what to do |
| `/nova:plan feature` | Create CPS Plan document | Planning new features |
| `/nova:design feature` | Create CPS Design document | Technical design after Plan |
| `/nova:review src/` | Adversarial code review (`--fast` / `--strict` / `--fix` / `--jury`) | Code quality check |
| `/nova:verify` | Combined review + gap (`--fast` / `--strict`) | Post-implementation check |
| `/nova:gap design.md src/` | Design↔Implementation gap detection (`--fast` / `--strict`) | Verify design alignment |
| `/nova:xv "question"` | Multi-AI perspective (Claude+GPT+Gemini, `--agent` for no API keys) | Design decisions, architecture choices |
| `/nova:auto feature` | Implement→verify cycle (`--verify-only` / `--emergency`) | End-to-end automation |
| `/nova:init project` | Initialize Nova + create custom agents | New project setup |
| `/nova:propose pattern` | Propose recurring patterns as rules | Rule evolution |
| `/nova:metrics` | Measure Nova adoption level | Adoption tracking |
| `/nova:explore` | Auto-analyze codebase, brief where to start | First time on a new project |

## Workflow

### Auto Workflow (Natural Language)

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
/nova:plan → /nova:xv (if needed) → /nova:design → Build → /nova:gap → /nova:review
```

## Specialist Agents (5 Types)

Each agent has a built-in Nova self-check checklist.

| Agent | Expertise | Built-in Checklist |
|-------|----------|-------------------|
| `architect` | System design, tech selection, scalability | Design alignment, non-functional requirements |
| `senior-dev` | Code quality, refactoring, tech debt | Execution verification, env change 3-step, boundary values |
| `qa-engineer` | Test strategy, edge cases, quality verification | Boundary values, Known Gaps, Hard-Block classification |
| `security-engineer` | Vulnerability scanning, threat modeling, auth | Auth/secret Hard-Block, Known Gaps |
| `devops-engineer` | CI/CD, infrastructure, deployment | Post-deploy checklist, blocker classification |

## Session State (NOVA-STATE.md)

Nova maintains context across sessions via `NOVA-STATE.md`.

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

## API Keys (Optional)

Only `/nova:xv` (multi-perspective collection) requires API keys. Everything else works without them.

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

## What Nova Catches

Our CI runs a [self-verification test](tests/test-self-verify.sh) against intentionally flawed code:

| Defect | Type | Detection Method |
|--------|------|-----------------|
| Missing `GET /api/auth/me` endpoint | Design-Implementation Gap | Design doc vs route handler diff |
| Plaintext password storage | Security | Design requires bcrypt, no hashing in code |
| No email duplicate check (missing 409) | Verification Contract Breach | Design specifies 409, no conflict handling |
| Hardcoded JWT secret key | Security Pattern | Static analysis: string literal |

## FAQ

### When should I NOT use Nova?

- **One-line fixes**: Typos, version bumps — no CPS needed
- **Clear bug fixes**: Stack trace points to cause? Just fix it
- **Throwaway prototypes**: Skip the process
- **Tasks under 30 minutes**: If the cycle takes longer than the task, it's overhead

**Rule of thumb**: If you can hold the entire change in your head, you don't need Nova.

### Can `/nova:xv` multi-AI consensus be wrong?

Yes. Claude, GPT, and Gemini share much training data. Even unanimous agreement may reflect a shared blind spot. The final call is always yours.

### How does Nova work with orchestrators like Paperclip?

Nova is a Quality Gate — it verifies, not orchestrates. The orchestrator builds, Nova checks. It's the checkpoint inside their loop.

## Documentation

- [Usage Guide](docs/usage-guide.md) — Detailed command and agent reference
- [Nova Engineering](docs/nova-engineering.md) — Full methodology (4 Pillars, CPS, security)
- [Tutorial: Todo API](examples/tutorial-todo-api.md) — End-to-end workflow walkthrough

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- API keys: OpenAI + Google AI Studio (optional, for `/nova:xv` only)

## License

MIT — [Spacewalk Engineering](https://spacewalk.tech)
