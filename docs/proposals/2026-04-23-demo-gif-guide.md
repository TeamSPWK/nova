# Nova Demo GIF — Recording Guide

For the README and launch tweets. Users can't record terminal GIFs for you, so this is a self-serve guide.

## 1. Install tools (one-time)

```bash
brew install asciinema agg
# agg = asciinema → gif converter (Rust-based, fast)
```

## 2. Choose the demo story

Best impact (20 sec): **Nova catches a bug that Claude generated.**

Scripted flow:
1. Show a deliberately broken file (hardcoded secret, missing endpoint, etc.)
2. Run `/nova:check`
3. Evaluator subagent reports Hard-Block
4. Commit is blocked at the git commit step
5. Show the verdict summary

## 3. Prep the stage

```bash
# Clean shell: remove Powerlevel10k clutter
export PS1='$ '
# Fresh Claude Code session in the Nova repo
cd ~/develop/swk/nova
# Seed a broken file (for demo reproducibility)
cat > /tmp/nova-demo/login.ts <<'EOF'
export async function login(email: string, password: string) {
  const jwt_secret_key = "hardcoded-super-secret-1234";  // Hard-Block
  return signJwt({ email }, jwt_secret_key);
}
EOF
```

## 4. Record

```bash
asciinema rec -t "Nova /nova:check catches a hardcoded secret" demo.cast
# Inside the recording:
#   claude
#   > /nova:review /tmp/nova-demo/login.ts
#   (wait for Evaluator output)
#   Ctrl+D to exit Claude
# Ctrl+D again to stop recording
```

**Pacing tip**: Type slowly the first 2 seconds (sets context). After the first enter, let Claude's output stream. Don't edit pauses out — the "waiting" is part of the drama when the evaluator subagent is thinking.

## 5. Convert to GIF

```bash
# Optimized for README embed (≤2 MB target)
agg demo.cast demo.gif \
  --theme monokai \
  --font-size 16 \
  --cols 100 \
  --rows 28 \
  --speed 1.2 \
  --idle-time-limit 1.5

# Check size
ls -lh demo.gif
# If >3 MB: re-run with --speed 1.5 or crop with gifsicle
```

## 6. Alternative — MP4 (smaller, sharper)

GitHub README supports `<video>` tags. MP4 is 5-10× smaller than GIF for the same quality.

```bash
# asciinema → mp4 via svg-term + ffmpeg
npm install -g svg-term-cli
svg-term --in demo.cast --out demo.svg
ffmpeg -i demo.svg -c:v libx264 -pix_fmt yuv420p -crf 23 demo.mp4
```

Embed in README:
```html
<video src="assets/demo.mp4" controls muted autoplay loop></video>
```

## 7. Place + commit

```bash
mv demo.gif ~/develop/swk/nova/assets/
# (or demo.mp4)
```

Add to `README.md` right under the hero (before Quick Start):

```markdown
![Nova demo — catching a hardcoded secret](assets/demo.gif)
```

## 8. Alternative demos (if the bug-catch takes too long to set up)

- **`/nova:next` triage** (10 sec) — shows Nova diagnosing project state and recommending next command. Good first demo.
- **`/nova:scan`** (15 sec) — fresh repo analysis output. Shows the "onboarding value."
- **`/nova:ask`** multi-AI consensus (20 sec) — shows Claude+GPT+Gemini converging or diverging. Impressive because rarely seen.

## 9. Publishing

| Where | Format | Size target |
|-------|--------|------------|
| README.md | GIF or MP4 | ≤2 MB |
| Twitter/X | MP4 | ≤512 MB (unlikely) but ≤15 MB recommended |
| Reddit | GIF via imgur | ≤20 MB |
| Hacker News | Link out to GitHub README (don't embed) | — |

## Pitfalls

- **Secret leakage**: the demo file contains a "secret" string. Make sure it's dummy content (`super-secret-1234`) and not a real key you typed absentmindedly.
- **Terminal theme**: default macOS black is fine; avoid Solarized (low contrast on projector/phone).
- **Font**: asciinema uses the terminal's font; switch to a rendered font in `agg` if your terminal is exotic.
- **Re-record if caught a bug you didn't plan for**: authentic bugs are best, but only if they end in PASS.
