# 运维实施文档（Runbook）— .NET + Vue 示例工程

> 责任角色：运维 DevOps 智能体。本文是**可复用**的实施骨架，新项目复制后按实际情况填空。
> 原则：任何人（或任何智能体）依据本文，可从零重建并验证本环境。

## 1. 环境架构

| 环境 | 用途 | 网络 | 数据 | 生命周期 |
|---|---|---|---|---|
| dev | 开发自测（`dotnet run` + `npm run dev`） | 宿主 localhost | 无持久化 | 开发者本地，随用随起 |
| staging | 集成/功能/性能/安全测试与部署门禁演练 | Compose 隔离网络 `172.34.0.0/24`（`internal: true`） | 无持久化，容器销毁即清空 | **一次性**，用完 `down -v` |
| prod | 生产（本模板不提供，须另行按项目补 IaC 与审批） | 独立 VPC/Namespace | 独立实例 | 长期，仅人工审批后变更 |

拓扑（staging）：

```
浏览器 ──:80──▶ frontend(Nginx) ──/api/──▶ backend(ASP.NET Core :8000)
                      │                          │
                      └── 静态产物               └── /health 供 HEALTHCHECK
```

隔离五要素（对应规范 §7.2）：

| 维度 | 本模板落实方式 |
|---|---|
| 环境隔离 | `docker compose up -d --build` 全新建；`down -v` 销毁 |
| 网络隔离 | `internal: true` + 独立网段 `172.34.0.0/24`，出口不通外网 |
| 凭证隔离 | 不注入任何生产密钥，仅 `ASPNETCORE_URLS` / `ENV` |
| 数据隔离 | 无数据库、无真实用户数据，全部为内存常量 |
| 执行沙箱 | `read_only: true`、`no-new-privileges:true`、CPU/内存限额、非 root 用户 |

## 2. 依赖与前置条件

| 依赖 | 版本要求 | 校验命令 | 缺失后果 |
|---|---|---|---|
| .NET SDK | 8.0.x（LTS） | `dotnet --list-sdks` | `build.sh` / `test.sh` 失败 |
| Node.js | ≥ 20 | `node -v` | `lint.sh` / 前端构建失败 |
| npm | ≥ 10 | `npm -v` | 同上 |
| Docker Engine | ≥ 24 | `docker --version` | 隔离环境无法启动 |
| Docker Compose | v2（`docker compose` 子命令） | `docker compose version` | 无法一键启动 |
| bash | 4+（Windows 用 Git Bash / WSL） | `bash --version` | `scripts/*.sh` 无法执行 |
| curl | 任意 | `curl --version` | `health.sh` 失败 |

端口占用：

| 端口 | 用途 | 冲突时处理 |
|---|---|---|
| 8000 | 后端 API | `docker compose` 改宿主机映射，或本地 `ASPNETCORE_URLS` 改端口 |
| 80 | 前端 Nginx | 同上；Windows 上可能与 IIS/其他服务冲突 |
| 3000 | Vite dev server | 改 `vite.config.ts` 的 `server.port` |

> 缺失工具时，`scripts/*.sh` 会给出清晰提示并以非 0 退出，而不是静默通过。

## 3. 构建步骤

```bash
# 0. 进入模板根目录
cd templates/dotnet

# 1. 后端还原 + Release 构建
cd backend
dotnet restore
dotnet build -c Release
cd ..

# 2. 前端依赖 + 产物构建
cd frontend
npm ci            # 首次或 lock 文件不存在时用 npm install
npm run build     # 产出 dist/
cd ..

# 3. 等价的一键门禁（推荐，供编排器调用）
bash scripts/build.sh   # 内部即执行上述 1、2 两步
```

构建产物位置：

| 产物 | 路径 | 说明 |
|---|---|---|
| 后端程序集 | `backend/bin/Release/net8.0/DemoApi.dll` | 运行需 .NET 8 runtime |
| 前端静态资源 | `frontend/dist/` | 交给 Nginx 托管 |

