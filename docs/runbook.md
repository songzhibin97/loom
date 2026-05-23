# Runbook — Day-1 上手（Claude Code）

这份文档假设你刚拿到 loom，目标是**今天就在 Claude Code 里跑出第一个 workflow**。

## 0. 准备

你需要：

- Claude Code 已装好（`claude` 命令可用）
- 一个 git 项目（loom 放在项目里，比如 `<repo>/loom/`）
- bash + python3 + PyYAML（验证脚本用）

```bash
python3 -c "import yaml" || pip install pyyaml --break-system-packages
```

## 1. 安装 slash command

```bash
cd <repo>
mkdir -p .claude/commands
ln -s "$(pwd)/loom/adapters/claude-code/commands/workflow.md" \
      .claude/commands/workflow.md
```

可选：设置 `LOOM_HOME`，否则 slash command 会用 `git rev-parse --show-toplevel` 自动找。

```bash
export LOOM_HOME="$(pwd)/loom"
```

## 2. 跑 verify.sh

```bash
bash loom/verify.sh
```

输出全绿才往下走。任何 `✗` 都意味着引用对不上、frontmatter 有问题、或文档语义有冲突——这些不修，orchestrator 跑起来会出意外。

## 3. 跑第一个 workflow

打开 Claude Code 会话：

```
> /workflow run prd-to-ship "我想给后台加批量导出 CSV 的功能"
```

会发生什么：

1. Claude Code 把 slash command 的内容塞给主 agent
2. 主 agent 读 `orchestrator/meta-agent.md`，按指令进入主循环
3. 它创建 `.workflow/<时间戳>-<rand>/` 作为 run 目录，把 requirement 写进去
4. 跑第一个 skill（`prd-clarify`，spawn 一个 Task）
5. Task 完成后，主 agent 检查产物、判定 pass/fail
6. 转到下一个 state（`draft_prd`），再 spawn 一个 Task
7. 一直跑到撞到 `review_prd_gate`，主 agent 打印 gate 提示，**结束本轮**

你会看到类似：

```
→ gather_requirements
▶ skill: prd-clarify attempt 1
✓ pass
→ draft_prd
▶ skill: prd-author attempt 1
✓ pass
→ review_prd_gate

PRD 草稿在 artifacts/PRD.md。
  - approve            采用，进入 TRD
  - revise <反馈>      回去改 PRD
  - back               退回需求澄清
  - abort              终止

── 回复方式：/workflow continue approve 或 /workflow continue revise <反馈> 等
```

主 agent 现在等着你。

## 4. 通过 gate

```
> /workflow continue approve
```

或者

```
> /workflow continue revise 要加按时间过滤
```

主 agent 读到 `/workflow continue` 后，重新进入 orchestrator 模式，找到 active run 的 `.workflow/CURRENT`，根据 state.json 里的 `pending_gate` 字段，把你的输入当 gate 答复处理。

- `approve` → 转到下一 state，继续推进
- `revise <反馈>` → 反馈写到 `artifacts/PRD_feedback.md`，回到 `draft_prd` 重写
- `back` → 回到上游 gate / state
- `abort` → 走 `_abort`，终止 run

## 5. 看进度

```
> /workflow status
```

显示当前 active run 的 current_state、最近几条 history、pending_gate（如有）。**不**推进任何状态。

```
> /workflow list
```

显示 `.workflow/` 下所有 run（包括已完成的）。

## 6. Escalate（卡死时）

如果某条 fail 边的计数器达到 `max_attempts`：

- 主 agent 自动跳到 `on_exceed` 指向的 `kind: human` 状态
- 打印诊断（卡在哪、为什么、最近失败原因）+ 选项菜单
- 你 `/workflow continue 1` / `/workflow continue 2` 等选一个

如果选了"手动接管"（一般是选项 3 → `_resume_after_manual`）：

1. 主 agent 暂停，告诉你"手动改 artifacts 后输 `/workflow continue resume`"
2. 你在 `.workflow/<run-dir>/artifacts/` 里手动改文件
3. `/workflow continue resume` 让它从触发 escalate 的那个 state 重跑（计数器已 reset）

## 7. 跨会话 resume

state.json 落盘，所以你 kill Claude Code 重开都没事。新会话里：

```
> /workflow status
```

会显示有 active run。然后：

```
> /workflow continue
```

会从 state.current_state 接着跑。如果有 pending_gate，会重新打印 gate 提示。

## 8. 常见坑

### A. "no active workflow run"

`.workflow/CURRENT` 不存在或指向无效目录。`/workflow list` 看有什么 run，手动写：

```bash
echo "/abs/path/to/.workflow/<run-id>" > .workflow/CURRENT
```

### B. Sub-agent 没输出 JSON 块

主 agent 解析不到结尾的 `{ outputs_written, self_check, notes }`，会判 fail。这要么是 skill prompt 写得不好（没强调 JSON 块），要么是这次 Task 真的没干活。看 transcript：

```bash
cat .workflow/<run-id>/transcripts/<state>-<attempt>.md
```

### C. Skill 引用了不存在的文件

skill frontmatter 里 `inputs[].path` 写错。或者上游 skill 没生成预期的 output 文件。verify.sh 会查 frontmatter 格式但**不会查跨 skill 的 output→input 对接**——那个错只能 runtime 发现。

### D. Gate 反复 revise 5 次以上

主 agent 会在 gate 提示顶上加一段警告。你可以：
- 继续 revise（如果你觉得快搞定了）
- `/workflow continue abort` 终止
- `/workflow continue back` 退到更上游

### E. Working dir 已经脏了再跑 implement

implement skill 用 `git add -A` 暂存所有改动来生成 diff snapshot。如果你跑之前 working dir 已经有别的改动，会一起被算进 diff。建议：每次跑 workflow 前 `git status` 确认 working dir 干净。

## 9. 接下来

- 想加一个自己的 workflow → 看 `spec/workflow.md`
- 想加一个新 skill → 看 `spec/skill.md`，参考 `skills/prd-author/SKILL.md` 这类作为模板
- 想知道为什么这么设计 → 看 `docs/architecture.md`
- 想看一次坏路径怎么走 → 看 `docs/self-check-trace.md`

## 10. 还不能跑的

- Codex CLI — 见 `adapters/codex/README.md`
- 跨厂商真盲审（`model_hint: vendor:*`） — Claude Code 不支持 per-Task 切模型
- 并发多 run — 一次只能有一个 active run（`.workflow/CURRENT` 单一）
- 跨项目共享 run — `.workflow/` 是项目本地
