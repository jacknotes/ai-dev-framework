// k6 性能测试脚本（门禁：延迟/吞吐达标）
// 运行：k6 run --vus 50 --duration 30s tests/performance/load-test.js
//
// 注意：必须在隔离 staging 环境执行，绝不压生产。

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.API_BASE_URL || 'http://localhost:8000';

export const options = {
  thresholds: {
    http_req_failed: ['rate<0.01'],      // 错误率 < 1%
    http_req_duration: ['p(95)<500'],    // P95 < 500ms
    checks: ['rate>0.99'],
  },
};

export default function () {
  const health = http.get(`${BASE_URL}/health`);
  check(health, {
    'health 状态码 200': (r) => r.status === 200,
    'health 响应 ok': (r) => r.json('status') === 'ok',
  });

  const greeting = http.get(`${BASE_URL}/api/v1/greeting`);
  check(greeting, {
    'greeting 状态码 200': (r) => r.status === 200,
    'greeting 含 message': (r) => !!r.json('message'),
    'greeting 含 time': (r) => !!r.json('time'),
  });

  sleep(1);
}
