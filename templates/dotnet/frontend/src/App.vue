<script setup lang="ts">
// 首页组件：加载后请求 /api/v1/greeting，渲染成功/失败/加载三态（对应 FR-4、FR-5）
import { ref, onMounted } from 'vue'
import { fetchGreeting, type Greeting } from './api'

const greeting = ref<Greeting | null>(null)
const error = ref('')

onMounted(async () => {
  try {
    greeting.value = await fetchGreeting()
  } catch (e) {
    error.value = e instanceof Error ? e.message : '未知错误'
  }
})
</script>

<template>
  <main class="app">
    <h1>.NET + Vue 最小示例工程</h1>
    <p class="stack">ASP.NET Core 8 Minimal API · C# 12 · Vue 3 + TypeScript</p>

    <p v-if="greeting" class="greeting">
      {{ greeting.message }} <span class="time">({{ greeting.time }})</span>
    </p>
    <p v-else-if="error" class="error">{{ error }}</p>
    <p v-else class="loading">加载中…</p>
  </main>
</template>

<style scoped>
.app {
  font-family: system-ui, sans-serif;
  max-width: 600px;
  margin: 4rem auto;
  text-align: center;
}
.stack {
  color: #888;
  font-size: 0.85rem;
}
.greeting {
  font-size: 1.2rem;
  color: #2c7a2c;
}
.time {
  color: #888;
  font-size: 0.9rem;
}
.error {
  color: #c0392b;
}
.loading {
  color: #888;
}
</style>
