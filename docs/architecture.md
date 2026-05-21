# 架构设计

## 1. 设计目标

把"需求 → PRD → TRD → 实现 → 测试 → review → 提交"这类**多步、有状态、可能回退**的 agentic 工作流，做成：

- **可声明**：用一份 YAML 描述清楚整个流程
- **可移植**：同一份 YAML 在 Claude Code 和 Codex CLI 里都能跑
- **可恢复**：随时 kill 随时 resume，state 落盘
- **可观测**：每一步的输入、输出、判定都有记录
- **可逃生**：任何循环都有 max_attempts，超阈值自动 escalate
- **少打扰**：人只在 gate 节点和卡死时被叫醒

## 2. 四层模型

```
┌────────────────────────────────────────────────────────────────────┐
│  Workflow                                                          │
│  ──────────                                                        │
│  YAML 文件，描述一个有向图。节点 = state，边 = transition。        │
│  状态种类：skill / gate / parallel / decide / human / terminal     │
├────────────────────────────────────────────────────────────────────┤
│  Skill                                                             │
│  ──────                                                            │
│  Markdown 文件，frontmatter 声明 I/O 契约，body 是 prompt。        │
│  Skill 是无状态、可替换、跨 workflow 复用的"积木"。                │
├────────────────────────────────────────────────────────────────────┤
│  Orchestrator (Meta-agent)                                         │
│  ───────────────────────────                                       │
│  一份 prompt，被 CLI 当主 agent 加载。职责：                       │
│    - 读 state.json，确定 current_state                             │
│    - 按 current_state.kind 派活给 subagent / 直接询问用户          │
│    - 评估 subagent 产出是否满足 success_criteria                   │
│    - 更新 state.json，走到下一条边                                 │
│    - 触发 escalate                                                 │
├────────────────────────────────────────────────────────────────────┤
│  Adapter                                                           │
│  ────────                                                          │
│  非常薄的 CLI 特化层。负责"orchestrator 怎么被启动"和              │
│  "subagent 怎么 spawn"这两件事，其它一律复用。                     │
└────────────────────────────────────────────────────────────────────┘
```

### 为什么分这四层

| 关切 | 落在哪一层 |
|---|---|
| 业务流程长什么样 | Workflow |
| 每一步具体怎么做 | Skill |
| 卡点 / 失败 / 回退的判断逻辑 | Orchestrator |
| 怎么在某个 CLI 里启动 | Adapter |

改业务流程不动 skill；换 skill 实现不动 workflow；换 CLI 不动以上任何一层。

## 3. 状态机语义

### 3.1 State 种类

| kind | 行为 |
|---|---|
| `skill` | spawn 一个 subagent 跑指定的 skill，根据产出 + success_criteria 判定 pass/fail |
| `gate` | 同会话里直接问用户，根据用户回答路由（approve / revise / back / abort） |
| `parallel` | 并行 fan-out 到 N 个 reviewer skill，再用 aggregator 收敛成单一判定 |
| `decide` | LLM-as-judge：让 orchestrator 自己根据当前 context 决定走哪条边（少用，容易失控） |
| `human` | 升级到人，列出诊断和选项（这是 escalate 的着陆点） |
| `terminal` | 结束 |

### 3.2 Transition 关键字

```yaml
some_state:
  kind: skill
  skill: foo
  on_pass:    next_state         # success_criteria 满足
  on_fail:    upstream_state     # 不满足
  max_attempts: 3                # 这条 on_fail 边最多走几次
  on_exceed:  escalation_state   # 超了之后去哪
```

对 `gate`：

```yaml
review_prd_gate:
  kind: gate
  prompt: "PRD 草稿已生成。approve / revise <反馈> / back / abort"
  routes:                          # 必须用 routes:，不是 on_approve/on_revise/...
    approve: draft_trd
    revise:  draft_prd             # revise 时反馈写到 feedback_artifact，下次 draft_prd 会看到
    back:    gather_requirements
    abort:   _abort
  feedback_artifact: artifacts/PRD_feedback.md
```

