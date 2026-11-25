<%@ page contentType="text/html;charset=UTF-8" language="java" pageEncoding="UTF-8" session="false" %>
<%--
  首页 — PG-1（见 docs/pages.md）

  归属模块：视图模块（backend/src/main/webapp/index.jsp）

  设计约束（务必遵守，违反即视为破坏模块切分）：
    1. 本页面**不写任何 Java 业务逻辑**。这里没有 JSP 脚本片段（scriptlet）、没有 JDBC、
       没有对 service 的直接调用。数据一律通过 Ajax 从 GET /api/v1/greeting 取得。
       原因：页面内嵌业务逻辑会让"视图模块"与"领域模块"的边界彻底消失，
       两个开发者又开始改同一个文件。
    2. 只依赖契约中声明过的字段：message、time（见 docs/api-spec.yaml）。
       不要读 data.msg、data.data.message 之类的"猜测字段"。
    3. 失败时显示固定文案「问候语加载失败」，便于自动化断言（FR-4）。

  注意：接口地址由 EL 拼出上下文路径（见页面底部的 contextPath 变量），
  因此 ROOT 部署与 /app 子上下文部署都能正常工作。不要写死 /api/v1/...，
  那在非 ROOT 上下文下会 404，是 JSP 项目最常见的部署事故之一。
--%>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>JSP + Servlet 示例</title>
    <style>
        :root {
            color-scheme: light dark;
            --bg: #0f1115;
            --card: #171a21;
            --text: #e6e8ee;
            --muted: #9aa3b2;
            --accent: #4f8cff;
            --border: #262b36;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            background: var(--bg);
            color: var(--text);
            font-family: system-ui, -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
        }
        main {
            width: 100%;
            max-width: 560px;
            padding: 32px;
            border: 1px solid var(--border);
            border-radius: 14px;
            background: var(--card);
        }
        h1 { margin: 0 0 8px; font-size: 22px; }
        p.lead { margin: 0 0 24px; color: var(--muted); font-size: 14px; line-height: 1.6; }
        .panel {
            padding: 18px 20px;
            border: 1px solid var(--border);
            border-radius: 10px;
            background: rgba(79, 140, 255, .06);
        }
        #greeting { font-size: 20px; font-weight: 600; word-break: break-word; }
        #greeting.error { color: #ff6b6b; }
        #time { margin-top: 8px; font-size: 13px; color: var(--muted); font-variant-numeric: tabular-nums; }
        footer { margin-top: 22px; font-size: 12px; color: var(--muted); }
        code { font-size: 12px; padding: 1px 5px; border-radius: 4px; background: rgba(255,255,255,.08); }
    </style>
</head>
<body>
<main>
    <h1>JSP + Servlet 示例</h1>
    <p class="lead">
        本页由 <code>index.jsp</code> 渲染，数据通过 <code>fetch</code> 请求
        <code>/api/v1/greeting</code> 获取。页面与接口同源同容器，
        这是 JSP 栈"前后端边界模糊"的直观体现。
    </p>

    <section class="panel" aria-live="polite">
        <%-- 初始文案为「加载中…」，成功后替换为接口返回的 message --%>
        <div id="greeting">加载中…</div>
        <%-- 时间字段由接口返回（契约字段 time），前端只做展示，不做时区换算 --%>
        <div id="time"></div>
    </section>

    <footer>
        契约：<code>docs/api-spec.yaml</code>　｜　页面清单：<code>docs/pages.md</code>
    </footer>
</main>

<script>
    (function () {
        'use strict';

        var greetingEl = document.getElementById('greeting');
        var timeEl = document.getElementById('time');

        /**
         * 上下文路径由容器通过 EL 注入（ROOT 部署时为空串，/app 部署时为 "/app"）。
         *
         * 为什么不用写死的相对路径：
         *   "api/v1/greeting" 这类相对路径在 /index.jsp 下解析正确，但在
         *   /app（欢迎页转发，URL 末尾无斜杠）下会被解析成 /api/v1/greeting，直接 404。
         * 为什么不用 JSP 脚本片段（scriptlet）：
         *   那会破坏"视图模块不写 Java 逻辑"的约定；EL 只读取容器提供的请求上下文路径，
         *   不引入任何业务逻辑，属于 JSP 的标准用法。
         */
        var contextPath = '${pageContext.request.contextPath}';
        var endpoint = contextPath + '/api/v1/greeting';

        /**
         * 渲染失败状态。文案固定为「问候语加载失败」，便于自动化断言（FR-4）。
         * 不展示原始异常或堆栈，避免信息泄露。
         */
        function showError() {
            greetingEl.textContent = '问候语加载失败';
            greetingEl.classList.add('error');
            timeEl.textContent = '';
        }

        function render(data) {
            // 只读契约字段：message、time
            if (!data || typeof data.message !== 'string') {
                showError();
                return;
            }
            greetingEl.textContent = data.message;
            greetingEl.classList.remove('error');
            timeEl.textContent = data.time ? ('时间：' + data.time) : '';
        }

        function load() {
            fetch(endpoint, {
                method: 'GET',
                headers: { 'Accept': 'application/json' },
                // 同源请求默认携带 cookie；本示例无会话，显式声明便于阅读
                credentials: 'same-origin'
            })
                .then(function (resp) {
                    if (!resp.ok) {
                        throw new Error('HTTP ' + resp.status);
                    }
                    return resp.json();
                })
                .then(render)
                .catch(function (err) {
                    // 仅在控制台记录简要原因，不向页面暴露细节
                    console.error('加载问候语失败：', err && err.message ? err.message : err);
                    showError();
                });
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', load);
        } else {
            load();
        }
    })();
</script>
</body>
</html>
