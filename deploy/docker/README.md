# Docker 隔离测试环境（推荐方案）

> 适用：已安装 Docker Desktop + WSL2 的 Windows 机器。
> 这是**首选的隔离方案**——五重隔离全部由容器运行时强制执行，
> 不依赖"进程自觉"，也不依赖宿主机工具链。

---

## 1. 前置条件（缺一不可）

| 项 | 要求 | 校验命令 |
|---|---|---|
| Windows | Win10 2004+ / Win11 | `winver` |
| WSL2 | 已启用并**重启过** | `wsl --version` |
| 虚拟化 | BIOS 开启 VT-x/AMD-V | 任务管理器 → 性能 → 虚拟化：已启用 |
| Docker Desktop | ≥ 4.x，后端选 **WSL2** | `docker version` |
| 磁盘 | ≥ 20 GB 可用 | — |

> **最常见的坑**：`VirtualMachinePlatform` 显示 Enabled，但没重启。
> 此时 `vmcompute.exe` 不存在，Docker engine 会返回 500。
> `setup.ps1` 会先检查这一项，不满足就明确报错而不是让你瞎试。

---

## 2. 首次配置（重启后执行一次）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/setup.ps1
```

它做五件事：

1. 校验 `vmcompute.exe` 是否存在（判断是否真的重启过）
2. 把默认 WSL 版本设为 2
3. 写入 Docker 镜像加速器到 `%USERPROFILE%\.docker\daemon.json`
4. 重启 Docker Desktop 并等待引擎就绪
5. **真实拉取一个镜像**验证加速器有效（不拉成功就报错，不假装成功）

### 为什么必须配镜像加速器

本机实测 `registry-1.docker.io` **直连超时**。不配加速器，
`docker compose build` 会卡在拉 `node:20-alpine`、`python:3.12-slim`。

已实测可用的源：

| 源 | 状态 |
|---|---|
| `https://docker.1panel.live` | ✅ 默认使用，实测 200 |
| `https://docker.m.daocloud.io` | ✅ 可达（401 属正常，需认证头） |
| `https://hub.rat.dev` | ✅ 可达 |

换源：`-Mirror https://docker.m.daocloud.io`

---

## 3. 日常使用

```powershell
# 启动（构建 + 起服务 + 等 healthy）
powershell -File deploy/docker/up.ps1

# 在容器内跑五道门禁（与 CI 同一口径）
powershell -File deploy/docker/verify.ps1

# 销毁（容器/网络/卷/镜像全清）
powershell -File deploy/docker/down.ps1
```

切换模板：`-Template vue-go`。

---

## 4. 这套环境的隔离强度（对比本机方案）

| 隔离维度 | Docker 方案 | 本机方案（deploy/local） |
|---|---|---|
| 网络 | **`internal: true`，容器无法访问外网**，独立网段 172.32 | 只绑 127.0.0.1，仍可访问外网 |
| 数据 | 只读根文件系统 + tmpfs，**物理上无法持久化** | 目录可删，但进程能写任意路径 |
| 凭证 | 容器内只有显式注入的测试变量 | 同上，但无法阻止读宿主机环境变量 |
| 沙箱 | `read_only` + `no-new-privileges` + CPU/内存硬限额 | **无法限 CPU/内存** |
| 一次性 | `down -v` 连卷一起删 | 删目录 + 杀进程 |
| 防恶意代码 | ✅ 容器边界 | ❌ **不防** |

**结论：Docker 方案是真正的沙箱；本机方案只是"不污染环境"。**
有 Docker 时一律优先用它。

---

## 5. 五道门禁怎么在容器里跑

```
gates 容器（node:20-bookworm-slim + python3）
  ├─ bash scripts/lint.sh    → 前端 ESLint + 后端 ruff
  ├─ bash scripts/build.sh   → 前端 tsc+vite + 后端 compileall
  ├─ bash scripts/test.sh    → 前端 Vitest(80%覆盖) + 后端 pytest
  ├─ bash scripts/e2e.sh     → 无 *.spec.* 用例时明确跳过
  └─ HEALTH_HOST=backend bash scripts/health.sh  → 走容器网络访问 backend
```

为什么健康检查要单独注入 `HEALTH_HOST=backend`：
在容器网络里，后端的主机名是服务名 `backend`，不是 `localhost`。
用 `localhost` 会连到 gates 容器自己，产生**假失败**。

**为什么门禁要跑在容器里而不是宿主机**：宿主机 Node/Python 版本与
容器内的可能不同，"本地过、容器红"是典型的口径不一致问题。

### 依赖如何满足（沙箱没有外网）

`internal: true` 意味着容器**无法联网**，所以容器内 `npm install` 必然失败
（实测报 `EAI_AGAIN`）。方案：

1. **构建期**（有网）把 `frontend/`、`backend/` 依赖装进镜像：
   前端落到 `/opt/frontend-deps/node_modules`，后端装进系统 Python。
2. **运行期** entrypoint 把依赖从镜像播种到**命名卷**
   `frontend-node-modules`（首次挂载为空），写 `.seed-complete` 标记，
   之后启动秒进。

> 为什么不直接 cp 到源码目录的 bind mount：
> 238 个包中途复制失败会留下半成品 node_modules，
> 表现为 `eslint: not found`，且无法自愈（实测踩过，只到位 40 个包）。
> 命名卷 + 完成标记是幂等且可恢复的。

---

## 6. 隔离强度实测

在本机用真实 Docker 验证（非理论推导）：

| 验证项 | 命令 | 实测结果 |
|---|---|---|
| 外网阻断（DNS） | `getent hosts registry.npmjs.org` | `DNS_FAIL` |
| 外网阻断（直连 IP） | `curl https://1.1.1.1` | `egress=000` |
| 内网互通 | `curl http://backend:8000/health` | `200` |
| 只读根文件系统 | `touch /etc/test` | `Read-only file system` |
| 非 root 运行 | `id` | `uid=100(app)` |
| 销毁彻底性 | `down.ps1` 后断言 | 容器/网络/卷/镜像 **全部为 0** |

门禁真实性（负向验证）：故意注入语法错误后，
`build.sh` 与 `test.sh` 均返回 **exit=1**；还原后恢复 **exit=0**。
**这证明门禁不是恒真。**

---

## 7. 常见问题

**Q：`docker compose up` 报 `network ... has internal: true` 相关错误？**
A：`internal` 网络下服务不能访问外网，这是设计意图。构建阶段（build）可以用外网，
运行阶段不行。安全扫描若需要外网更新规则库，需单独加 `--network host` 的临时容器，
且**只在隔离环境**使用。

**Q：镜像拉取超时？**
A：先确认 `setup.ps1` 的拉取测试通过。若失效，换 `-Mirror` 参数重跑。

**Q：`gates` 容器里报 `eslint: not found`？**
A：说明依赖播种未完成。检查命名卷 `frontend-node-modules` 是否被误删，
或执行 `down.ps1` 后重新 `up.ps1 -WithGates`（会重建卷并重新播种）。

**Q：为什么基础镜像从 bullseye 换成 bookworm？**
A：Debian 11 已 EOL，`deb.debian.org` 对它返回 404
（实测 `python3.9-minimal_3.9.2-1+deb11u7_amd64.deb 404 Not Found`），
`apt-get install` 直接失败。

**Q：能把它当生产环境用吗？**
A：**绝对不能。** 它的用途是"验证代码 + 门禁自洽"，不是"承载生产流量"。
生产需要独立的 IaC、密钥管理和审批流程。
