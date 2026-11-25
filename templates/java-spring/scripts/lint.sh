#!/usr/bin/env bash
# =============================================================================
# 门禁1：静态检查 / 格式
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# 执行：bash scripts/lint.sh
#
# 后端检查顺序（按 pom.xml 中已配置的插件自动选择，不会凭空失败）：
#   1) 配了 spotless-maven-plugin  → mvn -q -B spotless:check
#   2) 配了 maven-checkstyle-plugin → mvn -q -B checkstyle:check
#   3) 都没配（本模板默认情况）    → 退化为 mvn -q -B compile -DskipTests（仅编译期检查）
# 前端：npm run lint（ESLint 9 flat config）
#
# 两端都会执行一遍再汇总，避免"前端失败就看不到后端问题"。
# 本脚本只读，不修改源码（spotless:apply / eslint --fix 需由人显式执行）。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
POM="$BACKEND_DIR/pom.xml"

MVN="${MVN:-mvn}"
NPM="${NPM:-npm}"
FAILED=0

err() {
  echo "!! $*" >&2
  FAILED=1
}

# ---------------------------------------------------------------------------
# 后端
# ---------------------------------------------------------------------------
echo "==> [lint] 后端：Maven 静态检查"

if [[ ! -d "$BACKEND_DIR" ]]; then
  err "缺少 backend/ 目录"
elif [[ ! -f "$POM" ]]; then
  err "缺少 backend/pom.xml，无法执行后端检查"
elif ! command -v "$MVN" >/dev/null 2>&1; then
  err "未检测到 $MVN 命令，无法执行后端 lint。请安装 Maven 3.9+ 并确保在 PATH 中（或改用 Docker 构建）。"
else
  if grep -q 'spotless-maven-plugin' "$POM"; then
    echo "[lint] 检测到 spotless-maven-plugin → $MVN -q -B spotless:check"
    ( cd "$BACKEND_DIR" && "$MVN" -q -B spotless:check ) \
      || err "spotless 格式检查未通过。可执行 'cd backend && mvn spotless:apply' 自动修复后重跑。"
  elif grep -q 'maven-checkstyle-plugin' "$POM"; then
    echo "[lint] 检测到 maven-checkstyle-plugin → $MVN -q -B checkstyle:check"
    ( cd "$BACKEND_DIR" && "$MVN" -q -B checkstyle:check ) \
      || err "checkstyle 检查未通过。请按上方的 checkstyle 报告修正代码风格后重跑。"
  else
    echo "[lint] 提示：backend/pom.xml 未配置 spotless / checkstyle 插件，"
    echo "[lint]       退化为编译期检查 → $MVN -q -B compile -DskipTests"
    echo "[lint]       该退化只覆盖语法与类型，不含格式校验；如需要严格格式门禁，"
    echo "[lint]       请在 backend/pom.xml 中加入 spotless-maven-plugin 后重跑本脚本。"
    ( cd "$BACKEND_DIR" && "$MVN" -q -B compile -DskipTests ) \
      || err "后端编译失败（退化模式）。请查看上方 Maven 输出。"
  fi
fi

# ---------------------------------------------------------------------------
# 前端
# ---------------------------------------------------------------------------
echo "==> [lint] 前端：ESLint"

if [[ ! -d "$FRONTEND_DIR" ]]; then
  err "缺少 frontend/ 目录"
elif [[ ! -f "$FRONTEND_DIR/package.json" ]]; then
  err "缺少 frontend/package.json，无法执行前端检查"
elif ! command -v "$NPM" >/dev/null 2>&1; then
  err "未检测到 $NPM 命令，无法执行前端 lint。请安装 Node.js 20 LTS（含 npm）。"
elif [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
  err "frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM install"
else
  ( cd "$FRONTEND_DIR" && "$NPM" run lint ) \
    || err "ESLint 报告了 error 级问题。请按上方输出修正（可先尝试 'npm run lint -- --fix'）。"
fi

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
if [[ "$FAILED" -ne 0 ]]; then
  echo "[lint] 失败：存在未通过的静态检查项" >&2
  exit 1
fi
echo "[lint] 通过"
exit 0
