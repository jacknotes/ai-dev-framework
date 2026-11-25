import { useEffect, useState } from 'react'
import { fetchGreeting, fetchHealth, type Greeting } from './api'

// 首页：展示后端问候语 + 后端健康状态，用于一眼确认前后端是否联通。
export default function App() {
  const [greeting, setGreeting] = useState<Greeting | null>(null)
  const [error, setError] = useState('')
  const [health, setHealth] = useState('检查中…')

  // 拉取问候语；组件卸载后不再 setState，避免测试环境的空指针告警
  useEffect(() => {
    let cancelled = false
    fetchGreeting()
      .then((g) => {
        if (!cancelled) setGreeting(g)
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : '未知错误')
      })
    return () => {
      cancelled = true
    }
  }, [])

  // 拉取健康状态；失败时只降级显示，不影响主内容
  useEffect(() => {
    let cancelled = false
    fetchHealth()
      .then((h) => {
        if (!cancelled) setHealth(h.status)
      })
      .catch(() => {
        if (!cancelled) setHealth('不可用')
      })
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <main style={{ fontFamily: 'system-ui', maxWidth: 600, margin: '4rem auto', textAlign: 'center' }}>
      <h1>Java + Spring Boot 最小示例工程</h1>
      <p style={{ color: '#888', fontSize: '0.9rem' }}>
        后端健康：<span data-testid="health">{health}</span>
      </p>
      {greeting ? (
        <p style={{ fontSize: '1.2rem', color: '#2c7a2c' }}>
          {greeting.message}{' '}
          <span style={{ color: '#888', fontSize: '0.9rem' }}>({greeting.time})</span>
        </p>
      ) : error ? (
        <p style={{ color: '#c0392b' }}>{error}</p>
      ) : (
        <p style={{ color: '#888' }}>加载中…</p>
      )}
    </main>
  )
}
