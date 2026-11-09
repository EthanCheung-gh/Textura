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
          /*
           * KaTeX 有两个引用方：ReportsPage 的公式渲染，以及 mermaid 内部（流程图里的数学标签）。
           * 不指定时 Rollup 会给每处各切一个 `katex-*.js`（实测 261.72 kB + 262.06 kB）。
           * 注意这两份**不是同一个版本**：根依赖是 katex@0.19.1，mermaid 自带 katex@0.18.10，
           * 所以按路径归一后得到的是一个装着两份实现的 chunk（524.90 kB，gzip 155.88 kB）。
           * 收益是「一个可预测的 chunk 名、一个 chunk / 一次请求」——
           * **体积不省**，mermaid 数学路径会多下 ~262 kB（它本来只需要自己那份，现在拿到两份）。
           * （想真正省掉这 262 kB 需要把 mermaid 的 katex 解析到根版本，那是改语义的决定，不在这里做。）
           * manualChunks 只决定「进哪个文件」，不改变「什么时候加载」：katex 仍是懒加载 chunk，
           * 入口 chunk 里没有对它的静态 import（见构建产物验证）。CSS 不走这里。
           */
          if (/node_modules[\\/]katex[\\/]/.test(id) && !id.endsWith('.css')) return 'katex';
          return undefined;
        },
      },
    },
  },
});
