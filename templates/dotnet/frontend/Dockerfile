# 前端 Dockerfile（Vue 3 + TypeScript + Vite）
# 用途：构建静态产物后交给 Nginx 托管，并把 /api/ 反代到隔离网络内的 .NET 后端。
# 说明：Nginx 版本与 templates/vue-go 保持一致；本模板额外提供 /healthz 探针端点。

# ---------- 构建阶段 ----------
FROM node:20-alpine AS builder
WORKDIR /app

# 先复制依赖清单并安装，利用层缓存：源码改动不重复安装依赖
COPY package.json ./
RUN npm install

# 再复制源码并构建
COPY . .
RUN npm run build

# ---------- 运行阶段：Nginx 托管静态产物 ----------
FROM nginx:1.27-alpine

# 用自定义配置替换默认站点（含 /api 反代与 /healthz 探针）
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 复制构建产物
COPY --from=builder /app/dist /usr/share/nginx/html

# 把 pid 文件指向 /tmp：配合 compose 的 read_only（根文件系统只读）运行。
# /tmp 与 /var/cache/nginx 由 compose 以 tmpfs 挂载为可写层。
RUN sed -i -E 's#^[[:space:]]*pid[[:space:]]+.*#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf \
    && ( grep -q '^pid /tmp/nginx.pid;' /etc/nginx/nginx.conf \
         || echo 'pid /tmp/nginx.pid;' >> /etc/nginx/nginx.conf ) \
    && sed -i -E 's#^[[:space:]]*user[[:space:]]+.*#user nginx;#' /etc/nginx/nginx.conf

EXPOSE 80

# 容器级健康检查：探针只命中 Nginx 自身，不依赖后端可用性
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=5 \
    CMD wget -qO- http://localhost/healthz || exit 1
