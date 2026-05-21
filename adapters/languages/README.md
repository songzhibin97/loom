# Language adapters

loom 的 skill 都是**语言无关**的。Skill 需要的语言特化命令、文件模式、惯用法——build 怎么跑、测试怎么跑、什么样叫「skip」——一律从本目录读 adapter，不写进 skill。

## skill 怎么用 adapter

1. **识别主语言**：看 repo 根的标记文件——
   - `go.mod` → Go
   - `pyproject.toml` / `setup.py` / `requirements.txt` → Python
   - `Cargo.toml` → Rust
   - `package.json` → JavaScript / TypeScript
2. **读 `<loom>/adapters/languages/<lang>.md`**。`<loom>` 解析与 slash command 一致：`$LOOM_HOME` → `$(git rev-parse --show-toplevel)/loom` → `./loom`。
3. **用其中声明的 verb / pattern / checklist** 作为该用途的命令。

## 每个 adapter 必须声明

| Section | 提供什么 | 谁用 |
|---|---|---|
| Detection | 根标记文件 | sub-agent 自己定位 adapter |
| Verb `build` | 编译 / 类型检查命令 | `implement` |
| Verb `static-check` | lint / vet / 类型检查 | `implement` |
| Verb `format` | 自动格式化 | `implement` |
| Verb `test-verbose-race` | 跑全部测试，verbose + race-equivalent | `test-runner` |
| Verb `test-by-name` | 跑单个具名测试 | `mutation-verify` |
| Verb `doc-lookup` | 不读函数体查导出签名 | `author-invariant-tests` |
| File pattern `test-file` | 测试文件 glob | `author-invariant-tests` / `mutation-verify` |
| File pattern `source` | 非测试源码 glob | `mutation-verify` / `reviewer-quality` |
| Skip markers | 这门语言「跳过测试」的写法 | `test-runner` / `reviewer-quality` |
| Error wrapping idiom | 错误如何包裹以保留链 | `reviewer-quality` |
| Correctness checklist | 这门语言常踩的坑 | `reviewer-quality` |
| Concurrency-faithful doubles | 怎么写真并发的测试 double | `author-invariant-tests` |

## 状态

| Adapter | 状态 |
|---|---|
| `go.md` | 完整——`prd-to-ship` Trial 010 用它 |
| `python.md` | Stub——按你的项目填 |
| `rust.md` | Stub |
| `javascript.md` | Stub |

## 加一门语言

复制任意 stub 改名，把 verb / pattern / checklist 填实。Detection 标记文件要和现有的不冲突。改本文件上面的状态表。提交前在目标 repo 把每个 verb 都跑一遍验证。
