#!/usr/bin/env bash
# 门禁 4：健康检查（部署后执行，对应框架「部署健康检查」门禁）
# 契约：exit 0 = 服务健康；exit 非 0 = 不健康或不可达
# 内容：curl http://localhost:${PORT:-8000}/health
# 用法：bash scripts/health.sh          # 默认 8000 端口
#       PORT=8080 bash scripts/health.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 端口可通过环境变量覆盖，与 deploy/docker-compose.yml 保持一致
PORT="${PORT:-8000}"
URL="http://localhost:${PORT}/health"

echo "[health] 模板根目录：${ROOT_DIR}"
echo "[health] 探测：${URL}"

# ---- 前置检查：工具是否安装 ----
if ! command -v curl >/dev/null 2>&1; then
  echo "[health] 错误：未找到 curl。请先安装 curl（Windows 可用 Git Bash / WSL 自带的 curl）。" >&2
  exit 127
fi

# -f：4xx/5xx 视为失败；-s：静默；-S：失败时仍打印错误；--max-time：防挂起
if ! BODY="$(curl -fsS --max-time 10 "${URL}")"; then
  echo "[health] 失败：无法访问 ${URL}（服务未启动、端口不对或健康检查未通过）" >&2
  echo "[health] 排查建议：docker compose ps / docker compose logs backend" >&2
  exit 1
fi

echo "[health] 响应：${BODY}"

# 校验响应体包含 "status":"ok"，仅 HTTP 200 不足以判定健康
if ! printf '%s' "${BODY}" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
  echo "[health] 失败：响应体未包含 '\"status\":\"ok\"'，判定为不健康" >&2
  exit 1
fi

echo "[health] 通过：服务健康"
exit 0
