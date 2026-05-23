# loom

一个 **CLI 无关的 agentic workflow 编排引擎**。

loom 自身只是**框架**（orchestrator 算法 + spec 契约 + adapter + verify）。运行时实际加载的 skill 和 workflow 在**你的 ext 仓**里（独立 maintain）。loom 仓里的 `examples/` 是同时点的参考实现，给新人 bootstrap 和给所有人对照。

## 解决什么问题

你已经有一堆零散的 skill（写 PRD 的、写 TRD 的、写代码的、独立写测试的、变异验证的、review 的、提交的⋯⋯），想把它们串成「一句需求进，一份可提交的代码出」的流程，并且：

- 关键节点（PRD 澄清、TRD 拍板）允许在同一个 CLI 会话里和人对话
- 中间环节（实现、独立写测试、跑测试、变异验证、review）无人值守
- 测试串通糊弄 / review 不过 / TRD 走不通 时，自动回到上游对应节点重新来
- 同一条回退边踩多了，会升级到人（而不是无限重试）
- **框架本身**很少动；**你 maintain 的 skill 内容**单独迭代

## 架构（lean engine + ext）

```
┌──────────────────────────────────────────────────────────┐
│  loom（框架，本仓）                                       │
│  ├── orchestrator/    meta-agent 算法                     │
│  ├── spec/            skill + workflow 契约               │
│  ├── adapters/        Claude Code / Codex / 语言 adapter  │
│  ├── examples/        reference impl（不参与 runtime）    │
│  └── verify.sh        lint                                │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  你的 ext 仓（如 ~/work/my-flow）—— $LOOM_EXT_HOME        │
│  ├── skills/<name>/SKILL.md     运行时实际加载            │
│  └── workflows/<name>.yaml      运行时实际加载            │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  你的业务项目                                              │
│  ├── (可选) .loom-ext/        项目本地覆盖                │
│  │       ├── skills/<name>/                              │
│  │       └── workflows/<name>.yaml                       │
│  ├── .claude/commands/workflow.md → loom 的 slash command  │
│  └── .workflow/               runtime state（loom 写）    │
└──────────────────────────────────────────────────────────┘
```

skill / workflow 查找顺序：① project-local `.loom-ext/` → ② `$LOOM_EXT_HOME/` → 报错。**`<LOOM_HOME>/examples/` 不参与运行时**，仅作样板。

## 设计原则

1. **Skill 是数据，不是代码。** 任何能写 prompt 的人都能加新 skill，不用碰编排器。
2. **状态可序列化。** 跑到一半的工作流能存档、能 resume、能被另一个会话接手。
3. **每个循环都有 escape hatch。** 不允许无限重试。卡住就升级——回上游节点、或者问人。
4. **Orchestrator 是裁判，不是选手。** 它不写代码、不写 PRD，只看 skill 产出符不符合 `success_criteria`，然后路由。
5. **同会话对话只在 gate 节点发生。** skill 执行期内不打扰人；gate 节点集中收人的输入。
6. **拦截要执行，不是阅读。** 测试与实现由独立 sub-agent 写；变异预言机改坏实现验证测试有牙；负向检查永远靠跑而非读。

## 快速开始

需要装两个：① loom 框架，② 你的 ext 仓（skill 内容）。

### 1. 装 loom 框架

```bash
# 一次性，全机器一份
git clone https://github.com/songzhibin97/loom ~/.loom
export LOOM_HOME=~/.loom            # 加进 ~/.zshrc / ~/.bashrc
```

### 2. 装/建你的 ext 仓

**已有 ext 仓**（如 my-flow）：

```bash
git clone https://github.com/songzhibin97/my-flow ~/work/my-flow
bash ~/work/my-flow/install.sh      # 写 LOOM_EXT_HOME 进 shell rc
```

**第一次建你自己的 ext 仓**——从 examples cherry：

```bash
mkdir -p ~/work/my-flow && cd ~/work/my-flow
git init
cp -r ~/.loom/examples/skills .
cp -r ~/.loom/examples/workflows .
# 加你自己的 README + install.sh + .gitignore（参考 my-flow 的样板）
export LOOM_EXT_HOME=~/work/my-flow
git add . && git commit -m "init from loom examples"
```

### 3. 在业务项目里启用 loom

```bash
cd ~/work/myproject
mkdir -p .claude/commands
ln -s "$LOOM_HOME/adapters/claude-code/commands/workflow.md" .claude/commands/workflow.md

# verify 一下整套是连通的
bash $LOOM_HOME/verify.sh

# Claude Code 里跑
/workflow run prd-to-ship "我想给后台加批量导出 CSV"
```

### 4. （可选）项目本地覆盖

要为某个项目定制特定 skill 或 workflow，不动你的 my-flow：

```bash
cd ~/work/myproject
mkdir -p .loom-ext/{skills,workflows}
# 复制要覆盖的：
cp -r "$LOOM_EXT_HOME/skills/prd-author" .loom-ext/skills/
# 改 .loom-ext/skills/prd-author/SKILL.md
```

loom 会优先用 `.loom-ext/`，找不到再去 `$LOOM_EXT_HOME/`。

详细日常操作（gate 怎么答、卡死怎么 escalate、resume 怎么用）见 `docs/runbook.md`。

**Codex CLI 暂未实现。** 见 `adapters/codex/README.md`。

## 核心契约速览

完整规范见 `spec/`。一个 skill 长这样（实际位于 `$LOOM_EXT_HOME/skills/trd-author/SKILL.md`，loom examples 里有同样的参考版）：

```markdown
---
name: trd-author
description: 把 PRD 转成可实施的 TRD —— 核心是「不变量→实现→测试」映射
inputs:
  - { name: prd, path: artifacts/PRD.md }
outputs:
  - { name: trd, path: artifacts/TRD.md }
success_criteria:
  - "TRD 含『不变量→实现→测试 映射』表，PRD 每个 INV-N 和 NFR-N 都有一行"
  - "每个 [hard] 不变量注明 enforcing 构造（条件 UPDATE / 唯一约束 / 状态校验）"
  - "每个不变量都有 always-run 测试层；不允许只靠 db-gated 测试"
retry_policy:
  max_attempts: 3
---

你是高级软件工程师。把 PRD 的每条编号不变量映射到具体实现位置和测试……
（prompt body）
```

prd-to-ship Phase 3 的执行式拦截链（节选自 `$LOOM_EXT_HOME/workflows/prd-to-ship.yaml`）：

```yaml
implement:                          # 只写实现代码，不写测试
  kind: skill
  skill: implement
  on_pass: author_tests
  on_fail: implement
  max_attempts: 3
  on_exceed: escalate_trd

author_tests:                       # 独立测试作者，看不到实现
  kind: skill
  skill: author-invariant-tests
  on_pass: run_invariant_tests
  on_fail: author_tests
  max_attempts: 3
  on_exceed: escalate_trd

run_invariant_tests:                # 真跑契约套件 -race，逐 INV 对照
  kind: skill
  skill: test-runner
  on_pass: mutation_verify
  on_fail: implement                # 测试挂 → 实现偏离规格
  max_attempts: 3
  on_exceed: escalate_trd

mutation_verify:                    # 改坏 enforce 代码，确认测试变红
  kind: skill
  skill: mutation-verify
  on_pass: code_review
  on_fail: author_tests             # 测试没牙 → 重写测试
  max_attempts: 2
  on_exceed: escalate_trd
```

—

继续读 `docs/architecture.md` 看完整设计、`docs/runbook.md` 看日常操作、`examples/README.md` 看参考实现怎么用。
