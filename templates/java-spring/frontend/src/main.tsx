import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'

// 应用挂载入口：index.html 中的 #root 节点
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
