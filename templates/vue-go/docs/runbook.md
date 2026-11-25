# 运维实施文档（Runbook）— Vue + Go 模板

> 判据：**任何人不看对话、只读本仓库，能否从零重建环境？** 不能，就是没交付。

## 1. 环境架构（dev / staging / prod）

| 环境 | 用途 | 数据 | 凭证 | 生命周期 |
|---|---|---|---|---|
| dev | 本地开发自测 | 内存 | 无 | 常驻 |
| staging | 隔离测试（功能/安全/性能/UI） | 合成数据，tmpfs | 仅测试凭证 | 一次性，用完即销毁 |
| prod | 生产 | 真实数据 | 生产密钥 | 常驻，**只读禁地** |

## 2. 依赖与前置条件

| 依赖 | 版本 | 校验命令 |
|---|---|---|
| Docker + Compose | ≥ 24 | `docker --version` |
| Node.js | ≥ 20 | `node -v` |
| Go | ≥ 1.22 | `go version` |

## 3. 构建步骤（可复现命令）

```bash
# 前端
cd frontend && npm ci && npm run build

# 后端
cd backend && go build ./...

# 统一门禁入口（契约见 docs/04）
bash scripts/lint.sh
bash scripts/build.sh
bash scripts/test.sh
```

## 4. 部署步骤（含回滚）

```bash
cd deploy && docker compose up -d --build
PORT=8000 bash scripts/health.sh

# 回滚：销毁重建（隔离环境无状态）
docker compose down -v && docker compose up -d --build
```

## 5. 健康检查与监控指标

| 指标 | 阈值 | 采集方式 |
|---|---|---|
| `/health` 状态码 | 200 | `scripts/health.sh` |
| 启动就绪时间 | < 30s | 健康检查重试次数 |
| 容器内存 | < 256M | `docker stats` |

## 6. 故障排查手册

| 现象 | 可能原因 | 处置 |
|---|---|---|
| 健康检查一直失败 | 端口占用 / 依赖未起 | 查 `docker compose logs backend` |
| 前端 502 | nginx 反代后端未就绪 | 确认 `depends_on` 与 healthcheck |
| `go vet` 报错 | 代码问题或 Go 版本不符 | 对齐 `go.mod` 中的 go 版本 |

## 7. 备份与恢复

隔离环境**不备份**（数据在 tmpfs，重启即清空，这是设计意图）。
生产备份策略由生产 runbook 单独维护，**不得复用本文件的测试凭证**。

## 8. 凭证与权限清单（分级）

| 凭证 | 使用环境 | 存放位置 | 备注 |
|---|---|---|---|
| `TEST_DB_PASSWORD` | 仅 staging | compose 默认值 | 测试专用，非真实密码 |
| 生产密钥 | 仅 prod | 生产 secrets | **绝不注入测试流水线** |
