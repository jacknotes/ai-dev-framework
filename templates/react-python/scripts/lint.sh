#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁1：静态检查（前端 ESLint + 后端 ruff）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# 允许调用方指定解释器（CI 里通常是 /usr/bin/env python3 或 npm）
PYTHON="${PYTHON:-python}"
NPM="${NPM:-npm}"

echo "==> [lint] 前端：ESLint"
if [ -d "$ROOT/frontend" ]; then
  if [ ! -d "$ROOT/frontend/node_modules" ]; then
    echo "!! frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM ci" >&2
    FAILED=1
  elif ! command -v "$NPM" >/dev/null 2>&1; then
    echo "!! 未找到 $NPM，无法执行前端 lint" >&2
    FAILED=1
  else
    ( cd "$ROOT/frontend" && "$NPM" run lint ) || FAILED=1
  fi
else
  echo "!! 缺少 frontend/ 目录" >&2
  FAILED=1
fi

echo "==> [lint] 后端：ruff"
if [ -d "$ROOT/backend" ]; then
  if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "!! 未找到 python，无法执行后端 lint" >&2
    FAILED=1
  elif ! "$PYTHON" -m ruff --version >/dev/null 2>&1; then
    echo "!! 未安装 ruff，请执行：$PYTHON -m pip install ruff" >&2
    FAILED=1
  else
    ( cd "$ROOT/backend" && "$PYTHON" -m ruff check . ) || FAILED=1
  fi
else
  echo "!! 缺少 backend/ 目录" >&2
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "[lint] 失败：存在未通过的静态检查项" >&2
  exit 1
fi
echo "[lint] 通过"