镜像构建：

```bash
docker build -t demoapi-backend:local ./backend
docker build -t demoapi-frontend:local ./frontend
```

## 4. 部署步骤（含回滚）

### 4.1 首次部署（staging）

```bash
cd deploy
docker compose config          # 先校验编排语法
docker compose up -d --build
docker compose ps              # 等待 STATUS 显示 healthy
curl -fsS http://localhost:8000/health        # 期望 {"status":"ok"}
curl -fsS http://localhost:80/api/v1/greeting # 经 Nginx 反代验证
```

### 4.2 常规发布（同一环境滚动更新）

```bash
# 1) 记录当前版本，供回滚定位
docker image ls --format '{{.Repository}}:{{.Tag}}' | grep demoapi

# 2) 拉取/构建新镜像并只更新变更服务
docker compose up -d --build backend

# 3) 门禁：健康检查必须通过，否则进入 4.3 回滚
bash ../scripts/health.sh
```

### 4.3 回滚（必须能在 5 分钟内完成）

```bash
# 方式 A：回退到上一稳定镜像标签（推荐，生产形态）
docker compose down
docker tag demoapi-backend:previous demoapi-backend:local
docker compose up -d
bash ../scripts/health.sh

# 方式 B：回退代码版本后重建（staging 演练常用）
git log --oneline -5
git checkout <上一个稳定 commit>
docker compose up -d --build
bash ../scripts/health.sh
```

回滚判定与纪律：

| 情况 | 动作 |
|---|---|
| `health.sh` 非 0 且重试 3 次仍失败 | 立即回滚到上一稳定版本，保留现场日志 |
| 错误率 > 5% 或 P95 延迟翻倍 | 回滚，事后分析 |
| 回滚后仍不健康 | 升级给编排器并通知人类，禁止继续试错 |

```bash
# 回滚前先留现场（保留 72 小时）
docker compose logs --no-color > rollback-$(date +%Y%m%d%H%M%S).log
```

### 4.4 销毁

```bash
cd deploy && docker compose down -v --remove-orphans
```

## 5. 健康检查与监控指标

### 5.1 健康检查

| 层级 | 手段 | 命令 | 通过标准 |
|---|---|---|---|
| 容器 | Dockerfile `HEALTHCHECK` | `docker inspect --format '{{.State.Health.Status}}' <容器>` | `healthy` |
| 服务 | 门禁脚本 | `bash scripts/health.sh`（`PORT` 可覆盖，默认 8000） | exit 0 且响应含 `"status":"ok"` |
| 端到端 | 经 Nginx 反代 | `curl -fsS http://localhost/api/v1/greeting` | 200 且含 `message` |

### 5.2 监控指标（staging 最小集）

| 指标 | 采集方式 | 告警阈值（示例） |
|---|---|---|
| 存活状态 | `/health` 每 10s 探测 | 连续 3 次失败 → 告警 |
| HTTP 5xx 比例 | 容器访问日志 / Nginx `access.log` | > 5% 持续 5 分钟 |
| P95 延迟 | 压测报告（k6） | > 500ms（本示例阈值，业务项目按 SLA 调整） |
| 容器内存 | `docker stats` | > 限额 80% 持续 10 分钟 |
| 容器重启次数 | `docker inspect .RestartCount` | 10 分钟内 ≥ 2 次 |

> 本模板不含 Prometheus/Grafana 接入；生产项目须补齐指标导出与告警通道。

## 6. 故障排查手册

