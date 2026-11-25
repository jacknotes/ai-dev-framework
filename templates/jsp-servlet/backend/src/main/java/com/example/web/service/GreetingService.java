package com.example.web.service;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Objects;

/**
 * 问候语领域服务。
 *
 * <p>归属模块：领域模块（{@code service} 包）。
 *
 * <p><b>为什么单独成类而不是写在 Servlet 里：</b>
 * <ul>
 *   <li>本类不 import 任何 {@code jakarta.servlet.*}，因此单测无需启动 Tomcat；</li>
 *   <li>Servlet 只做"读参数 → 调本类 → 写 JSON"的翻译工作，业务规则集中在此；</li>
 *   <li>领域模块开发者可以独立改动本类，不需要碰 {@code webapp/} 与 Servlet 类。</li>
 * </ul>
 *
 * <p>时间通过 {@link Clock} 注入，默认使用系统时钟；测试可注入固定时钟以获得确定性断言。
 */
public class GreetingService {

    /** 默认问候语，取值与 docs/api-spec.yaml 中的 example 保持一致。 */
    public static final String DEFAULT_MESSAGE = "Hello from JSP backend";

    /** ISO-8601 格式，带时区偏移，例如 2026-11-25T20:21:41+08:00。 */
    private static final DateTimeFormatter TIME_FORMATTER = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    private final Clock clock;

    /** 生产用构造器：使用系统默认时区的时钟。 */
    public GreetingService() {
        this(Clock.systemDefaultZone());
    }

    /**
     * 测试用构造器：注入可控时钟。
     *
     * @param clock 时钟，不能为 null
     */
    public GreetingService(Clock clock) {
        this.clock = Objects.requireNonNull(clock, "clock 不能为 null");
    }

    /**
     * 生成问候语。
     *
     * @return 含 {@code message} 与 {@code time} 的不可变结果对象
     */
    public Greeting greet() {
        return greet(DEFAULT_MESSAGE);
    }

    /**
     * 生成指定正文的问候语。
     *
     * @param message 问候语正文；为 null 或空白时回退到 {@link #DEFAULT_MESSAGE}
     * @return 含 {@code message} 与 {@code time} 的不可变结果对象
     */
    public Greeting greet(String message) {
        String text = (message == null || message.isBlank()) ? DEFAULT_MESSAGE : message.trim();
        return new Greeting(text, nowAsIsoString());
    }

    /**
     * 当前时间的 ISO-8601 表示（带偏移，精确到秒）。
     *
     * <p>截断到秒是为了让响应稳定、便于契约示例比对；毫秒对展示无意义。
     *
     * @return 形如 {@code 2026-11-25T20:21:41+08:00} 的字符串
     */
    public String nowAsIsoString() {
        return OffsetDateTime.now(clock)
                .truncatedTo(ChronoUnit.SECONDS)
                .format(TIME_FORMATTER);
    }

    /**
     * 问候语结果对象。
     *
     * <p>字段名与 OpenAPI 契约一一对应，改动即视为契约变更。
     * 真实项目应将其提升为 {@code model} 包下的独立 POJO。
     *
     * @param message 问候语正文
     * @param time    ISO-8601 时间串
     */
    public record Greeting(String message, String time) {
    }
}
