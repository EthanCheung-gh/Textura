import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    alias: {
      '@textura/mcp': fileURLToPath(
        new URL('./packages/textura-mcp/src/index.ts', import.meta.url),
      ),
    },
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'packages/**/*.test.ts'],
    css: true,
    reporters: ['default'],
  },
});