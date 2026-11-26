# 测试环境部署方法（deploy）

> 本目录是"测试环境怎么装"的**唯一方法入口**。
> 目标：任何使用者（含 AI 智能体）读完本文，就能在**一次确认**后，
> 用一条命令把测试环境所需资源装好、启动、并跑通五道门禁。

---

## 1. 先确认，再安装（约定，必须先遵守）

**这条约定对人和 AI 都生效：**

1. **读到本文时，先不要擅自安装。** 安装会创建虚拟环境、安装依赖、启动进程/容器，
   属于对机器有副作用的操作，必须先征得用户同意。
2. 向用户说明要做什么、影响范围、预计耗时，然后问：
   > "检测到需要安装测试环境。是否现在一键安装？"
3. **用户同意后**，再执行下面的一键命令。
4. 用户拒绝时，停止，不安装、不启动。

> 为什么要这一步：安装不是只读操作，且不同机器工具链不同（有没有 Docker、有没有 Python）。
> 先确认能避免"AI 擅自装一堆东西 / 擅自起服务"。

---

## 2. 一键安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\install.ps1
```

这条命令按顺序做 4 件事（**只编排，不复刻既有脚本**）：

```
[1/4] 探测工具链          docker / bash / python
[2/4] 自动选择后端        有 Docker → docker；无 → local（本机闭环）
[3/4] 装资源 + 启动        venv + 前后端依赖 + 起服务（或 docker compose build/up）
[4/4] 五道门禁            lint → build → test → e2e → health，退出码即结论
```

**退出码：0 = 资源就绪且五道门禁全绿；非 0 = 安装或某道门禁失败。**

### 常用参数

| 参数 | 取值 | 说明 |
|---|---|---|
| `-Stack` | `react-python`(默认) / `vue-go` / `java-spring` / `dotnet` / `jsp-servlet` | 选择技术栈 |
| `-Backend` | `auto`(默认) / `docker` / `local` | 强制指定后端，`auto` 自动探测 |
| `-SkipVerify` | 开关 | 只装资源并启动，跳过门禁 |

示例：

```powershell
# 指定技术栈
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\install.ps1 -Stack vue-go

# 强制本机方案（无 Docker / 无 WSL）
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\install.ps1 -Backend local

# 只装资源不跑门禁（后续单独验证）
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\install.ps1 -SkipVerify
```

---

## 3. 两种后端（装什么、装在哪）

| 维度 | Docker 方案（推荐） | 本机方案（降级） |
|---|---|---|
| 前置 | Docker Desktop + WSL2 | Git Bash + Python 3.10+ |
| 环境隔离 | 一次性容器 + 独立网段 | 一次性 `sandbox/` 目录 + 独立 venv |
| 网络 | 服务端口只绑 `127.0.0.1`（本机可访问，局域网不可达） | 只监听 `127.0.0.1` |
| 数据 | 只读根文件系统 + tmpfs，不落盘 | 数据全在 `sandbox/data`，`down` 即删 |
| 资源限额 | CPU/内存硬限额 | 无法限 CPU/内存 |
| 防恶意代码 | ✅ 容器边界 | ❌ 不防（只防污染、误连真实服务） |

**结论：有 Docker 一律优先 Docker；本机方案只用于"暂时没有 Docker"的场景。**

> `install.ps1 -Backend auto` 会自动判断：`docker version` 引擎就绪 → docker，否则 → local。
> 首次配置 Docker 加速器需要单独执行一次（会重启 Docker Desktop）：
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\setup.ps1
> ```

---

## 4. 分步手动执行（不想走一键时）

### Docker 方案

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\setup.ps1     # 首次：加速器 + WSL2 校验（需已重启）
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\up.ps1        # 构建 + 启动
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\verify.ps1    # 容器内五道门禁
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\down.ps1      # 销毁
```

### 本机方案

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\local\setup.ps1      # 一次性：venv + 依赖
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\local\up.ps1         # 启动（backend 18080 / frontend 13000）
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\local\verify.ps1     # 本机五道门禁
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\local\down.ps1       # 销毁
```

> 详细说明：`deploy/docker/README.md`、`deploy/local/README.md`。

---

## 5. 五道门禁（装完必须跑）

| 门禁 | 脚本 | 通过条件 |
|---|---|---|
| 静态检查 | `scripts/lint.sh` | `exit 0`（前端 ESLint + 后端 ruff） |
| 构建 | `scripts/build.sh` | `exit 0`（前端 tsc+vite + 后端 compileall） |
| 单元测试 | `scripts/test.sh` | `exit 0`（前端 Vitest 覆盖率 80% + 后端 pytest） |
| e2e | `scripts/e2e.sh` | `exit 0`（无用例时明确跳过，见脚本注释） |
| 健康检查 | `scripts/health.sh` | `exit 0`（curl 后端 /health 重试） |

**门禁由真实退出码判定，绝不允许 `|| true` / `; exit 0` 式假通过。**

---

## 6. 环境销毁（用完即毁）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\docker\down.ps1      # Docker
powershell -NoProfile -ExecutionPolicy Bypass -File deploy\local\down.ps1       # 本机
```

---

## 7. 目录清单

```
deploy/
├── README.md            # 本文件：部署方法（先确认 → 一键安装）
├── install.ps1          # 一键安装入口（探测 → 选后端 → 装资源 → 五道门禁）
├── docker-compose.yml   # 通用 Docker 编排（示例/旧版）
├── Dockerfile.backend
├── docker/              # Docker 方案（推荐，真沙箱）
│   ├── README.md  setup.ps1  up.ps1  verify.ps1  down.ps1  daemon.json
├── local/               # 本机方案（无 Docker 降级，只绑 127.0.0.1）
│   ├── README.md  setup.ps1  up.ps1  verify.ps1  down.ps1
└── mocks/               # WireMock 契约 mock（替代外部依赖）
```
