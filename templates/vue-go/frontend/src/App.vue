<script setup lang="ts">
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
    <h1>Vue + Go 最小示例工程</h1>
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
