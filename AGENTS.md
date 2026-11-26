# AGENTS.md — 框架仓库工作须知

> 本文件会被 DeepSeek Harness / Claude Code 等工具**自动注入**到每个智能体的上下文。
> 它只写"必须知道、容易踩错"的内容；完整规范见 `docs/`。

---

## 1. 你在什么仓库里

这是 **AI-Dev-Framework 框架仓库本身**，不是业务项目。它是一套"模板的生产工厂"：
产出物是 `templates/` 下的项目起点，以及 `docs/` `prompts/` `pipeline/` `deploy/` 这些**项目无关的复用资产**。

**框架是"库"，项目是"实例"。** 框架仓库管"怎么协作"，项目仓库管"协作出什么"。

| 目录 | 作用 | 改动影响 |
|---|---|---|
| `docs/01` | 宪法：角色/流水线/门禁/隔离 | 改它等于改所有项目的规则 |
| `docs/02` | 复用方式 + GitHub 推送 | — |
| `docs/03` | 落地方案、为什么这样设计 | — |
| `docs/04` | 五入口命令契约（最工程化） | — |
| `prompts/` | 9 个角色提示词 | 所有项目共享 |
| `pipeline/` | DSH workflow 编排脚本 | 所有项目共享 |
| `deploy/` | 隔离环境（Docker + 本机两套） | 所有项目共享 |
| `templates/` | 5 套技术栈项目起点 | 只影响新建项目 |
| `tools/` | 建项目 / 自检脚本 | — |

---

## 2. 五条铁律（违反即返工）

1. **门禁必须由真实退出码判定。** 任何 `return true` / `|| true` / `; exit 0` 式的"假通过"都是严重缺陷。这是本框架存在的前提。
2. **`scripts/*.sh` 五入口契约不可增删。** 只有 `lint / build / test / health / e2e` 五个。新增技术栈只实现这 5 个脚本，编排器与 CI 零改动。
3. **写代码的智能体不得验收自己的代码。** 单元测试归开发，集成/UI/性能/安全归独立智能体。
4. **只改自己职责的目录。** 前端智能体不碰 `backend/`，测试智能体不碰业务代码，评审智能体只读。
5. **绝不碰生产。** 所有自动化只打在一次性 staging；测试凭证绝不包含生产密钥。

---

## 3. 改了东西必须跑的验证

```powershell
# 全量自检（语法 + 契约完整性 + 编码 + 换行符）
powershell -ExecutionPolicy Bypass -File tools\verify-framework.ps1
```

最低要求：**25 个 `scripts/*.sh` 必须全部通过 `bash -n` 语法检查**，且每个模板的 5 个入口齐全。

---

## 4. 三个最容易踩的坑（血泪教训）

### 坑 1：换行符。`.sh` 必须是 LF

Windows 上 `core.autocrlf=true` 会把 `.sh` 检出成 CRLF，bash 报 `$'\r': command not found`，
**25 个门禁脚本在新克隆的机器上会全部失效**，而报错完全不指向换行符。
→ 仓库根必须有 `.gitattributes` 锁定 `*.sh text eol=lf`。**不要删它。**

### 坑 2：覆盖率门槛把无业务逻辑文件算进去了

`main.tsx`、`vite-env.d.ts`、`dist/` 被算进分母，导致模板开箱即红
（`coverage for functions (66.66%) does not meet 80%`）。
→ `vite.config.ts` 的 `coverage.exclude` 必须排除入口/声明/测试/构建产物。

### 坑 3：钉死依赖版本会在新版 Python 上装不上

`pydantic==2.9.2` 在 Python 3.14 无预编译 wheel，被迫源码编译 `pydantic-core` 而失败。
→ 用兼容区间 `>=x,<y`；需要可复现时另生成 `requirements.lock.txt`。

---

## 5. 新增一套技术栈模板的正确做法

```powershell
# 1. 复制一个结构最接近的现有模板
Copy-Item templates\react-python templates\my-stack -Recurse

# 2. 只改这些：backend/ 或 frontend/ 的实现、5 个 scripts、docs/api-spec.yaml
#    绝对不要改：scripts 的文件名、退出码语义、docs/ 的章节结构

# 3. 验证（会做语法检查 + 契约完整性检查）
powershell -ExecutionPolicy Bypass -File tools\verify-framework.ps1 -Stack my-stack
```

**判据**：新模板必须让 `bash -n` 全过，且 5 个入口都存在。能否真实跑通取决于本机工具链，
但**必须诚实标注**"未安装工具 → 明确失败"，绝不能静默返回 0。

---

## 6. 新项目怎么开始（给用户的一句话答案）

```powershell
powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name 我的项目 -Stack react-python -Path D:\ai\我的项目
```

生成的是**独立的新仓库**，自带 `AGENTS.md`、`docs/`、五入口 `scripts/`、CI、隔离环境。
详见 `docs/00-快速开始.md`。

**对话式引导协议（用户在框架仓库会话中表达开发意图时，按此引导）：**

1. **听需求 → 推荐模板**：用户描述想做什么，对照 `templates/` 下 5 套技术栈（react-python/vue-go/java-spring/dotnet/jsp-servlet）推荐最合适的一套并说明理由，**用户确认后**才执行 `new-project.ps1` 生成；
2. **引导到新项目**：生成后告诉用户"到新项目目录的 agent 会话中继续"，项目级 `AGENTS.md` 已内置开工引导协议（介绍项目 → 选团队档位 → 初始化 git → 环境就绪检查）；
3. **不代做**：框架会话不代替用户在新项目里做决定——档位选择、git 初始化、环境安装都由新项目会话引导用户逐步确认。

**测试环境一键安装**：读到 `deploy/README.md` 后先向用户确认，同意后再执行
`powershell -NoProfile -ExecutionPolicy Bypass -File deploy\install.ps1`（探测工具链 → 选后端 → 装资源 → 五道门禁）。

**可访问性约定**：所有服务端口发布在 **127.0.0.1**（前端 13000 / 后端 18080 / DB 15432 / Mock 18081 / ZAP 18090，实际以各模板 compose 为准）。隔离防的是"生产与局域网"，不是"本机用户"——`internal: true` 已移除（实测它会让 ports 发布失效，本机用户反而无法访问）。

---

## 7. 提交规范

Conventional Commits：`<type>(<scope>): <subject>`，type ∈ `feat|fix|docs|test|refactor|chore|perf|security`。

分支：`main`（受保护）← `develop` ← `feature/*`。
