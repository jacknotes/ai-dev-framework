// 问候接口 e2e 用例
//
// 追溯：docs/requirements.md FR-1「展示问候语」
// 归属：独立测试智能体（开发智能体不得修改本文件）
//
// 设计原则：
//   - 黑盒：只通过页面可见内容与 HTTP 接口断言，不 import 业务代码。
//   - 断言"契约字段"（message / time），这是前后端双方约定的对外行为。

import { test, expect } from '@playwright/test';

const API_URL = process.env.API_BASE_URL || 'http://backend:8000';

test.describe('问候接口契约', () => {
  test('GET /api/v1/greeting 返回 message 与 time', async ({ request }) => {
    const resp = await request.get(`${API_URL}/api/v1/greeting`);
    expect(resp.status()).toBe(200);

    const body = await resp.json();

    // 契约必填字段（见 docs/api-spec.yaml 的 required: [message, time]）
    expect(body).toHaveProperty('message');
    expect(body).toHaveProperty('time');
    expect(typeof body.message).toBe('string');
    expect(body.message.length).toBeGreaterThan(0);

    // time 必须是可解析的时间字符串
    expect(Number.isNaN(Date.parse(body.time))).toBe(false);
  });

  test('首页渲染出问候语（端到端联通）', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    // 页面必须真的把后端返回的内容显示出来，
    // 而不是白屏或一直停在"加载中"
    await expect(page.getByText(/Hello from/i)).toBeVisible({ timeout: 15_000 });
  });
});
