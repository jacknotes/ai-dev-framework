// .NET 8 Minimal API 入口：/health 与 /api/v1/greeting
// 契约见 docs/api-spec.yaml，本文件只负责路由与跨域，业务逻辑保持极简。
// 注：Web SDK 的 ImplicitUsings 已引入常用命名空间，此处无需显式 using。

var builder = WebApplication.CreateBuilder(args);

// ---- 跨域（CORS）----
// 开发期放行任意来源，便于 Vite dev server / 本地调试直连；
// 生产环境应由 API 网关或反向代理统一收敛白名单，切勿原样上线。
const string DevCorsPolicy = "dev-cors";
builder.Services.AddCors(options =>
{
    options.AddPolicy(DevCorsPolicy, policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

var app = builder.Build();

// CORS 中间件必须早于端点映射注册，否则预检请求拿不到响应头。
app.UseCors(DevCorsPolicy);

// ---- 健康检查 ----
// 返回 {"status":"ok"}；容器 HEALTHCHECK 与 scripts/health.sh 共同依赖此接口。
app.MapGet("/health", () => Results.Json(new { status = "ok" }));

// ---- 示例业务接口 ----
// 返回问候语与服务器 UTC 时间（ISO-8601 往返格式，DateTime.UtcNow.ToString("O")）。
// 时间字段用字符串而非时间戳，避免前端时区/精度歧义，见 docs/architecture.md §4.2。
app.MapGet("/api/v1/greeting", () => Results.Json(new GreetingResponse(
    Message: "Hello from .NET backend",
    Time: DateTime.UtcNow.ToString("O")
)));

app.Run();

/// <summary>
/// 问候接口的响应传输对象，字段须与 api-spec.yaml 的 GreetingResponse 保持一致。
/// 序列化采用 System.Text.Json 默认 camelCase：Message → message、Time → time。
/// </summary>
internal sealed record GreetingResponse(string Message, string Time);

/// <summary>
/// 供集成测试使用：WebApplicationFactory&lt;Program&gt; 需要一个可访问的入口类型。
/// Minimal API 的隐式 Program 类默认是 internal，故显式声明为 public partial。
/// </summary>
public partial class Program
{
}