> 注：早期草稿用过 `on_approve:` / `on_revise:` 字段名——已废弃。所有 gate 一律用 `routes: { <intent>: <state> }`。

对 `parallel`：

```yaml
code_review:
  kind: parallel
  fan_out: [reviewer-quality, reviewer-security, reviewer-test-honesty]
  aggregator: review-aggregator   # 一个 skill，输入是 N 份 review，输出 pass/fail + 理由
  on_pass: commit
  on_fail: implement
```

### 3.3 Edge counter & escape hatch

每条带 `max_attempts` 的边在 `state.json.edge_counters` 里有一个计数器。**计数器随路径计数，不是随节点。** 也就是说：

- `run_tests → implement` 这条回退边踩了 3 次，counter 达到 max_attempts=3，触发 `on_exceed`
- 但 `code_review → implement` 是另一条回退边，独立计数

**语义：** `max_attempts: N` = "这条 fail 边最多走 N 次"。第 N 次失败后 bump 到 N，已达上限，转 `on_exceed`，不再回 on_fail。

**Reset：** human state 跑完后，把"触发 escalate 的上游 state"的所有外向 fail counter 清零；否则 resume 后第一次 fail 立刻又触发同一个 escalate。

`on_exceed` 一般指向上一层的"重新设计"节点：测试反复挂 → 怀疑 TRD 有问题 → 回到 TRD；review 反复挂 → 同上；PRD 反复 revise → escalate 到人，因为这意味着需求没想清楚。

### 3.4 为什么要这样设计 escape hatch

朴素的"失败就重试"会陷入两种坑：

1. **错位重试**：测试挂了 N 次，问题其实在 TRD 而不是 implement，但 workflow 一直在 implement 里转
2. **隐形糊弄**：失败被 model 用"加个 try/except 跳过"或"删掉断言"绕过，看起来 pass 了但实际上没做事

第一种靠"分层回退 + max_attempts"解决：每一层都有一个"再不行就退到上一层"的出口。

第二种靠 **专门的反糊弄 reviewer**（`reviewer-test-honesty`）解决：它的 prompt 专门检查"测试有没有真的覆盖代码路径""断言是不是被弱化或删除""新增测试和被测代码是否相关"，等等。这个 reviewer 是 `parallel` 节点里的固定一员。

## 4. Skill 的 I/O 契约

Skill 之间**只通过文件传数据**，不直接传参。原因：

- Orchestrator 不需要理解每个 skill 内部的数据格式
- Skill 可以独立调试（手动喂 input 文件就能跑）
- State 可序列化

约定：所有 artifacts 落在 `.workflow/<run-id>/artifacts/`，skill frontmatter 里声明读哪些路径、写哪些路径。

```yaml
# skill 自己声明
inputs:
  - { name: prd, path: artifacts/PRD.md }
outputs:
  - { name: trd, path: artifacts/TRD.md }
success_criteria:
  - "TRD 每个模块都标注了测试策略"
  - "至少列出 3 个落地风险"
```

Orchestrator 在 spawn 之前会：

1. 检查所有 input 文件存在
2. 把这些路径填到 skill prompt 的占位符里
3. spawn subagent，让它读 input、写 output
4. subagent 回来后，检查 output 文件是否生成
5. 跑一个轻量 judge（一般就是 orchestrator 自己用 success_criteria 对照），判定 pass/fail

## 5. State.json 模式

```jsonc
{
  "workflow": "prd-to-ship",
  "run_id": "2026-05-19-1437-abc",
  "started_at": "2026-05-19T14:37:00Z",
  "current_state": "run_tests",

  "context": {
    "raw_requirement": "我想给后台加一个批量导出 CSV 的功能"
  },

  "artifacts": {
    "prd": "artifacts/PRD.md",
    "trd": "artifacts/TRD.md",
    "diff": "artifacts/diff.patch"
  },

  "history": [
    { "ts": "...", "state": "gather_requirements", "result": "pass", "attempt": 1 },
    { "ts": "...", "state": "draft_prd",           "result": "pass", "attempt": 1 },
    { "ts": "...", "state": "review_prd_gate",     "result": "approve" },
    { "ts": "...", "state": "draft_trd",           "result": "pass", "attempt": 1 },
    { "ts": "...", "state": "implement",           "result": "pass", "attempt": 1 },
    { "ts": "...", "state": "run_tests",           "result": "fail", "attempt": 1,
      "notes": "3 个用例失败：导出大文件时超时" }
  ],

  "edge_counters": {
    "run_tests->implement": 1
  },

  "pending_gate": null,
  "escalation": null
}
```

