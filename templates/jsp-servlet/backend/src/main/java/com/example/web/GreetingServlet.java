package com.example.web;

import com.example.web.service.GreetingService;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;

/**
 * 问候接口：GET /api/v1/greeting。
 *
 * <p>归属模块：视图模块（Web 适配层）。
 * 本类只做三件事：调用 {@link GreetingService}、把返回对象序列化成契约规定的 JSON、
 * 写出响应。**不允许**在此加入业务分支——业务规则一律下沉到 service 层，
 * 否则领域模块的单测就必须启动容器了。
 *
 * <p>响应契约见 docs/api-spec.yaml：
 * <pre>
 * 200 {"message":"Hello from JSP backend","time":"2026-11-25T20:21:41+08:00"}
 * </pre>
 */
@WebServlet(name = "greetingServlet", urlPatterns = {"/api/v1/greeting"})
public class GreetingServlet extends HttpServlet {

    private static final long serialVersionUID = 1L;

    /**
     * 领域服务；Servlet 维持无状态，天然线程安全（Tomcat 每个 Servlet 只有一个实例）。
     *
     * <p>声明为 {@code transient}：{@link HttpServlet} 实现了 {@code Serializable}，
     * 而 {@code GreetingService} 不是；不声明会在极少数容器序列化 Servlet 的场景下
     * 抛 {@code NotSerializableException}。Servlet 本来也不应该被序列化。
     */
    private final transient GreetingService greetingService;

    /** 无参构造：容器通过 web.xml / 注解实例化时使用。 */
    public GreetingServlet() {
        this(new GreetingService());
    }

    /**
     * 便于测试注入的构造器。
     *
     * @param greetingService 领域服务实例，不可为 null
     */
    public GreetingServlet(GreetingService greetingService) {
        if (greetingService == null) {
            throw new IllegalArgumentException("greetingService 不能为 null");
        }
        this.greetingService = greetingService;
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        GreetingService.Greeting greeting;
        try {
            // 契约中当前未定义查询参数；此处仅透传 service 的默认行为
            greeting = greetingService.greet();
        } catch (RuntimeException ex) {
            // 不向客户端泄露异常信息与堆栈，仅记录到容器日志
            log("生成问候语失败", ex);
            writeJson(resp, HttpServletResponse.SC_INTERNAL_SERVER_ERROR,
                    "{\"error\":\"internal_error\"}");
            return;
        }

        String body = "{\"message\":" + quote(greeting.message())
                + ",\"time\":" + quote(greeting.time()) + "}";
        writeJson(resp, HttpServletResponse.SC_OK, body);
    }

    /**
     * 写出 JSON 响应。统一在此设置编码与缓存策略，避免各个分支遗漏。
     */
    private static void writeJson(HttpServletResponse resp, int status, String body) throws IOException {
        resp.setStatus(status);
        resp.setContentType("application/json;charset=UTF-8");
        resp.setCharacterEncoding("UTF-8");
        resp.setHeader("Cache-Control", "no-store");
        try (PrintWriter out = resp.getWriter()) {
            out.write(body);
        }
    }

    /**
     * 最小 JSON 字符串转义。
     *
     * <p>本模板不引入 Jackson/Gson 以减少依赖面；代价是必须自己处理好转义。
     * 真实项目应换成成熟的序列化库，避免遗漏边界情况（如代理对、控制字符）。
     *
     * @param raw 原始字符串，null 视为空串
     * @return 带双引号的 JSON 字符串字面量
     */
    static String quote(String raw) {
        if (raw == null) {
            return "\"\"";
        }
        StringBuilder sb = new StringBuilder(raw.length() + 16);
        sb.append('"');
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    // 其余控制字符（U+0000–U+001F）必须转义，否则 JSON 不合法。
                    // 注意：源码字符串里写的是**两个**反斜杠加 u%04x，编译后才得到单反斜杠 + u 的
                    // JSON 转义序列。若源码只写一个反斜杠，javac 会在词法分析前把它当作
                    // Unicode 转义处理（这是一个著名的 Java 陷阱），此处必须保留双反斜杠。
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
        return sb.toString();
    }
}
