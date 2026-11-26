// Playwright 配置文件
//
// 为什么需要它：
//   e2e 用例必须能独立运行，不依赖调用方在命令行重复传参。
//   baseURL 通过环境变量 TEST_BASE_URL 注入（隔离环境里是 http://frontend，
//   容器网络内用服务名而非 localhost），带默认值便于本地调试。
//
// 注意：本目录只读依赖，不引入额外 npm 包。Playwright 由容器内的 test-runner 镜像提供。

import { defineConfig, devices } from '@playwright/test';

const BASE_URL = process.env.TEST_BASE_URL || 'http://frontend';
const API_URL = process.env.API_BASE_URL || 'http://backend:8000';

export default defineConfig({
  testDir: './specs',
  // 隔离环境资源有限，串行执行，避免并发抢占导致假失败
  fullyParallel: false,
  workers: 1,
  // CI 里失败即停，本地保留重试以便区分"偶发"与"真错"
  retries: process.env.CI ? 0 : 1,
  reporter: [
    ['list'],
    ['json', { outputFile: 'e2e-results.json' }],
  ],
  timeout: 30_000,
  expect: { timeout: 10_000 },

  use: {
    baseURL: BASE_URL,
    // 失败时留证据，便于独立测试智能体出报告
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'off',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  // 把 API 地址暴露给用例，避免用例里硬编码
  metadata: { apiURL: API_URL },
});
