// 后端单元测试：覆盖 /health 与 /api/v1/greeting 两个契约接口。
// 使用 WebApplicationFactory<Program> 在进程内启动完整应用，不占端口、无需外部依赖。
// 运行：dotnet test（对齐框架门禁 3）

using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace DemoApi.Tests;

/// <summary>
/// 契约接口测试。所有断言均对照 docs/api-spec.yaml 的字段与示例值。
/// </summary>
public class GreetingTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public GreetingTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Health_应返回_ok()
    {
        // Act
        var response = await _client.GetAsync("/health");

        // Assert：状态码与内容类型
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);

        // Assert：响应体为 {"status":"ok"}
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;
        Assert.Equal(JsonValueKind.Object, root.ValueKind);
        Assert.True(root.TryGetProperty("status", out var status), "响应缺少 status 字段");
        Assert.Equal("ok", status.GetString());
    }

    [Fact]
    public async Task Greeting_应返回_message_与_time()
    {
        // Act
        var response = await _client.GetAsync("/api/v1/greeting");

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;

        Assert.True(root.TryGetProperty("message", out var message), "响应缺少 message 字段");
        Assert.True(root.TryGetProperty("time", out var time), "响应缺少 time 字段");

        Assert.Equal("Hello from .NET backend", message.GetString());

        // time 必须是可解析的 ISO-8601 字符串，且与当前 UTC 时间接近（容忍 5 分钟偏差）
        var raw = time.GetString();
        Assert.False(string.IsNullOrWhiteSpace(raw));
        Assert.True(
            DateTimeOffset.TryParse(raw, out var parsed),
            $"time 不是合法的 ISO-8601 时间：{raw}");
        Assert.Equal(TimeSpan.Zero, parsed.Offset);
        Assert.True(
            (DateTimeOffset.UtcNow - parsed).Duration() < TimeSpan.FromMinutes(5),
            "time 与当前 UTC 时间偏差过大");
    }

    [Fact]
    public async Task Greeting_应带_CORS_响应头()
    {
        // 模拟浏览器跨域请求，验证 Program.cs 已启用 CORS（FR-3）
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/greeting");
        request.Headers.Add("Origin", "http://localhost:3000");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(
            response.Headers.Contains("Access-Control-Allow-Origin"),
            "缺少 Access-Control-Allow-Origin 响应头，CORS 未生效");
    }

    [Fact]
    public async Task 未知路由_应返回_404()
    {
        // 负向用例：确认路由未过度匹配，避免契约外的路径被意外放行
        var response = await _client.GetAsync("/api/v1/not-exist");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
