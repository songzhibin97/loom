#!/usr/bin/env bash
# setup-test-env.sh
#
# 一键准备一个隔离的测试环境，把 loom 接到一个空 git 项目上。
#
# 用法：
#   bash /Users/songzhibin/go/src/Songzhibin/loom/setup-test-env.sh
#   bash /Users/songzhibin/go/src/Songzhibin/loom/setup-test-env.sh ~/my-test-dir
#
# 默认目标目录：~/sw-test

set -e

TARGET="${1:-$HOME/sw-test}"
SW_HOME="$(cd "$(dirname "$0")" && pwd)"

echo "Self-workflow:   $SW_HOME"
echo "Test env target: $TARGET"
echo

# 1) 准备目录
if [[ -d "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
  echo "⚠ $TARGET 已存在且非空。"
  read -p "  清空它继续？(y/N) " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "abort."
    exit 1
  fi
  rm -rf "$TARGET"
fi
mkdir -p "$TARGET"
cd "$TARGET"

# 2) git init（slash command 的项目根 fallback 会用到）
echo "[1/5] git init"
git init -q

# 3) 装 slash command（软链，方便日后改 loom 直接生效）
echo "[2/5] symlink slash command"
mkdir -p .claude/commands
ln -sf "$SW_HOME/adapters/claude-code/commands/workflow.md" .claude/commands/workflow.md
echo "       .claude/commands/workflow.md → $SW_HOME/adapters/claude-code/commands/workflow.md"

# 4) 写一份 env 提示（用 direnv 的话 `direnv allow` 自动加载；不用也可以手动 source）
echo "[3/5] write env hint (.envrc)"
cat > .envrc <<EOF
# 启动 claude 前 source 这个文件（或手动 export 这两个变量）
export LOOM_HOME="$SW_HOME"
export LOOM_PROJECT_ROOT="$TARGET"
EOF
echo "       .envrc 已写入"

# 5) 跑 verify.sh
echo "[4/5] verify.sh lint"
if bash "$SW_HOME/verify.sh" > /tmp/sw-verify.out 2>&1; then
  echo "       ✓ verify.sh 全绿"
else
  echo "       ✗ verify.sh 失败，详情见 /tmp/sw-verify.out"
  cat /tmp/sw-verify.out
  exit 1
fi

# 6) 起一个最小可被 implement skill 玩的 hello world 项目骨架
echo "[5/5] seed a tiny project skeleton"
cat > README.md <<'EOF'
# sw-test

A throwaway project to smoke-test loom's prd-to-ship workflow.
EOF
cat > hello.py <<'EOF'
def main():
    print("hello world")

if __name__ == "__main__":
    main()
EOF
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "init"

echo
echo "================================================================="
echo "✓ 环境就绪。"
echo
echo "下一步："
echo "  cd $TARGET"
echo "  source .envrc                      # 或手动 export 那两个变量"
echo "  claude                             # 启动 Claude Code"
echo
echo "进了会话后，把这一行粘进去："
echo
echo '  /workflow run prd-to-ship "做一个 hello world CLI 工具"'
echo
echo "完整测试步骤 + 里程碑 + 报告模板见："
echo "  $SW_HOME/TEST.md"
