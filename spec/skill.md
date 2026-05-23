# Skill 规范

一个 skill = 一个 markdown 文件。运行时**实际加载**的位置：

1. `$PROJECT_ROOT/.loom-ext/skills/<name>/SKILL.md` —— 项目本地覆盖（可选，最高优先级）
2. `$LOOM_EXT_HOME/skills/<name>/SKILL.md` —— 用户 ext 仓（如 `~/work/my-flow/skills/`）

loom 框架自身的 `<LOOM_HOME>/examples/skills/` 仅作参考实现，**不参与运行时查找**。本文档约定的所有路径示例 `skills/<name>/...` 默认意指你的 ext 仓里那份。

Skill 是**无状态、可替换、跨 workflow 复用**的"积木"。它不知道自己被谁调用、调用之前做了什么、调用之后还要做什么。它只看自己的 input 文件、按 prompt 干活、写 output 文件。

## 1. 文件结构

```markdown
---
<frontmatter>
---

<body — 也就是 prompt>
```

## 2. Frontmatter 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | ✓ | 唯一标识，kebab-case。必须等于所在目录名 |
| `description` | ✓ | 一句话，给 orchestrator 看的（Claude Code 也用它做 skill 发现） |
| `inputs` | ✓ | 这个 skill 需要读哪些 artifact 文件 |
| `outputs` | ✓ | 这个 skill 会写哪些 artifact 文件 |
| `success_criteria` | ✓ | orchestrator 判定 pass/fail 的清单 |
| `retry_policy` |   | 默认 `{ max_attempts: 1 }`。被 workflow 边上的同名字段覆盖 |
| `model_hint` |   | 倾向哪个模型跑（"strong" / "fast" / "vendor:openai" / "vendor:anthropic"） |
| `tools` |   | 这个 skill 在 subagent 里允许用哪些工具，默认 `[Read, Write, Edit, Bash]` |
| `timeout_seconds` |   | subagent 超时，默认 600 |

### 2.1 `inputs` / `outputs` 格式

```yaml
inputs:
  - name: prd                    # skill body 里用 {{prd}} 引用
    path: artifacts/PRD.md       # 相对 .workflow/<run-id>/ 的路径
    required: true               # 默认 true。false 时 input 可为空
outputs:
  - name: trd
    path: artifacts/TRD.md
    must_exist_after: true       # 默认 true。run 完后这个文件必须存在
```

### 2.2 `success_criteria` 格式

每条是一句自然语言判断。orchestrator 跑完 skill 后会用这些条目逐项核对（也是 LLM 判定，但和 skill 主体隔离开）。

```yaml
success_criteria:
  - "TRD 里每个模块都标注了依赖、接口签名和测试策略"
  - "至少列出 3 个落地风险"
  - "对每个风险给了缓解方案或验证手段"
```

写 criteria 的三个原则：

1. **可证伪。** "TRD 写得很好"不行；"TRD 至少 3 个模块、每个模块有测试策略"可以。
2. **指向产物，不是过程。** "认真思考了风险"不行；"风险章节列了至少 3 条"可以。
3. **面向覆盖，不是形状。** 「PRD 含背景、目标、非目标章节」是形状检查——章节齐全 ≠ 需求覆盖了。「输入需求每个可观察行为都对应一条编号不变量」是覆盖检查。当输入是结构化清单时（如需求里多个不变量），criteria 应明确到「每一条都有对应输出条目」。

### 2.3 `retry_policy`

```yaml
retry_policy:
  max_attempts: 3
  backoff: none                  # MVP 只支持 none
```

Skill 自己声明的 max_attempts 是默认值。Workflow 的 state 上写的 `max_attempts` 优先级更高（不同 workflow 对同一个 skill 可以有不同容忍度）。

## 3. Body（prompt）规范

Body 是 skill 的实际 prompt。约定：

- **第一行**：身份声明（"你是 ...", "Act as ..."）。
- **占位符**用 `{{name}}` 语法引用 frontmatter `inputs` 里声明的 name。orchestrator 在 spawn 之前会把 `{{prd}}` 替换成实际文件路径或文件内容（取决于 skill 自己怎么用）。
- **明确写出输出位置**：让 subagent 知道把结果写到哪个文件。
- **不要在 prompt 里调度其它 skill**。组合靠 workflow，不靠 prompt 套娃。
- **包含 self-check 段落**：在 prompt 末尾让 subagent 自检一遍 `success_criteria`，并把自检结果一起输出。这能让后续的 judge 更省事，也能减少糊弄。

### 必须的输出契约（normative）

每个 SKILL.md 的 body **必须**在末尾包含一段说明，要求 sub-agent 在最终消息里输出一个 JSON 块，独占代码段，格式严格：

````
最后输出 JSON 块（独占一段，```json ... ``` 围起来）：

```json
{ "outputs_written": ["<absolute path>", ...],
  "self_check": [
    { "criterion": "<copy from frontmatter>", "satisfied": true|false, "evidence": "<具体引用>" }
  ],
  "notes": "<one line, any concerns>" }
```
````

**为什么这条是 skill 自己负责，而不是 orchestrator 追加：** 单一来源——skill body 自己写，sub-agent 只看到一份契约；如果未来调试也只看 SKILL.md 就够，不用回头读 orchestrator 内部逻辑。

Orchestrator 的 `run_skill_state` 在 parse Task 返回时取这个 JSON。Context 截断导致丢失时，orchestrator 有 fallback（见 `orchestrator/meta-agent.md` §run_skill_state 第 4 步）。

### 推荐模板