| 现象 | 可能原因 | 排查命令 | 处置 |
|---|---|---|---|
| `scripts/*.sh` 报「未安装 dotnet」 | SDK 缺失或不在 PATH | `dotnet --list-sdks` | 安装 .NET 8 SDK 后重开终端 |
| `dotnet format --verify-no-changes` 失败 | 代码格式不合规 | `dotnet format` | 本地格式化后重新提交，勿在 CI 里自动改代码 |
| `dotnet test` 找不到 `Program` | 入口类未声明为 `public partial class Program` | 查看 `backend/Program.cs` 末尾 | 补上该声明（`WebApplicationFactory` 依赖它） |
| 后端启动报端口占用 | 8000 被占用 | `docker compose ps`、`netstat -ano \| findstr :8000` | 换端口或停掉占用进程 |
| `/api/v1/greeting` 返回 404 | 路由前缀写错 | `curl -i http://localhost:8000/api/v1/greeting` | 对齐 `api-spec.yaml`，不要单方面改路径 |
| 前端页面空白 | 构建产物缺失或 Nginx 未挂载 | `docker compose logs frontend` | 重新 `npm run build` 或重建镜像 |
| 浏览器报 CORS 错误 | 直连后端且未被 CORS 放行 | 看响应头 `Access-Control-Allow-Origin` | 开发期走 Vite/nginx 代理同源访问；确认后端 CORS 已注册 |
| 容器 healthcheck 一直 `starting` | 依赖未就绪 / 启动超时 | `docker compose logs backend` | 延长 `start_period`，排查启动异常 |
| 容器起不来且提示只读文件系统 | `read_only: true` 但应用需写盘 | `docker compose logs backend` | 用 `tmpfs` 挂载所需目录，勿去掉 `read_only` |
| `npm test` 覆盖率不达标 | 新增代码未覆盖 | 看 `coverage/` 报告 | 补单测，禁止下调阈值掩盖问题 |

## 7. 备份与恢复

| 对象 | 是否需要备份 | 策略 | 恢复方式 |
|---|---|---|---|
| 源代码 | 是 | 以 Git 仓库为唯一事实源，每次合并即备份 | `git clone` + 指定 commit/tag |
| 容器镜像 | 是 | 打不可变标签（Git SHA）并推送镜像仓库 | `docker pull <repo>@<digest>` |
| 配置（compose/Dockerfile/nginx.conf） | 是 | 随代码入库，评审后合入 | 从 Git 取回 |
| 运行时数据 | 否 | 本示例无持久化数据 | — |
| 日志 | 是（短期） | 发布/回滚前导出到制品库，保留 72h | 从制品库下载查看 |

重建演练（每季度一次）：

```bash
git clone <repo> && cd <repo>/templates/dotnet
bash scripts/build.sh && bash scripts/test.sh
cd deploy && docker compose up -d --build
bash ../scripts/health.sh
docker compose down -v
```

> 判定标准：上述命令全部 exit 0，且 `scripts/health.sh` 在 60 秒内成功。

## 8. 凭证与权限清单

| 凭证/权限 | 用途 | 存放位置 | 归属环境 | 轮换周期 |
|---|---|---|---|---|
| 无生产密钥 | 本模板刻意不引入任何生产凭证 | — | — | — |
| Docker 守护进程访问 | 构建与运行容器 | 本机 Docker 上下文 | dev/staging | 不适用 |
| 镜像仓库推送凭证（可选） | 推送带标签镜像 | CI Secrets（如 `REGISTRY_TOKEN`） | CI | 90 天 |
| Git 仓库写权限 | 提交代码 | SSH Key / PAT | 开发环境 | 90 天 |
| 部署环境访问（生产） | 生产变更 | 由人类在审批后临时授予 | prod | 单次有效 |

强制纪律：

1. **生产密钥绝不注入 staging**；staging 只用一次性、无权限的测试凭证。
2. 凭证只通过环境变量或密钥管理系统注入，**严禁写入仓库**（`.gitignore` 已屏蔽 `.env*`）。
3. 智能体按最小权限运行：测试/安全角色只读 + 可执行测试，不具备改业务代码权限。
4. 任何生产变更须经人类审批（规范 §1.2 三个介入点之一），自动化不得绕过。
5. 每次发布后核对权限清单，发现冗余授权立即回收。
