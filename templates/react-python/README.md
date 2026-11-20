# React + Python 最小示例工程（模板）

> AI 多智能体协同开发框架的**项目目录模板**，可复制为新项目起点，目录结构遵循框架规范 §5。

## 目录结构

```
react-python/
├── .gitignore
├── docs/                 # 需求、架构、API 契约
│   ├── requirements.md
│   ├── architecture.md
│   └── api-spec.yaml
├── frontend/             # React 18 + TypeScript + Vite
│   ├── src/              # 组件 + API 客户端 + 单测
│   ├── Dockerfile
│   ├── nginx.conf
│   └── package.json
├── backend/              # Python 3.12 + FastAPI
│   ├── app/              # main + routers
│   ├── tests/            # pytest 单测
│   ├── Dockerfile
│   └── requirements.txt
└── deploy/
    └── docker-compose.yml
```

## 本地快速开始

**后端（终端 1）：**
```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

**前端（终端 2）：**
```bash
cd frontend
npm install
npm run dev        # 访问 http://localhost:3000
```

## 隔离环境一键启动（推荐）

```bash
cd deploy
docker compose up -d --build
curl http://localhost:8000/health
# 前端 http://localhost:80
docker compose down -v
```

## 运行测试（对应框架门禁）

```bash
# 后端单测
cd backend && pip install -r requirements-dev.txt && pytest

# 前端 lint + 单测（含覆盖率门禁）+ 构建
cd frontend && npm install && npm run lint && npm test && npm run build
```
