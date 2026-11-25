#!/usr/bin/env bash
# =============================================================================
# 门禁4：部署后健康检查
# 契约见 docs/04-门禁与命令契约.md：exit 0 = 通过，非 0 = 失败
# 执行：bash scripts/health.sh            # 默认检查 http://localhost:8000/health
#       PORT=80 bash scripts/health.sh    # 经前端 Nginx 检查
#       HEALTH_HOST=127.0.0.1 PORT=8000 HEALTH_RETRIES=10 bash scripts/health.sh
#
# 判定标准：HTTP 200 且响应体符合契约 {"status":"ok"}。
# 失败时输出末行可直接贴进失败报告（含排查建议）。
# 本脚本只读，不修改任何业务代码，可重复执行（幂等）。
# =============================================================================
set -euo pipefail

HOST="${HEALTH_HOST:-${HOST:-localhost}}"
PORT="${PORT:-8000}"
RETRIES="${HEALTH_RETRIES:-5}"    # 重试次数：容忍服务刚启动
INTERVAL="${HEALTH_INTERVAL:-2}"  # 重试间隔（秒）
URL="http://${HOST}:${PORT}/health"

info() {
  echo "[health] $*"
}

fail() {
  echo "[health][失败] $*" >&2
  exit 1
}

# curl 是本门禁唯一硬依赖
if ! command -v curl >/dev/null 2>&1; then
  fail "未检测到 curl 命令，无法执行健康检查。请安装 curl，或手工验证 ${URL}。"
fi

BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/health_body.XXXXXX")"
trap 'rm -f "$BODY_FILE"' EXIT

info "检查目标：${URL}（最多重试 ${RETRIES} 次，间隔 ${INTERVAL}s）"

HTTP_CODE="000"
for i in $(seq 1 "$RETRIES"); do
  HTTP_CODE="000"
  # -f：HTTP >=400 视为失败；-sS：静默但保留错误信息；-m：单次超时
  # 放到 if 条件里，避免在 -e 下中断，同时不吞掉门禁结论（真正的判定在下方）
  if ! HTTP_CODE="$(curl -sS -m 5 -o "$BODY_FILE" -w '%{http_code}' -f "$URL" 2>/dev/null)"; then
    HTTP_CODE="${HTTP_CODE:-000}"
  fi

  if [[ "$HTTP_CODE" == "200" ]]; then
    BODY="$(cat "$BODY_FILE" 2>/dev/null || echo '')"
    info "第 ${i} 次尝试成功，HTTP 200"
    info "响应体：${BODY}"
    # 语义校验：契约要求 body 含 {"status":"ok"}
    if [[ "$BODY" == *'"status"'* && "$BODY" == *'ok'* ]]; then
      info "==== health 通过：服务存活且响应符合契约 ===="
      exit 0
    fi
    fail "HTTP 200 但响应体不符合契约（期望含 {\"status\":\"ok\"}，实际：${BODY}）。"
  fi

  if [[ "$i" -lt "$RETRIES" ]]; then
    info "第 ${i}/${RETRIES} 次尝试失败（HTTP ${HTTP_CODE}），${INTERVAL}s 后重试…"
    sleep "$INTERVAL"
  else
    info "第 ${i}/${RETRIES} 次尝试失败（HTTP ${HTTP_CODE}），已达最大重试次数。"
  fi
done

fail "健康检查未通过（最后状态码 ${HTTP_CODE}）。排查建议：
  1) 服务是否已启动：docker compose -f deploy/docker-compose.yml ps
  2) 端口是否正确映射：docker port java-spring-backend
  3) 查看日志：docker compose -f deploy/docker-compose.yml logs --tail=200 backend
  4) 手工验证：curl -v ${URL}"
