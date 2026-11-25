# 需求文档 — JSP + Servlet 最小示例工程

> 本文件演示框架规范要求的"含可测验收标准的需求文档"格式。
> 注意：JSP 项目的功能常常横跨 `webapp/`（页面）与 `service/`（领域）两层，
> 因此每条需求后面都标注了**归属模块**，便于按目录拆任务。

## 1. 背景与目标

提供一个 Java 17 + Servlet 6 / JSP 3.1 的最小可运行示例，作为 AI 多智能体协同开发框架
在**遗留栈（JSP）**上的 POC 起点。目标不是演示 JSP 的全部能力，而是演示：

1. 一个 war 工程如何在隔离环境中构建、启动、被健康检查；
2. 模糊的前后端边界如何用**目录切分 + 双契约（API Spec + 页面清单）**管理；
3. 统一命令契约（`scripts/` 五入口）如何在非 Node/Go 栈上落地。

## 2. 用户故事

- 作为**用户**，我希望打开首页就能看到后端返回的问候语，以确认页面与接口已联通。
- 作为**用户**，我希望接口失败时页面给出可读的提示，而不是白屏或堆栈。
- 作为**运维**，我希望有一个不依赖页面的健康检查端点，以便探针和回滚判定使用。
- 作为**开发者**，我希望业务逻辑不在 Servlet 里，以便不启动容器就能写单测。
- 作为**评审/测试智能体**，我希望有机器可读的接口契约和页面清单，以便独立验证而不读实现。

## 3. 功能需求

| 编号 | 需求 | 优先级 | 验收标准 | 归属模块 |
|---|---|---|---|---|
| FR-1 | 健康检查接口 | P0 | `GET /health` 返回 HTTP 200，`Content-Type: application/json`，body 严格为 `{"status":"ok"}`（字段名、取值均不得变化，供探针解析） | 视图模块（`HealthServlet`） |
| FR-2 | 问候接口 | P0 | `GET /api/v1/greeting` 返回 HTTP 200，JSON 含且仅含契约中定义的 `message`、`time` 两字段；`message` 取值为 `Hello from JSP backend`；`time` 为 ISO-8601 带时区偏移的时间串（如 `2026-11-25T20:21:41+08:00`），可被 `OffsetDateTime.parse` 解析 | 视图模块（Servlet）+ 领域模块（`GreetingService`） |
| FR-3 | 首页展示问候语 | P0 | 访问 `/` 或 `/index.jsp` 返回 HTTP 200 的 HTML；页面加载完成后经 `fetch` 请求 `/api/v1/greeting`，将 `message` 渲染到 `#greeting` 元素；浏览器控制台无未捕获异常 | 视图模块（`index.jsp`） |
| FR-4 | 前端异常处理 | P1 | 人为令接口返回非 2xx（或在网络面板断网）时，`#greeting` 区域显示固定文案 `问候语加载失败`，且页面其余部分不白屏、不弹出原始堆栈信息 | 视图模块（`index.jsp`） |
| FR-5 | 领域逻辑与 Web 层解耦 | P1 | `GreetingService` 不 import 任何 `jakarta.servlet.*`；`GreetingServiceTest` 可在无 Tomcat、无 Spring 的情况下 `mvn test` 通过 | 领域模块 |
| FR-6 | 字符编码一致 | P1 | 接口响应与页面响应均为 UTF-8；页面内的中文文案在浏览器中不乱码（`Content-Type` 含 `charset=UTF-8`） | 视图模块 |
| FR-7 | 容器可运行 | P0 | `docker compose up -d --build` 后，容器 `HEALTHCHECK` 在 90 秒内转为 `healthy`；`/health` 可访问；容器内进程 UID 不为 0 | 运维（`Dockerfile` / compose） |
| FR-8 | 统一命令契约可用 | P0 | `scripts/` 下 5 个脚本均可执行；`lint.sh`、`build.sh`、`test.sh` 在依赖齐备时 exit 0；工具缺失时打印明确中文提示并以非 0 退出（`e2e.sh` 例外，占位恒 0） | 运维 + 两个开发模块 |

## 4. 非功能需求

| 编号 | 类别 | 要求 | 验收方式 |
|---|---|---|---|
| NFR-1 | 可维护性 | 业务规则只存在于 `service` 层；Servlet 不含业务分支 | 代码评审：`GreetingServlet#doGet` 方法体 < 25 个有效代码行，且唯一的分支是异常兜底（无业务条件判断） |
| NFR-2 | 可测试性 | `service` 层的公开方法均有单测覆盖（本示例 7 个用例覆盖正常/边界/异常路径） | `mvn test` 全绿即可判定；**不设覆盖率阈值**（未接 JaCoCo，见 `architecture.md` §7） |
| NFR-3 | 安全 | 容器非 root 运行；`read_only` 根文件系统；`no-new-privileges`；响应不暴露堆栈 | 检查 `docker inspect` 的 `Config.User` 与 compose 的安全选项 |
| NFR-4 | 启动性能 | 冷启动到 `/health` 可用 ≤ 60 秒（隔离环境，1 vCPU / 512M，与 compose 限额一致） | `time` 计时 + 探针日志 |
| NFR-5 | 体积 | 运行镜像基于 `tomcat:10.1-jdk17-temurin`，不额外安装 JDK | `docker images` 查看 |
| NFR-6 | 兼容性 | 仅支持 Jakarta EE 9+ 命名空间（`jakarta.servlet.*`），不兼容 `javax.servlet.*` | 编译期即可发现 |

## 5. 范围之外（本期明确不做）

- 不做用户登录、会话管理与权限控制。
- 不接数据库（无 DAO 实作，仅保留目录与包结构占位）。
- 不做国际化（i18n）与多主题。
- 不接入覆盖率门禁与 Checkstyle 规则集（属于后续技术债，见 `architecture.md` §7）。
- 不提供 `tests/` 下的集成测试实作（模板预留位置）。

## 6. 澄清问题与假设

| 问题 | 当前假设 | 影响 |
|---|---|---|
| Tomcat 用哪个大版本？ | 10.1（Servlet 6.0 / JSP 3.1） | 决定 `jakarta.*` 命名空间；换 9.x 需退回 `javax.*` |
| 是否需要热部署？ | POC 阶段不需要，改代码重新 `package` 即可 | 因此不内置 `tomcat7-maven-plugin`（不兼容）与 cargo 插件 |
| 应用上下文路径？ | 部署为 `ROOT`（`/`） | 无需改代码：`index.jsp` 用 EL 读取 `pageContext.request.contextPath` 拼接口地址，改成 `/app` 也能直接工作 |
| 时间字段时区？ | 服务器默认时区，输出带偏移的 ISO-8601 | 跨时区部署时前端只做展示，不做时区换算 |
| 端口？ | 8080 | `scripts/health.sh` 支持 `PORT` 环境变量覆盖 |

## 7. 验收清单（对应框架门禁）

- [ ] `bash scripts/lint.sh` exit 0
- [ ] `bash scripts/build.sh` exit 0，且 `backend/target/ROOT.war` 存在
- [ ] `bash scripts/test.sh` exit 0，`GreetingServiceTest` 全部通过
- [ ] 隔离环境 `up` 后 `bash scripts/health.sh` exit 0
- [ ] `docs/api-spec.yaml` 的响应示例与实际返回一致（字段名与示例值）
- [ ] `docs/pages.md` 中列出的页面均存在，且依赖接口均在 `api-spec.yaml` 中有定义
