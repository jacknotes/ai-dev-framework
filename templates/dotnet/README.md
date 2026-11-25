# .NET + Vue 最小示例工程（模板）

> 这是 AI 多智能体协同开发框架的**项目目录模板**，可直接复制为新项目起点。
> 目录结构遵循框架规范 `docs/01` §5，门禁实现遵循 `docs/04-门禁与命令契约.md`
> 的「五入口契约」（`scripts/` 下 5 个脚本，判定只看退出码）。

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | ASP.NET Core 8 Minimal API + C# 12（.NET 8） |
| 前端 | Vue 3 + TypeScript + Vite |
| 测试 | 后端 xUnit + `WebApplicationFactory`；前端 Vitest + Vue Test Utils |
| 部署 | Docker 多阶段构建 + Nginx 托管静态产物 |

## 目录结构

```
dotnet/
├── .gitignore
├── README.md
├── docs/                       # 需求、架构、API 契约、运维手册
│   ├── requirements.md         # 需求文档 + 可测验收标准
│   ├── architecture.md         # 技术选型 / 架构图 / 模块 / 数据模型 / 契约
│   ├── api-spec.yaml           # OpenAPI 3.0.3 契约（前后端唯一事实源）
│   └── runbook.md              # 运维实施文档（8 小节）
├── backend/                    # ASP.NET Core 8 Minimal API
│   ├── DemoApi.csproj
│   ├── Program.cs              # 路由 / CORS / 启动入口
│   ├── Dockerfile              # 多阶段构建 + 非 root + HEALTHCHECK
│   └── tests/
│       ├── DemoApi.Tests.csproj
│       └── GreetingTests.cs
├── frontend/                   # Vue 3 + TypeScript + Vite
│   ├── src/                    # main.ts / App.vue / api.ts + 单测
│   ├── index.html
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── eslint.config.js
│   ├── nginx.conf
│   └── Dockerfile
├── deploy/
│   └── docker-compose.yml      # 隔离环境一键启动
└── scripts/                    # 统一命令契约（编排器只认这 5 个入口）
    ├── lint.sh
    ├── build.sh
    ├── test.sh
    ├── health.sh
    └── e2e.sh
```

## 本地快速开始（不使用 Docker）

前置条件：.NET SDK 8.0、Node.js 20+、npm 10+。

**后端（终端 1）：**
```bash
cd backend
dotnet run
# 监听 http://localhost:8000
# 验证：curl http://localhost:8000/health
```

**前端（终端 2）：**
```bash
cd frontend
npm install
npm run dev
# 访问 http://localhost:3000（Vite 已代理 /api → 8000）
```

> 前后端联调依赖 CORS：后端 `Program.cs` 已启用开发期宽松 CORS，生产由网关统一收敛。

## 隔离环境一键启动（推荐，符合框架「不碰真实环境」）

```bash
cd deploy
docker compose up -d --build
curl http://localhost:8000/health      # 后端健康检查，期望 {"status":"ok"}
curl http://localhost:8000/api/v1/greeting
# 前端: http://localhost:80
docker compose down -v                 # 用完即销毁，数据不留痕
```

隔离要点：`internal: true` 独立网段 `172.34.0.0/24`、`read_only` + `no-new-privileges`、
CPU/内存限额、无生产凭证、无真实数据。

## 运行测试（对应框架门禁）

框架编排器不关心本项目用 `dotnet` 还是 `npm`，它只调用 `scripts/` 下的 5 个固定入口：

```bash
bash scripts/lint.sh && bash scripts/build.sh && bash scripts/test.sh
```

> 可复现的完整构建/部署/故障排查命令见 [`docs/runbook.md`](docs/runbook.md)，这里是唯一命令来源；本节只作快速起步。

## 与框架的关系

| 框架产物 | 本模板对应 |
|---|---|
| 规范文档 §5 目录约定 | 本模板 `docs/` / `frontend/` / `backend/` / `deploy/` 结构 |
| 规范文档 §7 五重隔离 | `deploy/docker-compose.yml`（网络/沙箱/资源/凭证/数据） |
| 门禁 1 静态检查 | `scripts/lint.sh` → `dotnet format` + `eslint` |
| 门禁 2 构建 | `scripts/build.sh` → `dotnet build -c Release` + `vite build` |
| 门禁 3 单元测试 | `scripts/test.sh` → `dotnet test` + `vitest`（覆盖率门槛） |
| 门禁 4 部署健康检查 | `scripts/health.sh` + 容器 `HEALTHCHECK` |
| 门禁 5 集成/E2E | `scripts/e2e.sh`（占位，待接入 Playwright） |
| 单一事实源 | `docs/api-spec.yaml` 是前后端唯一接口约定 |
| 运维可复用资产 | `docs/runbook.md`（8 小节实施骨架） |
| 统一命令契约（`docs/03` §2.3 / `docs/04`） | `scripts/` 5 个入口，技术栈可插拔，判定只看退出码 |

## 复制为新项目

```bash
cp -r templates/dotnet /path/to/new-project
cd /path/to/new-project
# 1. 改 backend/DemoApi.csproj 的文件名/程序集名与 Program.cs 的业务路由
# 2. 改 frontend/package.json 的 name
# 3. 改 deploy/docker-compose.yml 的 name 与网段（避免与其他模板冲突）
# 4. 按 docs/requirements.md 模板重写需求，再按流程推进
```
