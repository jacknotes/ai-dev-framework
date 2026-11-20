// 统一的 API 客户端，与后端契约 /api/v1/greeting 对应
export interface Greeting {
  message: string
  time: string
}

export async function fetchGreeting(): Promise<Greeting> {
  const res = await fetch('/api/v1/greeting')
  if (!res.ok) {
    throw new Error(`请求失败: ${res.status}`)
  }
  return res.json()
}
