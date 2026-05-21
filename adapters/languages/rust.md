# Language adapter: Rust

> STATUS: STUB —— 用到 Rust 项目前把 verb / checklist 填实。

## Detection
根标记：`Cargo.toml`。

## Verbs

| Purpose | Command（建议默认） |
|---|---|
| `build` | `cargo build --all-targets` |
| `static-check` | `cargo clippy --all-targets -- -D warnings` |
| `format` | `cargo fmt` |
| `test-verbose-race` | `cargo test -- --nocapture`（Rust safe code 无内置 race detector；unsafe / 并发重的用 `loom` crate 或 `miri`） |
| `test-by-name` | `cargo test '<TestName>' -- --nocapture --exact` |
| `doc-lookup` | `cargo doc --no-deps`（生成后看 `target/doc/<crate>/<symbol>.html`）；私有项 `cargo rustdoc -- --document-private-items` |

## File patterns
- `test-file`：`src/` 里 `#[test]` / `#[tokio::test]` 标注的 item + `tests/*.rs` 集成测试
- `source`（非测试）：`src/**/*.rs` 排除 `#[test]` / `#[cfg(test)]` 项，且排除 `tests/`

## Skip markers
- `#[ignore]`——`cargo test` 默认跳过，`--ignored` 才跑
- 测试体里早期 `return;` 短路（静态难抓，靠 test-runner 解析 SKIP 行）

## Error wrapping idiom
- 应用层：`anyhow::Context::context("...")`
- 库 API：`thiserror::Error` + `#[from]` 包裹下游错误

## Correctness checklist
（TBD——按你的项目填。建议起点：生产路径禁 `unwrap()`（用 `?` 或显式 error）；共享类型显式 `Send + Sync`；async 上下文里不阻塞。）

## Concurrency-faithful test doubles
（TBD。Async 用 per-key `tokio::sync::Mutex`；sync 用 per-key `parking_lot::Mutex`。并发关键路径要穷举 interleaving 时用 `loom` crate。）
