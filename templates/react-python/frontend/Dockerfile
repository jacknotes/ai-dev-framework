# 前端 Dockerfile（React + Vite）
# 用途：staging 隔离环境。构建产物由 Nginx 托管，反代 /api 到后端。

FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
