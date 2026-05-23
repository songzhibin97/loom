# Language adapter: JavaScript / TypeScript

> STATUS: STUB —— 用到 JS/TS 项目前把 verb / checklist 填实。

## Detection
根标记：`package.json`。

## Verbs

| Purpose | Command（建议默认） |
|---|---|
| `build` | `npm run build`（或 TS-only 类型检查 `tsc --noEmit`） |
| `static-check` | `npm run lint`（eslint）+ `tsc --noEmit` |
| `format` | `npm run format`（prettier） |
| `test-verbose-race` | `npm test -- --reporter=verbose`（Node 无 race detector；async race-敏感的用 `--detectOpenHandles` + 重复跑） |
| `test-by-name` | `npm test -- --testNamePattern='<TestName>'`（Jest）或 `--grep '<TestName>'`（Mocha） |
| `doc-lookup` | TypeScript：`tsc --emitDeclarationOnly` 看 `.d.ts`；JS：读 export 上方的 JSDoc |

## File patterns
- `test-file`：`*.test.{js,ts,jsx,tsx}` / `*.spec.{js,ts,jsx,tsx}` / `__tests__/*.{js,ts}`
- `source`（非测试）：`src/**/*.{js,ts,jsx,tsx}` 排除上面

## Skip markers
- `it.skip(...)`、`xit(...)`、`describe.skip(...)`、`xdescribe(...)`
- `test.skip(...)`、`test.only(...)`（`only` 也值得注意——它让其它测试根本没跑）

## Error wrapping idiom
`throw new Error('...', { cause: originalErr })`（ES2022）——通过 `err.cause` 链可查。

## Correctness checklist
（TBD——按你的项目填。建议起点：每个 Promise 都 `await`，不要 floating；显式 `Error` 类型不抛字符串；`any` 必须有理由；strict null checks 开。）

## Concurrency-faithful test doubles
（TBD。JS 单线程，「并发」= async 交错。用真 `async/await` + per-key Promise 队列保序；除非显式测 timer 否则不要 mock timer。）
