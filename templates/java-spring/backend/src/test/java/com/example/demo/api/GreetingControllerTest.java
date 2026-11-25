package com.example.demo.api;

import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 接口单元测试（对应框架门禁：后端单测通过）。
 *
 * <p>使用 @WebMvcTest 只装载 Web 层，不启动完整容器：速度快，且不需要数据库/外部服务。
 * 用例覆盖正常路径与错误路径，便于测试智能体独立复核。
 */
@WebMvcTest(GreetingController.class)
class GreetingControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("GET /health 返回 200，body 为 {\"status\":\"ok\"}")
    void health_shouldReturnOk() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    @DisplayName("GET /api/v1/greeting 返回 message 与可解析的 ISO-8601 time")
    void greeting_shouldReturnMessageAndTime() throws Exception {
        // Instant.toString() 的输出形如 2026-11-20T08:00:00.123456Z，用正则约束格式
        mockMvc.perform(get("/api/v1/greeting"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Hello from Java backend"))
                .andExpect(jsonPath("$.time").value(matchesPattern(
                        "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z")));
    }

    @Test
    @DisplayName("POST /api/v1/greeting 返回 405（方法不允许）")
    void greeting_shouldRejectPost() throws Exception {
        mockMvc.perform(post("/api/v1/greeting"))
                .andExpect(status().isMethodNotAllowed());
    }
}
