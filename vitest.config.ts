import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    // `.test.tsx` 也纳入匹配：组件测试若命名为 ReportEditor.test.tsx，只写 `.test.ts`
    // 会让它被静默跳过（跑绿了却根本没执行）。目前还没有 .tsx 测试，用例数不变。
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    css: true,
    reporters: ['default'],
  },
});
