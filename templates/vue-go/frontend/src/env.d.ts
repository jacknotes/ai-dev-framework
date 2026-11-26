/// <reference types="vite/client" />

// 让 TypeScript 认识 .vue 单文件组件
//
// 为什么用 Record<string, unknown> 而不是 {}：
//   `{}` 在 TS 里表示"任何非空值"，会被 @typescript-eslint/no-empty-object-type
//   判为 error（实测：模板 lint 门禁开箱即红）。
//   Record<string, unknown> 表达"任意属性映射"，语义更准确且能过 lint。
declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
