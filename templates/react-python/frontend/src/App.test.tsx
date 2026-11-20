import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import App from './App'
import * as api from './api'

vi.mock('./api', () => ({
  fetchGreeting: vi.fn(),
}))

describe('App', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('成功时渲染问候语', async () => {
    vi.mocked(api.fetchGreeting).mockResolvedValue({
      message: 'Hello from Python backend',
      time: '2026-11-20T08:00:00+00:00',
    })

    render(<App />)

    await waitFor(() => {
      expect(screen.getByText(/Hello from Python backend/)).toBeInTheDocument()
    })
  })

  it('失败时渲染错误信息', async () => {
    vi.mocked(api.fetchGreeting).mockRejectedValue(new Error('请求失败: 500'))

    render(<App />)

    await waitFor(() => {
      expect(screen.getByText(/请求失败: 500/)).toBeInTheDocument()
    })
  })
})
