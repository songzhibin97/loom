# Workflow 规范

一个 workflow = 一个 YAML 文件，路径形如 `workflows/<name>.yaml`。

它描述一个**有向图状态机**：节点是 state，边是 transition。orchestrator 读这个 YAML，按状态机跑。

## 1. 顶层结构

```yaml
name: prd-to-ship                  # 唯一标识
description: 一句话流程介绍
version: 1                         # schema 版本，目前固定 1

inputs:                            # 启动 workflow 时必须提供的参数
  - name: requirement
    description: 一句话需求
    required: true

start: gather_requirements         # 入口 state

states:
  <state_name>:
    kind: skill | gate | parallel | decide | human | terminal
    # ... 见下文
```

## 2. State 通用字段

```yaml
some_state:
  kind: <one of: skill / gate / parallel / decide / human / terminal>
  comment: 可选，给读 YAML 的人看
```

每种 kind 有自己的额外字段。

## 3. `kind: skill`

```yaml
implement:
  kind: skill
  skill: implement                 # 引用 skills/implement/SKILL.md
  inputs:                          # 覆盖 skill 默认的 input 路径（可选）
    - { name: trd, path: artifacts/TRD.md }
  on_pass: run_tests
  on_fail: implement               # 失败时回到自己（默认就是 fail 即重试自己）
  max_attempts: 3                  # 这个 state 的失败计数器上限
  on_exceed: escalate_trd          # 上限触发后去哪
```

**判定逻辑：**

1. spawn subagent（Task tool），跑 skill
2. 检查所有声明的 output 文件是否生成
3. LLM judge 用 skill 的 `success_criteria` 逐条对照
4. 全部满足 → `on_pass`；否则 → `on_fail`，对应的 edge counter +1
5. **counter ≥ `max_attempts` → `on_exceed`**
   - 语义：`max_attempts: N` = "这条 fail 边最多走 N 次"。第 N 次失败后 bump 到 N，立即转 on_exceed，不再回 on_fail。

### 3.1 边计数器 reset

跑完 `kind: human` 状态后，把"触发它的那个 state（从 history 倒着找最近一次 fail 所在的 state）的所有外向 fail counter"清零。否则 resume 后第一次失败立刻又触发同一 escalate。

## 4. `kind: gate`

人机交互节点。在同一个 CLI 会话里直接问用户。

```yaml
review_prd_gate:
  kind: gate
  prompt: |
    PRD 草稿在 artifacts/PRD.md。请 review：
      - approve            采用，继续 TRD
      - revise <反馈>      回去改 PRD（反馈会写到 artifacts/PRD_feedback.md）
      - back               退回需求澄清
      - abort              终止 workflow
  routes:
    approve: draft_trd
    revise:  draft_prd
    back:    gather_requirements
    abort:   _abort
  feedback_artifact: artifacts/PRD_feedback.md   # 可选；revise 时把反馈写到这
```

`_abort` 是保留状态，等价于一个 terminal。

**用户回答的解析：** orchestrator 用宽松匹配（"批准"/"approve"/"ok"/"通过" 都映射到 approve）。新增同义词在 orchestrator prompt 里维护，不在 workflow YAML 里。

## 5. `kind: parallel`

并行 fan-out 多个 reviewer，聚合判定。

```yaml
code_review:
  kind: parallel
  fan_out:
    - skill: reviewer-quality
    - skill: reviewer-security
    - skill: reviewer-test-honesty
      model_hint: vendor:openai      # 双盲：换厂商
  aggregator: review-aggregator       # 一个 skill，输入是 N 份 review，输出 verdict
  shared_inputs:                      # 所有 reviewer 都能读的 artifacts
    - { name: diff, path: artifacts/diff.patch }
    - { name: trd,  path: artifacts/TRD.md }
  on_pass: commit
  on_fail: implement
  max_attempts: 2
  on_exceed: escalate_trd
```

**执行细节：**

