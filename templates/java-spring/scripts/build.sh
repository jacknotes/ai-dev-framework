#!/usr/bin/env bash
# =============================================================================
# 门禁2：构建
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过（且产物存在），非 0 = 失败
# 执行：bash scripts/build.sh
#
# 后端：mvn -q -B package -DskipTests  → backend/target/*.jar
# 前端：npm run build（tsc -b && vite build）→ frontend/dist/index.html
#
# 说明：构建门禁与测试门禁分离，此处跳过单测（单测走 scripts/test.sh）。
#       两端都会尝试构建再汇总；通过后会校验产物确实存在（"构建成功"不等于"有产物"）。
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
# 后端打包
# ---------------------------------------------------------------------------
echo "==> [build] 后端：Maven 打包"

if [[ ! -f "$BACKEND_DIR/pom.xml" ]]; then
  err "缺少 backend/pom.xml，无法执行后端构建"
elif ! command -v "$MVN" >/dev/null 2>&1; then
  err "未检测到 $MVN 命令，无法执行后端构建。请安装 Maven 3.9+（或改用 Docker：docker build -t java-spring-backend ./backend）。"
else
  echo "[build] 执行：$MVN -q -B package -DskipTests"
  if ( cd "$BACKEND_DIR" && "$MVN" -q -B package -DskipTests ); then
    JAR_PATH="$(ls -1 "$BACKEND_DIR"/target/*.jar 2>/dev/null | grep -v '\.original$' | head -n 1 || true)"
    if [[ -n "$JAR_PATH" ]]; then
      echo "[build] 后端产物：$JAR_PATH"
    else
      err "Maven 执行成功但 target/ 下未找到 jar 产物，构建结果不可用。"
    fi
  else
    err "后端打包失败。请查看上方 Maven 输出（常见原因：JDK 不是 21、依赖下载失败、编译错误）。"
  fi
fi

# ---------------------------------------------------------------------------
# 前端打包
# ---------------------------------------------------------------------------
echo "==> [build] 前端：Vite 打包"

if [[ ! -f "$FRONTEND_DIR/package.json" ]]; then
  err "缺少 frontend/package.json，无法执行前端构建"
elif ! command -v "$NPM" >/dev/null 2>&1; then
  err "未检测到 $NPM 命令，无法执行前端构建。请安装 Node.js 20 LTS（含 npm）。"
elif [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
  err "frontend/node_modules 不存在，请先安装依赖：cd frontend && $NPM install"
else
  echo "[build] 执行：$NPM run build"
  if ( cd "$FRONTEND_DIR" && "$NPM" run build ); then
    if [[ -f "$FRONTEND_DIR/dist/index.html" ]]; then
      echo "[build] 前端产物：$FRONTEND_DIR/dist/"
    else
      err "构建命令成功但未生成 dist/index.html，产物不可用。"
    fi
  else
    err "前端构建失败。请查看上方输出（TypeScript 类型错误或 Vite 打包错误）。"
  fi
fi

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
if [[ "$FAILED" -ne 0 ]]; then
  echo "[build] 失败：构建未全部通过或产物缺失" >&2
  exit 1
fi
echo "[build] 通过"
exit 0
