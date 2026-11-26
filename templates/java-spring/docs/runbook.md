# 运维实施文档（Runbook）— Java + Spring Boot 最小示例工程

> 版本：v0.1.0　｜　阶段：部署（流水线阶段 8）　｜　负责人：运维 DevOps 智能体
> 定位：**可复用骨架**。本项目仅为模板，落地到真实项目时按 §1 的占位符替换后再执行。
> 约定：所有命令在仓库根目录 `templates/java-spring/` 下执行；`$TAG` 为镜像标签（建议用 `git rev-parse --short HEAD`）。

## 1. 环境架构

| 环境 | 用途 | 地址 | 数据 | 凭证 | 生命周期 |
|---|---|---|---|---|---|
| dev | 开发自测 | 前端 `:3000`、后端 `:8000` | 无 | 无 | 常驻 |
| staging | 集成/安全/性能测试 | 前端 `:80`、后端 `:8000` | 合成数据 | 测试专用 | 一次性，用完销毁 |
| prod | 生产 | 由实际平台决定 | 真实数据 | 生产密钥（独立） | 长驻 |

**拓扑**（staging 隔离沙箱）：

```
宿主机
└── Docker 网络 java-spring-sandbox（172.33.0.0/24，端口只绑 127.0.0.1）
    ├── frontend  Nginx :80   → 静态资源 + /api 反代
    └── backend   Spring Boot :8000 → /health、/api/v1/greeting
```

**硬性约束**：staging 与 prod 之间网络不通、凭证不同、数据不同源（对齐规范 §7.2 五重隔离）。

## 2. 依赖与前置条件

| 依赖 | 版本要求 | 校验命令 | 缺失时 |
|---|---|---|---|
| JDK | 21+ | `java -version` | 安装 Temurin 21，或改用 Docker 构建 |
| Maven | 3.9+ | `mvn -v` | 安装 Maven 3.9，或改用 Docker 构建 |
| Node.js | 20+ | `node -v` | 安装 Node 20 LTS |
| npm | 10+ | `npm -v` | 随 Node 安装 |
| Docker | 24+ | `docker version` | 安装 Docker Desktop / Engine |
| Docker Compose | v2 | `docker compose version` | 升级到 Compose v2（`docker-compose` 旧版命令不兼容） |
| curl | 任意 | `curl --version` | `scripts/health.sh` 依赖，用包管理器安装 |

**资源建议**：构建机 ≥ 2 CPU / 4G 内存（Maven + npm 同时构建）；运行机 ≥ 1 CPU / 1G。

**网络与端口**：需能访问 Maven Central 与 npm registry（构建期）；运行期沙箱网络 `internal` 不出网。宿主机端口 80、8000 不得被占用。

## 3. 构建步骤

```bash
# 0) 前置检查（任一失败即停止）
java -version && mvn -v && node -v && docker compose version

# 1) 质量门禁：lint → 单测（失败即中止，不要继续构建）
bash scripts/lint.sh
bash scripts/test.sh

# 2) 构建产物
bash scripts/build.sh
#   后端产物：backend/target/demo-0.1.0.jar
#   前端产物：frontend/dist/

# 3) 构建镜像（带版本标签，便于回滚）
TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
docker build -t java-spring-backend:$TAG ./backend
docker build -t java-spring-frontend:$TAG ./frontend

# 4) 产物校验（可选）
docker image inspect java-spring-backend:$TAG --format '{{.Config.User}} {{.Config.ExposedPorts}}'
# 期望：app map[8000/tcp]（非 root 用户）
```

**注意**：`scripts/build.sh` 会跳过测试（`-DskipTests`），单测必须在步骤 1 单独且先行执行。

## 4. 部署步骤（含回滚）

### 4.1 首次部署（staging）

```bash
cd deploy
docker compose up -d --build

# 等待就绪（后端 JVM 冷启动约 20–40s）
for i in $(seq 1 30); do
  curl -fsS http://localhost:8000/health && break
  sleep 2
done

# 验收
curl -fsS http://localhost:8000/api/v1/greeting   # 应含 "Hello from Java backend"
curl -fsS http://localhost/health                  # 经 Nginx 透传
docker compose ps                                  # 两个服务均为 healthy
```

### 4.2 版本升级（灰度思路）

