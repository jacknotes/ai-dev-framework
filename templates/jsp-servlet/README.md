# JSP + Servlet 最小示例工程（模板）

> 这是 AI 多智能体协同开发框架的**项目目录模板**，可直接复制为新项目起点。
> 技术栈：Java 17 + Servlet 6 / JSP 3.1 + Maven + Tomcat 10.1（Jakarta EE，`jakarta.servlet.*`）。
> 目录结构遵循框架规范文档 §5；**工作归属按模块（目录）切分**，遵循落地方案 §2.4。

## 为什么这个模板单独存在

JSP 是典型的"前后端边界模糊"的遗留栈：一个 `.jsp` 文件里既有 HTML，也可能有 Java 片段和 SQL。
把它硬塞进"前端智能体 + 后端智能体"的模型里，两个智能体会**互相踩同一批文件**，评审时也无法判断"这行归谁"。

所以本模板的结论是（对应 `docs/03-AI全闭环落地方案.md` §2.4）：

> **按模块（目录）切分工作归属，而不是按"前端/后端"切分。**

详细归属表见本文末尾「模块切分说明」。

## 目录结构

```
jsp-servlet/
├── .gitignore
├── README.md                    # 本文档：快速开始 + 模块切分说明
├── docs/                        # 单一事实源：需求、架构、契约
│   ├── requirements.md          # 需求 + 可测验收标准
│   ├── architecture.md          # 技术选型 + 架构图 + 模块划分
│   ├── api-spec.yaml            # Ajax 接口契约（OpenAPI 3.0.3）
│   ├── pages.md                 # 页面清单（JSP 项目的第二份契约）
│   └── runbook.md               # 运维实施文档骨架（8 小节）
├── backend/                     # 唯一的应用模块（Maven war 工程）
│   ├── pom.xml
│   ├── Dockerfile               # 多阶段构建，war → webapps/ROOT
│   └── src/
│       ├── main/java/com/example/web/
│       │   ├── HealthServlet.java        # GET /health
│       │   ├── GreetingServlet.java      # GET /api/v1/greeting
│       │   └── service/
│       │       └── GreetingService.java  # 领域逻辑（与 Servlet 分离）
│       ├── main/webapp/
│       │   ├── index.jsp                 # 首页，fetch 调 Ajax 接口
│       │   └── WEB-INF/web.xml           # 必要容器配置
│       └── test/java/com/example/web/
│           └── GreetingServiceTest.java  # JUnit 5 单测
├── deploy/
│   └── docker-compose.yml       # 隔离环境一键启动
└── scripts/                     # 框架统一命令契约（编排器只认这 5 个入口）
    ├── lint.sh
    ├── build.sh
    ├── test.sh
    ├── health.sh
    └── e2e.sh
```

> 注意与 `templates/vue-go/` 的差异：本模板**没有** `frontend/` 目录。JSP 的"前端"是
> `backend/src/main/webapp/` 下的页面与静态资源，它必须和 Java 代码一起打进同一个 war 包，**不能独立构建**。
> 这是 JSP 栈的客观事实，不是偷懒；拆成两个物理模块只会制造一个无法单独运行的半成品。

## 本地快速开始（不使用 Docker）

### 方式 A：打 war 包丢进本地 Tomcat 10.1（推荐，最贴近生产）

```bash
cd backend
mvn -B clean package
# 产物：backend/target/ROOT.war

# 复制到本地 Tomcat 10.1 的 webapps 下（Tomcat 必须是 10.1，即 Jakarta 命名空间）
cp target/ROOT.war "$CATALINA_HOME"/webapps/
"$CATALINA_HOME"/bin/startup.sh      # Windows: bin\startup.bat

# 访问
curl http://localhost:8080/health
# 浏览器打开 http://localhost:8080/index.jsp
```

