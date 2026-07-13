# Ginsu

**Cut the work in half.** Let one coding agent spawn and drive the other in a real terminal window you can watch—without becoming the human message bus between them.

Ginsu is omnidirectional:

```text
Claude orchestrator ──▶ ginsu --engine codex  ──▶ visible Codex worker
Codex orchestrator  ──▶ ginsu --engine claude ──▶ visible Claude worker
```

The orchestrator sends a prompt, the worker acts in the repository, and Ginsu returns the clean reply. Follow-up prompts resume the same worker session. You can watch every turn and keep steering the orchestrator while it delegates.

Ginsu is a thin wrapper over the official Codex and Claude Code CLIs. It uses your existing subscriptions and local configuration—no proxy, API-key swap, or model impersonation.

## Install

```bash
git clone https://github.com/hurttlocker/ginsu && cd ginsu && ./install.sh
```

Requires `python3` plus the worker CLI you intend to run: [Codex CLI](https://github.com/openai/codex), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), or both. macOS uses Terminal or iTerm; Linux uses tmux.

## Use

```bash
# Claude driving Codex (backward-compatible default)
ginsu spawn dev ~/my-repo
ginsu send  dev "audit the auth flow, don't commit"

# Codex driving Claude
ginsu spawn reviewer ~/another-repo --engine claude
ginsu send  reviewer "review the current changes for real failure modes"

# Both engines use the same control surface
ginsu send  dev "now fix the bug you found"        # resumes the session
ginsu send  dev "trace the race" --effort xhigh   # per-turn override
ginsu review dev
ginsu diff  dev
```

`ginsu send` blocks and prints the reply for its own queued ticket. It exits nonzero when the turn fails or times out, so an orchestrating agent never mistakes a stale response for success.

| command | what it does |
|---|---|
| `ginsu spawn <worker> <repo> [--engine codex\|claude]` | open a visible worker; Codex is the default |
| `ginsu send <worker> "<prompt>" [--no-wait] [--effort E] [--model M]` | queue a prompt and normally wait for its reply |
| `ginsu review <worker> [focus]` | request an adversarial repository review |
| `ginsu test <worker> [focus]` | request focused tests for current changes |
| `ginsu restart <worker>` | reopen the saved engine and repository with a fresh session |
| `ginsu read <worker>` | print the latest reply |
| `ginsu diff <worker>` | show repository status and diff |
| `ginsu logs <worker> [n]` | show the active backend's stderr |
| `ginsu list` / `status` / `tail` / `stop` | manage workers |

Prompts are queued per worker. Rapid or concurrent sends never clobber one another, and each caller receives the reply tied to its own ticket. Ginsu allows one active worker per repository.

## Config

| variable | default | notes |
|---|---|---|
| `GINSU_ENGINE` | `codex` | default backend; `--engine` overrides it at spawn |
| `GINSU_CODEX_MODEL` | `gpt-5.6-sol` | default Codex model |
| `GINSU_CLAUDE_MODEL` | `sonnet` | default Claude model |
| `GINSU_MODEL` | unset | override the model default for either selected engine |
| `GINSU_EFFORT` | `high` | `low·medium·high·xhigh·max` |
| `GINSU_SANDBOX` | `write` | `write` · `read` · `bypass` |
| `GINSU_CLAUDE_PERMISSION_MODE` | `acceptEdits` | Claude `write` policy; also supports `auto` or `dontAsk` |
| `GINSU_TERM` | `auto` | `iterm·terminal·tmux` |
| `GINSU_TIMEOUT` | `900` | seconds a blocking send waits |
| `GINSU_ALLOW_NESTED` | `0` | set to `1` only when the user explicitly authorizes nested workers |

Worker configuration is saved at spawn, so a new Terminal window or an existing tmux server does not need to inherit the caller's environment. `restart` preserves the selected engine, CLI path, model, effort, and security mode.

## Security model

The same `read` / `write` / `bypass` vocabulary maps to different native controls:

- **Codex:** `write` is `--sandbox workspace-write`; `read` is `--sandbox read-only`; `bypass` disables approvals and sandboxing.
- **Claude:** `write` is `--permission-mode acceptEdits` by default; `read` is plan mode; `bypass` uses `--dangerously-skip-permissions`.

Claude permission modes are approval policies, **not operating-system sandboxes**. Do not describe Claude `write` as sandboxed. Use `bypass` only on a trusted machine and repository, and always inspect `ginsu diff` before committing.

Ginsu also exports a delegation depth inside every worker. Nested calls that inherit the worker environment are refused unless `GINSU_ALLOW_NESTED=1` is explicitly set, preventing accidental agent recursion. This is a workflow guard, not a security boundary against a worker deliberately changing its environment.

## How it works

- Codex turn 1 uses `codex exec --json`; later turns use `codex exec resume <session-id>`. Resume inherits the session sandbox because current Codex rejects `--sandbox` on the resume subcommand.
- Claude turn 1 uses `claude -p --output-format stream-json --session-id <uuid>`; later turns use `--resume <session-id>`.
- A backend-aware renderer turns each JSON event stream into a clean visible window and writes the final response to the caller's ticket.
- `spawn` opens the worker loop via Terminal/iTerm or tmux. The loop processes queued tickets in order and persists session state under `~/.ginsu/<worker>/`.
- The response file is cleared before every turn. CLI failures return a visible warning and nonzero status instead of a stale reply.

## Test

```bash
bash -n ginsu
tests/test_ginsu.sh
```

The harness uses fake Codex and Claude CLIs to verify first turns, resume, concurrent queue ownership, explicit failures, engine-preserving restart, and recursion protection without spending model quota.

## License

MIT © hurttlocker
