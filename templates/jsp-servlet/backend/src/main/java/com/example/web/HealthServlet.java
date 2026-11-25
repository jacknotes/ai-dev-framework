package com.example.web;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;

/**
 * 健康检查端点：GET /health。
 *
 * <p>归属模块：视图模块（Web 适配层）。
 * 该类刻意保持"无业务逻辑"——它只证明 JVM 与 webapp 已就绪，
 * 不做任何下游依赖检查（不查数据库、不查外部服务），
 * 因此可以安全地同时用作 liveness 与 readiness 探针。
 *
 * <p>返回体必须严格为 {"status":"ok"}：字段名与取值均被容器 HEALTHCHECK
 * 与 scripts/health.sh 依赖，任何修改都属于契约变更。
 *
 * <p>映射方式：使用 {@code @WebServlet} 注解（而非 web.xml），
 * 因此 web.xml 中不再重复声明 {@code <servlet>}，避免双份配置不一致。
 */
@WebServlet(name = "healthServlet", urlPatterns = {"/health"})
public class HealthServlet extends HttpServlet {

    private static final long serialVersionUID = 1L;

    /** 固定响应体，避免每次拼接；内容与 docs/api-spec.yaml 的 /health 一致。 */
    private static final String HEALTHY_JSON = "{\"status\":\"ok\"}";

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        // 显式声明 UTF-8，虽然本响应体是纯 ASCII，但保持全链路编码策略一致
        resp.setContentType("application/json;charset=UTF-8");
        resp.setCharacterEncoding("UTF-8");
        // 健康检查结果不应被任何中间层缓存
        resp.setHeader("Cache-Control", "no-store");
        resp.setStatus(HttpServletResponse.SC_OK);

        try (PrintWriter out = resp.getWriter()) {
            out.write(HEALTHY_JSON);
        }
    }
}