> **为什么不用 `mvn tomcat7:run`？**
> `tomcat7-maven-plugin` 只支持 `javax.servlet` 命名空间，与 Servlet 6（`jakarta.servlet`）
> 二进制不兼容，跑起来必然 `ClassNotFoundException: jakarta.servlet.http.HttpServlet`。
> 这是工具链的年代问题，不是配置问题——**不要在这个方向上浪费重试轮次**。
> 需要 IDE 内热部署时，改用 `cargo-maven3-plugin`（Tomcat 10.1 容器），见方式 B。

> **容器里为什么是 `webapps/ROOT/` 目录而不是 `ROOT.war` 文件？**
> 两者等价（Tomcat 都会把 war 展开成同名目录），但**目录形态**可以让运行期根文件系统
> 保持 `read_only: true`——war 形态下 Tomcat 必须在启动时写 `webapps/` 解包，只读就会失败。
> 因此 `Dockerfile` 在**构建期**就把 war 展开，运行期只读挂载。详见 `backend/Dockerfile` 注释。

### 方式 B：cargo-maven3-plugin（IDE 内一键运行，可选）

本模板的 `pom.xml` **故意不内置**该插件（保持"最小依赖"，避免每个项目继承一个 Maven 插件版本风险）。
需要时用一次性命令行调用，不写入 pom：

```bash
cd backend
mvn -B clean package
mvn org.codehaus.cargo:cargo-maven3-plugin:1.10.15:run \
  -Dcargo.maven.containerId=tomcat10x \
  -Dcargo.maven.containerUrl=https://repo.maven.apache.org/maven2/org/apache/tomcat/tomcat/10.1.34/tomcat-10.1.34.zip \
  -Dcargo.maven.wait=true
# 监听 http://localhost:8080
```

> 版本号只是示例锚点；离线环境请先把 Tomcat 安装包放到本地仓库或改用 `containerUrl` 指向内网镜像。

### 方式 C：直接用 Docker（无需本机装 Maven/JDK）

```bash
cd backend
docker build -t jsp-servlet-demo:dev .
docker run --rm -p 8080:8080 jsp-servlet-demo:dev
curl http://localhost:8080/health
```

> Windows 下若没有 `bash`，把上面所有 `bash scripts/*.sh` 换成 Git Bash / WSL 执行；
> 脚本本身不依赖 PowerShell。

## 隔离环境一键启动（推荐，符合框架"不碰真实环境"）

```bash
cd deploy
docker compose up -d --build
curl http://localhost:8080/health          # 期望：{"status":"ok"}
# 浏览器：http://localhost:8080/           （ROOT 上下文，欢迎页 index.jsp）
docker compose down -v                     # 用完即销毁
```

隔离要点（对应框架"五重隔离"）：

| 隔离项 | 本模板怎么做的 |
|---|---|
| 网络隔离 | 独立网段 `172.35.0.0/24`（与既有模板 172.31–172.34 全部错开，可同时启动）；端口只绑 `127.0.0.1` |
| 环境隔离 | 每个容器从镜像 + IaC 全新建，`down -v` 即销毁，无落盘状态 |
| 凭证隔离 | 模板内不含任何真实凭证；需要凭证时一律由外部注入测试值 |
| 数据隔离 | 无数据库；容器 `read_only`，仅 `tmpfs` 可写，重启即清空 |
| 执行沙箱 | `read_only` + `no-new-privileges` + CPU/内存上限 + Tomcat 以非 root 运行 |

> 只开 `8080` 一个端口，是因为 JSP 应用的页面与接口**同源**——不需要 Nginx 分层。
> 这正是"前后端边界模糊"在部署形态上的体现：一个 war、一个上下文、一个端口。

## 运行测试（对应框架门禁）

框架的编排器**只认 `scripts/` 下这 5 个固定入口**（详见 `docs/04-门禁与命令契约.md` §2 与落地方案 §2.3）。
技术栈细节封装在脚本里，门禁判定只看退出码：`0` 通过，非 `0` 失败。

```bash
# 以下命令均从模板根目录 templates/jsp-servlet/ 执行
bash scripts/lint.sh         # 门禁1：静态检查（未配 checkstyle 时退化为编译检查）
bash scripts/build.sh        # 门禁2：构建
bash scripts/test.sh         # 门禁3：单元测试
bash scripts/health.sh       # 门禁4：部署后健康检查
bash scripts/e2e.sh          # 门禁5：端到端（本模板为占位，恒 0；--strict 则非 0）
```

