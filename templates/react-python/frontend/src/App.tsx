import { useEffect, useState } from 'react'
import { fetchGreeting, type Greeting } from './api'

export default function App() {
  const [greeting, setGreeting] = useState<Greeting | null>(null)
  const [error, setError] = useState('')

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

  return (
    <main style={{ fontFamily: 'system-ui', maxWidth: 600, margin: '4rem auto', textAlign: 'center' }}>
      <h1>React + Python 最小示例工程</h1>
      {greeting ? (
        <p style={{ fontSize: '1.2rem', color: '#2c7a2c' }}>
          {greeting.message} <span style={{ color: '#888', fontSize: '0.9rem' }}>({greeting.time})</span>
        </p>
      ) : error ? (
        <p style={{ color: '#c0392b' }}>{error}</p>
      ) : (
        <p style={{ color: '#888' }}>加载中…</p>
      )}
    </main>
  )
}
