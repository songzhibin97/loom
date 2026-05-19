---
description: DEPRECATED. Do not install as an agent. Kept only as a design note. See commands/workflow.md.
---

# Why there's no `workflow-orchestrator` sub-agent

Earlier drafts of this project defined the orchestrator as a Claude Code
sub-agent (this file). That was **wrong** because Claude Code's `Task` tool
is one-shot: a sub-agent runs to completion and returns a final message.
It cannot pause mid-run to ask the user a question.

Since the orchestrator's whole point is to drive `kind: gate` and
`kind: human` states — both of which require the user's reply between
transitions — making it a sub-agent makes the gate semantics
**architecturally impossible** in Claude Code.

## What we do instead

The orchestrator is the **main agent's behavior**, loaded via the
`/workflow` slash command (see `../commands/workflow.md`). The main agent
is the one talking to the user, so gates work naturally: print the prompt,
end the turn, wait for the user's next message (`/workflow continue ...`).

Sub-agents (via `Task`) are used **only** to execute skills. They never
talk to the user, never nest.

## If you really need a "background orchestrator"

Then this whole approach isn't right for your case — you want a long-running
external process (Python / Node) that drives the CLI as a worker, not a
prompt-only design. That's a different project. (We considered this in
the original design questionnaire and the user picked the in-context
approach.)

---

**Do not symlink this file into `.claude/agents/`.** Use `../commands/workflow.md`
as the entry point.
