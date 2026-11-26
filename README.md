# AI 多智能体协同开发框架 — 使用说明

> **框架名称**：AI-Dev-Framework（AI 多智能体协同开发闭环框架）
> **版本**：v1.2
> **目标**：让 AI 工具自动完成「编程 → 测试 → 部署 → 交付」，极少人工干预，并形成规范文档。
> **当模板用（一条命令）**：`powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name 项目名 -Stack react-python -Path D:\ai\项目名`
> **第一次用**：直接看 [`docs/00-快速开始.md`](docs/00-快速开始.md)（5 分钟上手）。

---

## 0. 这个框架是什么

> **一个「编排器」+ 多个「职责独立的智能体」+ 一个「Git 仓库单一事实源」+ 一系列「质量门禁」+ 一套「隔离测试环境」。**

写代码的 AI 和验收代码的 AI 必须是**不同的智能体**（四眼原则），否则会"自己证明自己写对了"。所有智能体无状态，靠 Git 仓库交接，用完即弃。

### 库 vs 实例

```
框架仓库（本仓库）  = 库       →  管"怎么协作"：规范/提示词/编排/门禁/隔离/模板
新项目仓库（生成的） = 实例     →  管"协作出什么"：业务代码 + 该项目的文档与运行环境
```

框架升级**不会自动影响旧项目**（各自独立），需要时手动同步——这是刻意选择：避免"改框架把老项目搞挂"。

---

## 1. 目录结构（完整地图）

```
ai-dev-framework/
├── README.md                          # 本文档：总览 + 导航（从这里开始）
├── AGENTS.md                          # ★ AI 进入本仓库时的自动注入须知
├── LICENSE                            # MIT
├── .gitignore
├── .gitattributes                     # ★ 锁定 .sh 为 LF（没有它门禁在新克隆机器上会全废）
├── docs/
│   ├── 00-快速开始.md                  # ★ 使用者入口：一条命令建项目 → 开始 AI 编程
│   ├── 01-开发规范文档.md              # 交付物1：框架"宪法"（角色/流水线/门禁/隔离）
│   ├── 02-复用与GitHub推送指南.md      # 交付物2：框架复用方式 + 推送 GitHub 步骤
│   ├── 03-AI全闭环落地方案.md          # 交付物3：角色分工决策 + 闭环 + 隔离环境落地方案
│   └── 04-门禁与命令契约.md            # 交付物4：五入口契约（lint/build/test/health/e2e）
├── prompts/                           # 交付物5：9个角色提示词模板
│   ├── 00-orchestrator.md             #   编排器
│   ├── 01-pm.md                       #   需求/PM
│   ├── 02-architect.md                #   架构师
│   ├── 03-frontend-backend.md         #   前端/后端（含后端语言变体）
│   ├── 04-reviewer.md                 #   代码评审
│   ├── 05-qa.md                       #   测试 QA
│   ├── 06-security.md                 #   安全（红队）
│   ├── 07-devops.md                   #   运维 DevOps
│   └── 08-human-approver.md           #   人类审批话术模板
├── pipeline/
│   └── pipeline.workflow.js           # 交付物6：DSH workflow 编排脚本（门禁真实执行+失败重试）
├── scaffold/                          # 交付物7：复制进每个新项目的通用文件模板
│   ├── AGENTS.md.template             #   项目级 AI 须知
│   ├── gitattributes.template         #   项目级换行符锁定
│   ├── CHANGELOG.md.template          #   变更日志骨架
│   └── docs-00-项目约定.md.template    #   给人看的项目协作约定
├── tools/                             # ★ 框架工具（一键建项目 / 自检）
│   ├── new-project.ps1                #   从模板生成独立新项目
│   └── verify-framework.ps1           #   框架自检（语法/契约/编码/换行符/吞码）
├── deploy/                            # 交付物8：隔离环境
│   ├── docker/                        #   ★ Docker 方案（推荐，完整五重隔离）
│   │   ├── README.md                  #     前置条件、用法、隔离强度对比
│   │   ├── setup.ps1                  #     重启后一次性配置（镜像加速器+WSL2校验）
│   │   ├── up.ps1                     #     启动（复制模板到沙箱 → build → up → 等 healthy）
│   │   ├── verify.ps1                 #     容器内执行五道门禁
│   │   ├── down.ps1                   #     销毁（容器/网络/卷/镜像）
│   │   └── daemon.json                #     镜像加速器配置模板
│   ├── local/                         #   本机方案（无 Docker 时降级）
│   │   ├── README.md                  #     能力边界与安全设计
│   │   ├── setup.ps1                  #     一次性准备（venv+依赖）
│   │   ├── up.ps1                     #     启动（幂等，绑定 127.0.0.1）
│   │   ├── verify.ps1                 #     执行五道门禁并汇总
│   │   └── down.ps1                   #     销毁（进程树+数据）
│   ├── docker-compose.yml             #   框架级隔离环境（前端/后端/db/mock/test-runner/zap）
│   ├── Dockerfile.backend             #   后端镜像模板（最小镜像+非root）
│   └── mocks/
│       └── wiremock-mappings.json     #   外部依赖 Mock 示例
├── templates/                         # 交付物9：可直接复制的项目起点
│   ├── react-python/                  #   React 18 + TS + Vite ／ FastAPI
│   ├── vue-go/                        #   Vue 3 + TS + Vite ／ Go 1.22
│   ├── java-spring/                   #   React + Spring Boot 3.3 ／ Java 21
│   ├── dotnet/                        #   Vue 3 ／ ASP.NET Core 8
│   └── jsp-servlet/                   #   JSP 3.1 + Servlet 6 ／ Tomcat 10.1（按模块切分）
└── .github/
    ├── ISSUE_TEMPLATE/task.md         # Issue 模板（含可测验收标准）
    ├── pull_request_template.md       # PR 模板（含契约一致性自检）
    └── workflows/
        └── ai-dev-pipeline.yml        # 交付物10：CI/CD 自动门禁（按技术栈分流）
```

