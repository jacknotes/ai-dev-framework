/// <reference types="vitest" />
// Vite 配置：dev 端口 3000，/api 与 /health 反向代理到 Spring Boot 后端 8000。
// 说明：/health 单独代理，便于本地直接打开 http://localhost:3000/health 验证后端存活。
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
      '/health': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/setupTests.ts'],
    coverage: {
      // 覆盖率门禁只统计"有业务逻辑的代码"。
      // 入口文件（main.tsx）、测试初始化（setupTests.ts）、纯类型声明（vite-env.d.ts）
      // 无逻辑可测，若纳入统计会把门禁永久拖到 80% 以下——这是模板开箱即红的原因，故显式排除。
      exclude: [
        'src/main.tsx',
        'src/setupTests.ts',
        'src/**/*.d.ts',
        'src/**/*.test.{ts,tsx}',
        'vite.config.ts',
        'eslint.config.js',
        'dist/**',
        'coverage/**',
      ],
    },
  },
})
