import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 前端构建与测试配置
// dev server 把 /api 代理到 .NET 后端 8000 端口，避免浏览器跨域
export default defineConfig({
  plugins: [vue()],
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
    coverage: {
      // 覆盖率门禁只统计"有业务逻辑的代码"。
      // 入口文件（main.ts）、环境声明（env.d.ts）、测试自身无业务逻辑可测，
      // 若纳入统计会把门禁永久拖到 80% 以下——这是模板开箱即红的原因，故显式排除。
      exclude: [
        'src/main.ts',
        'src/env.d.ts',
        'src/**/*.d.ts',
        'src/**/*.test.ts',
        'vite.config.ts',
        'eslint.config.js',
        'dist/**',
        'coverage/**',
      ],
    },
  },
})
