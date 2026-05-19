# Adapters

Self-workflow 的核心（`orchestrator/meta-agent.md` + `spec/` + `workflows/` + `skills/`）是 CLI 无关的。
Adapter 负责把它接到具体 CLI 上。

## 当前状态

| Adapter | 状态 | 入口 |
|---|---|---|
| `claude-code/` | **实现并已对齐 Claude Code 实际能力** | `commands/workflow.md` |
| `codex/` | **TBD — 未实现** | 见 `codex/README.md` |

## Claude Code 安装

```bash
# 假设你的项目根是 <repo>，loom 在 <repo>/loom/

# 1. 把 slash command 软链到项目的 .claude/commands/
mkdir -p .claude/commands
ln -s "$(pwd)/loom/adapters/claude-code/commands/workflow.md" \
      .claude/commands/workflow.md

# 2. （可选）设置 LOOM_HOME，避免依赖 git rev-parse
export LOOM_HOME="$(pwd)/loom"
```

然后在 Claude Code 会话里：

```
/workflow run prd-to-ship "我想给后台加批量导出 CSV"
```

详细的 day-1 使用步骤见 `../docs/runbook.md`。

## Codex 安装

未实现。参见 `codex/README.md` 里需要先确认的事项。

## 设计取舍

之前的设计里 orchestrator 是一个 Claude Code 子 agent。这是**错的**——`Task` 工具是一次性返回的，子 agent 不能在跑一半时和用户对话，所以 gate 节点架构上就不成立。

现在 orchestrator 是**主 agent 的行为**（slash command 让主 agent 加载 `orchestrator/meta-agent.md` 后变身）。Sub-agent 只用来跑 skill。Gate / human / `_resume_after_manual` 节点的"等用户"通过"打印提示 → 写 pending_gate → return"实现，由用户下次输 `/workflow continue <answer>` 重新进入主 agent。详见 `adapters/claude-code/agents/orchestrator.md`（一份解释为什么不要把它装成 agent 的说明）。
