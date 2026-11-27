#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁5：集成 / UI 测试（必须在隔离环境内执行）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
#
# 说明：本模板暂未内置 e2e 用例。此脚本为可运行的占位实现——
#   若存在 tests/e2e/ 目录则用 Playwright 执行，否则明确跳过并返回 0。
#   注意：这里返回 0 是"未配置即跳过"的显式决策，而非"静默变绿"，
#   接入真实用例后请删除 SKIP 分支。
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="$ROOT/tests/e2e"

# 统计真实用例文件数量（排除 README 等文档占位）。
# 只看目录存在是错的：本模板 tests/e2e/ 里只有 README.md，
# 旧版据此误判"已配置 e2e"去调用 npx playwright，
# 在离线（internal 网络）环境下必然失败，掩盖真实结论（与 react-python 同款修复）。
count_specs() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -type f \( -name '*.spec.ts' -o -name '*.spec.js' \
                       -o -name '*.test.ts' -o -name '*.test.js' \) 2>/dev/null | wc -l | tr -d ' '
}

SPEC_COUNT="$(count_specs "$E2E_DIR")"
if [ "$SPEC_COUNT" = "0" ]; then
  echo "[e2e] 未发现 e2e 用例（tests/e2e/ 下无 *.spec.* / *.test.*），跳过（占位实现，非通过判定）"
  echo "[e2e] 注意：该跳过不代表功能已验证，交付前必须补齐真实用例"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "!! 未找到 npx，无法执行 Playwright e2e" >&2
  exit 1
fi

echo "==> [e2e] Playwright"
( cd "$E2E_DIR" && npx playwright test ) || { echo "[e2e] 失败：存在未通过的 e2e 用例" >&2; exit 1; }

echo "[e2e] 通过"
