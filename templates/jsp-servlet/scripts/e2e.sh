#!/usr/bin/env bash
# ============================================================================
# 门禁 5：端到端测试（e2e）— 占位实现
#
# 框架统一命令契约（docs/04-门禁与命令契约.md §2 / docs/03 §2.3）要求每个项目都提供 e2e.sh，
# 但**本模板不实现真正的浏览器级 E2E**，原因如下（诚实声明，不假装跑过）：
#
#   1. 真正的 E2E 需要 Playwright/Cypress + 浏览器内核 + 容器网络打通，
#      体积与维护成本远超"最小示例模板"的定位；
#   2. 按框架分工，E2E 属于**独立测试 AI** 的产出物（docs/01 §2），
#      不应由模板作者顺手写一个"看起来跑了"的脚本；
#   3. 若把占位脚本伪装成"通过"，会造成最危险的假绿 —— 门禁显示绿色，
#      实际什么都没验证。这正是框架要消灭的模式。
#
# 因此本脚本的行为是：
#   - 明确打印"未实现"，说明应该如何补；
#   - 以 exit 0 返回（不阻塞流水线，因为"未实现"是已知状态，不是失败）；
#   - 支持 --strict 参数，此时以 exit 1 返回 —— 供正式项目的 CI 使用，
#     避免占位脚本被误当成真实门禁。
#
# 用法：
#   bash scripts/e2e.sh            # 占位模式：打印说明，exit 0
#   bash scripts/e2e.sh --strict   # 严格模式：未实现即失败，exit 1
#
# 什么时候该把它变成真实门禁：
#   当项目决定引入 E2E 时，删除本占位实现，改为：
#     1) 用 compose 拉起隔离环境（deploy/docker-compose.yml）
#     2) 跑 Playwright 用例（tests/e2e/*.spec.ts）
#     3) 断言 docs/pages.md 中列出的每个页面与依赖接口
#   并将 tests/ 目录纳入仓库。
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STRICT=0
for arg in "$@"; do
    case "${arg}" in
        --strict) STRICT=1 ;;
        -h|--help)
            printf '用法: bash scripts/e2e.sh [--strict]\n'
            printf '  默认：占位模式，打印说明并以 0 退出（不阻塞流水线）\n'
            printf '  --strict：严格模式，未实现即非 0 退出（正式项目 CI 建议使用）\n'
            exit 0
            ;;
        *)
            printf '[e2e][错误] 未知参数：%s（用 --help 查看用法）\n' "${arg}" >&2
            exit 2
            ;;
    esac
done

log_info() { printf '[e2e] %s\n' "$*"; }
log_warn() { printf '[e2e][警告] %s\n' "$*" >&2; }

log_warn "端到端测试尚未实现（这是占位脚本，不代表已验证）。"
log_info ""
log_info "当前可用的替代验证（已实现，可直接执行）："
log_info "  1. 启动隔离环境：cd deploy && docker compose up -d --build"
log_info "  2. 健康检查：    bash ../scripts/health.sh --wait"
log_info "  3. 接口冒烟：    curl -fsS http://localhost:8080/api/v1/greeting"
log_info "  4. 页面冒烟：    curl -fsS http://localhost:8080/index.jsp | grep -q 'id=\"greeting\"'"
log_info ""
log_info "要升级为真实 E2E 门禁，请："
log_info "  - 新建 tests/e2e/ 目录，存放 Playwright 用例；"
log_info "  - 在 tests/ 下提供 tests/package.json 与 playwright.config.ts；"
log_info "  - 将本脚本改为：compose up → 等待 healthy → 执行 playwright test → 收集报告；"
log_info "  - 按 docs/pages.md 的页面清单逐项覆盖（PG-1 至少覆盖成功与失败两条路径）。"
log_info ""
log_info "技术债登记：见 docs/architecture.md §7「已知技术债与门禁边界」。"
log_info "E2E 由独立测试 AI 实现，见 docs/01-开发规范文档.md §2 与 docs/03 §3。"

if [[ "${STRICT}" -eq 1 ]]; then
    log_warn "严格模式：E2E 未实现，判定为失败。"
    exit 1
fi

log_info "占位模式：以 0 退出（请勿将其视为「通过」）。"
exit 0
