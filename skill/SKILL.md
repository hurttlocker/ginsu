---
name: ginsu
description: Delegate coding work to a visible Codex or Claude Code worker and drive it as a queued, resumable conversation. Use when the user asks one coding agent to spawn or steer the other, when delegating a bounded implementation or audit, or when seeking a cross-model review. Requires the ginsu CLI on PATH (github.com/hurttlocker/ginsu).
---

# Ginsu — drive the other coding agent

Use `ginsu` to keep the current agent as orchestrator while a visible worker acts in the target repository. Read every returned reply, verify the diff, and continue the same worker session when follow-up work is needed.

## Choose the engine

- From Claude Code, omit `--engine` to use the backward-compatible Codex default.
- From Codex, pass `--engine claude` to open a visible Claude Code worker.
- Choose a same-model worker only when the user explicitly wants parallel capacity rather than a cross-model check.

## Run the loop

```bash
ginsu spawn <worker> <repo> --engine codex|claude [--effort E] [--model M]   # flags persist as the worker's defaults
ginsu send <worker> "<bounded prompt>"
ginsu send <worker> "<follow-up prompt>"
ginsu send <worker> "<long build task>" --no-wait   # prints the ticket immediately
ginsu wait <worker> [ticket]                        # collect the reply (newest by default); idempotent
ginsu status <worker>                               # model/effort defaults, current ticket, queue, last result
ginsu diff <worker>
ginsu stop <worker>
```

Set the worker's effort/model once at spawn instead of repeating per-send flags. For tasks longer than your harness's command timeout, prefer `send --no-wait` + `ginsu wait` over background-shell workarounds — a timed-out blocking send loses only the wait, never the work, and `wait` re-attaches cleanly.

Treat `ginsu send` as a blocking tool call that returns the reply for its own queued ticket. Give the worker the repository context, exact task, constraints, and completion criteria.

Use:

- `ginsu review <worker> [focus]` for an adversarial review.
- `ginsu test <worker> [focus]` to write and run focused tests.
- `ginsu send <worker> "<prompt>" --effort <level> --model <name>` for per-turn overrides.
- `ginsu logs <worker>` after a nonzero result.
- `ginsu restart <worker>` to reopen the saved engine and repository with a fresh session.

## Enforce the boundaries

- Treat a nonzero `send` as failure, not an answer. Inspect logs and retry or repair.
- Run `ginsu diff` and relevant tests before trusting a completion claim.
- Keep one active worker per repository to avoid concurrent edits.
- Keep delegation one level deep. Ginsu refuses nested calls that inherit the worker environment unless the user explicitly authorizes nesting and `GINSU_ALLOW_NESTED=1` is set. Treat this as a workflow guard, not a security boundary.
- Explain the security model accurately. Codex `write` uses workspace-write sandboxing. Claude `write` maps to `acceptEdits` by default, which is a permission policy, not an operating-system sandbox. Use `read` for Claude plan mode or `bypass` only on a trusted machine and repository.
- Remember that each backend consumes the user's own Codex or Claude subscription.

## Maintain Ginsu

Read the single `ginsu` Bash file before changing it. Keep Codex sandbox flags on the first `exec` only; current `codex exec resume` rejects `--sandbox` and inherits the session sandbox. After changes, run `bash -n ginsu`, `git diff --check`, and the fake-backend harness. Test first-turn session creation, resumed turns, queue ownership, explicit failures, engine-preserving restart, and the nesting guard before opening a PR.

## Field lessons (from production dogfooding)

- **`stop` verifies the tree is dead (2.1.1).** The recorded pid is the loop wrapper; the engine is its child. Old `stop` killed that one pid and printed `stopped` on signal-send — a Codex turn once outlived its wrapper and committed to the repo after the operator was told it was dead. Now `stop` walks the descendants, signals TERM then KILL, polls `kill -0` until every pid is gone, and prints `stopped` only then; otherwise it prints `stop UNCONFIRMED … still alive: <pids>` and exits 1, and `restart` refuses to spawn over an unconfirmed stop. Treat a nonzero `stop` like a nonzero `send`: check `pgrep` and `git log` in the worker's repo before you reset or rebase there.
- **`stop` verifies the tree is dead (2.1.1).** The recorded pid is the loop wrapper; the engine is its child. Old `stop` killed that one pid and printed `stopped` on signal-send — a Codex turn once outlived its wrapper and committed to the repo after the operator was told it was dead. Now `stop` walks the descendants, signals TERM then KILL, polls `kill -0` until every pid is gone, and prints `stopped` only then; otherwise it prints `stop UNCONFIRMED … still alive: <pids>` and exits 1, and `restart` refuses to spawn over an unconfirmed stop. Treat a nonzero `stop` like a nonzero `send`: check `pgrep` and `git log` in the worker's repo before you reset or rebase there.
- **Long build turns outlive the default wait.** `ginsu send` gives up at `GINSU_TIMEOUT` (900s default) — but the worker keeps cutting; a timed-out send loses only the wait, never the work. Raise it per-send for build-sized tasks (`GINSU_TIMEOUT=1800 ginsu send …`), or skip the gamble: `send --no-wait` then `ginsu wait <worker> <ticket>` re-attaches to the turn's own reply and exit status, and stays re-readable if you need it twice.
- **Queue while it works.** Sends queue in ticket order, so you can fire an amendment mid-turn and the worker course-corrects on its next turn — no need to wait out the current turn before refining the spec.
- **Worker stderr accumulates across turns**, and every backend boot dumps MCP-auth chatter into it — when a turn fails, grep near the failure's timeframe instead of trusting the tail, or you'll debug three-day-old noise.
- **⚠️ Live-tree hazard:** if the worker is editing files that a daemon/cron/launchd job executes on a schedule, a mid-write import can crash the live process. Either have the worker stage as `*.new` files you install after validation, or park the last committed version over the boot window (snapshot the WIP → `git checkout -- file` → boot passes → restore).
