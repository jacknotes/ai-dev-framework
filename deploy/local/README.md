# 本机纯闭环测试环境（Local Closed-Loop Sandbox）

> 适用：**没有 Docker / 没有 WSL** 的机器。
> 目标：在本机跑起来一套**一次性、可销毁、不碰任何真实环境**的测试环境，
> 让 `lint → build → test → health → e2e` 五道门禁可以被真实执行。

---

## 1. 它解决什么问题

框架原本的隔离环境依赖 `deploy/docker-compose.yml`（Docker 五重隔离）。
但很多开发机装不了 Docker Desktop（需要 WSL2 / 虚拟化 / 管理员权限）。
本目录提供**等价的本机隔离方案**：用「独立进程 + 独立端口 + 独立虚拟环境 + 独立数据目录」替代「独立容器 + 独立网段」。

| 隔离维度 | Docker 方案 | 本机方案（本目录） |
|---|---|---|
| 环境隔离 | 一次性容器 | 一次性 `sandbox/` 目录 + 独立 venv，`down` 即删 |
| 网络隔离 | 独立网段 + `internal: true` | 只监听 `127.0.0.1`，不监听 `0.0.0.0`，局域网不可达 |
| 凭证隔离 | 仅测试凭证 | 启动时**主动校验**无 `PROD_*` 环境变量，发现即拒绝启动 |
| 数据隔离 | Postgres tmpfs | 数据全部落在 `sandbox/data/`，`down` 时整目录删除 |
| 执行沙箱 | 容器 + 只读 + 资源限额 | 独立 Python venv + 独立进程 + 端口白名单，`down` 精确杀进程 |

**明确的能力边界**（不要误以为是完整的 Docker 替代）：

- 本机方案**不能**限制 CPU/内存，也**不能**阻止进程访问文件系统。
- 它防的是「污染本机环境」和「误连真实服务」，**不防**恶意代码。
- 一旦你装好 Docker，请优先用 `deploy/docker-compose.yml`；本目录用于「暂时没有 Docker」的场景。

---

## 2. 目录与端口

| 项 | 值 | 说明 |
|---|---|---|
| 沙箱根目录 | `sandbox/`（已 gitignore） | 所有临时产物都在这里，删掉即可还原 |
| 后端 venv | `sandbox/.venv` | 与系统 Python **完全隔离**，不污染全局 site-packages |
| 后端地址 | `http://127.0.0.1:18080` | 只绑回环地址 |
| 前端地址 | `http://127.0.0.1:13000` | 只绑回环地址 |
| 数据目录 | `sandbox/data` | `down` 时整目录删除 |
| 日志 | `sandbox/logs/` | 后端与前端各自的 stdout/stderr |

> 刻意使用 **18080/13000** 而不是 8000/3000/80：
> 避免与你本机已有的服务抢端口，也避免误连到真实服务。

---

## 3. 用法

```powershell
# 1) 一次性准备：建 venv、装依赖（只做一次，之后可复用）
pwsh -File deploy/local/setup.ps1

# 2) 起环境（后台启动前后端，等到健康检查通过才返回）
pwsh -File deploy/local/up.ps1

# 3) 跑五道门禁（真实执行，返回真实退出码）
pwsh -File deploy/local/verify.ps1

# 4) 销毁：杀进程 + 删数据目录（环境回到"从未存在"）
pwsh -File deploy/local/down.ps1
```

`verify.ps1` 的退出码即整体门禁结论：**0 = 全部通过，非 0 = 有失败项**。

---

## 4. 五道门禁在本机如何落地

| 门禁 | 命令 | 本机实现 |
|---|---|---|
| 静态检查 | `scripts/lint.sh` | 前端 ESLint；后端 ruff（未装则明确失败，不静默通过） |
| 构建 | `scripts/build.sh` | 前端 `tsc -b && vite build`；后端 `compileall` |
| 单元测试 | `scripts/test.sh` | 前端 Vitest（覆盖率 80%）；后端 pytest |
| 健康检查 | `scripts/health.sh` | `curl 127.0.0.1:18080/health` 重试 |
| e2e | `scripts/e2e.sh` | 未配置用例时**明确跳过**并打印原因 |

> 注意：`scripts/*.sh` 是 bash 脚本，本机用 **Git Bash** 执行（`C:\Program Files\Git\bin\bash.exe`）。
> `setup.ps1` 会自动探测并把它加入 `PATH`。

---

## 5. 安全设计（为什么"不会碰真实环境"）

1. **只绑回环**：所有服务监听 `127.0.0.1`，同一局域网的其他机器无法访问。
2. **凭证拒启动**：`up.ps1` 会扫描环境变量，若发现 `PROD_*` / `DATABASE_URL` 指向非本地地址，**直接拒绝启动**。
3. **无真实数据**：示例工程不连任何数据库；即使将来接入，也只允许连 `sandbox/data` 下的本地实例。
4. **可验证的销毁**：`down.ps1` 结束时会断言 `sandbox/data` 已不存在、端口已释放。
5. **幂等**：重复 `up` 会先 `down`，不会残留多个进程。

---

## 6. 与 Docker 方案的取舍

| 场景 | 用哪个 |
|---|---|
| 日常开发、跑门禁 | 本机方案（快，秒级启动） |
| 交付前验证「容器内也能跑」 | `deploy/docker-compose.yml` |
| 安全扫描（ZAP）/ 多浏览器 e2e | Docker 方案（依赖现成镜像） |
| 性能压测 | 两者皆可；本机压测结果**不能**作为生产容量依据 |

---

## 7. 常见问题

**Q：为什么 `verify.ps1` 里 lint 失败，说找不到 ruff？**
A：ruff 故意不自动安装——门禁必须暴露真实缺失，而不是悄悄降级。装它：`sandbox\.venv\Scripts\python.exe -m pip install ruff`。

**Q：端口被占用怎么办？**
A：`up.ps1` 会检测并报错，不会抢占。改端口：`pwsh -File deploy/local/up.ps1 -BackendPort 18081 -FrontendPort 13001`。

**Q：能把它当"就能上线"的验收环境吗？**
A：**不能**。它验证的是「代码 + 门禁是否自洽」，不验证「生产基础设施是否适配」。
