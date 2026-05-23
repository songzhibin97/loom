#!/usr/bin/env bash
# verify.sh — loom smoke test
#
# Validates: directory layout, slash command frontmatter, workflow YAML
# structure (states / skills / transitions resolve), SKILL.md frontmatter,
# max_attempts semantics consistency across docs, no invented Codex flags.
#
# Requires: python3 + PyYAML.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ERR=0
fail() { echo "  ✗ $*"; ERR=1; }
ok()   { echo "  ✓ $*"; }
hdr()  { echo; echo "── $* ──"; }

# ─────────────────────────────────────────────────────────────────────────────
hdr "1. Directory layout"

for d in orchestrator examples examples/workflows examples/skills spec docs adapters/claude-code/commands adapters/languages; do
  if [[ -d "$d" ]]; then ok "$d/"; else fail "missing dir: $d/"; fi
done

for f in orchestrator/meta-agent.md \
         spec/skill.md spec/workflow.md \
         adapters/claude-code/commands/workflow.md \
         adapters/languages/README.md adapters/languages/go.md \
         examples/README.md \
         README.md; do
  if [[ -f "$f" ]]; then ok "$f"; else fail "missing file: $f"; fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "2. Slash command frontmatter"

cmd=adapters/claude-code/commands/workflow.md
if grep -qE '^allowed-tools:.*\bTask\b' "$cmd"; then
  ok "$cmd lists Task in allowed-tools"
else
  fail "$cmd missing 'Task' in allowed-tools"
fi
if grep -qE '^allowed-tools:.*\bAgent\b' "$cmd"; then
  fail "$cmd still references 'Agent' (correct tool is 'Task')"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "3. Every workflow YAML — structure + references resolve"

python3 - <<'PYEOF' || ERR=$?
import sys, os, yaml, pathlib

RESERVED = {"_abort", "_resume_after_manual"}
errs = []
skill_dir = pathlib.Path("examples/skills")

for wf_path in sorted(pathlib.Path("examples/workflows").glob("*.yaml")):
    print(f"  · {wf_path}")
    try:
        with open(wf_path) as f:
            wf = yaml.safe_load(f)
    except yaml.YAMLError as e:
        errs.append(f"{wf_path}: YAML parse error: {e}")
        continue

    if not isinstance(wf, dict):
        errs.append(f"{wf_path}: top-level isn't a mapping")
        continue

    for k in ("name", "version", "start", "states"):
        if k not in wf:
            errs.append(f"{wf_path}: missing top-level '{k}'")

    states = wf.get("states") or {}
    if not isinstance(states, dict):
        errs.append(f"{wf_path}: 'states' isn't a mapping")
        continue

    declared = set(states.keys())

    # start must point at a real state
    if wf.get("start") not in declared:
        errs.append(f"{wf_path}: start='{wf.get('start')}' isn't a declared state")

    # collect skill references
    referenced_skills = set()
    referenced_states = set()

    for sname, sdef in states.items():
        if not isinstance(sdef, dict):
            errs.append(f"{wf_path}: state '{sname}' value isn't a mapping")
            continue
        kind = sdef.get("kind")
        if kind not in {"skill", "gate", "parallel", "decide", "human", "terminal"}:
            errs.append(f"{wf_path}: state '{sname}' has invalid kind='{kind}'")

        # outgoing edges
        for edge_key in ("on_pass", "on_fail", "on_exceed"):
            if edge_key in sdef:
                referenced_states.add(sdef[edge_key])
        if "routes" in sdef and isinstance(sdef["routes"], dict):
            referenced_states.update(sdef["routes"].values())

        # max_attempts hygiene
        if "on_fail" in sdef:
            if "max_attempts" not in sdef:
                errs.append(f"{wf_path}:{sname}: has on_fail but no max_attempts")
            if "on_exceed" not in sdef:
                errs.append(f"{wf_path}:{sname}: has on_fail but no on_exceed")

        # skill references
        if kind == "skill" and "skill" in sdef:
            referenced_skills.add(sdef["skill"])
        if kind == "parallel":
            for item in sdef.get("fan_out", []):
                if isinstance(item, dict) and "skill" in item:
                    referenced_skills.add(item["skill"])
            if "aggregator" in sdef:
                referenced_skills.add(sdef["aggregator"])

    # verify state references
    for s in referenced_states:
        if s in RESERVED or s in declared:
            continue
        errs.append(f"{wf_path}: state '{s}' is referenced but not declared")

    # verify skill references
    for s in referenced_skills:
        if not (skill_dir / s / "SKILL.md").exists():
            errs.append(f"{wf_path}: skill '{s}' is referenced but examples/skills/{s}/SKILL.md doesn't exist")

if errs:
    for e in errs:
        print(f"  ✗ {e}")
    sys.exit(1)
else:
    print("  ✓ all workflow YAMLs OK")
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
hdr "4. Every SKILL.md — frontmatter"

python3 - <<'PYEOF' || ERR=$?
import sys, pathlib, yaml

errs = []
required = {"name", "description", "inputs", "outputs", "success_criteria"}