**两条规矩：**

- 永远先写 state.json，再返回给用户。这样 crash 后还能 resume。
- `history` 是 append-only。回退不删历史，只新增 entry。

## 6. Orchestrator 工作循环（伪码）

> 关键前提：orchestrator 是**主 agent 的行为**，不是 sub-agent。所以 gate / human / `_resume_after_manual` 不能"阻塞等用户"——它们只能"打印提示 → 写 pending_gate → return"，等用户下一次 `/workflow continue` 重新进入。

```
on entry (via /workflow run or /workflow continue):
  state = read state.json
  if pending_gate:
    handle_gate_answer(user_input)   # 解析、写 history、清 pending_gate、切 current_state

  loop:
    s = workflow.states[state.current_state]

    if s.kind in (gate, human, _resume_after_manual, terminal, _abort):
      handle_interactive_or_terminal(s)
      return                          # 控制权交回用户

    if s.kind == skill:
      task_result = Task(subagent_type="general-purpose",
                        prompt=render_skill(s.skill, state.artifacts))
      pass = judge_against(s.success_criteria, task_result, output_files)
      append_history(state, pass)
      next = pass ? s.on_pass : s.on_fail
      if not pass:
        bump_counter(edge = "{cur}->{on_fail}")
        if counter >= s.max_attempts:    # 注意是 ≥
          next = s.on_exceed

    if s.kind == parallel:
      for each fan_out skill: Task(...)
      verdict = Task(aggregator, ...)
      pass = parse VERDICT line
      ... (同 skill 的 counter / exceed)

    state.current_state = next
    write state.json
```

## 7. 跨 CLI 的兼容性（现状）

| 能力 | Claude Code | Codex CLI |
|---|---|---|
| 加载 slash command | `.claude/commands/*.md`，已验证 | 待你提供 Codex 实际 CLI 文档后实现 |
| Spawn sub-agent 跑 skill | `Task` 工具 | 待定 |
| 跑 bash | `Bash` 工具 | shell |
| 主 agent 同会话和用户对话 | 通过 slash command 让主 agent 进入 orchestrator 模式 | 待定 |
| `model_hint: vendor:*`（跨厂商盲审） | **不支持**（Claude Code 不能 per-task 切模型/厂商）；hint 仅作 prompt 风格提示 | 待定，理论上 Codex 可以 |

**当前实现状态：Claude Code 是主目标，Codex adapter 是 TBD。** 详见 `adapters/codex/README.md`。

## 8. 反糊弄机制（执行式拦截）

实测表明：单纯的静态 review（grep + LLM 读测试代码）只能抓**懒**的假——`t.Skip` 字面量、`assert True`、明显缺断言；抓不到**用功**的假（看着丰满、断言的值是错的）。更深的病根是 *谁写测试 ≠ 谁的目标*：实现 sub-agent 自己也写测试时，它的局部激励就是「让测试过」，最便宜过法是写假测试和自己的 bug 串通。

新版 `prd-to-ship` 用**结构 + 执行**两层兜底，静态降为次级：

