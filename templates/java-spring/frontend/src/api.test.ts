import { describe, it, expect, vi } from 'vitest'
import { fetchGreeting, fetchHealth } from './api'

// api.ts 单测：覆盖成功解析与异常路径，保证契约字段不被悄悄改坏
describe('api.ts', () => {
  it('fetchGreeting 解析后端返回', async () => {
    const mockData = { message: 'Hello from Java backend', time: 't' }
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockData),
    }) as unknown as typeof fetch

    const result = await fetchGreeting()

    expect(result).toEqual(mockData)
    expect(globalThis.fetch).toHaveBeenCalledWith('/api/v1/greeting')
  })

  it('fetchGreeting 非 2xx 时抛错', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    }) as unknown as typeof fetch

    await expect(fetchGreeting()).rejects.toThrow('请求失败: 500')
  })

  it('fetchHealth 解析 {"status":"ok"}', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: 'ok' }),
    }) as unknown as typeof fetch

    await expect(fetchHealth()).resolves.toEqual({ status: 'ok' })
    expect(globalThis.fetch).toHaveBeenCalledWith('/health')
  })

  it('fetchHealth 非 2xx 时抛错', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 503,
    }) as unknown as typeof fetch

    await expect(fetchHealth()).rejects.toThrow('健康检查失败: 503')
  })
})
