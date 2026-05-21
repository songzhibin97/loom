# Language adapter: Go

## Detection
根标记：`go.mod`。

## Verbs

| Purpose | Command |
|---|---|
| `build` | `go build ./...` |
| `static-check` | `go vet ./...` |
| `format` | `gofmt -w .` |
| `test-verbose-race` | `go test -v -race -count=1 ./...` |
| `test-by-name` | `go test -v -race -count=1 -run '^<TestName>$' ./...` |
| `doc-lookup` | `go doc <package>.<symbol>` |

## File patterns
- `test-file`：`*_test.go`
- `source`（非测试）：`*.go` 排除 `*_test.go`

## Skip markers
测试体内任一可达行命中即视为跳过：
- `t.Skip(...)`
- `t.SkipNow()`
- `t.Skipf(...)`
- `if testing.Short() { t.Skip(...) }` 短路

## Error wrapping idiom
用 `%w` 保留 chain：
```go
return fmt.Errorf("load user %d: %w", id, err)
```
`%v` / `%s` 破坏 `errors.Is` / `errors.As`。

## Correctness checklist
- 每个 goroutine 有退出条件：`<-ctx.Done()` / channel close / `wg.Done()`。
- `defer` 不在循环体内（在循环里 defer 会累积到函数退出才执行）。
- 错误用 `%w` 包裹（见上）。
- 分层不倒置：`data/` 不导入 `service/` / `server/`；`biz/` 声明 repo interface、`data/` 实现，不反向。
- Receiver 名一种类型用一致：`func (u *UserCase)` 全用 `u`，不要混 `u` / `uc`。
- Slice 已知长度时 `make([]T, 0, n)` 预分配；map / slice 在调用方会 range 时返回空容器，不返回 nil。
- 条件写（`UPDATE ... WHERE ...`、`DELETE ...`）必须查 `RowsAffected`——0 行不等于成功，要返回明确「未命中」结果。

## Concurrency-faithful test doubles
`[hard]` 不变量（并发/幂等）的 always-run double 必须**忠实建模并发**，不能用一把大锁把所有操作串起来。规范模式（取自 Trial 011 `txStore`）：
- 按 row / key 加锁（`lockFor(id) *sync.Mutex`），不是全局一把。
- 事务体在并行 goroutine 跑；按行锁解决冲突的方式 = 数据库行锁的方式。
- 生产 SQL 里的「条件 UPDATE」在 double 里对应：先锁行 → 查当前值 → 写。exactly-once 语义一致。
- 唯一约束在 double 里对应：lock-protected key 集合 + `errAlreadyExists`。

反模式：单个全局 `sync.Mutex` 包所有操作。它把并发串行化了，证明不了任何竞争安全。
