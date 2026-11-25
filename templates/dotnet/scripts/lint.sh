#!/usr/bin/env bash
# 门禁 1：静态检查（lint / 格式校验）
# 契约：exit 0 = 通过；exit 非 0 = 失败
# 内容：
#   1) 后端 dotnet format --verify-no-changes（只校验，不改代码）
#   2) 前端 npm run lint（eslint）
# 用法：bash scripts/lint.sh

set -euo pipefail

# 脚本所在目录的上一级 = 模板根目录（保证可从任意 cwd 调用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[lint] 模板根目录：${ROOT_DIR}"

# ---- 前置检查：工具是否安装 ----
if ! command -v dotnet >/dev/null 2>&1; then
  echo "[lint] 错误：未找到 dotnet。请先安装 .NET SDK 8.0（https://dotnet.microsoft.com/download/dotnet/8.0）。" >&2
  exit 127
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[lint] 错误：未找到 npm。请先安装 Node.js 20+（https://nodejs.org）。" >&2
  exit 127
fi

# ---- 1) 后端格式校验 ----
# 主工程与测试工程分别校验（两者是独立 csproj）
echo "[lint] 后端：dotnet format --verify-no-changes（主工程）"
dotnet format "${ROOT_DIR}/backend/DemoApi.csproj" --verify-no-changes --verbosity minimal

echo "[lint] 后端：dotnet format --verify-no-changes（测试工程）"
dotnet format "${ROOT_DIR}/backend/tests/DemoApi.Tests.csproj" --verify-no-changes --verbosity minimal

# ---- 2) 前端静态检查 ----
echo "[lint] 前端：npm run lint"
cd "${ROOT_DIR}/frontend"

# 契约 §2 硬性约束：脚本内不联网安装依赖，缺失则明确报错退出
if [ ! -d node_modules ]; then
  echo "[lint] 错误：未找到 frontend/node_modules。请先在 setup 阶段安装依赖：" >&2
  echo "        cd frontend && npm install   # 已有 package-lock.json 时可用 npm ci" >&2
  exit 1
fi

npm run lint

echo "[lint] 通过"
exit 0
