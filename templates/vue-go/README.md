# Vue + Go 最小示例工程（模板）

> 这是 AI 多智能体协同开发框架的**项目目录模板**，可直接复制为新项目起点。
> 目录结构严格遵循框架规范文档 §5。

## 目录结构

```
vue-go/
├── .gitignore
├── docs/                 # 需求、架构、API 契约
│   ├── requirements.md
│   ├── architecture.md
│   └── api-spec.yaml
├── frontend/             # Vue 3 + TypeScript + Vite
│   ├── src/              # 组件 + API 客户端 + 单测
│   ├── Dockerfile
│   ├── nginx.conf
│   └── package.json
├── backend/              # Go 1.22
│   ├── cmd/server/main.go
│   ├── internal/api/     # handler + 单测
│   └── go.mod
└── deploy/
    └── docker-compose.yml  # 隔离环境一键启动
```

## 本地快速开始（不使用 Docker）

**后端（终端 1）：**
```bash
cd backend
go run ./cmd/server
# 监听 http://localhost:8000
```

**前端（终端 2）：**
```bash
cd frontend
npm install
npm run dev
# 访问 http://localhost:3000（Vite 已代理 /api → 8000）
```

## 隔离环境一键启动（推荐，符合框架"不碰真实环境"）

```bash
cd deploy
docker compose up -d --build
curl http://localhost:8000/health   # 后端健康检查
# 前端: http://localhost:80
docker compose down -v              # 用完即销毁
```

## 运行测试（对应框架门禁）

```bash
# 后端单测
cd backend && go test ./...

# 前端 lint + 单测（含覆盖率门禁）
cd frontend && npm install && npm run lint && npm test

# 前端构建
npm run build
```

## 与框架的关系

| 框架产物 | 本模板对应 |
|---|---|
| 规范文档 §5 目录约定 | 本模板目录结构 |
| 隔离环境五重隔离 | `deploy/docker-compose.yml` |
| 门禁（编译/lint/单测） | `go test` / `npm run lint` / `npm test` |
| 单一事实源 | `docs/` 下的需求/架构/契约 |
