import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 开发代理：前端同源请求 /api/*，转发到本地 FastAPI 服务，避免浏览器跨域。
export default defineConfig({
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
})