| 偷懒模式 | 一级拦截（结构 / 执行） | 二级拦截（静态） |
|---|---|---|
| 测试与 bug 串通（同一 agent 写两边） | **流程层独立**：契约测试由 `author-invariant-tests` sub-agent 写、**看不到实现代码**；`implement` sub-agent 不写测试 | — |
| 不变量漏覆盖 | **结构强制**：PRD 编号 `INV-N` → TRD 映射逐条引用 → `author-invariant-tests` 必须每条 ≥1 测试 → `test-runner` 逐 INV 对照执行结果 | — |
| 测试没牙（断言弱 / 编码 bug 当对） | **执行层**：`mutation-verify` 改坏 enforce 不变量的代码，跑该 INV 的契约测试必须变红；不变红 = 测试假，回 `author_tests` 重写 | `reviewer-quality` 静态扫弱断言（懒假预筛） |
| 不变量测试静默跳过 | **执行层**：`test-runner` 把 SKIP 的不变量测试视为 fail；任一 INV 测试没 PASS = 整体失败 | — |
| 实现 stub / 占位 / 空函数 | — | `reviewer-quality` 扫 `panic("not implemented")` / 空函数体 / 改动代码 TODO/FIXME |
| Sub-agent 自报达标但产物没达标 | orchestrator 独立 judge 读 output 对照 success_criteria（同 LLM 自审，软兜底） | — |

**诚实声明：** 「执行层」是真正的 ground truth——测试真跑、变异真破坏、SKIP 真当失败。静态层（reviewer-quality）是补充懒假预筛。「独立测试作者」是流程层属性（不同 sub-agent + prompt 禁读实现源码）；loom 不能用 tool whitelist 硬隔（Task API 不支持，见 §8.5），所以「不读实现」靠 prompt 规则 + 输出抽查（看测试有没有引用 TRD 未声明的内部细节），不是绝对隔离。但**就算 prompt 被违反**，独立 sub-agent + spec-derived 测试 + 变异预言机三者叠加，已比「同 agent 写两边 + 静态 review」高一个量级。

## 8.5 Claude Code adapter 的硬限制（必须知道）

下面这些是 Claude Code Task API 本身不支持的能力。**Skill frontmatter 里能写、但 runtime 不强制**：

| Skill frontmatter 字段 | 期望 | Claude Code 实际 | 后果 |
|---|---|---|---|
| `tools: [Read, Write, ...]` | 限制 sub-agent 能用的工具 | 不支持 per-Task 限制 | 仅作 prompt 提示。Sub-agent 理论上能用 orchestrator 范围内的所有工具 |
| `model_hint: strong / fast` | 切模型 | 不支持 per-Task 切模型 | 整段会议都用同一模型；hint 仅作风格提示 |
| `model_hint: vendor:openai` | 切厂商做盲审 | **完全做不到** | 真双盲必须靠 Codex adapter（TBD） |
| `timeout_seconds: 600` | 超时控制 | Task 有自己的隐式超时，不可配 | 长 skill 可能被 Claude Code 自己掐掉 |

加上这条："**Independent judge"实际是同一个 LLM**，不构成真正的独立验证——它只是把"读 output 文件 + 对照 criteria"这件事和 skill 执行隔开，但模型一致性偏差仍在。这部分的反糊弄真正靠的是 §8 表里『一级拦截』那栏——执行式（真跑测试、变异预言机）+ 流程式（独立测试作者）。

任何 spec / skill 文档里写 `model_hint: vendor:*` 等于在 Claude Code 下被静默降级。Codex adapter 实现后才能兑现。verify.sh 的 §12 会扫这类声明并 warn。

## 8.6 没解决的运维问题（已知）

- `.workflow/CURRENT` 没文件锁——两个 Claude Code session 同时跑 `/workflow run` 会 race
- gate 反复 revise 没有 max_attempts——已在 meta-agent.md §"Gate 反复打回"加硬上限 10，作为兜底
- success_criteria 写得太宽时 orchestrator judge 没辙——只能靠用户写好 criteria

## 9. 不做什么

为了让这个东西能落地，明确**不**做几件事：

- 不做可视化编辑器。YAML 手写。
- 不做远端 runtime / 队列 / 调度。一切跑在 CLI 进程里。
- 不做 RBAC、租户、审计日志。
- 不做"自动发现 skill"。skill 必须在 workflow 里被显式引用。
- 不做跨 workflow 通信。每个 run 是独立的。

## 10. 后续可以做但 MVP 不做

- workflow 可视化 dump（mermaid 输出）
- 多 run 并发（目前一次跑一个）
- 失败模式知识库（把 `on_exceed` 的诊断结果沉淀下来）
- Skill 版本管理（目前靠 git）
- Cost / latency tracking
