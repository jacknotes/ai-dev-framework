package com.example.demo.api;

import java.time.Instant;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 最小示例接口，契约见 docs/api-spec.yaml。
 *
 * <ul>
 *   <li>GET /health —— 存活探测，供 Docker HEALTHCHECK 与部署门禁使用；
 *   <li>GET /api/v1/greeting —— 返回问候语与服务器当前时间，供前端验证联通。
 * </ul>
 */
@RestController
public class GreetingController {

    /** 健康检查：只要进程能响应即视为存活，不查外部依赖。 */
    @GetMapping("/health")
    public HealthResponse health() {
        return new HealthResponse("ok");
    }

    /** 问候接口：返回结构与前端 frontend/src/api.ts 的 Greeting 类型一一对应。 */
    @GetMapping("/api/v1/greeting")
    public Greeting greeting() {
        return new Greeting("Hello from Java backend", Instant.now().toString());
    }

    /** 健康检查响应体。 */
    public record HealthResponse(String status) {}

    /** 问候响应体：message 为固定文案，time 为 ISO-8601 的 UTC 时间串。 */
    public record Greeting(String message, String time) {}
}
