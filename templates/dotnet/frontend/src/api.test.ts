import { describe, it, expect, vi, beforeEach } from 'vitest'
import { fetchGreeting } from './api'

// api 客户端单测：验证契约字段解析与错误分支（对应 FR-2 / FR-5）
describe('api.ts', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it('fetchGreeting 解析后端返回', async () => {
    const mockData = { message: 'Hello from .NET backend', time: '2026-11-25T12:00:00.0000000Z' }
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockData),
    }) as unknown as typeof fetch

    const result = await fetchGreeting()

    expect(result).toEqual(mockData)
    expect(globalThis.fetch).toHaveBeenCalledWith('/api/v1/greeting')
  })

  it('非 2xx 时抛错', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    }) as unknown as typeof fetch

    await expect(fetchGreeting()).rejects.toThrow('请求失败: 500')
  })
})
