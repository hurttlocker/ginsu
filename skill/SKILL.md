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
ginsu spawn <worker> <repo> --engine codex|claude
ginsu send <worker> "<bounded prompt>"
ginsu send <worker> "<follow-up prompt>"
ginsu diff <worker>
ginsu stop <worker>
```

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

Read the single `ginsu` Bash file before changing it. After changes, run `bash -n ginsu`, `git diff --check`, and the fake-backend harness. Test first-turn session creation, resumed turns, queue ownership, explicit failures, engine-preserving restart, and the nesting guard before opening a PR.
