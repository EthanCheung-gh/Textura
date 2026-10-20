import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Tauri 开发服务器：固定 1420 端口，供 tauri.conf.json 的 devUrl 使用。
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    watch: {
      ignored: ['**/src-tauri/**'],
    },
  },
  envPrefix: ['VITE_', 'TAURI_'],
  build: {
    target: 'es2022',
    sourcemap: false,
  },
});
