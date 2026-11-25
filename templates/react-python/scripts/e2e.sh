#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁5：集成 / UI 测试（必须在隔离环境内执行）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
#
# 判定逻辑（重要）：
#   只有真正存在**用例文件**（*.spec.ts / *.test.ts / *.spec.js）才开始跑。
#   只看 tests/e2e/ 目录是否存在是错的——本模板该目录里只有 README.md，
#   旧版据此误判"已配置 e2e"并去调用 npx playwright，
#   在离线（internal 网络）环境下必然失败，掩盖了真实结论。
#
#   未配置用例时明确跳过并返回 0，但这**不代表功能已验证**，
#   交付前必须补齐真实用例（见 tests/e2e/README.md）。
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="$ROOT/tests/e2e"

# 统计真实用例文件数量（排除 README、配置文件）
count_specs() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -type f \( -name '*.spec.ts' -o -name '*.spec.js' \
                       -o -name '*.test.ts' -o -name '*.test.js' \) 2>/dev/null | wc -l | tr -d ' '
}

SPEC_COUNT="$(count_specs "$E2E_DIR")"

if [ "$SPEC_COUNT" = "0" ]; then
  echo "[e2e] 未发现 e2e 用例（tests/e2e/ 下无 *.spec.* / *.test.*），跳过"
  echo "[e2e] 注意：跳过不等于通过，不代表功能已验证"
  echo "[e2e] 交付前需补齐真实用例，参见 tests/e2e/README.md"
  exit 0
fi

echo "[e2e] 发现 $SPEC_COUNT 个用例文件"

if ! command -v npx >/dev/null 2>&1; then
  echo "!! 未找到 npx，无法执行 Playwright e2e" >&2
  exit 1
fi

# Playwright 需要可用的 baseURL；未注入则明确失败而不是静默跳过
if [ -z "${TEST_BASE_URL:-}" ]; then
  echo "!! 未设置 TEST_BASE_URL，无法确定被测目标" >&2
  echo "   隔离环境下应为 http://frontend（容器网络内服务名）" >&2
  exit 1
fi

echo "==> [e2e] Playwright（目标 ${TEST_BASE_URL}）"
if ( cd "$E2E_DIR" && npx --no-install playwright test ); then
  echo "[e2e] 通过"
  exit 0
else
  echo "[e2e] 失败：存在未通过的 e2e 用例" >&2
  exit 1
fi
