<script setup lang="ts">
import { onMounted, ref } from 'vue'

type Status = 'checking' | 'ok' | 'error'

const status = ref<Status>('checking')
const message = ref('正在检查后端连接…')

async function checkHealth(): Promise<void> {
  status.value = 'checking'
  message.value = '正在检查后端连接…'

  try {
    const response = await fetch('/api/health')
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const data: unknown = await response.json()
    const isOk = typeof data === 'object' && data !== null && (data as { status?: unknown }).status === 'ok'
    if (!isOk) {
      throw new Error('响应格式与约定不符')
    }

    status.value = 'ok'
    message.value = '后端连接正常，健康检查返回 status: ok'
  } catch (error) {
    status.value = 'error'
    message.value = error instanceof Error ? error.message : String(error)
  }
}

onMounted(checkHealth)
</script>

<template>
  <main class="page">
    <h1>课程视频智能平台</h1>
    <p class="subtitle">v0.1 项目骨架 · 前后端连通性检查</p>

    <section class="card" :data-status="status">
      <p class="label">GET /api/health</p>

      <p class="state">
        <span class="dot" aria-hidden="true"></span>
        <span v-if="status === 'checking'">检查中…</span>
        <span v-else-if="status === 'ok'">连接成功</span>
        <span v-else>连接失败</span>
      </p>

      <p class="message">{{ message }}</p>

      <p v-if="status === 'error'" class="hint">
        请确认后端已启动（默认 http://127.0.0.1:8000），然后重试。
      </p>

      <button type="button" :disabled="status === 'checking'" @click="checkHealth">
        {{ status === 'checking' ? '检查中' : '重新检查' }}
      </button>
    </section>
  </main>
</template>

<style scoped>
.page {
  max-width: 40rem;
  margin: 0 auto;
  padding: 4rem 1.5rem;
  font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
  color: #1f2933;
}

h1 {
  margin: 0 0 0.5rem;
  font-size: 1.75rem;
}

.subtitle {
  margin: 0 0 2rem;
  color: #616e7c;
}

.card {
  padding: 1.5rem;
  border: 1px solid #d9e2ec;
  border-radius: 0.75rem;
  background: #ffffff;
}

.card[data-status='ok'] {
  border-color: #9ae6b4;
  background: #f0fff4;
}

.card[data-status='error'] {
  border-color: #feb2b2;
  background: #fff5f5;
}

.label {
  margin: 0 0 1rem;
  font-family: ui-monospace, 'Cascadia Code', monospace;
  font-size: 0.875rem;
  color: #616e7c;
}

.state {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0 0 0.5rem;
  font-size: 1.125rem;
  font-weight: 600;
}

.dot {
  width: 0.625rem;
  height: 0.625rem;
  border-radius: 50%;
  background: #cbd2d9;
}

.card[data-status='ok'] .dot {
  background: #38a169;
}

.card[data-status='error'] .dot {
  background: #e53e3e;
}

.message {
  margin: 0 0 1rem;
  color: #323f4b;
  word-break: break-word;
}

.hint {
  margin: 0 0 1rem;
  padding: 0.75rem;
  border-radius: 0.5rem;
  background: #ffffff;
  font-size: 0.875rem;
  color: #616e7c;
}

button {
  padding: 0.5rem 1rem;
  border: 1px solid #bcccdc;
  border-radius: 0.5rem;
  background: #ffffff;
  font-size: 0.9375rem;
  cursor: pointer;
}

button:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

button:not(:disabled):hover {
  border-color: #7b8794;
}
</style>
