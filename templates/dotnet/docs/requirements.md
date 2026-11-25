# 需求文档 — .NET + Vue 最小示例工程（模板）

> 本文件演示框架规范要求的「含可测验收标准的需求文档」格式。
> 复制为新项目时，请**整篇重写**功能需求表，保留结构与编号规则。

## 1. 背景与目标

提供一个 ASP.NET Core 8 Minimal API（后端）+ Vue 3（前端）的最小可运行示例，
作为 AI 多智能体协同开发框架在 .NET 技术栈上的项目起点（POC 起点）。

目标：

1. 前后端通过**契约先行**（`docs/api-spec.yaml`）解耦，两个智能体可并行开发。
2. 每个功能需求都带**可自动判定的验收标准**，供独立测试智能体对照执行。
3. 全流程可在隔离容器环境内跑通，不触碰任何真实环境。

## 2. 用户故事

- 作为**用户**，我希望访问首页时能看到后端返回的问候语，以验证前后端联通。
- 作为**运维**，我希望后端提供健康检查接口，以便容器编排与门禁脚本判定服务存活。
- 作为**编排器**，我希望项目提供 `scripts/` 下 5 个统一入口，以便不关心技术栈地驱动门禁。
- 作为**前端开发**，我希望接口失败时页面有明确错误提示，而不是白屏。

## 3. 功能需求

| 编号 | 需求 | 优先级 | 验收标准 |
|---|---|---|---|
| FR-1 | 后端健康检查接口 | P0 | `GET /health` 返回 200，响应体为 `{"status":"ok"}`，`Content-Type: application/json` |
| FR-2 | 后端问候接口 | P0 | `GET /api/v1/greeting` 返回 200，响应体同时含 `message` 与 `time` 字段；`message` 固定为 `Hello from .NET backend`，`time` 为 ISO-8601 UTC 时间（`DateTime.UtcNow.ToString("O")`） |
| FR-3 | 后端跨域支持 | P0 | 带 `Origin` 头的请求响应含 `Access-Control-Allow-Origin`；`OPTIONS` 预检返回 204 |
| FR-4 | 前端展示问候语 | P0 | 页面挂载后请求 `/api/v1/greeting`，成功后渲染 `message` 文本与 `time` |
| FR-5 | 前端异常处理 | P1 | 接口非 2xx 时页面渲染错误文案（含状态码 `请求失败: <code>`），不出现白屏 |
| FR-6 | 统一命令契约 | P0 | `scripts/lint.sh`、`build.sh`、`test.sh` 全部 exit 0；`health.sh` 在服务已启动时 exit 0；`e2e.sh` exit 0 |
| FR-7 | 隔离环境可启动 | P1 | `deploy/docker-compose.yml` 中 `docker compose up -d --build` 后，后端与前端容器 healthcheck 均为 `healthy` |

## 4. 非功能需求

- **可测性**：后端单测覆盖 `/health` 与 `/api/v1/greeting` 两个接口的成功路径；
  前端单测覆盖成功/失败两条渲染路径，行覆盖率门槛 80%。
- **安全**：容器以非 root 用户运行，`read_only` 根文件系统 + `no-new-privileges`。
- **可移植**：前后端均可在 Docker 隔离网络内运行，不依赖宿主环境装 .NET/Node。
- **可观测**：后端提供 `/health` 供容器 `HEALTHCHECK` 与门禁脚本使用。

## 5. 范围外（Out of Scope）

- 不做鉴权/登录，不涉及用户体系。
- 不做持久化数据库，无数据迁移。
- 不做国际化与多主题。

## 6. 澄清问题与假设

- 假设仅需本地/隔离环境运行，不接入生产网络。
- 假设后端端口 8000，前端 dev 端口 3000、容器端口 80。
- 假设 CORS 在开发期宽松放行，生产由 API 网关统一收敛（本模板不实现网关）。
- `.NET 8` 为 LTS，如新项目需要 `.NET 9`，须同步修改 `DemoApi.csproj`、Dockerfile 与 runbook。