```bash
# 1) 拉取/构建新版本镜像并打标签
NEW_TAG=$(git rev-parse --short HEAD)
docker build -t java-spring-backend:$NEW_TAG ./backend

# 2) 仅更新后端，观察健康状态
cd deploy
docker compose up -d --no-deps --build backend
docker compose ps backend

# 3) 观察 10 分钟错误率与延迟（见 §5），无异常再更新前端
docker compose up -d --no-deps --build frontend
```

### 4.3 回滚（目标：5 分钟内恢复）

**触发条件**：健康检查连续失败、错误率 > 5%、P95 延迟翻倍、关键功能不可用。

```bash
# 方案 A：回滚到上一个已知良好镜像标签（推荐）
cd deploy
PREV_TAG=<上一个稳定版本 sha>
docker tag java-spring-backend:$PREV_TAG java-spring-backend:current
docker compose up -d --no-deps --force-recreate backend
bash ../scripts/health.sh          # 必须返回 200

# 方案 B：整体回退到上一 commit 并重建（环境完全可复现时使用）
git checkout <上一个稳定 commit>
cd deploy && docker compose up -d --build
```

**回滚后动作**：保留现场（`docker compose logs --tail=500 > /tmp/incident-$(date +%s).log`）、记录时间线、在 `CHANGELOG.md` 标注、48h 内补根因分析。

**回滚验证清单**：
- [ ] `scripts/health.sh` 退出码 0
- [ ] `docker compose ps` 全部 healthy
- [ ] 前端首页可打开且显示问候语
- [ ] 日志无 ERROR 堆栈新增

### 4.4 销毁隔离环境

```bash
cd deploy && docker compose down -v   # -v 连同网络一并清理，符合"用完即弃"
```

## 5. 健康检查与监控指标

### 5.1 探针

| 探针 | 端点 | 期望 | 用途 |
|---|---|---|---|
| 后端存活 | `GET :8000/health` | 200 + `{"status":"ok"}` | Docker HEALTHCHECK、部署门禁、`scripts/health.sh` |
| 前端存活 | `GET :80/` | 200 | 前端容器 HEALTHCHECK |
| 前端透传 | `GET :80/health` | 200 | 验证 Nginx → 后端链路 |

手动检查：

```bash
bash scripts/health.sh                 # 默认 8000
PORT=80 bash scripts/health.sh         # 经前端 Nginx
docker inspect --format '{{.State.Health.Status}}' java-spring-backend
```

### 5.2 关键指标与阈值

| 指标 | 采集方式 | 告警阈值（建议） |
|---|---|---|
| 请求成功率 | Nginx access log / APM | < 99% 持续 5 分钟 |
| P95 延迟 | APM 或压测报告 | `/health` > 50ms、`/api/v1/greeting` > 100ms |
| 容器 CPU | `docker stats` | 持续 > 80% 限额（0.5 core） |
| 容器内存 | `docker stats` | 持续 > 85% 限额（512M），警惕 OOMKilled |
| JVM 堆使用 | JVM 指标（如接入 Micrometer） | 老年代 > 85% 且 Full GC 频繁 |
| 重启次数 | `docker inspect .RestartCount` | 5 分钟内 ≥ 2 次 |
| 健康状态 | `docker compose ps` | 任意容器 `unhealthy` |

快速采集：

```bash
docker stats --no-stream
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs --tail=200 backend | grep -iE 'error|exception'
```

## 6. 故障排查手册

