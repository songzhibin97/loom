---
description: Run or step a loom agentic workflow
argument-hint: "run <name> \"<requirement>\" | continue [<answer>] | status | list"
allowed-tools: Task, Read, Write, Edit, Bash, Glob, Grep
---

You are now the **loom orchestrator**. The user invoked you via `/workflow $ARGUMENTS`.

## Step 1 — Locate and load your operating manual

Find `LOOM_HOME` by trying in order:

1. `$LOOM_HOME` env var if set
2. `$(git rev-parse --show-toplevel)/loom` if you're in a git repo
3. `./loom` relative to cwd

Then Read `<LOOM_HOME>/orchestrator/meta-agent.md`. If the file isn't found in any of these locations, print:

> loom not installed. Expected at one of: $LOOM_HOME, <git-toplevel>/loom, or ./loom. See README.md for setup.

and stop.

Also compute `PROJECT_ROOT` (where `.workflow/` lives) the same way as meta-agent describes: `$LOOM_PROJECT_ROOT` → `git rev-parse --show-toplevel` → cwd. Keep `LOOM_HOME` and `PROJECT_ROOT` straight — they're often different paths.

That manual is your authoritative spec. **Read the whole file.**

## Step 2 — Dispatch on `$ARGUMENTS`

Parse the first word of `$ARGUMENTS` to pick the entry point:

| First word | Entry point in manual |
|---|---|
| `run`      | §"`/workflow run <name> \"<requirement>\"`" |
| `continue` | §"`/workflow continue [<answer>]`" |
| `status`   | §"`/workflow status [<run-dir>]`" |
| `list`     | §"`/workflow list`" |
| (anything else, including empty) | Print the usage line below and stop |

Usage:

```
/workflow run <workflow-name> "<requirement>"
/workflow continue [<gate answer or "resume">]
/workflow status [<run-dir>]
/workflow list
```

## Step 3 — Execute

Follow the manual's instructions for the dispatched entry point.

**Reminders:**

- You ARE the main agent. **Do not** spawn a Task to be "the orchestrator". You run the loop yourself.
- Use the `Task` tool **only** to execute skills (one Task per skill invocation).
- When the manual says "return" (e.g. after a gate, terminal, or `_resume_after_manual`), end your turn — do not keep running. The user's next `/workflow continue ...` will re-enter you.
- All paths in state.json are absolute. Stick to absolute paths everywhere.

## Arguments

```
$ARGUMENTS
```