```markdown
---
name: trd-author
description: 把已确认的 PRD 转成可实施的 TRD
inputs:
  - { name: prd, path: artifacts/PRD.md }
  - { name: prd_feedback, path: artifacts/PRD_feedback.md, required: false }
outputs:
  - { name: trd, path: artifacts/TRD.md }
success_criteria:
  - "TRD 至少包含：架构概览、模块拆分、接口签名、数据模型、测试策略、风险与缓解"
  - "每个模块都有明确的依赖列表"
  - "至少列出 3 个落地风险"
retry_policy:
  max_attempts: 3
model_hint: strong
tools: [Read, Write, Edit, Bash]
---

你是一位高级软件工程师，负责把 PRD 转成可实施的 TRD。

## 输入
- PRD：`{{prd}}`
- （可选）上一轮 review 的反馈：`{{prd_feedback}}`

## 任务
1. 读 PRD，确认你理解每一条需求。
2. 起草 TRD，包含：架构概览、模块拆分、接口签名、数据模型、测试策略、风险。
3. 把 TRD 写到 `{{trd}}`。

## 风格
- 简洁，避免空话。
- 接口签名用实际语言（Go / Python / TS 看项目）。
- 风险章节不允许"可能存在性能问题"这种空话——要具体到"批量导出 10 万行 CSV 时，X 函数会一次性把数据加载进内存"。

## 自检（必做）
写完后，逐条对照 `success_criteria` 自检，把结果以下面的格式追加到 TRD 末尾的 `<!-- self-check -->` 注释块里：

    <!-- self-check
    - [x] 至少包含：架构概览、模块拆分、...
    - [x] 每个模块都有明确的依赖列表
    - [ ] 至少列出 3 个落地风险  ← 这里只写了 2 个
    -->

如果有任意一项没满足，**不要交付**——回去补足再写。
```

## 4. 命名约定

- skill 目录和 `name` 字段保持一致：`skills/trd-author/SKILL.md` 里 `name: trd-author`
- review 类 skill 以 `reviewer-` 开头：`reviewer-quality`, `reviewer-security`, `reviewer-regression`
- 聚合 / 裁判类以 `-aggregator` 或 `-judge` 结尾

## 5. 怎么手动调试一个 skill

不依赖 orchestrator 也能跑：

```bash
# 1. 准备一个 fake run 目录
mkdir -p .workflow/dev/artifacts
cp my-prd.md .workflow/dev/artifacts/PRD.md

# 2. 让任意 CLI agent 读 SKILL.md，按它的 prompt 干活
#    把 {{prd}} 手动替换成 .workflow/dev/artifacts/PRD.md
```

这是 skill 必须**独立可调试**的硬性要求——也是为什么 skill 之间只通过文件传数据。

## 6. 执行式拦截 doctrine（prd-to-ship 不变量流）

`prd-to-ship` 工作流引入一组**结构性反糊弄**机制——靠流程层（不同 sub-agent 互不可见）+ 执行层（真跑测试、变异预言机）保证测试与实现真的对齐，而不是靠静态 review 事后阅读。涉及的约定：

### 6.1 不变量编号
- PRD 用 `## 不变量` 段列编号清单 `INV-1..N`，每条一行可证伪、消费者视角。
- PRD 用 `## 非功能需求` 段列 `NFR-1..M`。
- 每条 INV / NFR 标 `[hard]` 或 `[normal]`——hard = 并发 / 幂等 / 原子性 / 状态机 / exactly-once；`mutation-verify` 据此定靶。

### 6.2 artifact 约定
- `artifacts/PRD.md` —— 含上述编号不变量。
- `artifacts/TRD.md` —— 含「不变量→实现→测试 映射」表，每个 INV/NFR 一行；每个 [hard] 行注明 enforcing 构造（条件 UPDATE / 唯一约束 / 状态校验）。
- `artifacts/test_manifest.md` —— 每个 INV/NFR → 测试函数 → 文件 → 测试层级。
- `artifacts/reviews/mutation.md` —— 变异预言机报告，逐 hard 不变量「破坏 → 测试红✓/绿✗」+ VERDICT。

### 6.3 独立测试作者原则
- 写**契约测试**的 sub-agent（`author-invariant-tests`）只看 PRD 不变量 + TRD 接口签名，**不读实现源码函数体**。
- 写**实现**的 sub-agent（`implement`）只看 TRD，**不写任何 `*_test.go`**，看不到契约测试。
- 实现与契约测试由不同 sub-agent 写、互不可见——这是流程层的硬属性，单个 skill 的 prose 实现不了。

### 6.4 always-run 测试层规则
- 每个不变量必须有 `always-run` 层的契约测试（无条件运行、不依赖外部环境）。
- 并发 / 幂等不变量的 always-run 测试必须是**真并发**：真 goroutine + 忠实建模并发的内存 double（按行加锁、事务体并行），不能是单 mutex 串行化的假并发。
- 允许在 always-run 之上再加 `db-gated` 层（真依赖如 Postgres），但**不允许任何不变量只有 db-gated 测试**——环境缺失它静默跳过、套件仍报绿、不变量没验。
- `test-runner` 把 SKIP 的不变量测试视为失败。

### 6.5 变异预言机
- `mutation-verify` 故意改坏 enforce 不变量的代码，跑该不变量的契约测试，要求它**变红**；不变红 = 测试是假的，回 `author_tests` 重写。
- 这是「测试是否真有牙」的**执行式**验证，比静态阅读测试代码强一个量级。

### 6.6 语言无关
skill 都是**语言无关**的。语言特化的命令（build / test / format）、文件模式（test-file / source）、skip markers、错误包裹、正确性 checklist —— 一律从 `<loom>/adapters/languages/<lang>.md` 读。skill body 引用 verb 时用 backtick（如 `` `build` ``、`` `test-verbose-race` ``），其值由 adapter 提供。详见 `adapters/languages/README.md`。
