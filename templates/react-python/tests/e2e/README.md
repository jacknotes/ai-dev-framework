# tests/e2e/ — 端到端测试用例

> 由**独立测试智能体**编写与执行；开发智能体**不得修改本目录**（见 `docs/01` §2 角色权限）。

## 目录结构

```
tests/e2e/
├── playwright.config.ts     # Playwright 配置（baseURL 由环境变量注入）
├── specs/
│   ├── health.spec.ts       # 服务可用性：/health、首页可加载
│   └── greeting.spec.ts     # 契约一致性：/api/v1/greeting 字段、首页渲染
└── README.md
```

## 这些用例验证什么

| 用例 | 追溯 | 断言 |
|---|---|---|
| `/health` 返回 200 + `status=ok` | 非功能「服务可用性」 | 状态码与响应体 |
| 首页可加载并渲染内容 | 非功能「服务可用性」 | 非白屏 |
| `/api/v1/greeting` 含 `message`/`time` | FR-1 + `docs/api-spec.yaml` required 字段 | 字段存在且类型正确、`time` 可解析 |
| 首页显示问候语 | FR-1（端到端联通） | 页面上能看到 `Hello from...` |

## 为什么这些断言是"黑盒"的

用例**不 import 任何业务代码**，只通过 HTTP 与页面可见内容观察行为。
这样测试智能体无法"让用例配合实现"，只能验证对外承诺是否兑现。

## 怎么运行

隔离环境内（推荐，容器已备好 Playwright 与浏览器）：

```powershell
powershell -File deploy/docker/up.ps1 -WithE2E
powershell -File deploy/docker/verify.ps1
```

本地直接跑（需自行 `npm i -D @playwright/test && npx playwright install chromium`）：

```bash
cd tests/e2e
TEST_BASE_URL=http://localhost:13000 API_BASE_URL=http://localhost:8000 npx playwright test
```

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `TEST_BASE_URL` | `http://frontend` | 前端地址。容器网络内用服务名，宿主机用 `http://localhost:<port>` |
| `API_BASE_URL` | `http://backend:8000` | 后端地址，同上 |

> `scripts/e2e.sh` 会检测 `tests/e2e/` 下是否存在 `*.spec.*` 文件：
> 有则真实执行并以退出码判定，无则明确输出"跳过"（**跳过不等于通过**）。

## 扩展建议

- 每个功能需求至少要有一条 e2e 覆盖，并在注释里标注需求编号。
- 失败时 Playwright 会自动留 screenshot / trace（见 `playwright.config.ts`），
  测试智能体应把这些证据附进 `docs/test/<日期>-e2e-report.md`。
