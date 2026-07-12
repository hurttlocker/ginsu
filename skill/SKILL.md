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

## Rules
- **Verify, don't trust the reply.** After Codex says it's done, run `ginsu diff <worker>` (and tests) — a claim of success is not success.
- **One worker per repo.** Don't spawn a second worker in the same repo, and don't run an interactive `codex` there while a worker is live.
- **Mind the sandbox.** Default `GINSU_SANDBOX=bypass` gives Codex full access — only for repos the user trusts. Prefer `write` + `ginsu apply` when unsure.
- **It's the user's subscription.** Codex runs on their Codex/ChatGPT sub — heavy use draws down that quota. Right-size delegated work.
- **Keep the user in the loop.** They're watching the window; narrate what you delegated and what came back.
