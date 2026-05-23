# examples/

参考实现 —— 这里的 skill 和 workflow **不参与 loom 运行时**。它们是给新用户做 bootstrap、给所有人做对照样板用的。

## 为什么在这里

loom 的设计是 **lean engine + 用户 extension**：
- **loom 本体**（仓根的 `orchestrator/`、`spec/`、`adapters/`、`verify.sh`）—— 纯框架，不带运行时 skill/workflow。
- **用户的 `$LOOM_EXT_HOME`** —— 用户 maintain 的 skill + workflow 仓，运行时**实际**被加载的内容。
- **`examples/`**（这里）—— 同一时点的「框架自家参考实现」，用来：
  1. 给新用户 bootstrap：第一次建自己的 `LOOM_EXT_HOME` 时，从这里 cp 一份做起点。
  2. 给所有人对照：「loom 设想的标准用法」长什么样。
  3. 给 verify.sh 持续 lint：保证 reference impl 与 spec 同步、不烂掉。

## 内容

```
examples/
├── skills/                       14 个 workflow-phase skill（与 my-flow 同时点 cherry 出来）
│   ├── prd-clarify/              需求澄清 + 候选不变量
│   ├── prd-author/               PRD：编号不变量 INV-N / NFR-N
│   ├── trd-author/               TRD：不变量 → 实现 → 测试 映射
│   ├── implement/                只写代码，不写测试
│   ├── author-invariant-tests/   独立测试作者（不读实现）
│   ├── mutation-verify/          变异预言机（核心拦截）
│   ├── test-runner/              跑契约套件 + 解析 SKIP
│   ├── reviewer-quality/         次级静态 review
│   ├── reviewer-security/        次级静态 review
│   ├── reviewer-regression/      issue-to-fix 用
│   ├── review-aggregator/        并行 review 聚合
│   ├── committer/                本地 commit
│   ├── issue-triage/             bug 分诊
│   └── bug-reproduce/            写复现失败测试
└── workflows/
    ├── prd-to-ship.yaml          新功能流（含 author_tests + run_invariant_tests + mutation_verify）
    └── issue-to-fix.yaml         bug 修复流
```

## 怎么从 examples 起手

```bash
# 1. 建你自己的 ext 仓
mkdir -p ~/work/my-flow && cd ~/work/my-flow
git init

# 2. 从 examples 拷过来
cp -r /path/to/loom/examples/skills .
cp -r /path/to/loom/examples/workflows .

# 3. 加 install.sh + README + .gitignore，commit
# （参考已有的 my-flow 仓结构）

# 4. 把环境变量指过来
export LOOM_EXT_HOME=~/work/my-flow

# 5. 在业务项目里跑
/workflow run prd-to-ship "..."
```

## 这里**不会**被 loom 运行时加载

loom 的 skill / workflow 查找路径**不包含** `loom/examples/`。这里只是文件 + 文档。你直接编辑 `examples/skills/foo/SKILL.md` 不会影响任何在跑的 workflow。要修改运行时行为，去你的 `$LOOM_EXT_HOME` 改。

## 升级 examples

loom 框架升级时，如果 reference impl 也变了（例如改了 skill prompt 范式），examples/ 这里跟着更新。**你已有的 `$LOOM_EXT_HOME` 不会被自动覆盖**——升级 loom 框架 vs 升级你的 ext 内容是两件独立的事。你可以选择性地 diff `loom/examples/` 和你的 `$LOOM_EXT_HOME`，挑想要的改动 cherry-pick 过来。
