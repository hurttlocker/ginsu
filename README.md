# Ginsu

**Cut the work in half.** Let one coding agent spawn and drive the other in a real terminal window you can watch—without becoming the human message bus between them.

Ginsu is omnidirectional:

```text
Claude orchestrator ──▶ ginsu --engine codex  ──▶ visible Codex worker
Codex orchestrator  ──▶ ginsu --engine claude ──▶ visible Claude worker
Either orchestrator ──▶ ginsu --engine opencode ──▶ visible OpenCode worker
```

The orchestrator sends a prompt, the worker acts in the repository, and Ginsu returns the clean reply. Follow-up prompts resume the same worker session. You can watch every turn and keep steering the orchestrator while it delegates.

Ginsu is a thin wrapper over the official Codex, Claude Code, and OpenCode CLIs. It uses their local provider configuration and never changes saved model defaults. OpenCode can route models through providers such as OpenRouter when configured there.

## Install

```bash
git clone https://github.com/hurttlocker/ginsu && cd ginsu && ./install.sh
```

Requires `python3` plus the worker CLI you intend to run: [Codex CLI](https://github.com/openai/codex), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), or [OpenCode](https://opencode.ai/docs/cli/). macOS uses Terminal or iTerm; Linux uses tmux.

## Use

```bash
# Claude driving Codex (backward-compatible default)
ginsu spawn dev ~/my-repo
ginsu send  dev "audit the auth flow, don't commit"

# Codex driving Claude
ginsu spawn reviewer ~/another-repo --engine claude
ginsu send  reviewer "review the current changes for real failure modes"

# OpenCode with an OpenRouter model (provider configured in OpenCode)
ginsu spawn scout ~/another-repo --engine opencode --model openrouter/stealth/space-bunny-alpha
ginsu send scout "inspect the layout and report the cause"

# Spawn with sticky defaults — every turn inherits them, no per-send flags
ginsu spawn heavy ~/my-repo --effort xhigh --model gpt-5.6-sol

# All engines use the same control surface
ginsu send  dev "now fix the bug you found"        # resumes the session
ginsu send  dev "trace the race" --effort xhigh   # per-turn override
ginsu review dev
ginsu diff  dev

# Fire-and-forget, then collect — built for orchestrators with command timeouts
ginsu send dev "refactor the auth flow" --no-wait   # prints: queued → dev (ticket 7)
ginsu status dev                                    # working=7 queued=none last=6 (exit 0)
ginsu wait dev 7                                    # blocks, prints the reply, exits with turn status
```

`ginsu send` blocks and prints the reply for its own queued ticket. It exits nonzero when the turn fails or times out, so an orchestrating agent never mistakes a stale response for success. A timed-out send loses only the wait, never the work — collect the reply later with `ginsu wait` (replies stay re-readable until pruned; only the newest ~30 are kept).

| command | what it does |
|---|---|
| `ginsu spawn <worker> <repo> [--engine codex\|claude\|opencode] [--effort E] [--model M]` | open a visible worker; flags persist as its defaults |
| `ginsu send <worker> "<prompt>" [--no-wait] [--effort E] [--model M]` | queue a prompt and normally wait for its reply |
| `ginsu wait <worker> [ticket]` | wait for a queued turn (newest by default) and print its reply; idempotent |
| `ginsu review <worker> [focus]` | request an adversarial repository review |
| `ginsu test <worker> [focus]` | request focused tests for current changes |
| `ginsu restart <worker>` | reopen the saved engine and repository with a fresh session |
- `ginsu release <worker> [--force]` stops an idle worker and removes its linked git worktree. It refuses while a turn is working or queued, and refuses uncommitted changes without `--force`, so cleanup can never destroy a worker's in-flight work.
| `ginsu read <worker>` | print the latest reply |
| `ginsu diff <worker>` | show repository status and diff |
| `ginsu logs <worker> [n]` | show the active backend's stderr |
| `ginsu status <worker>` | liveness, model/effort defaults, current ticket, queue, last result |
| `ginsu list` / `tail` / `stop` | manage workers |

Prompts are queued per worker. Rapid or concurrent sends never clobber one another, and each caller receives the reply tied to its own ticket. Ginsu allows one active worker per repository.

## Config

| variable | default | notes |
|---|---|---|
| `GINSU_ENGINE` | `codex` | default backend; `--engine` overrides it at spawn |
| `GINSU_CODEX` / `GINSU_CLAUDE` | detected on PATH | CLI path, including a provider wrapper |
| `GINSU_CODEX_MODEL` | `gpt-5.6-sol` | default Codex model |
| `GINSU_CLAUDE_MODEL` | `sonnet` | default Claude model |
| `GINSU_OPENCODE_MODEL` | unset | OpenCode uses its configured model unless set here or at spawn |
| `GINSU_MODEL` | unset | override the model default for either selected engine |
| `GINSU_EFFORT` | `high` | `low·medium·high·xhigh·max` |
| `GINSU_SANDBOX` | `write` | `write` · `read` · `bypass` |
| `GINSU_CLAUDE_PERMISSION_MODE` | `acceptEdits` | Claude `write` policy; also supports `auto` or `dontAsk` |
| `GINSU_OPENCODE` | detected on PATH | OpenCode CLI path; persisted per worker |
| `GINSU_TERM` | `auto` | `iterm·terminal·tmux` |
| `GINSU_TIMEOUT` | `900` | seconds a blocking send waits |
| `GINSU_ALLOW_NESTED` | `0` | set to `1` only when the user explicitly authorizes nested workers |
| `GINSU_DEFAULTS_FILE` | `${XDG_CONFIG_HOME:-$HOME/.config}/ginsu/defaults` | personal routing defaults file |

For personal routing defaults, create `${XDG_CONFIG_HOME:-$HOME/.config}/ginsu/defaults` with plain `KEY=VALUE` lines:

```text
GINSU_ENGINE=claude
GINSU_CLAUDE_MODEL=provider/model-id
GINSU_CLAUDE=/path/to/claude-wrapper
GINSU_EFFORT=high
```

The file accepts `GINSU_ENGINE`, `GINSU_EFFORT`, and the `GINSU_CODEX`, `GINSU_CLAUDE`, or `GINSU_OPENCODE` CLI/model keys. Ginsu reads values as text, not shell code. Explicit environment values win over this file, and `spawn --engine`, `--model`, and `--effort` win for that worker. Without a file, the built-in Codex default remains. Keep credentials out of this file; a CLI wrapper can obtain them from the worker environment or a credential store at launch. Set `GINSU_DEFAULTS_FILE` to use another file.

Worker configuration is saved at spawn, so a new Terminal window or an existing tmux server does not need to inherit the caller's environment. `restart` preserves the selected engine, CLI path, model, effort, and security mode.

## Security model

The same `read` / `write` / `bypass` vocabulary maps to different native controls:

- **Codex:** `write` is `--sandbox workspace-write`; `read` is `--sandbox read-only`; `bypass` disables approvals and sandboxing.
- **Claude:** `write` is `--permission-mode acceptEdits` by default; `read` is plan mode; `bypass` uses `--dangerously-skip-permissions`.
- **OpenCode:** `read` uses the plan agent and denies edit, shell, and external-directory permissions for that worker; `write` uses the build agent with its configured permissions; `bypass` adds `--auto`. OpenCode modes are permission policies, not OS sandboxes.

Claude and OpenCode permission modes are approval policies, **not operating-system sandboxes**. Use `bypass` only on a trusted machine and repository, and always inspect `ginsu diff` before committing.

Ginsu also exports a delegation depth inside every worker. Nested calls that inherit the worker environment are refused unless `GINSU_ALLOW_NESTED=1` is explicitly set, preventing accidental agent recursion. This is a workflow guard, not a security boundary against a worker deliberately changing its environment.

## How it works

- Codex turn 1 uses `codex exec --json`; later turns use `codex exec resume <session-id>`. Resume inherits the session sandbox because current Codex rejects `--sandbox` on the resume subcommand.
- Claude turn 1 uses `claude -p --output-format stream-json --session-id <uuid>`; later turns use `--resume <session-id>`.
- OpenCode uses `opencode run --format json`; later turns use `--session <session-id>`. `--effort` maps to OpenCode's model `--variant` only when explicitly set.
- A backend-aware renderer turns each JSON event stream into a clean visible window and writes the final response to the caller's ticket.
- `spawn` opens the worker loop via Terminal/iTerm or tmux. The loop processes queued tickets in order and persists session state under `~/.ginsu/<worker>/`.
- The response file is cleared before every turn. CLI failures return a visible warning and nonzero status instead of a stale reply.

## Test

```bash
bash -n ginsu
tests/test_ginsu.sh
```

The harness uses fake Codex, Claude, and OpenCode CLIs to verify first turns, resume, concurrent queue ownership, explicit failures, engine-preserving restart, and recursion protection without spending model quota.

## License

MIT © hurttlocker
