# Ginsu

**Cut the work in half.** Let your Claude Code agent spawn and drive a Codex agent running in a real terminal window you can watch — no more copy-pasting prompts between two terminals.

If you've ever had Claude Code and Codex open side by side, one writing while you shuttle prompts to the other by hand, Ginsu is that workflow, automated. Claude sends the prompt, Codex does the work in the repo, Claude reads the reply and sends the next one. You watch the whole thing happen and keep talking to Claude the entire time.

```
you ─▶ claude ─▶ ginsu send ─▶ [ Codex worker, live in a window ] ─▶ reply ─▶ claude ─▶ you
                     ▲                                                    │
                     └──────────────── next prompt ◀──────────────────────┘
```

## Why

Two coding agents are better than one — Claude to orchestrate and reason, Codex (GPT‑5.x) to execute and critique. But driving both means you become a human message bus, pasting prompts back and forth. Ginsu makes Claude the message bus instead. It's the visible version: you still see every keystroke Codex makes, so you stay in the loop and can steer either agent at any time.

It's a thin wrapper over the **official Codex CLI** (`codex exec` + `codex exec resume`). No proxy, no API keys, no model swap — Codex runs on your own Codex/ChatGPT subscription, exactly as it does when you run it by hand.

## Install

```bash
git clone https://github.com/hurttlocker/ginsu && cd ginsu && ./install.sh
```

Requires the [Codex CLI](https://github.com/openai/codex) (`codex`) and Claude Code. macOS uses Terminal or iTerm; Linux uses tmux.

## Use

```bash
ginsu spawn dev ~/my-repo        # a Codex worker opens in a window, in ~/my-repo
ginsu send  dev "audit the auth flow, don't commit"   # → prints Codex's reply
ginsu send  dev "now fix the bug you found"           # Codex remembers the audit
ginsu diff  dev                  # see what Codex changed
```

`ginsu send` waits and returns Codex's reply, so **Claude can call it directly** and act on the answer. That's the point — Claude spawns the worker, delegates, reads the result, and iterates, while you watch.

| command | what it does |
|---|---|
| `ginsu spawn <worker> <repo>` | open a visible Codex worker in `<repo>` |
| `ginsu send <worker> "<prompt>" [--no-wait]` | send a prompt; waits and prints the reply |
| `ginsu read <worker>` | print the latest reply |
| `ginsu diff <worker>` | show what Codex changed (git status + diff) |
| `ginsu apply <worker>` | apply Codex's latest proposed diff (sandbox modes) |
| `ginsu list` / `status` / `tail` / `stop` | manage workers |

## Config (env)

| var | default | notes |
|---|---|---|
| `GINSU_MODEL` | `gpt-5.6-sol` | any model your Codex CLI has |
| `GINSU_EFFORT` | `high` | `low·medium·high·xhigh·max` |
| `GINSU_SANDBOX` | `bypass` | `bypass` (full access) · `write` (workspace‑write) · `read` (read‑only) |
| `GINSU_TERM` | `auto` | `iterm·terminal·tmux` |

⚠️ **`bypass` runs Codex with `--dangerously-bypass-approvals-and-sandbox`** (full access, no sandbox). Convenient on a machine and repo you trust; use `GINSU_SANDBOX=write` for a safer default and `ginsu apply` to review-then-apply.

## How it works

- Turn 1: `codex exec --json <sandbox> -m <model> -o <reply-file> -C <repo> "<prompt>"` — Codex emits a structured event stream, and Ginsu renders it into a clean window: reasoning, the commands it runs, the files it touches, and the reply — with a live spinner and a per-turn `elapsed · tokens` footer, instead of raw log spew. The final message is also written to a file (Claude's clean reply). Codex's own startup chatter goes to a log, not your window.
- Later turns: `codex exec resume <session-id> …` — same session, so Codex keeps its memory. The session id comes straight from Codex's `thread.started` event — no scanning session files.
- `spawn` opens the window via AppleScript (Terminal/iTerm) or tmux. The worker loop watches an inbox file; `send` writes to it and blocks on a turn counter until Codex finishes, then hands you back the reply.

That's the whole trick. It's small on purpose — read `ginsu`, it's one file.

## License

MIT © hurttlocker
