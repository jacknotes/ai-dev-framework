#!/usr/bin/env bash
# ------------------------------------------------------------
# 门禁4：部署后健康检查
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# 用法：PORT=8000 bash scripts/health.sh
# ------------------------------------------------------------
set -euo pipefail

HOST="${HEALTH_HOST:-localhost}"
PORT="${PORT:-8000}"
URL="http://${HOST}:${PORT}/health"
RETRIES="${HEALTH_RETRIES:-15}"
INTERVAL="${HEALTH_INTERVAL:-2}"

echo "==> [health] 检查 ${URL}（最多重试 ${RETRIES} 次）"

if ! command -v curl >/dev/null 2>&1; then
  echo "!! 未找到 curl，无法执行健康检查" >&2
  exit 1
fi

for i in $(seq 1 "$RETRIES"); do
  if curl -fsS --max-time 5 "$URL" >/dev/null 2>&1; then
    echo "[health] 通过（第 ${i} 次尝试）"
    exit 0
  fi
  sleep "$INTERVAL"
done

echo "[health] 失败：${URL} 在 ${RETRIES} 次尝试内未就绪" >&2
exit 1
