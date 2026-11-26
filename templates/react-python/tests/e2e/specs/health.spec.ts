// 健康检查 e2e 用例
//
// 追溯：docs/requirements.md 非功能需求「服务可用性」
// 归属：独立测试智能体（开发智能体不得修改本文件）
//
// 设计原则：
//   - 只通过外部接口观察行为，不 import 业务代码（黑盒）。
//   - 断言"用户能看到/能拿到的东西"，不是"实现细节"。

import { test, expect } from '@playwright/test';

const API_URL = process.env.API_BASE_URL || 'http://backend:8000';

test.describe('服务可用性', () => {
  test('后端 /health 返回 200 且 status=ok', async ({ request }) => {
    const resp = await request.get(`${API_URL}/health`);
    expect(resp.status()).toBe(200);

    const body = await resp.json();
    expect(body).toEqual({ status: 'ok' });
  });

  test('前端首页可加载并返回 HTML', async ({ page }) => {
    const resp = await page.goto('/', { waitUntil: 'domcontentloaded' });
    expect(resp?.status()).toBe(200);

    // 页面必须能渲染出内容，而不是白屏
    await expect(page.locator('body')).not.toBeEmpty();
  });
});
