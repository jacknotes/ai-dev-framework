/// <reference types="vitest" />
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
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/setupTests.ts'],
    coverage: {
      // 覆盖率门禁只统计"有业务逻辑的代码"。
      // 入口文件（main.tsx）、测试初始化（setupTests.ts）、纯类型声明无逻辑可测，
      // 若纳入统计会把门禁永久拖到 80% 以下——这是模板开箱即红的原因，故显式排除。
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
