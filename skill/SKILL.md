---
name: ginsu
description: Delegate hands-on coding work to a Codex worker running in a visible terminal, and drive it as a conversation. Use when the user wants Claude to spawn/steer a second (Codex) agent, when you want to hand off well-scoped execution while you keep orchestrating, or for a cross-model second opinion (Claude drafts, Codex critiques). Requires the `ginsu` CLI on PATH (github.com/hurttlocker/ginsu).
---

# Ginsu — drive a Codex worker

`ginsu` lets you (Claude) run a Codex agent in a real terminal window the user watches, send it prompts, and read its replies. Use it to split work: you orchestrate and reason; Codex executes in the repo. The user sees everything and can steer either of you.

## When to reach for it
- The user asks you to "have Codex do X", "spawn a worker", "you drive Codex", or is manually relaying prompts between a Claude and a Codex terminal.
- You want to hand off a well-scoped, hands-on chunk (an audit, a refactor, wiring, tests) while you stay free to plan the next step.
- You want an independent cross-model review: draft the change, then have Codex try to break it.

## The loop
```bash
ginsu spawn <worker> <repo>              # opens a visible Codex worker; do this once per repo
ginsu send  <worker> "<clear prompt>"    # BLOCKS and returns Codex's reply — read it, decide next
ginsu send  <worker> "<next prompt>"     # same session: Codex remembers prior turns
ginsu diff  <worker>                     # inspect what Codex changed before trusting "done"
ginsu stop  <worker>                     # when finished
```

`ginsu send` returns Codex's final message as text, so treat it like any tool result: read it, verify against `ginsu diff`, and send the next instruction. Give Codex the same quality of brief you'd want — context, the exact task, and what "done" looks like.

## Modes & knobs
- **Dial thinking per task:** `ginsu send <worker> "<prompt>" --effort xhigh` (or `low` for a mechanical edit) — overrides just that turn. `--model <name>` likewise.
- **Adversarial review:** `ginsu review <worker> [focus]` — Codex reviews the repo and tries to refute it. Use it as a cross-model second opinion on your own change.
- **Tests:** `ginsu test <worker> [focus]` — Codex writes and runs tests for the current changes.
- Prompts queue per worker, so you can line several up; each `send` still returns its own reply.

## Rules
- **A failed turn is loud, not silent.** `ginsu send` exits **nonzero** and returns a `⚠ ginsu: Codex turn failed…` message when Codex errors or times out — don't treat that as an answer; run `ginsu logs <worker>` to see why, then retry or fix. (Long task timing out? Raise `GINSU_TIMEOUT`.)
- **Verify, don't trust the reply.** After Codex says it's done, run `ginsu diff <worker>` (and tests) — a claim of success is not success.
- **One worker per repo.** Don't spawn a second worker in the same repo, and don't run an interactive `codex` there while a worker is live.
- **Mind the sandbox.** Default `GINSU_SANDBOX=bypass` gives Codex full access — only for repos the user trusts. Prefer `write` and review with `ginsu diff` when unsure.
- **It's the user's subscription.** Codex runs on their Codex/ChatGPT sub — heavy use draws down that quota. Right-size delegated work.
- **Keep the user in the loop.** They're watching the window; narrate what you delegated and what came back.

## Hacking on it (fixing Ginsu itself)

Ginsu is your link to the Codex model — if it breaks mid-task, you can repair it and keep going. It's **one bash file** (`ginsu`) with a small embedded Python renderer (`write_renderer`). Read it top to bottom; it's short by design.

- **Where it runs from:** whatever `command -v ginsu` points at (usually a symlink into `~/.local/bin` created by `install.sh`, targeting the repo's `ginsu`). Editing that file is live immediately — there's no build step.
- **After any edit:** `bash -n ginsu` (syntax), then test on a throwaway repo before trusting it:
  ```bash
  cd /tmp && rm -rf gtest && mkdir gtest && cd gtest && git init -q
  ginsu spawn t /tmp/gtest
  ginsu send t "create ping.txt with the word ping, then reply done"   # watch the window
  ginsu send t "what file did you just make?"   # proves resume/memory
  ginsu diff t && ginsu stop t
  ```
- **Runtime state per worker** lives in `$GINSU_HOME/<worker>/` (default `~/.ginsu/<worker>/`): `inbox`, `turn`, `session.id`, `response.out`, `render.py`, and **`codex.err`** — Codex's own startup chatter (MCP/auth noise) is redirected there, *out* of the window. Read `codex.err` first when a turn misbehaves.
- **Backbone facts that bite:** the loop uses `codex exec --json` (turn 1) and `codex exec resume <id>` (later turns). ⚠️ `codex exec resume` **rejects both `-C` and `--color`** (they're valid only on plain `exec`) — passing them makes every turn after the first silently no-op. The session id is read from the first `--json` event, `thread.started`. Codex **blocks reading piped stdin**, so every invocation ends with `</dev/null` (harmless in the TTY window, essential when driven headless).
- **If a fix is worth keeping**, commit it in the repo and push — the CLI is meant to be extended.