for sk in sorted(pathlib.Path("examples/skills").glob("*/SKILL.md")):
    text = sk.read_text()
    if not text.startswith("---\n"):
        errs.append(f"{sk}: no frontmatter")
        continue
    end = text.find("\n---\n", 4)
    if end == -1:
        errs.append(f"{sk}: frontmatter not terminated")
        continue
    fm_text = text[4:end]
    try:
        fm = yaml.safe_load(fm_text)
    except yaml.YAMLError as e:
        errs.append(f"{sk}: frontmatter YAML error: {e}")
        continue
    if not isinstance(fm, dict):
        errs.append(f"{sk}: frontmatter isn't a mapping")
        continue

    missing = required - set(fm.keys())
    if missing:
        errs.append(f"{sk}: frontmatter missing {sorted(missing)}")

    # name must equal directory
    if fm.get("name") != sk.parent.name:
        errs.append(f"{sk}: name='{fm.get('name')}' != dir='{sk.parent.name}'")

    # inputs/outputs must be lists of mappings with name + path
    for field in ("inputs", "outputs"):
        items = fm.get(field) or []
        if not isinstance(items, list):
            errs.append(f"{sk}: {field} isn't a list")
            continue
        for i, item in enumerate(items):
            if not isinstance(item, dict):
                errs.append(f"{sk}: {field}[{i}] isn't a mapping")
                continue
            if "name" not in item:
                errs.append(f"{sk}: {field}[{i}] missing 'name'")
            if "path" not in item:
                errs.append(f"{sk}: {field}[{i}] missing 'path' (use 'path:', not 'from:')")
            elif str(item["path"]).startswith("/"):
                errs.append(f"{sk}: {field}[{i}] path is absolute; must be relative to run_dir")

if errs:
    for e in errs:
        print(f"  ✗ {e}")
    sys.exit(1)
else:
    print("  ✓ all SKILL.md OK")
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
hdr "5. max_attempts semantics consistency across docs"

# Forbid the legacy strict-greater phrasing. Backticks/code-quoting around max_attempts is fine.
for f in spec/workflow.md docs/architecture.md orchestrator/meta-agent.md; do
  if grep -qE 'counter[[:space:]>`]*[[:space:]]>[[:space:]]*`?max_attempts' "$f" 2>/dev/null; then
    # Looks like ">" not ">="
    if grep -qE 'counter[[:space:]>`]*[[:space:]]>=' "$f"; then : # >= is fine
    else
      fail "$f uses 'counter > max_attempts' (legacy); should be '≥'"
      continue
    fi
  fi
  # Check that the file actually discusses the semantics
  if grep -qE '(≥|>=)[[:space:]]*`?max_attempts' "$f"; then
    ok "$f uses ≥ semantics"
  elif grep -qE 'max_attempts.*第.*次.*on_exceed|达到[[:space:]]*max_attempts' "$f"; then
    ok "$f describes semantics correctly (达到/第N次)"
  else
    fail "$f doesn't state counter ≥ max_attempts semantics explicitly"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "6a. Reviewer / aggregator templates use plain 'VERDICT:' line, not '## VERDICT:'"

# Orchestrator regex is `^VERDICT: (pass|fail)$`. Any reviewer / aggregator
# template that puts `##` in front of VERDICT will not match → first run hits it.
# Note: use here-string (not pipe) so fail() updates ERR in current shell.
for sk in examples/skills/reviewer-*/SKILL.md examples/skills/review-aggregator/SKILL.md examples/skills/mutation-verify/SKILL.md; do
  matches=$(grep -nE '^(#+|>|-)[[:space:]]+VERDICT:[[:space:]]*(pass|fail)' "$sk" || true)
  if [[ -n "$matches" ]]; then
    while IFS= read -r l; do
      fail "$sk:$l (VERDICT line has markdown prefix; orchestrator regex won't match)"
    done <<< "$matches"
  else
    ok "$sk VERDICT lines clean"
  fi
done

hdr "6b. No legacy 'from:' in workflow YAMLs or spec examples"

python3 - <<'PYEOF' || ERR=$?
import sys, pathlib, yaml, re

errs = []

# (1) Walk workflow YAMLs structurally.
for wf_path in sorted(pathlib.Path("examples/workflows").glob("*.yaml")):
    try:
        wf = yaml.safe_load(wf_path.read_text())
    except yaml.YAMLError:
        continue
    def walk(obj, path=""):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "from":
                    errs.append(f"{wf_path}{path}: uses 'from:' (should be 'path:')")
                walk(v, f"{path}.{k}")
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                walk(v, f"{path}[{i}]")
    walk(wf)

# (2) Also scan spec/workflow.md example snippets for 'name: ..., from: ...'.
spec = pathlib.Path("spec/workflow.md").read_text()
for m in re.finditer(r"\bname:\s*\w+,\s*from:\s*\S+", spec):
    errs.append(f"spec/workflow.md example still uses 'from:' near: {m.group(0)!r}")

if errs:
    for e in errs:
        print(f"  ✗ {e}")
    sys.exit(1)
else:
    print("  ✓ all workflow YAMLs and spec examples use 'path:'")
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
hdr "7. No invented Codex flags in committed docs"

