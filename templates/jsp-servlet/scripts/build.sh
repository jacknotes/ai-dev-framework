#!/usr/bin/env bash
# ============================================================================
# 门禁 2：构建（build）
#
# 框架统一命令契约（docs/04-门禁与命令契约.md §2 / docs/03 §2.3）：
#   exit 0  = 构建成功
#   exit ≠0 = 构建失败，退回编码环节
#
# 本脚本做什么：
#   1. 调 mvn package -DskipTests 打出 war（产物名固定 ROOT.war，见 pom 的 finalName）
#   2. 校验产物真实存在，且必要文件在包内
#   3. 校验 jakarta.servlet-api **没有**被打进 war（作用域必须是 provided）
#
# 为什么第 3 步值得单独校验：
#   如果把 Servlet API 打进 WEB-INF/lib，容器启动时会与 Tomcat 自带的实现冲突，
#   常见表现是启动正常但请求 500 / LinkageError，且日志晦涩。编译期无法发现，
#   只能在产物层面拦。这是 JSP 项目高频事故点。
#
# 用法：
#   bash scripts/build.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"
POM_FILE="${BACKEND_DIR}/pom.xml"
WAR_FILE="${BACKEND_DIR}/target/ROOT.war"

log_info() { printf '[build] %s\n' "$*"; }
log_err()  { printf '[build][错误] %s\n' "$*" >&2; }
log_warn() { printf '[build][警告] %s\n' "$*" >&2; }

# ---------- 前置检查 ----------
if [[ ! -f "${POM_FILE}" ]]; then
    log_err "未找到 ${POM_FILE}，请确认脚本位于模板的 scripts/ 目录下。"
    exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
    log_err "未找到 mvn（Maven）。"
    log_err "请安装 Maven 3.9+（需 JDK 17：java -version 应显示 17.x）后重试。"
    log_err "或改用 Docker 构建：docker build -t jsp-servlet-demo backend"
    exit 1
fi

# ---------- 构建 ----------
log_info "开始构建：mvn -q -B clean package -DskipTests"

if ! ( cd "${BACKEND_DIR}" && mvn -q -B clean package -DskipTests ); then
    log_err "Maven 构建失败，请查看上方输出定位原因（常见原因见 docs/runbook.md §3.4）。"
    exit 1
fi

# ---------- 产物校验 ----------
if [[ ! -f "${WAR_FILE}" ]]; then
    log_err "构建命令成功但未找到产物：${WAR_FILE}"
    log_err "请检查 pom.xml 的 <finalName> 是否为 ROOT。"
    exit 1
fi

log_info "产物已生成：${WAR_FILE}"

WAR_SIZE="$(wc -c < "${WAR_FILE}" | tr -d ' ')"
log_info "产物大小：${WAR_SIZE} 字节"

if [[ "${WAR_SIZE}" -lt 1000 ]]; then
    log_err "产物大小异常（< 1KB），疑似空包。请检查 src/main/webapp 是否被正确打包。"
    exit 1
fi

# 必要文件检查（index.jsp / WEB-INF/web.xml）
if command -v unzip >/dev/null 2>&1; then
    MISSING=0
    for entry in "index.jsp" "WEB-INF/web.xml"; do
        if unzip -l "${WAR_FILE}" | grep -q "${entry}"; then
            log_info "包内包含：${entry}"
        else
            log_err "包内缺失：${entry}"
            MISSING=1
        fi
    done
    if [[ "${MISSING}" -ne 0 ]]; then
        log_err "war 结构不完整，部署后必然 404，已判失败。"
        exit 1
    fi

    # Servlet API 绝不能出现在产物中（应为 provided）
    if unzip -l "${WAR_FILE}" | grep -q 'WEB-INF/lib/jakarta.servlet'; then
        log_err "检测到 jakarta.servlet API 被打进 WEB-INF/lib。"
        log_err "请把 pom.xml 中 jakarta.servlet-api / jsp-api 的 <scope> 改为 provided。"
        exit 1
    fi
    log_info "依赖作用域检查通过：Servlet/JSP API 未被打包。"
else
    log_warn "未找到 unzip，跳过包内结构校验（仅在本机缺少 unzip 时发生）。"
    log_warn "这不影响构建结论，但少了一层保护，建议安装 unzip。"
fi

log_info "构建门禁通过。"
exit 0
