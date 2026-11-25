# ============================================================================
# JSP + Servlet 示例 — 多阶段 Dockerfile
#
#   阶段 1（builder）：maven:3.9-eclipse-temurin-17 编译并打 war
#   阶段 2（runtime）：tomcat:10.1-jdk17-temurin 运行，war 展开为 webapps/ROOT
#
# 关键设计：
#   1. 运行镜像不含 Maven、不含源码、不含 JDK 之外的构建工具（依赖面最小）。
#   2. **构建期就把 war 展开成目录**，运行期因此可以 read_only: true。
#      （若保留 war，Tomcat 启动时需要在 webapps/ 下解包，只读根文件系统会失败。）
#   3. 以非 root 用户 tomcat（UID 1000）运行。官方镜像已把 CATALINA_HOME
#      chown 给 tomcat，无需额外授权。
#   4. Servlet/JSP API 作用域为 provided，不会被打进产物（可在构建校验中确认）。
# ============================================================================

# ---------------------------------------------------------------------------
# 阶段 1：构建
# ---------------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# 先只复制 pom.xml 以利用层缓存：依赖不变时不会重复下载
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline || true

# 再复制源码并打包
COPY src ./src
RUN mvn -B -q clean package -DskipTests \
    && test -f /build/target/ROOT.war \
    && mkdir -p /build/exploded \
    && cd /build/exploded \
    && jar -xf /build/target/ROOT.war

# ---------------------------------------------------------------------------
# 阶段 2：运行
# ---------------------------------------------------------------------------
FROM tomcat:10.1-jdk17-temurin

# 元信息（便于镜像溯源，也是变更审计的一部分）
LABEL org.opencontainers.image.title="jsp-servlet-demo" \
      org.opencontainers.image.description="JSP 3.1 + Servlet 6 最小示例（Jakarta EE）" \
      org.opencontainers.image.version="0.1.0"

# 统一语言与编码，避免 JSP 与日志乱码
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=Asia/Shanghai
# 容器内堆上限由容器内存比例决定，避免硬编码 -Xmx 后与 docker 限额冲突；
# OOM 时直接退出，交给编排层重启，而不是留下一具"半死不活"的 JVM。
ENV CATALINA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8"

# 清空官方镜像自带的示例应用（ROOT/docs 等），避免默认页抢占根上下文。
# 只清空内容、保留 webapps/ 目录本身；ROOT/ 由下面的 COPY 创建并直接指定属主，
# 避免留下一个 root:root 的目录让非 root 进程读不到。
RUN rm -rf "$CATALINA_HOME"/webapps/*

# 显式安装 curl：HEALTHCHECK 依赖它，且不同 tag 的基础镜像预装情况不一致。
# 安装必须在切到非 root 之前完成（运行期根文件系统只读，无法再装）。
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# 复制**已展开**的应用目录（不是 war），因此运行期无需写入 webapps/
COPY --from=builder --chown=tomcat:tomcat /build/exploded/ "$CATALINA_HOME"/webapps/ROOT/

# 运行期需要可写的只有临时目录与工作目录。
# 这里必须**预先创建全部 tmpfs 挂载点**：容器以 read_only 运行时，
# 若挂载点在镜像里不存在，运行期无法在只读根文件系统上创建它，容器会启动失败。
# （compose 里挂载的 5 个路径必须与下面保持一致。）
RUN mkdir -p "$CATALINA_HOME"/temp \
             "$CATALINA_HOME"/work \
             "$CATALINA_HOME"/logs \
             "$CATALINA_HOME"/conf/Catalina \
    && chown -R tomcat:tomcat "$CATALINA_HOME"/temp \
                              "$CATALINA_HOME"/work \
                              "$CATALINA_HOME"/logs \
                              "$CATALINA_HOME"/conf/Catalina

# 说明：Tomcat 会把 catalina.out 写到 $CATALINA_HOME/logs。
# 容器以 read_only 运行时，compose 会用 tmpfs 挂载该目录（见 deploy/docker-compose.yml），
# 因此日志落在内存里、容器销毁即消失——这是隔离环境的预期行为。
# 生产环境应改为挂载持久卷或配置 log4j/JUL 输出到 stdout 由采集器收集（见 runbook §5.3）。

USER tomcat

WORKDIR "$CATALINA_HOME"

EXPOSE 8080

# 健康检查：/health 返回 200 即视为健康。
# start-period 给足解包与 JSP 首次编译的时间（JSP 首次访问才会编译）。
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

# 默认前台运行（便于容器日志采集）。
# 使用 exec 形式，docker run 追加的参数会直接传给 catalina.sh（如 --add-opens）。
ENTRYPOINT ["catalina.sh", "run"]
