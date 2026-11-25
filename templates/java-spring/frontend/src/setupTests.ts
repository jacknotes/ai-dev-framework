import '@testing-library/jest-dom/vitest'

// Vitest 全局初始化：注册 jest-dom 断言（toBeInTheDocument 等）。
// 如需 mock fetch / 清理 localStorage，统一在此扩展，避免各测试文件重复。
