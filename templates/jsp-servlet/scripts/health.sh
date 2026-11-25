#!/usr/bin/env bash
# ============================================================================
# 门禁 4：健康检查（health）— 部署后执行
#
# 框架统一命令契约（docs/04-门禁与命令契约.md §2 / docs/03 §2.3）：
#   exit 0  = 服务健康
#   exit ≠0 = 不健康，立即回滚（见 docs/runbook.md §4.4）
#
# 判定标准：GET /health 返回 HTTP 200，且响应体包含 "status":"ok"。
#   只判 200 是不够的：某些错误配置下容器会返回 200 的默认页，
#   那说明请求根本没打到我们的 Servlet。所以必须校验响应体。
#
# 用法：
#   bash scripts/health.sh                       # 默认 http://localhost:8080
#   PORT=9090 bash scripts/health.sh             # 覆盖端口
#   HEALTH_URL=http://10.0.0.5:8080/health bash scripts/health.sh
#   bash scripts/health.sh --wait                # 启动场景：轮询等待就绪
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------- 参数 ----------
PORT="${PORT:-8080}"
HEALTH_URL="${HEALTH_URL:-http://localhost:${PORT}/health}"
WAIT_MODE=0
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"   # 秒；与 compose 的 start_period 对齐

for arg in "$@"; do
    case "${arg}" in
        --wait)   WAIT_MODE=1 ;;
        -h|--help)
            printf '用法: bash scripts/health.sh [--wait]\n'
            printf '  --wait    轮询等待服务就绪（最多 WAIT_TIMEOUT 秒，默认 90）\n'
            printf '环境变量: PORT（默认 8080）、HEALTH_URL、WAIT_TIMEOUT\n'
            exit 0
            ;;
        *)
            printf '[health][错误] 未知参数：%s（用 --help 查看用法）\n' "${arg}" >&2
            exit 2
            ;;
    esac
done

log_info() { printf '[health] %s\n' "$*"; }
log_err()  { printf '[health][错误] %s\n' "$*" >&2; }
log_warn() { printf '[health][警告] %s\n' "$*" >&2; }

# ---------- 前置检查 ----------
if ! command -v curl >/dev/null 2>&1; then
    log_err "未找到 curl，无法执行健康检查。"
    log_err "请安装 curl："
    log_err "  - Windows: Windows 10+ 通常自带；或在 Git Bash / WSL 中执行"
    log_err "  - macOS:   brew install curl"
    log_err "  - Linux:   sudo apt install curl"
    log_err "注意：健康检查未执行不等于健康，因此这里以非 0 退出。"
    exit 1
fi

log_info "目标：${HEALTH_URL}"

# ---------- 单次探测 ----------
# 返回 0 表示健康；非 0 表示不健康（不直接退出，便于 --wait 轮询）
probe_once() {
    local body http_code
    # -s 静默、-S 出错时仍打印错误、--max-time 5 防止挂死
    body="$(curl -sS --max-time 5 -w '\n%{http_code}' "${HEALTH_URL}" 2>/dev/null || true)"
    http_code="$(printf '%s' "${body}" | tail -n 1)"
    body="$(printf '%s' "${body}" | sed '$d')"

    if [[ "${http_code}" != "200" ]]; then
        log_warn "HTTP 状态码：${http_code:-无响应}（期望 200）"
        return 1
    fi

    if ! printf '%s' "${body}" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
        log_warn "响应体不符合契约，期望包含 \"status\":\"ok\"，实际：${body}"
        return 1
    fi

    log_info "健康检查通过：${body}"
    return 0
}

# ---------- 执行 ----------
if [[ "${WAIT_MODE}" -eq 1 ]]; then
    log_info "轮询等待就绪（最多 ${WAIT_TIMEOUT} 秒）..."
    elapsed=0
    while [[ "${elapsed}" -lt "${WAIT_TIMEOUT}" ]]; do
        if probe_once; then
            exit 0
        fi
        sleep 3
        elapsed=$(( elapsed + 3 ))
    done
    log_err "等待超时（${WAIT_TIMEOUT}s）后服务仍不健康。"
    log_err "排查入口见 docs/runbook.md §6；常见原因：容器未启动、上下文路径不是 ROOT、war 未解包完成。"
    exit 1
fi

if probe_once; then
    exit 0
fi

log_err "健康检查失败。"
log_err "建议排查顺序："
log_err "  1. docker compose ps                 # 容器是否 running / healthy"
log_err "  2. docker compose logs --tail=100    # 启动日志是否有 SEVERE"
log_err "  3. curl -v ${HEALTH_URL}             # 看响应头与状态码"
log_err "详见 docs/runbook.md §6 故障排查手册。"
exit 1
