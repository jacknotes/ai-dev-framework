import { describe, it, expect, vi } from 'vitest'
import { fetchGreeting } from './api'

describe('api.ts', () => {
  it('fetchGreeting 解析后端返回', async () => {
    const mockData = { message: 'hello', time: 't' }
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
