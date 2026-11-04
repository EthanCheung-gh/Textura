/**
 * 16:9 / 最低 1920×1080 的对外截图集（应用市场等），与 README 的 3:2 截图集分开维护；
 * 本脚本不走 3:2 补白（截图一律 `{ pad: false }`，输出严格 1920×1080）。
 *
 * 7 条主视图：dashboard / calendar / okr / gtd / gantt / sop / settings
 * 落盘目录：docs/screenshots/16x9/<route>.png
 *
 * 每张写完立刻用 pngSize() 回读校验（w * 9 === h * 16），视口或补白逻辑一旦改动
 * 就会立刻报错，而不是静默产出错误尺寸的截图。
 */
import { readFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage, pngSize } from './lib.mjs';

const ROUTES = ['dashboard', 'calendar', 'okr', 'gtd', 'gantt', 'sop', 'settings'];
const SHOT_DIR = 'docs/screenshots/16x9';
const VIEWPORT = { width: 1920, height: 1080 };
// 与 3:2 截图脚本（smoke.mjs，默认 9333）错开端口，避免两个 QA 进程抢同一个 Chrome。
const CHROME_PORT = Number(process.env.TEXTURA_CHROME_PORT || 9334);

const results = [];

await withPage(
  async (page, chrome) => {
    console.log(`[16x9] Chrome: ${chrome.browserVersion}  BASE_URL=${BASE_URL}`);
    // 显式设置视口，不依赖 withPage 的默认值
    await page.setViewport(VIEWPORT.width, VIEWPORT.height);

    for (const route of ROUTES) {
      await page.goto(`${BASE_URL}/?route=${route}`, { route });
      await sleep(900); // 等图表 / 字体 / 保存防抖稳定
      const shot = `${SHOT_DIR}/${route}.png`;
      await page.screenshot(shot, { pad: false });

      // 自校验：对外截图必须是原生 16:9，且与视口尺寸一致
      const { width, height } = pngSize(readFileSync(shot));
      if (width * 9 !== height * 16) {
        throw new Error(`[16x9] ${shot} 不是 16:9：${width}×${height}（width * 9 !== height * 16）`);
      }
      if (width !== VIEWPORT.width || height !== VIEWPORT.height) {
        throw new Error(`[16x9] ${shot} 尺寸异常：${width}×${height}，期望 ${VIEWPORT.width}×${VIEWPORT.height}`);
      }

      const issues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
      results.push({ route, shot, size: `${width}x${height}`, issues });
      console.log(`[16x9] ${route} -> ${shot} ${width}x${height} errors=${issues.length}`);
      for (const issue of issues) console.log(`    [${issue.level}] ${issue.source}: ${issue.text.slice(0, 300)}`);
    }
  },
  { width: VIEWPORT.width, height: VIEWPORT.height, port: CHROME_PORT, profileDir: '/tmp/textura-qa-profile-16x9' },
);

const expected = ROUTES.length;
const failures = results.filter((entry) => entry.issues.some((issue) => issue.level === 'error'));

console.log('\n=== 16:9 SHOTS SUMMARY ===');
console.log(`captured: ${results.length}/${expected}  目录: ${SHOT_DIR}/  尺寸: ${VIEWPORT.width}×${VIEWPORT.height}`);
console.log(`console errors: ${failures.length} 项${failures.length ? `（${failures.map((e) => e.route).join(', ')}）` : ''}`);
for (const entry of failures) {
  console.log(`    ${entry.route}: ${entry.issues.filter((i) => i.level === 'error').length} error(s)`);
}
if (results.length !== expected) {
  console.log(`FAILED: 只产出 ${results.length}/${expected} 张`);
  process.exitCode = 1;
}
if (failures.length) process.exitCode = 1;
