# Nova

[![CI](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamSPWK/nova/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.2.0-blue)](https://github.com/TeamSPWK/nova/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Build Right the First Time. Faster Every Time.**

[한국어](README.ko.md)

> AI coding tools make you type faster — but the real bottleneck isn't typing.
> A single wrong decision in week 1 compounds into a full rewrite by week 4.
> Nova **structures design decisions** to eliminate rework.

Nova is a [Claude Code](https://claude.ai/code) plugin that brings structured methodology to AI-assisted development: independent evaluation, multi-perspective analysis, and living rules that evolve with your project.

## Quick Start

```bash
# Install (30 seconds)
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

# Start
/nova:next   # Shows what to do next
```

## How It Works

Nova installs into your Claude Code environment and **automatically applies** its methodology to every conversation — no commands needed. The CLAUDE.md auto-apply rules handle complexity assessment, Generator-Evaluator separation, and verification.

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
| `/nova:auto feature` | Autonomous Plan → Design → Build → Verify pipeline |
| `/nova:xv "question"` | Multi-AI perspective collection (Claude + GPT + Gemini) |
| `/nova:gap design.md src/` | Detects gaps between design and implementation |
| `/nova:review src/` | Adversarial code review |
| `/nova:team preset` | Spawns parallel Agent Teams (QA, review, debug, etc.) |
| `/nova:init project` | Initializes Nova in a new project |
| `/nova:propose pattern` | Proposes a new rule from recurring patterns |
| `/nova:metrics` | Measures Nova adoption level |

> **Works without commands too.** Once installed, Nova's auto-apply rules in CLAUDE.md handle complexity assessment → implementation → independent verification in normal conversations.

## Agent Teams

`/nova:team` spawns purpose-built parallel agent teams. Team members appear in the tmux side panel.

| Preset | Team | Use Case |
|--------|------|----------|
| `qa` | Tester + Edge-case + Regression | Pre-PR quality check |
| `visual-qa` | Screenshot + Interaction + A11y | UI/UX verification |
| `review` | Architecture + Security + Performance | Code review |
| `design` | API + Domain Model + DX | Feature design |
| `refactor` | Clean Code + Dependencies + Tests | Tech debt |
| `debug` | Root Cause + Logs + Fix | Production issues |

> Agent Teams is experimental. Enable: add `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"` to `.claude/settings.json` env.

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

**Auto mode**: `/nova:auto feature` → One approval → Autonomous execution → Done

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

## Documentation

- [Usage Guide](docs/usage-guide.md) — Detailed command and agent reference
- [Nova Engineering](docs/nova-engineering.md) — Full methodology (4 Pillars, CPS, security)
- [Tutorial: Todo API](examples/tutorial-todo-api.md) — End-to-end workflow walkthrough

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- API keys: OpenAI + Google AI Studio (optional, for `/nova:xv` only)

## License

MIT — [Spacewalk Engineering](https://spacewalk.tech)
