#!/usr/bin/env bash
# =============================================================================
# 门禁5：集成 / UI 测试（E2E）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# 执行：bash scripts/e2e.sh
#
# 当前状态：**占位实现**。本模板尚未内置 e2e 用例，因此脚本只做环境自检并输出指引，
#   始终以 0 退出，保证流水线可跑通。
#   注意：这里的 exit 0 是"未配置用例即跳过"的显式决策，不代表功能已验证；
#   接入真实用例后必须删掉 SKIP 分支，改由测试结果决定退出码。
#
# 接入方式（推荐 Playwright，接入后把下方 SKIP 分支替换为真实执行）：
#   1) cd frontend && npm i -D @playwright/test && npx playwright install --with-deps
#   2) 新增 tests/e2e/greeting.spec.ts，覆盖：打开首页 → 显示 "Hello from Java backend"
#   3) 先启动隔离环境：cd deploy && docker compose up -d --build
#   4) 在下方 SKIP 分支处改为：npx playwright test
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="$ROOT_DIR/tests/e2e"
PORT="${PORT:-8000}"
URL="http://localhost:${PORT}/health"

echo "==> [e2e] 集成 / UI 测试"

# ---- SKIP 分支：未配置 e2e 用例时显式跳过 ----
if [[ ! -d "$E2E_DIR" ]]; then
  echo "[e2e] 未配置 tests/e2e/，跳过（占位实现，非通过判定）"
  echo "[e2e] 注意：该跳过不代表功能已验证，交付前必须补齐真实用例（见脚本头部接入步骤）"
  # 仅做提示性连通性自检，不影响退出码
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 3 "$URL" >/dev/null 2>&1; then
      echo "[e2e] 环境自检：后端 ${URL} 可访问，可直接接入 e2e 用例"
    else
      echo "[e2e] 环境自检：后端 ${URL} 不可访问，请先执行 'cd deploy && docker compose up -d --build'"
    fi
  else
    echo "[e2e] 环境自检：未检测到 curl，跳过连通性探测"
  fi
  echo "[e2e] 占位执行完成（exit 0）"
  exit 0
fi

# ---- 已配置用例：真实执行 ----
if ! command -v npx >/dev/null 2>&1; then
  echo "!! 未检测到 npx 命令，无法执行 e2e。请安装 Node.js 20 LTS（含 npx）。" >&2
  exit 1
fi

echo "[e2e] 执行：npx playwright test（工作目录：$E2E_DIR）"
if ! ( cd "$E2E_DIR" && npx playwright test ); then
  echo "[e2e] 失败：存在未通过的 e2e 用例" >&2
  exit 1
fi

echo "[e2e] 通过"
exit 0
