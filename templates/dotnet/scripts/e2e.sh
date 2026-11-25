#!/usr/bin/env bash
# 门禁 5：端到端 / 集成测试（占位实现）
# 契约：exit 0 = 通过（占位阶段恒通过）；exit 非 0 = 失败
# 现状：本模板未内置 E2E 用例，脚本按框架契约「可运行且明确说明」实现，不阻塞流水线。
# 用法：bash scripts/e2e.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[e2e] 模板根目录：${ROOT_DIR}"
echo "[e2e] 当前为占位实现：本模板未内置端到端用例，跳过执行并返回 0。"
echo "[e2e] 接入建议（按项目实际补全）："
echo "        1) 安装 Playwright：cd frontend && npm i -D @playwright/test && npx playwright install"
echo "        2) 依赖隔离环境：cd deploy && docker compose up -d --build"
echo "        3) 编写用例覆盖 docs/requirements.md 的验收标准（FR-4/FR-5）"
echo "        4) 将本脚本第 3 段替换为：npx playwright test --reporter=list"
echo "[e2e] 说明：E2E 属独立测试智能体职责，开发智能体不判定自己的 UI 是否通过。"

# 占位阶段固定通过；接入真实用例后，改为执行测试命令并透传其退出码
exit 0