- 每个 reviewer 在自己的 subagent 里跑，**不能看到其它 reviewer 的输出**（这就是"盲"）
- 每个 reviewer 写自己的 review 文件到 `artifacts/reviews/<reviewer-name>.md`
- aggregator 读所有 review，输出 `artifacts/review_verdict.md`（含 pass/fail + 理由 + 受影响行号）
- pass/fail 由 aggregator 输出决定，**不**由 orchestrator 二次判断

## 6. `kind: decide`

让 orchestrator 自己根据当前上下文决定走哪条边。**少用**，因为它把可控的状态机退化成"AI 拍脑袋"。

```yaml
should_continue:
  kind: decide
  prompt: |
    根据 state.history，判断需求是否还在合理范围。
    选项：continue / pivot / abort
  routes:
    continue: implement
    pivot:    draft_trd
    abort:    _abort
```

合法用法：分支条件非常依赖语义判断、又不适合让人介入（比如"PRD 是改 bug 还是加功能，路由到不同分支"）。

## 7. `kind: human`

升级到人。一般是 `on_exceed` 的着陆点。

```yaml
escalate_trd:
  kind: human
  diagnosis: |
    包含：当前 state.history 摘要、edge_counters、最近一次失败的 reviewer 评语。
  prompt: |
    工作流卡住了。可能原因：TRD 的方案走不通，或测试糊弄被反复识破。
    选项：
      1) 回到 TRD 重新设计 (draft_trd)
      2) 回到 PRD 重新审视需求 (draft_prd)
      3) 手动介入，我来改 artifacts/，你 resume
      4) 终止
  routes:
    "1": draft_trd
    "2": draft_prd
    "3": _resume_after_manual
    "4": _abort
```

`_resume_after_manual` 也是保留状态：orchestrator 会等用户输入 `resume` 后从同一个状态再跑一次。

## 8. `kind: terminal`

```yaml
done:
  kind: terminal
  summary: |
    输出整个 run 的摘要：跑了几个 state、产出哪些 artifacts、有哪些 escalation。
```

## 9. 完整的 schema 速查

```yaml
name:        string (required)
description: string
version:     int (required, = 1)
inputs:      [ { name, description, required } ]
start:       string (state name, required)

states:
  <name>:
    kind: skill | gate | parallel | decide | human | terminal

    # kind=skill
    skill: <skill-name>
    inputs: [ { name, path } ]
    on_pass: <state>
    on_fail: <state>
    max_attempts: int
    on_exceed: <state>

    # kind=gate
    prompt: string
    routes: { <intent>: <state> }
    feedback_artifact: string

    # kind=parallel
    fan_out: [ { skill, model_hint? } ]
    aggregator: <skill-name>
    shared_inputs: [ { name, path } ]
    on_pass, on_fail, max_attempts, on_exceed (同 skill)

    # kind=decide
    prompt: string
    routes: { <intent>: <state> }

    # kind=human
    diagnosis: string
    prompt: string
    routes: { <choice>: <state> }

    # kind=terminal
    summary: string
```

## 10. 保留 state 名

| 名字 | 含义 |
|---|---|
| `_abort` | 立刻终止 run，写一条 `aborted` 历史 |
| `_resume_after_manual` | 暂停 orchestrator，等用户在 CLI 里输 `resume` |

不要在 workflow 里自定义这两个名字。

## 11. 一个 workflow 最少要长什么样

```yaml
name: minimal
version: 1
inputs:
  - { name: topic, required: true }
start: only_step
states:
  only_step:
    kind: skill
    skill: do-thing
    on_pass: done
    on_fail: only_step
    max_attempts: 2
    on_exceed: _abort
  done:
    kind: terminal
```

## 12. Lint 清单

写完一个 workflow，过一遍：

- [ ] 每个非 terminal state 都有出边
- [ ] 所有 `on_pass`/`on_fail`/`on_exceed` 引用的 state 都存在
- [ ] 所有 `skill:` 引用的 skill 都存在
- [ ] 每条 `on_fail` 都有 `max_attempts` 和 `on_exceed`，没有死循环
- [ ] `start` 指向的 state 存在
- [ ] 至少有一条路径能走到 terminal
