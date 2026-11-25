import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import App from './App'
import * as api from './api'

// 隔离网络：把 api 模块整体替换为可控制的 mock
vi.mock('./api', () => ({
  fetchGreeting: vi.fn(),
  fetchHealth: vi.fn(),
}))

describe('App', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('成功时渲染问候语与健康状态', async () => {
    vi.mocked(api.fetchGreeting).mockResolvedValue({
      message: 'Hello from Java backend',
      time: '2026-11-20T08:00:00Z',
    })
    vi.mocked(api.fetchHealth).mockResolvedValue({ status: 'ok' })

    render(<App />)

    await waitFor(() => {
      expect(screen.getByText(/Hello from Java backend/)).toBeInTheDocument()
    })
    expect(screen.getByTestId('health')).toHaveTextContent('ok')
  })

  it('问候接口失败时渲染错误信息，不白屏', async () => {
    vi.mocked(api.fetchGreeting).mockRejectedValue(new Error('请求失败: 500'))
    vi.mocked(api.fetchHealth).mockResolvedValue({ status: 'ok' })

    render(<App />)

    await waitFor(() => {
      expect(screen.getByText(/请求失败: 500/)).toBeInTheDocument()
    })
  })

  it('健康检查失败时降级显示"不可用"，不影响主内容', async () => {
    vi.mocked(api.fetchGreeting).mockResolvedValue({
      message: 'Hello from Java backend',
      time: '2026-11-20T08:00:00Z',
    })
    vi.mocked(api.fetchHealth).mockRejectedValue(new Error('健康检查失败: 503'))

    render(<App />)

    await waitFor(() => {
      expect(screen.getByTestId('health')).toHaveTextContent('不可用')
    })
    expect(screen.getByText(/Hello from Java backend/)).toBeInTheDocument()
  })
})
