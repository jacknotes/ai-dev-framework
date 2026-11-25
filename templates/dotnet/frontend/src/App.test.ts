import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import App from './App.vue'
import * as api from './api'

// 组件单测：成功与失败两条渲染路径（对应 FR-4 / FR-5），失败路径确保不白屏
vi.mock('./api', () => ({
  fetchGreeting: vi.fn(),
}))

describe('App.vue', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('成功时渲染问候语', async () => {
    vi.mocked(api.fetchGreeting).mockResolvedValue({
      message: 'Hello from .NET backend',
      time: '2026-11-25T12:00:00.0000000Z',
    })

    const wrapper = mount(App)
    await wrapper.vm.$nextTick()
    await flushPromises()

    expect(wrapper.text()).toContain('Hello from .NET backend')
  })

  it('失败时渲染错误信息', async () => {
    vi.mocked(api.fetchGreeting).mockRejectedValue(new Error('请求失败: 500'))

    const wrapper = mount(App)
    await wrapper.vm.$nextTick()
    await flushPromises()

    expect(wrapper.text()).toContain('请求失败: 500')
  })
})

// 等待 onMounted 内的 Promise 链落地
function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0))
}
