# 最小试跑指南

目的：验证 loom 的 orchestrator 能在真 Claude Code 里跑起来——只跑到第一个 gate 就算成功。

## 0. 准备（一次性，由 setup-test-env.sh 完成）

```bash
bash /Users/songzhibin/go/src/Songzhibin/loom/setup-test-env.sh
```

如果它已经跑完且全绿，跳到 §1。

## 1. 启动

```bash
cd ~/sw-test                # 或你指定的测试目录
source .envrc               # 加载 LOOM_HOME / LOOM_PROJECT_ROOT
claude                      # 启动 Claude Code 会话
```

## 2. 在 Claude Code 会话里粘这一行

```
/workflow run prd-to-ship "做一个 hello world CLI 工具"
```

## 3. 三个里程碑（按顺序应该出现）

### ✦ 里程碑 1：orchestrator 启动了

主 agent 应该：
- Read `loom/orchestrator/meta-agent.md`
- Read `loom/workflows/prd-to-ship.yaml`
- 创建 `.workflow/<时间戳>-<rand>/` 目录
- 写 `.workflow/CURRENT` 和 `.workflow/<id>/state.json`

**判断**：另开一个终端跑 `ls -la ~/sw-test/.workflow/` 能看到一个新目录 + `CURRENT` 文件。

✅ 通过 / ❌ 失败 / ❓ 不确定

### ✦ 里程碑 2：第一个 skill（`prd-clarify`）跑完了

主 agent 应该：
- 用 `Task` 工具 spawn 一个 sub-agent
- Sub-agent 读 `requirement.md` → 写 `clarifications.md`
- 主 agent 判定 pass、转到 `draft_prd`、再 spawn 一次 → 写 `PRD.md`

**判断**：`ls ~/sw-test/.workflow/*/artifacts/` 能看到 `requirement.md`、`clarifications.md`、`PRD.md` 三个文件。

✅ 通过 / ❌ 失败 / ❓ 不确定

### ✦ 里程碑 3：停在第一个 gate

主 agent 应该打印类似：

```
→ review_prd_gate

PRD 草稿在 artifacts/PRD.md。
  - approve            采用，进入 TRD
  - revise <反馈>      回去改 PRD
  - back               退回需求澄清
  - abort              终止

── 回复方式：/workflow continue approve 或 /workflow continue revise <反馈>
```

然后 **不再继续**（本轮结束，等你输入）。

**判断**：看到 gate 提示 + 主 agent 停止输出新内容、等待你下一句。

✅ 通过 / ❌ 失败 / ❓ 不确定

## 4. 报告方式

跑完后请贴这两样回来：

### A) Claude Code 会话的完整输出

从 `/workflow run` 那一行开始，到主 agent 停下来为止。**复制纯文本**，不要截图。

### B) 这条命令的结果（在终端跑）

```bash
ls -la ~/sw-test/.workflow/*/ 2>/dev/null
echo "---"
cat ~/sw-test/.workflow/*/state.json 2>/dev/null | head -60
echo "---"
ls ~/sw-test/.workflow/*/artifacts/ 2>/dev/null
```

## 5. 三种可能结局

| 结局 | 含义 | 下一步 |
|---|---|---|
| 三个里程碑全 ✅ | orchestrator 基本能跑 | 接着试 `/workflow continue approve`，看走不走到 TRD |
| 1 ✅，2 ❌ | sub-agent 行为和假设不符 | 大问题，要重做 sub-agent 那部分 |
| 1 ❌ | slash command / 路径加载有问题 | 最常见，多半是 `LOOM_HOME` 没设对 |

**不要担心** PRD 内容写得好不好——这是流程测试，看路径通不通。

## 6. 撞墙了怎么办

把会话原文贴回来。常见现象 + 我会怎么改：

| 现象 | 推测 |
|---|---|
| "loom not installed" 之类 | env var 没设 / git toplevel 找不到 / 软链断了 |
| 主 agent 不去 Read meta-agent.md，直接尝试自己解读 `/workflow run` | slash command 的 prompt 风格被忽视——要改写得更指令式 |
| Task 调用了但 sub-agent 输出末尾没 JSON 块 | skill body 的 JSON 契约说得不够强、或 Task 返回截断 |
| 主 agent spawn Task 后想等响应却卡住 | 我对 Task API 的同步/异步假设错了 |
| state.json 写错位置（不在 `.workflow/` 里） | 项目根定义没被 honored |

每个我都有对应的修法。但**先看现象再改**，不要猜。
