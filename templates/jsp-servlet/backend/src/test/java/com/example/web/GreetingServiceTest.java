package com.example.web;

import com.example.web.service.GreetingService;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * {@link GreetingService} 的单元测试。
 *
 * <p>归属模块：领域模块（针对 {@code service} 层的单测由领域模块开发者编写）。
 *
 * <p>本测试<b>不启动 Tomcat、不 mock HttpServletRequest</b>——这正是"业务逻辑与 Web 层分离"
 * 带来的直接收益：领域层的测试是纯 POJO 测试，毫秒级完成。
 *
 * <p>时间相关断言使用固定时钟（{@link Clock#fixed}），保证结果确定、可重复。
 */
@DisplayName("GreetingService 领域服务")
class GreetingServiceTest {

    /** 固定时刻：2026-11-25T12:21:41Z，在 +08:00 时区下即 20:21:41。 */
    private static final Instant FIXED_INSTANT = Instant.parse("2026-11-25T12:21:41Z");

    private static final ZoneOffset FIXED_OFFSET = ZoneOffset.ofHours(8);

    private static GreetingService serviceWithFixedClock() {
        return new GreetingService(Clock.fixed(FIXED_INSTANT, FIXED_OFFSET));
    }

    @Test
    @DisplayName("默认问候语应返回契约规定的文案")
    void shouldReturnDefaultMessage() {
        GreetingService.Greeting greeting = serviceWithFixedClock().greet();

        assertAll(
                () -> assertNotNull(greeting, "结果不应为 null"),
                () -> assertEquals("Hello from JSP backend", greeting.message(),
                        "message 必须与 docs/api-spec.yaml 的 example 一致"),
                () -> assertNotNull(greeting.time(), "time 不应为 null")
        );
    }

    @Test
    @DisplayName("时间字段应为 ISO-8601 带偏移的字符串，且可被解析回原值")
    void shouldFormatTimeAsIsoOffsetDateTime() {
        String time = serviceWithFixedClock().nowAsIsoString();

        assertEquals("2026-11-25T20:21:41+08:00", time,
                "时间应使用服务器时区偏移，并截断到秒");

        // 契约承诺 time 可被标准解析器读取；这里做一次往返校验
        OffsetDateTime parsed = OffsetDateTime.parse(time, DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        assertAll(
                () -> assertEquals(FIXED_INSTANT, parsed.toInstant(), "解析后的瞬时必须一致"),
                () -> assertEquals(FIXED_OFFSET, parsed.getOffset(), "偏移必须被保留")
        );
    }

    @Test
    @DisplayName("传入自定义正文时应原样使用（含首尾空白被裁剪）")
    void shouldUseProvidedMessage() {
        GreetingService service = serviceWithFixedClock();

        assertAll(
                () -> assertEquals("你好，JSP", service.greet("你好，JSP").message()),
                () -> assertEquals("hi", service.greet("  hi  ").message(), "首尾空白应被裁剪")
        );
    }

    @Test
    @DisplayName("正文为 null 或空白时应回退到默认文案")
    void shouldFallbackToDefaultWhenMessageIsBlank() {
        GreetingService service = serviceWithFixedClock();

        assertAll(
                () -> assertEquals(GreetingService.DEFAULT_MESSAGE, service.greet(null).message(),
                        "null 应回退到默认文案"),
                () -> assertEquals(GreetingService.DEFAULT_MESSAGE, service.greet("   ").message(),
                        "纯空白应回退到默认文案"),
                () -> assertEquals(GreetingService.DEFAULT_MESSAGE, service.greet("").message(),
                        "空串应回退到默认文案")
        );
    }

    @Test
    @DisplayName("构造器应拒绝 null 时钟")
    void shouldRejectNullClock() {
        // 实现使用 Objects.requireNonNull，因此抛出 NullPointerException。
        // 这里断言"快速失败"，而不是让 null 时钟潜伏到运行时才爆。
        NullPointerException ex = assertThrows(NullPointerException.class,
                () -> new GreetingService(null));
        assertTrue(ex.getMessage() != null && ex.getMessage().contains("clock"),
                "异常信息应指明是 clock 参数为 null");
    }

    @Test
    @DisplayName("结果对象是不可变 record，等值语义按字段比较")
    void greetingShouldBeImmutableRecord() {
        GreetingService service = serviceWithFixedClock();
        GreetingService.Greeting a = service.greet();
        GreetingService.Greeting b = service.greet();

        assertAll(
                () -> assertTrue(GreetingService.Greeting.class.isRecord(),
                        "Greeting 应为 record（不可变，天然具备 equals/hashCode）"),
                // 固定时钟下两次调用结果相同：证明服务无隐藏状态，且 record 的 equals 按字段比较
                () -> assertEquals(a, b, "同样输入的结果对象应相等"),
                () -> assertEquals(a.hashCode(), b.hashCode(), "相等对象应有相同 hashCode"),
                () -> assertEquals(2, GreetingService.Greeting.class.getRecordComponents().length,
                        "契约只允许两个字段：message、time")
        );
    }

    @Test
    @DisplayName("服务应可被安全地重复调用（无状态）")
    void shouldBeStateless() {
        GreetingService service = serviceWithFixedClock();

        String first = service.greet().message();
        String second = service.greet().message();

        assertAll(
                () -> assertEquals(first, second, "同样的输入应得到同样的输出"),
                // 注意：不能用 service::greet —— greet() 有两个重载
                //（无参与 greet(String)），方法引用会在
                // Executable 与 ThrowingSupplier 之间产生歧义（实测编译失败）。
                // 用显式 lambda 消除歧义。
                () -> assertDoesNotThrow(() -> service.greet(), "重复调用不应抛出异常")
        );
    }
}
