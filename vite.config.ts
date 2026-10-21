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
    rollupOptions: {
      output: {
        /*
         * 只拆三类稳定第三方库，其余交给 Rollup 自动分包（路由 lazy chunk 已覆盖视图代码）。
         * 注意不要把 zustand 放进 flow：它同时被主 store 使用，会把 flow chunk 拖回首屏。
         */
        manualChunks(id: string) {
          if (!id.includes('node_modules')) return undefined;
          if (/node_modules[\\/](react|react-dom|scheduler)[\\/]/.test(id)) return 'react';
          if (
            /node_modules[\\/](@xyflow[\\/](react|system)|@dagrejs[\\/](dagre|graphlib)|classcat)[\\/]/.test(
              id,
            )
          ) {
            return 'flow';
          }
          if (/node_modules[\\/]date-fns[\\/]/.test(id)) return 'date';
          return undefined;
        },
      },
    },
  },
});
