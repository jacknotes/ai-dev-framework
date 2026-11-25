// 统一的 API 客户端：与后端契约 docs/api-spec.yaml 的 /api/v1/greeting 对应。
// 约定：所有出网请求集中在本文件，组件不得直接调用 fetch，便于 mock 与契约对齐。

/** 问候接口响应，字段与 api-spec.yaml 的 GreetingResponse 一一对应 */
export interface Greeting {
  message: string
  time: string
}

/**
 * 拉取后端问候语。
 * @throws Error 当响应非 2xx 时抛出，错误文案含状态码，供界面直接展示。
 */
export async function fetchGreeting(): Promise<Greeting> {
  const res = await fetch('/api/v1/greeting')
  if (!res.ok) {
    throw new Error(`请求失败: ${res.status}`)
  }
  return res.json()
}
