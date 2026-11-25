#!/usr/bin/env bash
# 门禁 3：单元测试（含前端覆盖率门槛 80%）
# 契约：exit 0 = 通过；exit 非 0 = 失败
# 内容：
#   1) 后端 dotnet test（xUnit + WebApplicationFactory）
#   2) 前端 npm test（vitest run --coverage）
# 用法：bash scripts/test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[test] 模板根目录：${ROOT_DIR}"

# ---- 前置检查：工具是否安装 ----
if ! command -v dotnet >/dev/null 2>&1; then
  echo "[test] 错误：未找到 dotnet。请先安装 .NET SDK 8.0（https://dotnet.microsoft.com/download/dotnet/8.0）。" >&2
  exit 127
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[test] 错误：未找到 npm。请先安装 Node.js 20+（https://nodejs.org）。" >&2
  exit 127
fi

# ---- 1) 后端单测 ----
echo "[test] 后端：dotnet test"
dotnet test "${ROOT_DIR}/backend/tests/DemoApi.Tests.csproj" \
  -c Release \
  --nologo \
  --logger "console;verbosity=normal"

# ---- 2) 前端单测（覆盖率门槛已内置在 package.json 的 test 脚本）----
echo "[test] 前端：npm test"
cd "${ROOT_DIR}/frontend"

# 契约 §2 硬性约束：脚本内不联网安装依赖，缺失则明确报错退出
if [ ! -d node_modules ]; then
  echo "[test] 错误：未找到 frontend/node_modules。请先在 setup 阶段安装依赖：" >&2
  echo "       cd frontend && npm install   # 已有 package-lock.json 时可用 npm ci" >&2
  exit 1
fi

npm test

echo "[test] 通过"
exit 0
