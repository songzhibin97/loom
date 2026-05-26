# Language adapter: JavaScript / TypeScript

## Detection
根标记：`package.json`。
包管理器二级判定（影响 verb 命令前缀）：
- `pnpm-lock.yaml` → `pnpm`
- `yarn.lock` → `yarn`
- `bun.lockb` → `bun`
- 否则 → `npm`

下面命令以 `npm` 为例；其它包管理器把 `npm run X` 替换成 `pnpm X` / `yarn X` / `bun run X`。

## Verbs

| Purpose | Command |
|---|---|
| `build` | `npm run build`（TS-only 项目可仅跑 `tsc --noEmit` 作为类型检查） |
| `static-check` | `npm run lint` + `tsc --noEmit`（两条都跑；其中 `tsc --noEmit` 必跑，eslint 缺失只警告） |
| `format` | `npm run format`（prettier）或 `npm run lint -- --fix` |
| `test-verbose-race` | `npm test -- --reporter=verbose`（Vitest / Jest）；Node 单线程无 race detector，**异步竞争**用重复跑触发：Vitest `--repeats 10` / Jest 循环执行 `for i in 1..10; do npm test ...; done`，任一次红即记为失败 |
| `test-by-name` | Jest：`npx jest -t '<TestName>'`；Vitest：`npx vitest run -t '<TestName>'`；Mocha：`npx mocha --grep '<TestName>'`；Node test runner：`node --test --test-name-pattern='<TestName>'` |
| `doc-lookup` | TypeScript：先看导出符号上方 TSDoc/JSDoc；找不到时 `tsc --emitDeclarationOnly -p .` 生成 `.d.ts` 看签名；JS：直接读 export 上方 JSDoc |

## File patterns

- `test-file`：`*.test.{js,jsx,ts,tsx,mjs,cjs}` / `*.spec.{js,jsx,ts,tsx,mjs,cjs}` / `**/__tests__/**/*.{js,ts,jsx,tsx}` / `e2e/**/*.{spec,test}.{js,ts}`
- `source`（非测试）：`{src,app,lib,components,pages,routes,hooks,utils}/**/*.{js,jsx,ts,tsx,mjs}` 排除上面的 test 模式与 `**/*.d.ts`

## Skip markers
测试体内任一可达行命中即视为跳过/没真跑：

- 跳过：`it.skip(...)` / `xit(...)` / `test.skip(...)` / `describe.skip(...)` / `xdescribe(...)`
- 待办（不算跳过但也没跑）：`it.todo(...)` / `test.todo(...)`
- 排他（让别的全没跑）：`it.only(...)` / `fit(...)` / `describe.only(...)` / `fdescribe(...)` —— **always-run 套件里出现 `.only` 同样视为不合格**，它让其它 case 静默没跑
- 框架级跳过：`this.skip()`（Mocha context）、Playwright `test.fixme(...)` / `test.skip(condition, ...)`

## Error wrapping idiom
用 ES2022 `cause` 链：

```js
throw new Error('load user ' + id + ' failed', { cause: originalErr })
```

- 抛字符串（`throw 'oops'`）破坏 `instanceof Error` 与 stack——禁止。
- async function 内 `try { await ... } catch (e) { throw new Error('...', { cause: e }) }`。
- 不要吞错（空 catch / `.catch(() => {})`），至少 log + rethrow 或 log + 显式 fallback。

## Correctness checklist

