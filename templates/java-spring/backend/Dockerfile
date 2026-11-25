# 后端 Dockerfile（Java 21 + Spring Boot 3.3，多阶段构建 + 非 root）
# 位置：backend/Dockerfile
# 用法：docker build -t java-spring-backend ./backend

# ---- 构建阶段：Maven 编译打包 ----
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /build

# 先只拷 pom.xml 下载依赖，利用 Docker 层缓存，改代码时不必重新拉依赖
COPY pom.xml ./
RUN mvn -q -B dependency:go-offline

# 再拷源码并打包（跳过测试：单测在门禁阶段由 scripts/test.sh 单独执行）
COPY src ./src
RUN mvn -q -B package -DskipTests

# ---- 运行阶段：仅 JRE，镜像更小、攻击面更小 ----
FROM eclipse-temurin:21-jre

# 安装 curl 供 HEALTHCHECK 使用，并创建非 root 用户
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder --chown=app:app /build/target/*.jar /app/app.jar

# 切到非 root 用户运行（最小权限原则）
USER app

ENV PORT=8000
EXPOSE 8000

# 存活探针：与 docs/api-spec.yaml 的 /health 一致
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=5 \
    CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
