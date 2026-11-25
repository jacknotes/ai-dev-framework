# Java + Spring Boot 最小示例工程（模板）

> AI 多智能体协同开发框架的**项目目录模板**，可复制为新项目起点，目录结构遵循框架规范 §5。
> 技术栈：后端 Spring Boot 3.3 + Java 21 + Maven，前端 React 18 + TypeScript + Vite。

## 目录结构

```
java-spring/
├── .gitignore
├── docs/                     # 需求、架构、API 契约、运维手册
│   ├── requirements.md
│   ├── architecture.md
│   ├── api-spec.yaml
│   └── runbook.md
├── frontend/                 # React 18 + TypeScript + Vite
│   ├── src/                  # 组件 + API 客户端 + 单测
│   ├── Dockerfile
│   ├── nginx.conf
│   └── package.json
├── backend/                  # Spring Boot 3.3 + Java 21
│   ├── src/main/java/com/example/demo/
│   │   ├── DemoApplication.java      # 启动类
│   │   └── api/GreetingController.java
│   ├── src/test/java/com/example/demo/api/
│   │   └── GreetingControllerTest.java
│   ├── Dockerfile
│   └── pom.xml
├── deploy/
│   └── docker-compose.yml    # 隔离环境一键启动
└── scripts/                  # 统一命令契约（门禁入口）
    ├── lint.sh
    ├── build.sh
    ├── test.sh
    ├── health.sh
    └── e2e.sh
```

## 本地快速开始（不使用 Docker）

**后端（终端 1）：**
```bash
cd backend
mvn -B package -DskipTests
java -jar target/demo-0.1.0.jar
# 监听 http://localhost:8000（可用 PORT 环境变量覆盖）
```

也可以用 `mvn -B spring-boot:run` 直接跑，免去手动 `java -jar`。

**前端（终端 2）：**
```bash
cd frontend
npm install
npm run dev
# 访问 http://localhost:3000（Vite 已代理 /api、/health → 8000）
```

验证联通：
```bash
curl http://localhost:8000/health            # {"status":"ok"}
curl http://localhost:8000/api/v1/greeting   # {"message":"Hello from Java backend","time":"..."}
```

## 隔离环境一键启动（推荐，符合框架"不碰真实环境"）

```bash
cd deploy
docker compose up -d --build
curl http://localhost:8000/health   # 后端健康检查
# 前端: http://localhost:80
docker compose down -v              # 用完即销毁
```

沙箱网络为 `172.33.0.0/24`，`internal: true` 不出网；容器非 root、根文件系统只读、`no-new-privileges`，并带资源限额与健康检查。

## 运行测试（对应框架门禁）

统一入口是根目录的 `scripts/` 五门禁（`lint` / `build` / `test` / `health` / `e2e`）：

```bash
bash scripts/lint.sh && bash scripts/build.sh && bash scripts/test.sh
```

> 可复现的完整构建/部署/故障排查命令见 [`docs/runbook.md`](docs/runbook.md)，这里是唯一命令来源；本节只作快速起步。

## 统一命令契约（scripts/）

流水线中的门禁统一通过 `scripts/` 调用，避免每个智能体各自拼命令。
**约定：退出码 0 = 通过，非 0 = 失败**，失败时脚本会打印明确原因。
完整契约见框架文档 `docs/04-门禁与命令契约.md`（五入口、幂等、不依赖交互、失败原因可粘贴）。

| 脚本 | 做什么 | 对应门禁 |
|---|---|---|
| `bash scripts/lint.sh` | 后端格式/静态检查（`spotless:check` > `checkstyle:check` > 退化为 `compile`）、前端 `npm run lint` | Lint/格式：无 error 级告警 |
| `bash scripts/build.sh` | 后端 `mvn -q -B package -DskipTests`、前端 `npm run build` | 编译/构建：前端 build + 后端 build 成功 |
| `bash scripts/test.sh` | 后端 `mvn -q -B test`、前端 `npm test` | 单元测试：全通过、覆盖率达标 |
| `bash scripts/health.sh` | `curl http://localhost:${PORT:-8000}/health` | 部署健康检查：存活探针通过 |
| `bash scripts/e2e.sh` | 端到端测试占位（当前输出说明并成功退出；接入用例后改由结果决定退出码） | 功能/集成测试：用例全通过（后续接入） |

```bash
bash scripts/lint.sh                 # 依次执行
bash scripts/health.sh               # 服务需先启动
PORT=80 bash scripts/health.sh       # 经前端 Nginx 检查
```

> 工具未安装时脚本会明确提示（例如"未检测到 mvn，请安装 Maven 3.9+"）并以非 0 退出，不会静默通过。
> 脚本在 Windows 上请通过 Git Bash / WSL 执行；首次提交建议执行 `git add --chmod=+x scripts/*.sh` 记录可执行位。

## 与框架的关系

| 框架产物 | 本模板对应 |
|---|---|
| 规范文档 §5 目录约定 | 本模板目录结构 |
| 隔离环境五重隔离（§7.2） | `deploy/docker-compose.yml`（独立网段 + internal 网络 + 非 root + 只读根） |
| 门禁（编译/lint/单测） | `scripts/build.sh` / `scripts/lint.sh` / `scripts/test.sh` |
| 部署健康检查门禁 | `scripts/health.sh` + 容器 HEALTHCHECK |
| 契约一致性检查（阶段 1） | `docs/api-spec.yaml` ↔ `GreetingController` ↔ `frontend/src/api.ts` |
| 单一事实源 | `docs/` 下的需求/架构/契约/运维文档 |
| 运维 runbook 交付物（阶段 8） | `docs/runbook.md`（8 小节骨架，可直接复用） |
| 测试/安全/性能测试（阶段 5–7） | 预留 `scripts/e2e.sh` 与 `tests/` 扩展位 |

## 说明

- 示例只返回内存数据，无数据库、无鉴权，便于聚焦"流水线是否跑通"。
- 接口契约以 `docs/api-spec.yaml` 为准，改字段先改契约。
- 端口 8000（后端）/ 80（前端容器）、3000（前端 dev），与另两个模板保持一致。
