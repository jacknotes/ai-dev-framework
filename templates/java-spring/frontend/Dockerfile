# 前端 Dockerfile（React 18 + TypeScript + Vite）
# 位置：frontend/Dockerfile
# 用途：staging 隔离环境。构建产物由 Nginx 托管，并把 /api 反代到后端。

# ---- 构建阶段 ----
FROM node:20-alpine AS builder
WORKDIR /app

# 先拷依赖清单，利用层缓存
COPY package.json ./
RUN npm install

# 再拷源码构建（tsc 类型检查 + vite 打包）
COPY . .
RUN npm run build

# ---- 运行阶段 ----
FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:80/ >/dev/null 2>&1 || exit 1
