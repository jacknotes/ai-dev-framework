#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁3：单元测试（前端 Vitest 覆盖率 80%；后端 go test）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

GO="${GO:-go}"
NPM="${NPM:-npm}"

echo "==> [test] 前端：vitest run（覆盖率门槛 80%）"
if [ ! -d "$ROOT/frontend" ]; then
  echo "!! 缺少 frontend/ 目录" >&2
  FAILED=1
elif [ ! -d "$ROOT/frontend/node_modules" ]; then
  echo "!! frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM ci" >&2
  FAILED=1
elif ! command -v "$NPM" >/dev/null 2>&1; then
  echo "!! 未找到 $NPM，无法执行前端测试" >&2
  FAILED=1
else
  ( cd "$ROOT/frontend" && "$NPM" test ) || FAILED=1
fi

echo "==> [test] 后端：go test"
if [ ! -d "$ROOT/backend" ]; then
  echo "!! 缺少 backend/ 目录" >&2
  FAILED=1
elif ! command -v "$GO" >/dev/null 2>&1; then
  echo "!! 未找到 go，无法执行后端测试" >&2
  FAILED=1
else
  ( cd "$ROOT/backend" && "$GO" test ./... -cover ) || FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "[test] 失败：存在未通过的单元测试" >&2
  exit 1
fi
echo "[test] 通过"
