#!/usr/bin/env bash
# ============================================================================
# 门禁 1：静态检查（lint）
#
# 框架统一命令契约（docs/04-门禁与命令契约.md §2 / docs/03 §2.3）：
# 编排器只认这 5 个入口，判定只看退出码。
#   exit 0  = 通过
#   exit ≠0 = 失败，携带输出退回编码环节
#
# 本脚本的策略（JSP 遗留栈的务实做法，见 docs/03 §2.4 第 3 点）：
#   1. 若 backend/pom.xml 配置了 maven-checkstyle-plugin，则执行
#      mvn -q -B checkstyle:check，真正的风格检查。
#   2. 若未配置（本模板的默认状态），**不静默跳过**，而是退化为编译检查
#      mvn -q -B compile，并打印中文说明——明确告知"这次只验证了能编译"。
#      静默通过是最危险的失败模式：门禁看起来绿了，其实什么都没检查。
#
# 用法：
#   bash scripts/lint.sh
# ============================================================================

set -euo pipefail

# ---------- 定位目录（脚本可从任意工作目录调用）----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"
POM_FILE="${BACKEND_DIR}/pom.xml"

log_info() { printf '[lint] %s\n' "$*"; }
log_warn() { printf '[lint][警告] %s\n' "$*" >&2; }
log_err()  { printf '[lint][错误] %s\n' "$*" >&2; }

# ---------- 前置检查 ----------
if [[ ! -f "${POM_FILE}" ]]; then
    log_err "未找到 ${POM_FILE}，请确认脚本位于模板的 scripts/ 目录下。"
    exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
    log_err "未找到 mvn（Maven）。"
    log_err "请安装 Maven 3.9+ 并确保其在 PATH 中，例如："
    log_err "  - Windows: 下载 apache-maven 并配置 MAVEN_HOME / PATH"
    log_err "  - macOS:   brew install maven"
    log_err "  - Linux:   sudo apt install maven"
    log_err "也可跳过本机安装，改用 Docker：docker build -t jsp-servlet-demo backend"
    exit 1
fi

# ---------- 判断是否配置了 checkstyle 插件 ----------
# 只做文本层面的存在性判断：模板刻意不预置规则集，避免给遗留项目强加一套风格规范。
if grep -q 'maven-checkstyle-plugin' "${POM_FILE}"; then
    log_info "检测到 maven-checkstyle-plugin，执行风格检查：mvn -q -B checkstyle:check"
    if ( cd "${BACKEND_DIR}" && mvn -q -B checkstyle:check ); then
        log_info "静态检查通过。"
        exit 0
    else
        log_err "静态检查失败，请根据上方 Checkstyle 报告修复后重试。"
        exit 1
    fi
fi

log_warn "pom.xml 未配置 maven-checkstyle-plugin —— 已退化为编译检查。"
log_warn "本次门禁只能证明「代码可编译」，不覆盖代码风格与潜在缺陷。"
log_warn "如需真正的静态检查，请先引入 checkstyle 插件与规则集（属独立技术债任务，"
log_warn "不应在业务 PR 中顺手添加，见 docs/architecture.md §7）。"
log_info "执行编译检查：mvn -q -B compile"

if ( cd "${BACKEND_DIR}" && mvn -q -B compile ); then
    log_info "编译检查通过（注意：这不等于通过静态检查）。"
    exit 0
else
    log_err "编译失败，请根据上方 Maven 输出修复后重试。"
    exit 1
fi
