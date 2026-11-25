#!/usr/bin/env bash
# =============================================================================
# 门禁3：单元测试（含覆盖率阈值）
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# 执行：bash scripts/test.sh
#
# 后端：mvn -q -B test（JUnit 5 + @WebMvcTest + MockMvc）
# 前端：npm test（Vitest run + v8 覆盖率，行/函数/语句阈值 80%，阈值写在 package.json）
#
# 说明：两端都会执行一遍再汇总，任一失败即整体失败——不因一端先失败而跳过另一端，
#       这样失败报告能一次性给出完整的修复清单。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"

MVN="${MVN:-mvn}"
NPM="${NPM:-npm}"
FAILED=0

err() {
  echo "!! $*" >&2
  FAILED=1
}

# ---------------------------------------------------------------------------
# 后端单测
# ---------------------------------------------------------------------------
echo "==> [test] 后端：JUnit"

if [[ ! -f "$BACKEND_DIR/pom.xml" ]]; then
  err "缺少 backend/pom.xml，无法执行后端单测"
elif ! command -v "$MVN" >/dev/null 2>&1; then
  err "未检测到 $MVN 命令，无法执行后端单测。请安装 Maven 3.9+（或改用 Docker 运行测试）。"
else
  echo "[test] 执行：$MVN -q -B test"
  if ( cd "$BACKEND_DIR" && "$MVN" -q -B test ); then
    echo "[test] 后端单测通过（报告：backend/target/surefire-reports/）"
  else
    err "后端单测未通过。请查看上方 Maven 输出与 backend/target/surefire-reports/ 下的失败明细。"
  fi
fi

# ---------------------------------------------------------------------------
# 前端单测
# ---------------------------------------------------------------------------
echo "==> [test] 前端：Vitest + 覆盖率"

if [[ ! -f "$FRONTEND_DIR/package.json" ]]; then
  err "缺少 frontend/package.json，无法执行前端单测"
elif ! command -v "$NPM" >/dev/null 2>&1; then
  err "未检测到 $NPM 命令，无法执行前端单测。请安装 Node.js 20 LTS（含 npm）。"
elif [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
  err "frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM install"
else
  echo "[test] 执行：$NPM test"
  if ( cd "$FRONTEND_DIR" && "$NPM" test ); then
    echo "[test] 前端单测通过（覆盖率报告：frontend/coverage/）"
  else
    err "前端单测未通过，或覆盖率未达 80% 阈值。请查看上方 Vitest 输出。"
  fi
fi

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
if [[ "$FAILED" -ne 0 ]]; then
  echo "[test] 失败：存在未通过的单测门禁" >&2
  exit 1
fi
echo "[test] 通过"
exit 0