- **每个 Promise 都被消费**：要么 `await`，要么 `return`，要么进入 `.then()` 链，要么显式 `void promise`（少数场景）。floating promise（未被消费的 async 调用）会让错误丢失、tests 提前结束。eslint 规则 `no-floating-promises` 应开。
- **async function 不返回 `void`**：声明 `Promise<void>` 才显式。例外：事件处理器（`onClick={async () => ...}`）必须吞错或 wrap 在 catch 里。
- **`try/catch` 必须真做点啥**：log / rethrow / 转换为业务错误。空 catch、`catch (e) { /* ignore */ }`、`.catch(() => undefined)` 都是反模式。
- **不要混用 `.then()` 链和 `await`**：一个函数体内任选一种保持一致。混用会让 try/catch 范围难以推理。
- **TypeScript `strict` 必须开**：`strict: true` 含 `strictNullChecks` + `noImplicitAny`。`ts-ignore` / `ts-expect-error` 必须带注释解释为什么。
- **`any` 是 escape hatch，要带理由注释**。`unknown` 优先于 `any`。
- **导出类型用 named export，不用 default export**：默认导出在 IDE 重命名时不会跟着改。

### React 专项（写代码时注意；review 阶段更细见 reviewer-quality）

- **`useEffect` 依赖数组完整**：闭包里引用的所有外部变量都要进数组。eslint `react-hooks/exhaustive-deps` 必须开。
- **`useEffect` cleanup 必须有**：订阅 / 定时器 / AbortController / event listener 都要在 cleanup 里释放。否则组件卸载后 setState 报警告或泄漏。
- **不要在 render 函数里 await**：组件函数体是同步的；异步加载用 `useEffect` + state 或 React Suspense。
- **`key` prop 用稳定 ID**：列表 key 不要用 array index（除非列表绝不重排），否则 React diff 会复用错节点。
- **`useCallback` / `useMemo` 只在真有 referential equality 需求时用**：滥用会增加心智负担且 dep 数组错了反而出 bug。
- **状态更新基于上一次值用回调形式**：`setN(n => n + 1)` 而非 `setN(n + 1)`，避免批处理时读到旧值。

## Concurrency-faithful test doubles

JS 单线程，没有数据竞争意义上的 race，但有**异步交错**：多个 async 操作的微任务调度顺序会暴露逻辑错。`[hard]` 不变量（并发/幂等）的 always-run double 必须**真异步**，不能用一个全局 `await` 把所有操作串起来。

规范模式：

- **真并行 fan-out**：`await Promise.all([fn(a), fn(b), fn(c)])`、`Promise.allSettled([...])`。N 个 task 用 `Array.from({length: N}, (_, i) => fn(i))` 然后 `Promise.all`。
- **每 key 串行、跨 key 并行**：共享状态的 double 用 `Map<key, Promise>` 实现"每 key 一个 promise queue"——同 key 写串起来、不同 key 真并行。这对应数据库行锁语义：

  ```js
  class KeyLockedStore {
    #queues = new Map()
    async run(key, fn) {
      const prev = this.#queues.get(key) ?? Promise.resolve()
      const next = prev.then(fn, fn)  // 不管前一个成败都跑后一个
      this.#queues.set(key, next.catch(() => {}))
      return next
    }
  }
  ```

- **唯一约束 / 幂等**：double 里用 lock-protected key set + 抛 `AlreadyExistsError`。多次同 key 写只第一个生效，其它都收到那个具体类型化错误（断言 `instanceof AlreadyExistsError`）。
- **微任务调度搅拌**：测试里在并行 task 间插入 `await new Promise(r => setTimeout(r, 0))` 或 `await Promise.resolve()` 强制让出，扩大 race window。Vitest / Jest 提供 `vi.advanceTimersByTimeAsync` / `jest.advanceTimersByTimeAsync` 配合 fake timers 也行——但只在显式测 timer 时用 fake timer。
- **AbortController 测取消**：异步操作的取消用真 `AbortController` + `signal.aborted` 检查，不要 mock。

反模式：
- 全局 `mutex.lock(() => fn())` 把所有操作串行化——证明不了任何"并发安全"。
- mock `fetch` 但所有 mock 都同步 resolve——所有请求秒回，没有任何交错窗口。
- 用 `setTimeout(resolve, 0)` 假装"测了并发"——实际只测了同步执行 + 一次 yield。
- `it.only(...)` / `describe.only(...)` 在 always-run 套件里——让其它测试静默没跑。
