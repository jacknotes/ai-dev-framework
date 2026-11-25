#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁2：构建（前端 tsc + vite build；后端字节码编译校验）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

PYTHON="${PYTHON:-python}"
NPM="${NPM:-npm}"

echo "==> [build] 前端：tsc -b && vite build"
if [ ! -d "$ROOT/frontend" ]; then
  echo "!! 缺少 frontend/ 目录" >&2
  FAILED=1
elif [ ! -d "$ROOT/frontend/node_modules" ]; then
  echo "!! frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM ci" >&2
  FAILED=1
elif ! command -v "$NPM" >/dev/null 2>&1; then
  echo "!! 未找到 $NPM，无法执行前端构建" >&2
  FAILED=1
else
  ( cd "$ROOT/frontend" && "$NPM" run build ) || FAILED=1
fi

echo "==> [build] 后端：compileall"
if [ ! -d "$ROOT/backend" ]; then
  echo "!! 缺少 backend/ 目录" >&2
  FAILED=1
elif ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "!! 未找到 python，无法执行后端构建" >&2
  FAILED=1
else
  ( cd "$ROOT/backend" && "$PYTHON" -m compileall -q app ) || FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "[build] 失败：存在未通过的构建项" >&2
  exit 1
fi
echo "[build] 通过"
