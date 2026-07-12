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

Requires the [Codex CLI](https://github.com/openai/codex) (`codex`), Claude Code, and `python3`. macOS uses Terminal or iTerm; Linux uses tmux.

## Use

```bash
ginsu spawn dev ~/my-repo        # a Codex worker opens in a window, in ~/my-repo
ginsu send  dev "audit the auth flow, don't commit"   # → prints Codex's reply
ginsu send  dev "now fix the bug you found"           # Codex remembers the audit
ginsu send  dev "trace the race" --effort xhigh       # dial thinking up for this turn
ginsu review dev                 # adversarial code review of the repo
ginsu diff  dev                  # see what Codex changed
```

`ginsu send` waits and returns Codex's reply, so **Claude can call it directly** and act on the answer — and it **exits nonzero if the turn failed or timed out**, so a caller can trust the reply or react to the failure instead of acting on stale text. That's the point: Claude spawns the worker, delegates, reads the result, and iterates, while you watch.

| command | what it does |
|---|---|
| `ginsu spawn <worker> <repo>` | open a visible Codex worker in `<repo>` |
| `ginsu send <worker> "<prompt>" [--no-wait] [--effort E] [--model M]` | send a prompt; waits and prints the reply. `--effort`/`--model` override just this turn |
| `ginsu review <worker> [focus]` | ask Codex to adversarially review the repo |
| `ginsu test <worker> [focus]` | ask Codex to write + run tests for the current changes |
| `ginsu read <worker>` | print the latest reply |
| `ginsu diff <worker>` | show what Codex changed (git status + diff) |
| `ginsu logs <worker> [n]` | show Codex's stderr — debug a failed turn |
| `ginsu list` / `status` / `tail` / `stop` | manage workers |

Prompts are **queued per worker** — rapid or concurrent `send`s never clobber each other, and each reply is tied to its own prompt.

## Config (env)

| var | default | notes |
|---|---|---|
| `GINSU_MODEL` | `gpt-5.6-sol` | any model your Codex CLI has |
| `GINSU_EFFORT` | `high` | `low·medium·high·xhigh·max` |
| `GINSU_SANDBOX` | `write` | `write` (workspace‑write) · `bypass` (full access) · `read` (read‑only) |
| `GINSU_TERM` | `auto` | `iterm·terminal·tmux` |
| `GINSU_TIMEOUT` | `900` | seconds a blocking `send` waits before giving up |

Ginsu defaults to **`write`** (workspace-write): Codex can edit the repo but stays sandboxed. On a machine and repo you fully trust, `GINSU_SANDBOX=bypass` runs Codex with `--dangerously-bypass-approvals-and-sandbox` (full access, no sandbox) — faster and more capable, but⚠️ only where you trust it. Either way, review with `ginsu diff` before you commit.

## How it works

- Turn 1: `codex exec --json <sandbox> -m <model> -o <reply-file> -C <repo> "<prompt>"` — Codex emits a structured event stream, and Ginsu renders it into a clean window: reasoning, the commands it runs, the files it touches, and the reply — with a live spinner and a per-turn `elapsed · tokens` footer, instead of raw log spew. The final message is also written to a file (Claude's clean reply). Codex's own startup chatter goes to a log, not your window.
- Later turns: `codex exec resume <session-id> …` — same session, so Codex keeps its memory. The session id comes straight from Codex's `thread.started` event — no scanning session files.
- `spawn` opens the window via AppleScript (Terminal/iTerm) or tmux. `send` drops the prompt into a per-worker queue with a ticket; the worker loop processes tickets in order and writes each reply back under its ticket, so `send` waits for *its own* reply — not whatever finished first.
- Failures are explicit: the loop clears the reply file before every turn and checks Codex's exit status, so a crashed or errored turn returns a visible `⚠` message and a nonzero exit, never a stale success.

That's the whole trick. It's small on purpose — read `ginsu`, it's one file.

## License

MIT © hurttlocker
