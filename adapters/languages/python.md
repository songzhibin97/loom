# Language adapter: Python

> STATUS: STUB —— 用到 Python 项目前把 verb / checklist 填实。

## Detection
根标记：`pyproject.toml` / `setup.py` / `requirements.txt`。

## Verbs

| Purpose | Command（建议默认） |
|---|---|
| `build` | Python 动态——用 `python -m compileall <pkg>` 或 `mypy <pkg>` 作 "build" 门 |
| `static-check` | `ruff check .` 和/或 `mypy .` |
| `format` | `ruff format .`（或 `black .`） |
| `test-verbose-race` | `pytest -v`（无原生 race detector；race-敏感的用 `pytest-randomly` + `pytest-repeat -k <test> --count=20`） |
| `test-by-name` | `pytest -v -k '<TestName>'` |
| `doc-lookup` | `python -c "import <pkg>; help(<pkg>.<symbol>)"` |

## File patterns
- `test-file`：`test_*.py` 或 `*_test.py`（pytest 默认）
- `source`（非测试）：`*.py` 排除上面的测试文件

## Skip markers
- `@pytest.mark.skip(...)`、`@pytest.mark.skipif(...)`、`pytest.skip(...)`
- `@unittest.skip(...)`、`self.skipTest(...)`
- `@pytest.mark.xfail`（视作 skip 处理——预期失败也是没真验）

## Error wrapping idiom
`raise NewError("...") from original_err`——保留 `__cause__` 链。

## Correctness checklist
（TBD——按你的项目填。建议起点：公共函数必有 type hint；禁止 bare `except`；资源管理用 `with`；不可变默认参数；value type 用 `dataclass(frozen=True)`。）

## Concurrency-faithful test doubles
（TBD。Python 受 GIL，「真并发」多是线程；用 per-key `threading.Lock()` + `concurrent.futures.ThreadPoolExecutor(max_workers=N)`。asyncio 代码用 per-key `asyncio.Lock()` + `asyncio.gather`。）