手工等价命令：

| 门禁 | 脚本 | 等价命令 | 判定 |
|---|---|---|---|
| 静态检查 | `scripts/lint.sh` | `mvn -q -B checkstyle:check`（未配插件则 `mvn -q -B compile`） | exit 0 |
| 构建 | `scripts/build.sh` | `mvn -q -B clean package -DskipTests` | exit 0 且产出 `target/ROOT.war` |
| 单元测试 | `scripts/test.sh` | `mvn -q -B test` | exit 0，`GreetingServiceTest` 全绿 |
| 健康检查 | `scripts/health.sh` | `curl -fsS http://localhost:8080/health` | HTTP 200 且 body 含 `"status":"ok"` |
| 端到端 | `scripts/e2e.sh` | 占位 | 默认恒 0；`--strict` 时恒 1 |

> **门禁能力的诚实边界**（落地方案 §2.4 第 3 点）：JSP 遗留栈通常没有现成的 lint 与覆盖率工具。
> 本模板的门禁只承诺"**能编译 + 能启动 + 单测通过 + 健康检查通过**"，不承诺覆盖率阈值。
> 不要为了凑门禁去重构遗留系统；要提升门禁强度，应当作为独立技术债任务立项。
>
> 另：`scripts/test.sh` 会在测试跑完后校验 surefire 报告里的实际执行用例数，
> 若为 0 则判定失败——防止"测试类没被扫描到"这种假绿。

## 与框架的关系

| 框架产物 | 本模板对应 |
|---|---|
| 规范文档 §5 目录约定 | 本模板 `docs/` / `backend/` / `deploy/` / `scripts/`（无 `frontend/`，理由见上文） |
| 规范文档 §2 角色定义 | 「视图模块开发者」承接原"前端"职责，「领域模块开发者」承接原"后端"职责 |
| 落地方案 §2.4 JSP 遗留栈 | 本文「模块切分说明」+ `docs/architecture.md` §3 + `docs/pages.md` |
| 落地方案 §2.3 / 门禁契约 §2 统一命令契约 | `scripts/` 下 5 个脚本，退出码即门禁结论 |
| 规范文档 §7 / 落地方案 §7 五重隔离 | `deploy/docker-compose.yml` + `backend/Dockerfile` |
| 门禁（编译/lint/单测） | `scripts/lint.sh` / `scripts/build.sh` / `scripts/test.sh` |
| 门禁（部署健康检查） | `scripts/health.sh` + 容器 `HEALTHCHECK` |
| 单一事实源 | `docs/requirements.md`、`architecture.md`、`api-spec.yaml`、`pages.md` |
| 运维硬交付物 | `docs/runbook.md`（8 小节骨架） |

## 模块切分说明

### 为什么按目录切，而不按"前端/后端"切

1. **JSP 页面里可能直接写 Java 逻辑，物理上不存在"前端产物"。**
   `index.jsp` 编译后是 Servlet，跑在同一个 JVM、同一个 war、同一个上下文里。
   按"前端/后端"切，切的是**概念**，不是文件——两个智能体会同时需要改
   `src/main/webapp/` 和 `src/main/java/`，冲突不可避免。

2. **按"前端/后端"切会产生不可验收的任务。**
   "前端任务"在本栈里无法独立构建、独立运行、独立验收；而框架的拆解门禁要求
   **任务可独立验收**（规范 §3 阶段 2）。按目录切出的任务则可以：视图模块的产物是
   "页面能打开、Ajax 请求命中了契约里的字段"，领域模块的产物是"单测全绿、接口返回结构正确"。

3. **冲突域的边界恰好是目录。**
   `src/main/webapp/**` 与 `src/main/java/**/service|dao|model/**` 在文件系统上不相交，
   可以用工具权限（沙箱路径白名单）硬隔离，符合铁律三"最小权限靠工具隔离，而非提示词约束"。

