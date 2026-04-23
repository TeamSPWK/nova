# Nova Launch Messages — Phase 2 Distribution

Drafts for getting Nova in front of the right audiences. **Copy, tweak tone to fit the platform's norms, post.** Do not post multiple channels on the same day — spread over 1–2 weeks to avoid looking like a coordinated push.

---

## 1. r/ClaudeAI — Reddit

**Title**
```
I built a quality gate plugin for Claude Code that catches AI-generated bugs before commit
```

**Body**
```
Hi all — I've been using Claude Code heavily for ~6 months and kept hitting the same wall: AI writes code fast, but one bad decision in week 1 compounds into a rewrite by week 4. So I built Nova, an open-source plugin that inserts a verification checkpoint into every session.

What it does:
- Injects 10 auto-apply rules at session start (complexity assessment, generator/evaluator separation, pre-commit gate)
- Runs an independent adversarial evaluator subagent on code changes before commit
- Optional multi-AI consultation via Claude + GPT + Gemini for architecture decisions
- Local MCP server so the rules are available in any Claude Code session

Install:
  claude plugin marketplace add TeamSPWK/nova
  claude plugin install nova@nova-marketplace

Repo: https://github.com/TeamSPWK/nova
License: MIT

Would love feedback — especially on cases where the evaluator catches bugs vs. rubber-stamps them. That's the hardest balance.
```

**Notes**
- Post on a weekday morning US time (Tue/Wed 9-11am ET is historical sweet spot for dev subreddits)
- Be present in the comments for 2-3 hours; answer every question
- Don't flag it as promotion — tell the story honestly

---

## 2. Anthropic Discord — #claude-code

**Message**
```
Sharing a Claude Code plugin I've been using in production — open-sourced today.

Nova (https://github.com/TeamSPWK/nova) is a quality gate plugin: it adds an independent "evaluator" subagent that adversarially reviews code changes before commit, and a session-start hook that injects 10 auto-apply rules (complexity assessment, design→build→verify flow, blocker classification).

It's harness engineering — no prompt manipulation, just using Claude Code's hooks + plugins + subagents to govern when and how the model operates.

14 slash commands (/nova:plan, /nova:review, /nova:check, …), 10 skills, 6 specialist agents, local MCP server. MIT licensed.

Install: `claude plugin marketplace add TeamSPWK/nova`

Happy to walk through the internals if anyone's curious about harness-layer plugin patterns.
```

**Notes**
- Discord rewards conversation over promotion — be ready to answer questions in real-time
- Reply in thread to anyone who engages

---

## 3. Hacker News — Show HN

**Title**
```
Show HN: Nova – Quality gate plugin for Claude Code (harness engineering)
```

**Body**
```
Nova is an open-source Claude Code plugin that adds a verification checkpoint to every AI-coded session.

The core idea: the agent that writes code and the agent that verifies it should always be different — otherwise it's "reviewing your own homework." Nova injects an independent adversarial evaluator subagent via Claude Code's plugin/hooks system. Before every commit, the evaluator runs five checks (functionality, data flow, design alignment, craft, boundary values) and blocks commit if it finds hard-blockers.

I call this pattern "harness engineering" — instead of changing what the model knows (prompt engineering), you control when, how, and under what rules the model operates. The harness is Claude Code's hook/command/agent/skill system; Nova plugs into all four layers.

Features:
- 10 auto-apply rules injected at session start (complexity, sprint splitting, blocker classification)
- Generator-Evaluator separation as a hard pre-commit gate
- Multi-AI consensus via /nova:ask (Claude + GPT + Gemini)
- Design-implementation gap detection
- Local MCP server exposing the ruleset to any Claude Code session

Repo: https://github.com/TeamSPWK/nova
Docs: (auto-generated in README)
License: MIT

I'd especially love feedback on the evaluator's false-negative rate — where it missed a real bug — since that's the scariest failure mode.
```

**Notes**
- Post Tue/Wed 8-10am PT
- Show HN posts need clarity about **what you built** and **what feedback you want**
- If it takes off, reply to top comments within 30 min

---

## 4. X / Twitter — Thread

**Tweet 1 (hook)**
```
AI coding tools make you type faster — but typing isn't the bottleneck.

A wrong decision in week 1 becomes a rewrite in week 4.

So I built Nova: a Claude Code plugin that inserts a quality gate into every AI session. Open source today. ↓
```

**Tweet 2 (mechanism)**
```
Core idea: separate the agent that writes code from the agent that verifies it.

Nova injects an independent adversarial evaluator before every commit. It runs 5 checks (functionality, data flow, design alignment, craft, boundary values) and blocks commit if it finds hard-blockers.
```

**Tweet 3 (install)**
```
Install (30 sec):

claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace

Repo → github.com/TeamSPWK/nova
MIT licensed. 14 slash commands, 10 skills, 6 specialist agents.
```

**Tweet 4 (pitch the idea)**
```
I call this pattern "harness engineering": not changing WHAT the model knows (prompt engineering), but controlling WHEN, HOW, and UNDER WHAT RULES it operates.

Claude Code's hooks + plugins + subagents are the harness. Nova governs behavior via all four layers.
```

**Notes**
- Pin the thread
- Attach the demo GIF to tweet 2 (when we have one)
- Tag: @AnthropicAI @claude_code (if valid) — don't over-tag

---

## 5. awesome-claude-code — PR

**Repositories to target** (search GitHub for `awesome-claude-code`, `awesome-anthropic`, `awesome-llm-tools`):

1. Find the most-starred awesome list for Claude Code plugins
2. PR format:
```
### Nova
- **Nova** — Quality gate plugin for Claude Code. Independent adversarial evaluator, pre-commit quality gate, multi-AI cross-verification. [GitHub](https://github.com/TeamSPWK/nova)
```

**Notes**
- Awesome lists typically require: working repo, >100 stars OR active maintenance, clear README. We're at 0 stars — delay until >50 organic stars accumulate from r/ClaudeAI + HN.

---

## Execution Plan

| Day | Channel | Why this order |
|-----|---------|---------------|
| Day 0 (now) | OG card + demo GIF ready, this doc reviewed | Assets before launch |
| Day 1 (Tue/Wed) | r/ClaudeAI | Highest conversion target audience |
| Day 2 | Anthropic Discord #claude-code | Community that gets it |
| Day 4-5 | X thread | Amplifies Reddit/Discord momentum |
| Day 7-10 | Show HN (if Reddit went well) | Can cite Reddit engagement |
| Day 14+ | awesome-claude-code PR (if stars accumulated) | Long-tail traffic |

## Post-launch metrics to track

- Stars per day
- Install counts (if measurable via plugin registry)
- Open issues/discussions — a sign of real adoption
- Forks + PRs — deepest engagement signal

If Day 1 (Reddit) produces <10 stars, the problem is likely the README hero or the demo GIF — iterate on the asset, not the channels.
