# 框架复用与 GitHub 推送使用指南

> 本文回答两个问题：① 这套框架能否复用？② 如何推送到 GitHub，以后每个项目如何利用？

---

## 1. 结论：完全可以复用，而且"复用"是这套框架的设计目标

这套框架的**核心资产全部是"项目无关"的**，天然可复用：

| 可复用资产 | 位置 | 复用时是否需改动 |
|---|---|---|
| 规范文档（宪法） | `docs/01-开发规范文档.md` | 不改，全局通用 |
| 9 个角色提示词 | `prompts/` | 不改（或按团队微调） |
| 编排脚本骨架 | `pipeline/pipeline.workflow.js` | 只改 `meta.name` 和 `args.requirement` |
| 隔离环境模板 | `deploy/docker-compose.yml` | 按项目增删服务 |
| CI 门禁流水线 | `.github/workflows/ai-dev-pipeline.yml` | 按语言替换构建命令 |
| 项目目录模板 | `templates/vue-go/`、`templates/react-python/` | 作为新项目起点复制 |

**一句话：框架是"库"，项目是"实例"。框架仓库管"怎么协作"，每个项目仓库管"协作出什么"。**

---

## 2. 推送到 GitHub（一次性操作）

### 2.1 在本地初始化框架仓库

```bash
cd ai-dev-framework
git init
git add .
git commit -m "feat: 初始化 AI 多智能体协同开发框架（规范+提示词+编排+隔离环境+模板）"
```

### 2.2 在 GitHub 创建远程仓库

1. 打开 https://github.com/new
2. 仓库名：`ai-dev-framework`（或你喜欢的名字）
3. 设为 **Public**（方便复用/协作）或 Private
4. **不要**勾选 "Initialize with README"（因为本地已有内容）

### 2.3 关联并推送

```bash
git remote add origin https://github.com/<你的用户名>/ai-dev-framework.git
git branch -M main
git push -u origin main
```

> 用 SSH 方式则：`git@github.com:<用户名>/ai-dev-framework.git`

---

## 3. 每个新项目如何使用（两种模式）

### 模式 A：作为模板仓库克隆（推荐）

GitHub 支持把仓库标记为 Template，之后一键"用此模板新建仓库"。

**第一步：把框架仓库设为模板**

GitHub 仓库页 → **Settings** → 勾选 **"Template repository"**。

**第二步：每个新项目一键生成**

1. 打开框架仓库页 → 点绿色 **"Use this template"** → **"Create a new repository"**。
2. 填入新项目名，创建。
3. 得到的新仓库自动包含全部框架资产，但**独立于框架仓库**（改了不影响框架）。

**第三步：初始化项目代码**

```bash
git clone https://github.com/<用户名>/<新项目>.git
cd <新项目>

# 复制一个你需要的模板作为起点（如 React+Python）
cp -r templates/react-python/* .          # 或 vue-go
rm -rf templates/                          # 可选：不需要其他模板就删掉

git add . && git commit -m "feat: 基于 React+Python 模板初始化"
git push
```

### 模式 B：作为 Git Submodule 引用（适合想让所有项目始终同步框架更新）

如果希望多个项目**始终共享同一份框架、且框架更新时各项目能同步升级**，用 submodule：

```bash
# 在新项目里
git init
git submodule add https://github.com/<用户名>/ai-dev-framework.git framework

# 以后框架更新，各项目同步：
cd framework && git pull origin main
```

> 权衡：
> - **模式 A**：各项目独立拷贝，互不影响，简单，但框架更新不会自动同步到旧项目。
> - **模式 B**：框架统一管理、可升级，但项目与框架耦合，升级可能引入不兼容。
> - 建议：**框架资产（规范/提示词/编排）用 submodule 共享；项目代码用模板独立**。或初期用模式 A，框架稳定后再考虑 submodule。

---

## 4. 每个项目的标准工作流（复用后的日常）

建立项目后，按这个循环跑：

```
1. 定目标
   └─ 人类在 Issue/需求里写清目标与验收标准

2. 启动编排
   └─ 用 pipeline/pipeline.workflow.js（或你选择的编排框架）
   └─ 传入 args.requirement

3. 智能体接力（全自动）
   └─ PM→架构→前端+后端并行→评审→测试→安全→部署staging

4. 门禁自动校验（CI 自动跑）
   └─ lint / build / 单测 / 集成 / 安全 / 性能

5. 人工介入点（最少 3 处）
   └─ 定目标、关键门禁审批、最终验收

6. 交付
   └─ Release + 测试报告 + 安全报告 + runbook + CHANGELOG
```

---

## 5. 每个项目需要"项目化定制"的部分（清单）

复用框架时，**只有以下几处需要按项目改**，其余照搬：

| 定制项 | 文件 | 改什么 |
|---|---|---|
| 项目名 | `pipeline/pipeline.workflow.js` | `meta.name` |
| 需求 | 编排调用时 | `args.requirement` |
| 技术栈模板 | 选 `vue-go` 或 `react-python`，或新建 | 复制对应模板 |
| CI 构建命令 | `.github/workflows/ai-dev-pipeline.yml` | 换成实际语言的 lint/test/build |
| 隔离服务 | `deploy/docker-compose.yml` | 按项目增删 db/mq/redis 等 |
| 外部依赖 Mock | `deploy/mocks/` | 按项目接口写 WireMock 映射 |
| 门禁阈值 | 规范文档 §4 | 覆盖率、性能指标等 |

---

## 6. 框架本身的持续演进（让复用越来越省力）

每完成一个真实项目，把好用的东西**回填**进框架仓库，形成正循环：

- 好的角色提示词 → 更新 `prompts/`
- 新的语言模板（Java/.NET 等）→ 新增 `templates/<stack>/`
- 更完善的门禁 → 更新 `.github/workflows/`
- 踩过的坑 → 更新 `docs/01-开发规范文档.md`

这样框架会随使用不断变强，真正做到"为以后使用 AI 带来复用便利性"。

---

## 7. 快速决策表

| 你的场景 | 推荐做法 |
|---|---|
| 刚起步，先验证 | 模式 A：Template + 复制模板，跑 POC |
| 多个项目想统一升级框架 | 模式 B：Submodule 共享框架资产 |
| 想保留一份权威框架副本 | GitHub Template + 定期手动同步 |
| 担心框架改动影响老项目 | 模式 A（独立拷贝），框架稳定前别用 submodule |
