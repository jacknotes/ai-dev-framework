# 前端 Dockerfile（Vue 3 + Vite）
# 用途：staging 隔离环境使用。构建产物用 Nginx 托管，反向代理 /api 到后端。

# ---- 构建阶段 ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

# ---- 运行阶段：Nginx 托管静态产物 ----
FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
# 反向代理 /api 到后端服务（隔离网络内）
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