> 每个模板都自带 `scripts/{lint,build,test,health,e2e}.sh` 五入口契约，
> 新增技术栈只需实现这 5 个脚本，编排器与 CI 零改动（见 [`docs/04`](docs/04-门禁与命令契约.md)）。

---

## 2. 一条命令建项目

```powershell
powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name 我的项目 -Stack react-python -Path D:\ai\我的项目
```

可选技术栈：`react-python`（默认）、`vue-go`、`java-spring`、`dotnet`、`jsp-servlet`。
生成的是**完全独立的新仓库**（自带 `.git`、`AGENTS.md`、五入口 `scripts/`、CI、隔离环境）。

> 详细步骤、首次怎么开工、三种使用模式、FAQ 都在 [`docs/00-快速开始.md`](docs/00-快速开始.md)。

---

## 3. 阅读导航

| 你想做什么 | 看哪里 |
|---|---|
| 第一次用、5 分钟上手 | [`docs/00-快速开始.md`](docs/00-快速开始.md) |
| 理解"为什么这样设计"（宪法） | [`docs/01-开发规范文档.md`](docs/01-开发规范文档.md) |
| 复用 / 推 GitHub | [`docs/02-复用与GitHub推送指南.md`](docs/02-复用与GitHub推送指南.md) |
| 角色分工决策、闭环、隔离方案 | [`docs/03-AI全闭环落地方案.md`](docs/03-AI全闭环落地方案.md) |
| 改门禁 / 懂五入口契约 | [`docs/04-门禁与命令契约.md`](docs/04-门禁与命令契约.md) |
| 隔离环境（Docker，推荐） | [`deploy/docker/README.md`](deploy/docker/README.md) |
| 隔离环境（无 Docker） | [`deploy/local/README.md`](deploy/local/README.md) |
| 角色提示词模板 | [`prompts/`](prompts/) |
| DSH 编排脚本 | [`pipeline/pipeline.workflow.js`](pipeline/pipeline.workflow.js) |

---

## 4. 框架自检

```powershell
# 全量自检（25 个门禁脚本的语法 + 契约完整性 + 编码 + 换行符 + 吞码扫描）
powershell -ExecutionPolicy Bypass -File tools\verify-framework.ps1
```

改完任何模板/脚本后**必须**跑一遍。这是框架仓库唯一的质量底线。

---

## 5. 当前状态（v1.3）

核心能力均已落地：门禁真实退出码判定 + 失败退回重试、五入口契约 25 个脚本、CI 技术栈自动分流、
5 套技术栈模板、`tools/new-project.ps1` 一键建项目、`tools/verify-framework.ps1` 自检、
`deploy/docker` + `deploy/local` 两套隔离环境、框架与模板双 `AGENTS.md`（含对话式开工引导协议）。

**v1.3 新增**：
- **团队预设三档**（quickfix/feature/full）——按任务规模裁剪智能体，小修复不必全员上阵；
- **对话式开工引导**——说需求 → 推荐模板 → 选档位 → 引导 git → 环境就绪 → 说"开始"，全流程对话完成；
- **服务本机可访问**——全部端口发布到 `127.0.0.1`（前端 13000 / 后端 18080 / DB 15432），
  移除 `internal: true`（实测它会让 ports 发布失效）；隔离防"生产与局域网"，不防"本机用户"。

**已知待办**：① 真实 e2e 用例（当前无 `tests/e2e/` 时明确跳过，非"通过"）；② 首次验证 Java/.NET/JSP 模板的
`build/test`（本机无对应工具链）；③ 项目首次 `npm install` 后提交 `package-lock.json`；④ 每个项目跑完后回填复用资产。
