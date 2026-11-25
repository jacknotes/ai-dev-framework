package com.example.demo;

import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 应用启动入口。
 *
 * <p>端口约定：优先读取环境变量 PORT（由 deploy/docker-compose.yml 注入），缺省 8000，
 * 与 docs/api-spec.yaml 中 servers 的地址保持一致。
 *
 * <p>说明：这里用 setDefaultProperties 设置默认值，优先级低于命令行参数、系统属性与
 * application.properties，因此部署时仍可用 -Dserver.port=xxx 覆盖。
 */
@SpringBootApplication
public class DemoApplication {

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(DemoApplication.class);
        // 显式指定 Map<String, Object>，避免 Map.of 推断为 Map<String, String> 导致类型不匹配
        app.setDefaultProperties(Map.<String, Object>of(
                "server.port", System.getenv().getOrDefault("PORT", "8000")));
        app.run(args);
    }
}
