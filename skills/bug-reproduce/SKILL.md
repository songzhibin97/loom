---
name: bug-reproduce
description: 写一个能稳定复现 bug 的失败测试
inputs:
  - { name: diagnosis, path: artifacts/diagnosis.md }
  - { name: feedback,  path: artifacts/repro_feedback.md, required: false }
outputs:
  - { name: repro_test, path: artifacts/repro_test.md }
  - { name: repro_diff, path: artifacts/repro_diff.patch }
success_criteria:
  - "新增了一个测试用例，运行时**失败**（这就是复现成功）"
  - "失败信息和 issue 描述的现象一致"
  - "repro_test.md 含运行命令和失败输出"
retry_policy:
  max_attempts: 3
model_hint: strong
tools: [Read, Write, Edit, Bash]
---

你是 bug 复现 agent。

## 任务
基于 diagnosis 写一个测试，**让它失败**，证明 bug 真实存在。

## 步骤
1. 找到合适的测试文件位置（已有还是新建）。
2. 写测试。**测试运行后必须失败**——这是"复现成功"的定义。
3. 跑测试 (`pytest <file>::<test>` 之类的)。
4. 把命令 + 失败输出 + 推断写到 `{{repro_test}}`。
5. 生成只含这个测试改动的 diff：`git diff -- tests/ > {{repro_diff}}`。

## 输出
```
# Repro Test

## 文件
tests/test_export.py

## 测试代码
\`\`\`python
def test_export_empty_list():
    """复现 #1234：空 list 导出 panic"""
    assert ExportCSV([]) == ""  # 当前会 panic
\`\`\`

## 运行
\`\`\`
$ pytest tests/test_export.py::test_export_empty_list -v
FAILED ...
panic: runtime error: index out of range
\`\`\`

## 推断对应
失败信息匹配 issue 里的 "index out of range"。复现成功。
```

最后输出 JSON 块（独占一段，```json ... ```围起来）：

```json
{ "outputs_written": ["<absolute path>", ...],
  "self_check": [
    { "criterion": "<copy from frontmatter>", "satisfied": true, "evidence": "<具体引用>" }
  ],
  "notes": "<one line>" }
```