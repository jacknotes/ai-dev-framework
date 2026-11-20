import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import App from './App.vue'
import * as api from './api'

vi.mock('./api', () => ({
  fetchGreeting: vi.fn(),
}))

describe('App.vue', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('成功时渲染问候语', async () => {
    vi.mocked(api.fetchGreeting).mockResolvedValue({
      message: 'Hello from Go backend',
      time: '2026-11-20T08:00:00Z',
    })

    const wrapper = mount(App)
    await wrapper.vm.$nextTick()
    await flushPromises()

    expect(wrapper.text()).toContain('Hello from Go backend')
  })

  it('失败时渲染错误信息', async () => {
    vi.mocked(api.fetchGreeting).mockRejectedValue(new Error('请求失败: 500'))

    const wrapper = mount(App)
    await wrapper.vm.$nextTick()
    await flushPromises()

    expect(wrapper.text()).toContain('请求失败: 500')
  })
})

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0))
}