| 现象 | 可能原因 | 排查命令 | 处置 |
|---|---|---|---|
| 容器反复重启、`unhealthy` | JVM 启动超时 / 内存不足 | `docker logs java-spring-backend --tail=200` | 调大内存限额或 `start_period`；确认 `PORT` 与 `EXPOSE` 一致 |
| `curl /health` 连接拒绝 | 端口未映射 / 服务未起 | `docker compose ps`、`docker port java-spring-backend` | 检查 `ports` 映射与 `PORT` 环境变量 |
| 容器启动即退出、日志提示 `Read-only file system` | 只读根文件系统缺少可写目录 | `docker logs` 报错路径 | 为对应路径补 `tmpfs` 挂载（后端 `/tmp`，前端 `/var/cache/nginx`、`/var/run`） |
| 前端 502 Bad Gateway | 后端未就绪或服务名不符 | `docker compose logs frontend` | 确认 nginx.conf 中 `proxy_pass http://backend:8000` 与 compose 服务名一致 |
| 前端页面空白 | 构建产物缺失 / 路由回落失败 | `docker exec java-spring-frontend ls /usr/share/nginx/html` | 重新 `scripts/build.sh` 并重建镜像；确认 `try_files ... /index.html` |
| 前端请求 404（`/api/v1/greeting`） | 反代路径或后端路径不一致 | `curl -v http://localhost/api/v1/greeting` | 对齐 `api-spec.yaml`、Nginx `location /api/`、Controller 映射 |
| 单测失败 `No tests found` / `MockMvc` 注入失败 | 测试类包路径或注解错误 | `mvn -B test -pl .` | 确认 `@WebMvcTest(GreetingController.class)` 与类路径一致 |
| `mvn` 命令不存在 | 未安装 Maven | `mvn -v` | 见 §2；或全部改用 Docker 构建 |
| 依赖下载超时 | 构建机网络受限 | `mvn -B -U package` | 配置内网镜像源；或使用预置依赖缓存 |
| 80 端口被占用 | 宿主机已有 Web 服务 | `netstat -ano \| findstr :80`（Windows）/ `ss -lntp`（Linux） | 改映射端口，如 `"8080:80"` |

**通用四步法**：① 看现象与时间点 → ② 看容器状态与健康 → ③ 看日志（按 ERROR/Exception 过滤）→ ④ 最小复现（直接 curl 后端绕开前端）。

## 7. 备份与恢复

> 本模板无状态、无数据库，因此"备份"的对象是**可复现资产**而非数据。

| 对象 | 方式 | 频率 | 保留 |
|---|---|---|---|
| 源码与文档 | Git（远端仓库） | 每次提交 | 永久 |
| 镜像 | 镜像仓库按 `$TAG` 保留最近 10 个版本 | 每次发布 | 90 天 |
| 部署配置 | `deploy/docker-compose.yml` 纳入 Git | 变更即提交 | 永久 |
| 运行日志 | 容器日志导出到对象存储（可选） | 每日 | 30 天 |

```bash
# 导出当前运行的镜像清单，便于灾备重建
docker compose -f deploy/docker-compose.yml images > /tmp/images-$(date +%F).txt

# 导出容器日志
docker logs java-spring-backend > /tmp/backend-$(date +%F).log 2>&1
```

**恢复流程**：克隆仓库 → 检出目标 commit/tag → `bash scripts/build.sh` → `cd deploy && docker compose up -d --build` → `bash scripts/health.sh` 验证。**目标 RTO ≤ 15 分钟，RPO = 0（无状态，无数据丢失风险）。**

**若未来引入数据库**：必须补充①每日全量 + 每小时增量备份，②备份加密与异地存放，③每季度一次恢复演练并留存记录。此三项为上线前置条件。

## 8. 凭证与权限清单

| 凭证/权限 | 用途 | 存放位置 | 轮换周期 | 最小权限要求 |
|---|---|---|---|---|
| Git 只读令牌 | CI 拉取代码 | CI Secret | 90 天 | 仅目标仓库读 |
| 镜像仓库推送令牌 | 推送 `$TAG` 镜像 | CI Secret | 90 天 | 仅目标仓库写 |
| staging 部署凭证 | 部署隔离环境 | CI Environment Secret | 90 天 | 仅 staging 命名空间 |
| 生产部署凭证 | 生产发布 | 审批后临时下发 | 单次有效 | 仅生产命名空间，最小化 |
| 宿主机 SSH（如使用） | 远程运维 | 堡垒机/密钥库 | 180 天 | 禁 root 登录，仅跳板 |

**本模板明确不包含**：数据库密码、第三方支付/短信密钥、任何生产业务密钥。模板中的 `ENV=staging` 仅为环境标识，不是凭证。

**权限红线**：
1. 生产凭证绝不注入 staging/dev；测试用合成凭证须显式标注 `test_only_`。
2. 禁止把密钥写入代码、`docker-compose.yml`、镜像层或 Git 历史。
3. 人类审批点（架构评审、生产发布）不得由自动化绕过（对齐规范 §1.2）。
4. 人员离场/角色变更须在 24h 内回收对应凭证。
