#!/usr/bin/env bash
# ============================================================================
# 门禁 3：单元测试（test）
#
# 框架统一命令契约（docs/04-门禁与命令契约.md §2 / docs/03 §2.3）：
#   exit 0  = 全部用例通过
#   exit ≠0 = 存在失败/错误用例，退回编码环节
#
# 本脚本做什么：
#   1. mvn -q -B test（不跳过测试，不放过失败）
#   2. 校验 surefire 报告确实存在且有执行用例
#      —— 防"测试类没被扫描到、0 个用例、却 exit 0"这种假绿。
#
# 关于覆盖率：本模板**不设覆盖率阈值**。JSP 遗留栈缺少现成的覆盖率基线，
# 强行设阈值只会催生"为覆盖率而写空测试"。覆盖率门禁应当作为独立技术债任务
# 单独立项（见 docs/architecture.md §7），不允许在业务 PR 里顺手加。
#
# 用法：
#   bash scripts/test.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"
POM_FILE="${BACKEND_DIR}/pom.xml"
REPORTS_DIR="${BACKEND_DIR}/target/surefire-reports"

log_info() { printf '[test] %s\n' "$*"; }
log_err()  { printf '[test][错误] %s\n' "$*" >&2; }

# ---------- 前置检查 ----------
if [[ ! -f "${POM_FILE}" ]]; then
    log_err "未找到 ${POM_FILE}，请确认脚本位于模板的 scripts/ 目录下。"
    exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
    log_err "未找到 mvn（Maven）。"
    log_err "单元测试依赖 Maven + JDK 17，请先安装后重试。"
    log_err "若只想快速验证运行形态，可用 Docker：cd deploy && docker compose up -d --build"
    exit 1
fi

# ---------- 执行测试 ----------
log_info "开始执行单元测试：mvn -q -B test"

if ! ( cd "${BACKEND_DIR}" && mvn -q -B test ); then
    log_err "单元测试存在失败用例，门禁未通过。"
    log_err "请查看 ${REPORTS_DIR} 下的报告定位具体断言（报告会指出类名与行号）。"
    exit 1
fi

# ---------- 反"假绿"校验 ----------
if [[ ! -d "${REPORTS_DIR}" ]]; then
    log_err "测试命令成功但未生成 surefire 报告目录：${REPORTS_DIR}"
    log_err "这通常意味着测试类未被扫描到（命名需匹配 *Test / Test* / *Tests）。"
    exit 1
fi

# 统计实际执行的用例数
# surefire 的 .txt 报告里每个测试类有一行：
#   Tests run: 7, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.12 s -- in com.example.web.GreetingServiceTest
# 这里只认带 "-- in " 的"每个测试集"行，避免把可能的汇总行重复计入。
TOTAL_RUN=0
REPORT_FILES=0
if compgen -G "${REPORTS_DIR}/*.txt" > /dev/null; then
    while IFS= read -r report; do
        REPORT_FILES=$(( REPORT_FILES + 1 ))
        while IFS= read -r line; do
            if [[ "${line}" =~ Tests\ run:\ ([0-9]+),\ Failures:\ ([0-9]+),\ Errors:\ ([0-9]+),\ Skipped:\ ([0-9]+).*--\ in\  ]]; then
                TOTAL_RUN=$(( TOTAL_RUN + BASH_REMATCH[1] ))
            fi
        done < "${report}"
    done < <(find "${REPORTS_DIR}" -maxdepth 1 -name '*.txt' -type f | sort)
fi

log_info "报告文件数：${REPORT_FILES}"

if [[ "${TOTAL_RUN}" -eq 0 ]]; then
    log_err "检测到 0 个执行用例 —— 门禁不能靠「没有测试」来通过。"
    log_err "请确认 src/test/java 下存在测试类，且命名符合 surefire 默认规则。"
    log_err "若确认已有测试仍报此错，请检查是否被 -DskipTests / -Dmaven.test.skip 跳过。"
    exit 1
fi

log_info "执行用例总数：${TOTAL_RUN}（全部通过）"
log_info "测试报告：${REPORTS_DIR}"
log_info "测试门禁通过。"
exit 0
