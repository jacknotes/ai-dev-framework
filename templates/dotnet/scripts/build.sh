#!/usr/bin/env bash
# 门禁 2：构建
# 契约：exit 0 = 通过；exit 非 0 = 失败
# 内容：
#   1) 后端 dotnet build -c Release
#   2) 前端 npm run build（vue-tsc 类型检查 + vite build）
# 用法：bash scripts/build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[build] 模板根目录：${ROOT_DIR}"

# ---- 前置检查：工具是否安装 ----
if ! command -v dotnet >/dev/null 2>&1; then
  echo "[build] 错误：未找到 dotnet。请先安装 .NET SDK 8.0（https://dotnet.microsoft.com/download/dotnet/8.0）。" >&2
  exit 127
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[build] 错误：未找到 npm。请先安装 Node.js 20+（https://nodejs.org）。" >&2
  exit 127
fi

# ---- 1) 后端 Release 构建 ----
echo "[build] 后端：dotnet build -c Release"
dotnet build "${ROOT_DIR}/backend/DemoApi.csproj" -c Release --nologo

# ---- 2) 前端构建 ----
echo "[build] 前端：npm run build"
cd "${ROOT_DIR}/frontend"

# 契约 §2 硬性约束：脚本内不联网安装依赖，缺失则明确报错退出
if [ ! -d node_modules ]; then
  echo "[build] 错误：未找到 frontend/node_modules。请先在 setup 阶段安装依赖：" >&2
  echo "        cd frontend && npm install   # 已有 package-lock.json 时可用 npm ci" >&2
  exit 1
fi

npm run build

# ---- 3) 产物存在性校验（契约 §2：build 通过 = exit 0 且产物存在）----
echo "[build] 校验产物"
BACKEND_DLL="${ROOT_DIR}/backend/bin/Release/net8.0/DemoApi.dll"
FRONTEND_DIST="${ROOT_DIR}/frontend/dist/index.html"

if [ ! -f "${BACKEND_DLL}" ]; then
  echo "[build] 失败：未找到后端产物 ${BACKEND_DLL}" >&2
  exit 1
fi

if [ ! -f "${FRONTEND_DIST}" ]; then
  echo "[build] 失败：未找到前端产物 ${FRONTEND_DIST}" >&2
  exit 1
fi

echo "[build] 通过（产物：backend/bin/Release/net8.0/DemoApi.dll、frontend/dist/）"
exit 0
