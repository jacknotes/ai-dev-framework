// 统一的 API 客户端，与后端契约 docs/api-spec.yaml 对应。
// 开发态由 Vite 代理 /api → http://localhost:8000；容器内由 Nginx 反代。

/** 后端 GET /api/v1/greeting 的响应体。 */
export interface Greeting {
  message: string
  time: string
}

/** 后端 GET /health 的响应体。 */
export interface Health {
  status: string
}

/** 请求问候语；非 2xx 时抛出带状态码的错误，交给页面展示。 */
export async function fetchGreeting(): Promise<Greeting> {
  const res = await fetch('/api/v1/greeting')
  if (!res.ok) {
    throw new Error(`请求失败: ${res.status}`)
  }
  return res.json()
}

/** 请求健康检查；用于页面顶部的联通状态提示。 */
export async function fetchHealth(): Promise<Health> {
  const res = await fetch('/health')
  if (!res.ok) {
    throw new Error(`健康检查失败: ${res.status}`)
  }
  return res.json()
}