# Restrict scan: only flag occurrences in active docs (README, docs/, adapters/codex/)
SEARCH_PATHS=(README.md docs adapters/codex)
hits=$(grep -rEn 'codex[[:space:]]+--(system|input)\b' "${SEARCH_PATHS[@]}" 2>/dev/null || true)
if [[ -n "$hits" ]]; then
  echo "$hits" | while read l; do fail "$l"; done
else
  ok "no invented Codex flags"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "8. Architecture doc uses 'routes:' (not legacy 'on_approve' etc)"

if grep -nE '^\s*on_(approve|revise|back|abort):' docs/architecture.md > /dev/null; then
  matches=$(grep -nE '^\s*on_(approve|revise|back|abort):' docs/architecture.md)
  while IFS= read -r l; do
    fail "docs/architecture.md:$l (use 'routes: { approve: ... }', not 'on_approve:')"
  done <<< "$matches"
else
  ok "docs/architecture.md uses routes: throughout"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "9. Every SKILL.md has a JSON output contract block in body"

python3 - <<'PYEOF' || ERR=$?
import sys, pathlib, re
errs = []
for sk in sorted(pathlib.Path("examples/skills").glob("*/SKILL.md")):
    text = sk.read_text()
    # Strip frontmatter
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        body = text[end+5:] if end >= 0 else text
    else:
        body = text
    # Must mention outputs_written AND self_check in a JSON-like context
    has_outputs = "outputs_written" in body
    has_selfcheck = "self_check" in body
    has_json_fence = "```json" in body
    if not (has_outputs and has_selfcheck and has_json_fence):
        missing = []
        if not has_outputs: missing.append("'outputs_written'")
        if not has_selfcheck: missing.append("'self_check'")
        if not has_json_fence: missing.append("```json fence")
        errs.append(f"{sk}: body missing JSON output contract ({', '.join(missing)})")
if errs:
    for e in errs: print(f"  ✗ {e}")
    sys.exit(1)
else:
    print("  ✓ all SKILL.md bodies have JSON output contract")
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
hdr "10. Meta-agent has key behavioral sections"

for section in \
  "State.json 持久化" \
  "pending_gate 字段语义" \
  "edge_counters key 格式" \
  "history 行 schema" \
  "Gate 反复打回" \
  "PROJECT_ROOT"; do
  if grep -qF "$section" orchestrator/meta-agent.md; then
    ok "meta-agent.md has section: $section"
  else
    fail "meta-agent.md missing section: $section"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "11. Reserved state names special-cased in main loop pseudocode"

if grep -qE 'cur\s*==\s*"_abort"' orchestrator/meta-agent.md && \
   grep -qE 'cur\s*==\s*"_resume_after_manual"' orchestrator/meta-agent.md; then
  ok "main loop special-cases reserved state names before workflow.states lookup"
else
  fail "main loop must special-case _abort and _resume_after_manual before workflow.states lookup (would KeyError otherwise)"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "12. Workflows don't use model_hint: vendor:* (Claude Code can't honor)"

# Warn (not fail). vendor:* only works in Codex (TBD). We just want to surface it.
matches=$(grep -nE "model_hint:\s*vendor:" examples/workflows/*.yaml 2>/dev/null || true)
if [[ -n "$matches" ]]; then
  echo "  ⚠ vendor:* model_hint found (no-op in current Claude Code adapter):"
  while IFS= read -r l; do echo "    $l"; done <<< "$matches"
else
  ok "no vendor:* model_hint declarations"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "13. prd-to-ship.yaml contains the invariant-flow states"

for state in author_tests run_invariant_tests mutation_verify; do
  if grep -qE "^[[:space:]]+${state}:" examples/workflows/prd-to-ship.yaml; then
    ok "prd-to-ship has state: $state"
  else
    fail "prd-to-ship missing state: $state"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "14. Key skills carry execution-based interception rules in body"

# implement must say it does NOT write tests (contract tests live in author-invariant-tests)
if grep -qE "不写测试|不写任何测试文件|契约测试由独立" examples/skills/implement/SKILL.md; then
  ok "implement/SKILL.md carries the 'no tests' rule"
else
  fail "implement/SKILL.md should state implement does not write tests"
fi

# author-invariant-tests must say it does NOT read implementation source
if grep -qE "不读实现|不读.*函数体|没有看过实现|不许去看" examples/skills/author-invariant-tests/SKILL.md; then
  ok "author-invariant-tests/SKILL.md carries the 'do not read implementation' rule"
else
  fail "author-invariant-tests/SKILL.md should state it does not read implementation source"
fi

# mutation-verify must restore the tree (cp/backup pattern, not git checkout)
if grep -qE "还原|restore|mutbak" examples/skills/mutation-verify/SKILL.md; then
  ok "mutation-verify/SKILL.md carries the restore-tree rule"
else
  fail "mutation-verify/SKILL.md should describe how it restores the tree after each mutation"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo
if [[ $ERR -eq 0 ]]; then
  echo "✓ All checks passed."
else
  echo "✗ One or more checks failed."
fi
exit $ERR
