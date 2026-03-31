# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-3.1.1-blue)](https://github.com/TeamSPWK/nova/releases)
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

## How It Works

Nova installs into your Claude Code environment and **automatically applies** its Quality Gate methodology to every conversation — no commands needed. The CLAUDE.md auto-apply rules handle complexity assessment, Generator-Evaluator separation, and verification.

### Core Principles

| Principle | What It Means |
|-----------|--------------|
| **Structured** | CPS framework (Context → Problem → Solution) prevents building the wrong thing |
| **Consistent** | Same process and quality baseline regardless of who works or which AI is used |
| **X-Verification** | Multi-perspective collection from multiple AI models for design decisions |
| **Adaptive** | Rules evolve with the project — good patterns are proposed, reviewed, and absorbed |

### Generator-Evaluator Separation

> "A model tends to praise its own output."

The agent that implements code and the agent that evaluates it are **always separate**. The evaluator takes an adversarial stance: *find problems, don't rubber-stamp*.

## Commands

All commands use the `nova:` prefix.

| Command | Description |
|---------|------------|
| `/nova:next` | Recommends next action based on project state |
| `/nova:plan feature` | Creates a CPS Plan document |
| `/nova:design feature` | Creates a CPS Design document |
| `/nova:auto feature` | One-shot verification: static analysis + structural review + design alignment |
| `/nova:xv "question"` | Multi-AI perspective collection (Claude + GPT + Gemini) |
| `/nova:gap design.md src/` | Detects gaps between design and implementation |
| `/nova:review src/` | Adversarial code review |
| `/nova:init project` | Initializes Nova in a new project |
| `/nova:propose pattern` | Proposes a new rule from recurring patterns |
| `/nova:metrics` | Measures Nova adoption level |

> **Works without commands too.** Once installed, Nova's auto-apply rules in CLAUDE.md handle complexity assessment → implementation → independent verification in normal conversations.

## Workflow

```
Request
  │
  ├── Simple (bug fix, 1-2 files)
  │   └── Implement → Independent Evaluator → Done
  │
  ├── Medium (new feature, 3-7 files)
  │   └── Plan → Approve → Implement → Independent Evaluator → Done
  │
  └── Complex (8+ files, multi-module)
      └── Plan → Design → Sprint split → Approve
          → Per-sprint (Implement → Evaluate) loop
          → Independent Verifier → Done
```

**Manual mode**: `/nova:plan` → `/nova:xv` (if needed) → `/nova:design` → Build → `/nova:gap` → `/nova:review`

**Verify mode**: `/nova:auto feature` → One-shot verification → Quality Gate verdict

## Specialist Agents

| Agent | Expertise |
|-------|----------|
| `architect` | System architecture, tech selection, scalability |
| `senior-dev` | Code quality, refactoring, tech debt |
| `qa-engineer` | Test strategy, edge cases, quality verification |
| `security-engineer` | Vulnerability scanning, threat modeling, auth review |
| `devops-engineer` | CI/CD pipelines, infrastructure, deployment |

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

Our CI runs a [self-verification test](tests/test-self-verify.sh) against intentionally flawed code. Here's what the gap detection finds in a simple auth module:

| Defect | Type | Detection Method |
|--------|------|-----------------|
| Missing `GET /api/auth/me` endpoint | Design-Implementation Gap | Endpoint diff: design doc vs route handlers |
| Plaintext password storage | Security | Design requires bcrypt, code has no hashing import |
| No email duplicate check (missing 409) | Verification Contract Breach | Design specifies 409 response, code has no conflict handling |
| No password min-length validation | Verification Contract Breach | Design requires 8+ chars, code has no length check |
| JWT token missing userId | Data Contract Mismatch | Design specifies userId in token payload, code only includes email |
| Hardcoded JWT secret key | Security Pattern | Static analysis: string literal in `jwt.sign()` |

> These are **structural checks** that run without an AI model. When Nova's AI agents (`/nova:gap`, `/nova:review`) analyze code, they perform deeper semantic analysis on top of these structural patterns.

## FAQ

### When should I NOT use Nova?

Nova adds value when design decisions matter. For these cases, just code directly:

- **One-line fixes**: Typos, version bumps, config tweaks — no CPS needed.
- **Well-defined bug fixes**: Stack trace points to the cause? Fix it. Don't write a Plan.
- **Exploratory prototypes**: If you're going to throw it away, skip the process.
- **Tasks under 30 minutes**: If the full cycle (Plan → Design → Gap) takes longer than the task itself, it's overhead, not help.

**Rule of thumb**: If you can hold the entire change in your head, you don't need Nova.

### Are the KPIs proven results?

No. The KPIs in our methodology doc are **adoption targets**, not measured outcomes. We're transparent about this — Nova is a young project and we don't yet have statistically significant before/after data. If you run Nova on a real project and measure results, we'd love to hear about it.

### Can `/nova:xv` multi-AI consensus be wrong?

Yes. Known limitations:

- **Shared training bias**: Claude, GPT, and Gemini share much of the same training corpus. Strong Consensus doesn't guarantee correctness — it may reflect a shared blind spot.
- **Qualitative judgment**: Consensus levels (Strong/Partial/Divergent) are AI-generated assessments, not quantitative metrics.
- **Not a substitute for expertise**: `/nova:xv` enriches your decision-making material. The final call is always yours — especially in domains where all LLMs lack depth (niche frameworks, internal systems, novel architectures).

When all three models agree, ask yourself: *"Is this something they could all be wrong about?"* If yes, seek a human expert.

### How does Nova work with orchestrators like Paperclip?

Nova is a Quality Gate — it verifies, not orchestrates. External orchestrators (Paperclip, etc.) handle agent scheduling, budgets, and team coordination. Nova fits inside their loop as a verification checkpoint: the orchestrator builds, Nova checks.

## Documentation

- [Usage Guide](docs/usage-guide.md) — Detailed command and agent reference
- [Nova Engineering](docs/nova-engineering.md) — Full methodology (4 Pillars, CPS, security)
- [Tutorial: Todo API](examples/tutorial-todo-api.md) — End-to-end workflow walkthrough

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- API keys: OpenAI + Google AI Studio (optional, for `/nova:xv` only)

## License

MIT — [Spacewalk Engineering](https://spacewalk.tech)
