# 后端 Dockerfile（ASP.NET Core 8 Minimal API，多阶段构建 + 非 root + 健康检查）
# 位置：backend/Dockerfile；构建上下文：backend/
# 目标：运行镜像只含 ASP.NET Core 运行时，不含 SDK 与源码。

# ---------- 构建阶段 ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS builder
WORKDIR /src

# 先只复制工程文件并还原依赖，利用 Docker 层缓存：源码改动不必重新还原
COPY DemoApi.csproj ./
RUN dotnet restore DemoApi.csproj

# 再复制源码（tests/ 属于独立测试项目，不进入生产镜像）
COPY Program.cs ./

# Release 发布到 /app/publish；--no-restore 复用上一步缓存
RUN dotnet publish DemoApi.csproj \
        -c Release \
        -o /app/publish \
        --no-restore \
        /p:UseAppHost=false

# ---------- 运行阶段 ----------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# curl 仅用于容器内 HEALTHCHECK 探测 /health（运行时镜像默认不含）
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 系统用户并切换（最小权限原则，见规范 §7.2 执行沙箱）
RUN groupadd --system --gid 1001 appuser \
    && useradd --system --uid 1001 --gid appuser --shell /usr/sbin/nologin appuser

# 仅复制发布产物，并移交属主，保证非 root 用户可读
COPY --from=builder --chown=appuser:appuser /app/publish ./

# 监听 8000，与 deploy/docker-compose.yml、docs/api-spec.yaml 保持一致
# HOME 指向 /tmp：配合 read_only 根文件系统，避免运行时向不可写目录写入
# （/tmp 由 compose 以 tmpfs 挂载，见 deploy/docker-compose.yml）
ENV ASPNETCORE_URLS=http://+:8000 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_NOLOGO=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    HOME=/tmp

USER appuser

EXPOSE 8000

# 容器级健康检查：与 scripts/health.sh、compose healthcheck 判定标准一致
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=5 \
    CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["dotnet", "DemoApi.dll"]