4. **契约仍然先行。**
   切分不是为了各写各的，而是为了**并行**。两边靠两份机器可读的契约对齐：
   - `docs/api-spec.yaml`：Ajax 接口的请求/响应结构（机器可校验）
   - `docs/pages.md`：页面清单，标明每个页面调用哪个接口
   **禁止口头约定**——"我以为你会返回 `msg` 字段"这类问题必须在契约评审阶段拦下。

### 两个开发者各自负责哪些路径

| 归属 | 路径 | 职责 | 不得触碰 |
|---|---|---|---|
| **视图模块开发者**（原"前端"角色） | `backend/src/main/webapp/**`（含 `*.jsp`、`WEB-INF/web.xml`、`static/`）<br>`backend/src/main/java/com/example/web/*.java`（Servlet：Web 层适配） | 页面结构与交互、Ajax 端点、请求参数校验、JSON 序列化、错误页 | `**/service/**`、`**/dao/**`、`**/model/**`、`deploy/`、`scripts/` |
| **领域模块开发者**（原"后端"角色） | `backend/src/main/java/com/example/web/service/**`<br>`backend/src/main/java/com/example/web/dao/**`<br>`backend/src/main/java/com/example/web/model/**`<br>`backend/src/test/java/**`（针对上述层的单测） | 业务规则、数据访问、领域模型、领域层单测 | `backend/src/main/webapp/**`、Servlet 类、`deploy/`、`scripts/` |
| **架构师** | `docs/api-spec.yaml`、`docs/pages.md`、`docs/architecture.md` | 维护契约，评审任何契约变更 | 不写业务实现 |
| **运维 DevOps** | `deploy/`、`docs/runbook.md` | 编排、部署、回滚、监控 | 不改业务代码 |
| **测试 / 安全** | `tests/`（**尚未创建**，随首个 E2E 用例一并建立）、`docs/test/` | 只读代码 + 可执行测试，**无写权限** | 任何业务代码 |

两条补充规则：

- **Servlet 归视图模块，是为了让契约有唯一实现者。** Servlet 只做"翻译"：读参数 → 调 service →
  把返回对象序列化成契约规定的 JSON。业务规则一律下沉到 `service`，所以领域模块的单测不需要
  启动 Tomcat，也不 mock `HttpServletRequest`。
- **跨边界的改动走契约变更。** 任何需要同时改 `webapp/` 与 `service/` 的需求，先由架构师更新
  `api-spec.yaml` / `pages.md` 并评审通过，再拆成两个独立任务并行下发。**不许一个智能体顺手把两边都改了**
  ——那等于取消了四眼原则。

### 一个具体例子

需求：首页问候语要带用户名字。

| 步骤 | 归属 | 动作 |
|---|---|---|
| 1 | 架构师 | `api-spec.yaml` 的 `/api/v1/greeting` 增加可选 `name` 查询参数；`pages.md` 更新 `index.jsp` 的依赖说明 |
| 2 | 领域模块 | `GreetingService.greet(String name)` 重载 + 单测（含空名、非法字符） |
| 3 | 视图模块 | `GreetingServlet` 读 `name` 参数并透传；`index.jsp` 增加输入框，`encodeURIComponent` 后 fetch |
| 4 | 测试 | 独立 QA 按契约做接口测试，不读实现 |

两边**只通过契约交接**，互不看对方代码，也不需要同步"我今天改了什么"。

## 下一步

1. 改包名与 `groupId`/`artifactId`（`com.example` → 你的组织名）。
2. 按真实需求重写 `docs/requirements.md`，再让架构师补 `api-spec.yaml` 与 `pages.md`。
3. 复制本模板到新仓库后，先跑通 `scripts/lint.sh` → `build.sh` → `test.sh` 三连，确认门禁可用。
4. JSP 遗留项目通常缺测试，**先把 `service` 层的单测补起来**，这是性价比最高的一步。

> 完整规范见 `docs/01-开发规范文档.md`；JSP 栈的处理结论见 `docs/03-AI全闭环落地方案.md` §2.4。
