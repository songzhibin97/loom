# loom

一个 **CLI 无关的 agentic workflow 编排骨架**：用 YAML 把若干 skill 串成有状态的工作流，由一个 meta-agent 在 Claude Code 或 Codex CLI 里跑，关键节点和人对话，失败/卡死时自动回退或升级。

## 这是在解决什么问题

你已经有一堆零散的 skill（写 PRD 的、写 TRD 的、写代码的、review 的、跑测试的、提交的⋯⋯），想把它们串成"一句需求进，一份可提交的代码出"的流程，并且：

- 同一个流程能在 Claude Code 和 Codex CLI 里都跑起来
- 关键节点（PRD 澄清、TRD 拍板）允许在同一个 CLI 会话里和人对话
- 中间环节（实现、跑测试、review）尽量无人值守
- 测试糊弄 / review 不过 / TRD 走不通 时，自动回到上游对应节点重新来
- 同一条回退边踩多了，会升级到人（而不是无限重试）

这不是一个"框架"——它是一份**契约 + 示例**，你拿走改吧改吧就能用。

## 三层模型

```
┌──────────────────────────────────────────────────────┐
│  Workflow (YAML)        ← 状态机：节点 + 边 + 计数器  │
├──────────────────────────────────────────────────────┤
│  Skill (Markdown)       ← 原子能力：纯 prompt + I/O   │
├──────────────────────────────────────────────────────┤
│  Orchestrator (prompt)  ← Meta-agent：读 state、调度  │
├──────────────────────────────────────────────────────┤
│  Adapter (CLI 薄层)     ← Claude Code / Codex 拉起    │
└──────────────────────────────────────────────────────┘
```

**Skill 不知道彼此存在。** 它们靠 workflow 里的数据流串起来（A 的 output 写到 artifacts/，B 从 artifacts/ 读 input）。

**Orchestrator 不做实质工作。** 它只读 `state.json`、按 workflow 决定下一步该跑哪个 skill、把 skill 的产出归档、判断该走哪条边。所有"动手"都派给 subagent。

**State.json 是单一事实源。** 任何时刻 kill 掉再重启，下一次 orchestrator 启动就能从 state.json 接着跑。

## 目录结构

```
loom/
├── README.md                ← 你在这
├── docs/
│   ├── architecture.md      ← 完整设计、状态机语义、escape hatch
│   ├── runbook.md           ← Day-1 上手指南（Claude Code）
│   └── self-check-trace.md  ← 手 trace 一遍坏路径
├── spec/
│   ├── skill.md             ← Skill frontmatter + body 规范
│   └── workflow.md          ← Workflow YAML schema
├── orchestrator/
│   └── meta-agent.md        ← 编排器 prompt（CLI 无关，由 slash command 加载）
├── workflows/
│   ├── prd-to-ship.yaml     ← 示例：需求 → PRD → TRD → impl → test → review → commit
│   └── issue-to-fix.yaml    ← 示例：issue → triage → 复现 → fix → review → commit
├── skills/                  ← 13 个示例 skill
│   ├── prd-clarify/SKILL.md
│   ├── prd-author/SKILL.md
│   ├── trd-author/SKILL.md
│   ├── implement/SKILL.md
│   ├── test-runner/SKILL.md
│   ├── reviewer-quality/SKILL.md
│   ├── reviewer-security/SKILL.md
│   ├── reviewer-test-honesty/SKILL.md   ← 反"测试糊弄"
│   ├── reviewer-regression/SKILL.md     ← bug 修复专用
│   ├── review-aggregator/SKILL.md
│   ├── issue-triage/SKILL.md
│   ├── bug-reproduce/SKILL.md
│   └── committer/SKILL.md
├── adapters/
│   ├── claude-code/         ← slash command（当前唯一可用）
│   └── codex/               ← TBD（未实现）
└── verify.sh                ← 烟雾测试：lint 所有 YAML / SKILL.md / 引用一致性
```

## 快速开始（只支持 Claude Code）

```bash
# 1. 把 loom 放到你项目里（这里假设 <repo>/loom/）
git clone <wherever you put it> loom

# 2. 软链 slash command（不要软链 agent 文件，那个是停用的）
mkdir -p .claude/commands
ln -s "$(pwd)/loom/adapters/claude-code/commands/workflow.md" \
      .claude/commands/workflow.md

# 3. 跑一次 lint，确认所有引用对得上
bash loom/verify.sh

# 4. 在 Claude Code 会话里
> /workflow run prd-to-ship "我想给后台加批量导出 CSV"
```

详细日常操作（gate 怎么答、卡死怎么 escalate、resume 怎么用）见 `docs/runbook.md`。

**Codex CLI 暂未实现。** 见 `adapters/codex/README.md`。

## 核心契约速览

完整规范见 `spec/`，这里给一个最小例子：

**一个 skill（`skills/trd-author/SKILL.md`）：**

```markdown
---
name: trd-author
description: 把已确认的 PRD 转成可实施的 TRD，包含模块拆分、接口签名、风险点
inputs:
  - name: prd
    path: artifacts/PRD.md
outputs:
  - name: trd
    path: artifacts/TRD.md
success_criteria:
  - TRD 里每个模块都标注了依赖和测试策略
  - 列出至少 3 个落地风险
retry_policy:
  max_attempts: 3
---

你是高级软件工程师。基于 PRD 起草一份 TRD……
（这里是 prompt body）
```

**一条 workflow 边（`workflows/prd-to-ship.yaml` 节选）：**

```yaml
run_tests:
  kind: skill
  skill: test-runner
  on_pass: code_review
  on_fail: implement              # 测试挂了，回去重写
  max_attempts: 3
  on_exceed: escalate_trd         # 试了 3 次还挂，TRD 可能有问题

code_review:
  kind: parallel
  fan_out: [reviewer-quality, reviewer-security, reviewer-test-honesty]
  aggregator: review-aggregator
  on_pass: commit
  on_fail: implement
  max_attempts: 2
  on_exceed: escalate_trd
```

## 设计原则

1. **Skill 是数据，不是代码。** 任何能写 prompt 的人都能加新 skill，不用碰编排器。
2. **状态可序列化。** 跑到一半的工作流能存档、能 resume、能被另一个会话接手。
3. **每个循环都有 escape hatch。** 不允许无限重试。卡住就升级——回上游节点、或者问人。
4. **Orchestrator 是裁判，不是选手。** 它不写代码、不写 PRD，只看 skill 产出符不符合 `success_criteria`，然后路由。
5. **同会话对话只在 gate 节点发生。** skill 执行期内不打扰人；gate 节点集中收人的输入。

继续读 `docs/architecture.md` 看完整设计，或直接看 `workflows/prd-to-ship.yaml` 找感觉。
