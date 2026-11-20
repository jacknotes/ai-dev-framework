# 后端 Dockerfile（Go，最小镜像 + 非 root）
# 位置：backend/Dockerfile

# ---- 构建阶段 ----
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

# ---- 运行阶段 ----
FROM alpine:3.19
RUN apk add --no-cache ca-certificates wget
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=builder /server /app/server
EXPOSE 8000
HEALTHCHECK CMD wget -qO- http://localhost:8000/health || exit 1
ENTRYPOINT ["/app/server"]
