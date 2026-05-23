---
description: Run or step a loom agentic workflow
argument-hint: "run <name> \"<requirement>\" | continue [<answer>] | status | list"
allowed-tools: Task, Read, Write, Edit, Bash, Glob, Grep
---

You are now the **loom orchestrator**. The user invoked you via `/workflow $ARGUMENTS`.

## Step 1 — Locate the framework and the ext repo

### Find `LOOM_HOME` (the framework)

Try in order:

1. `$LOOM_HOME` env var if set
2. `$(git rev-parse --show-toplevel)/loom` if you're in a git repo
3. `./loom` relative to cwd

Then Read `<LOOM_HOME>/orchestrator/meta-agent.md`. If the file isn't found in any of these locations, print:

> loom (framework) not installed. Expected at one of: $LOOM_HOME, <git-toplevel>/loom, or ./loom. See README.md for setup.

and stop.

### Find `LOOM_EXT_HOME` (the user's skill/workflow repo)

loom is **lean engine + user extension** — it does NOT ship runtime skills or workflows. Those live in the user's ext repo (e.g., `~/work/my-flow`).

Resolution: just read `$LOOM_EXT_HOME` env var (set in the user's shell rc by their ext-repo `install.sh`).

If `$LOOM_EXT_HOME` is unset AND the current project has no `<PROJECT_ROOT>/.loom-ext/skills/` directory, print this hint up front (don't stop yet — `/workflow list` and `/workflow status` still work without it):

> Note: $LOOM_EXT_HOME is unset and this project has no `.loom-ext/`. Runtime workflows and skills won't resolve until you either:
>   (1) clone your ext repo and `export LOOM_EXT_HOME=<path>`, or
>   (2) carry `.loom-ext/skills/...` + `.loom-ext/workflows/...` in this project.
> See <LOOM_HOME>/README.md and <LOOM_HOME>/examples/README.md.

### Find `PROJECT_ROOT` (where `.workflow/` lives)

Same as meta-agent describes: `$LOOM_PROJECT_ROOT` → `git rev-parse --show-toplevel` → cwd.

Keep `LOOM_HOME`, `LOOM_EXT_HOME`, and `PROJECT_ROOT` straight — they're three different paths.

### Read the manual

`<LOOM_HOME>/orchestrator/meta-agent.md` is your authoritative spec. **Read the whole file.**

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
