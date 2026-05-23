# Codex CLI adapter — TBD（待验证）

**状态：未实现。**

之前的 prompt 文件包含了我不确定/编造的 Codex CLI flag（`--system`, `--model`, `--input`）。已删除以免误导。

## 实现这块需要的输入

要让 loom 在 Codex CLI 上跑起来，需要先确认下面这些事实，然后再写 adapter：

1. **怎么注入系统提示** — Codex CLI 用 `~/.codex/instructions.md`？`AGENTS.md`？`-c` 配置项？还是别的方式？
2. **有没有 sub-agent / nested model call 机制** — 如果有，怎么调用？参数怎么传？
3. **怎么指定单次调用用哪个 model / provider** — 这决定了"跨厂商盲审"能不能落地
4. **slash command 或等价物** — Codex 里 `/workflow run ...` 这种用户入口怎么定义？

填齐上面这些事实后，参考 `adapters/claude-code/commands/workflow.md` 的设计写一份对应的 Codex 入口。Meta-agent prompt 本身（`orchestrator/meta-agent.md`）大部分可以复用，只需要在文档里替换"Task 工具"为 Codex 的对应机制。

## 当前可用范围

当前 loom 只支持 **Claude Code**（已在 `adapters/claude-code/` 实现）。如果你想先在 Codex 上跑，需要先做上面的调研工作。
