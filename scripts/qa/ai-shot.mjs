/**
 * 大模型配置卡片截图（README / 用户手册用）。
 *
 * 用法：TEXTURA_BASE_URL=http://localhost:1430 node scripts/qa/ai-shot.mjs
 * 前置：先运行 `npm run build && npx vite preview --port 1430 --strictPort`。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const SHOT = 'docs/screenshots/settings-ai.png';

await withPage(async (page, chrome) => {
  await page.goto(`${BASE_URL}/?route=settings`, { route: 'settings' });
  await page.waitFor(`!!document.getElementById('settings-ai')`, { label: 'AI settings card' });
  await sleep(600);

  await page.eval(`
    const input = document.querySelector('#ai-api-key');
    if (!input) throw new Error('API Key 输入框缺失');
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(input, 'sk-textura-demo-1234567890');
    input.dispatchEvent(new Event('input', { bubbles: true }));
    const enable = [...document.querySelectorAll('[aria-label="启用大模型"] button')].find(
      (button) => button.textContent.trim() === '启用',
    );
    if (!enable) throw new Error('启用按钮缺失');
    enable.click();
    return true;
  `);
  await sleep(500);

  const box = await page.eval(`
    const el = document.getElementById('settings-ai')?.closest('.settings-card');
    if (!el) throw new Error('大模型卡片缺失');
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const rect = el.getBoundingClientRect();
    return {
      x: rect.x + window.scrollX,
      y: rect.y + window.scrollY,
      width: rect.width,
      height: rect.height,
    };
  `);

  const pad = 16;
  const { data } = await page.cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: true,
    clip: {
      x: Math.max(0, box.x - pad),
      y: Math.max(0, box.y - pad),
      width: box.width + pad * 2,
      height: box.height + pad * 2,
      scale: 1,
    },
  });

  mkdirSync('docs/screenshots', { recursive: true });
  writeFileSync(SHOT, Buffer.from(data, 'base64'));

  const detail = await page.eval(`
    const card = document.getElementById('settings-ai')?.closest('.settings-card');
    return {
      badge: card?.querySelector('.badge')?.textContent.trim() ?? null,
      enabled: document.querySelector('[aria-label="启用大模型"] button[aria-pressed="true"]')?.textContent.trim() ?? null,
      toolsNote: [...card.querySelectorAll('.settings-note')].map((el) => el.textContent.trim()).find((text) => text.includes('MCP')) ?? null,
    };
  `);
  const issues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
  console.log(
    JSON.stringify(
      {
        shot: SHOT,
        chrome: chrome.browserVersion,
        box,
        detail,
        consoleIssues: issues,
      },
      null,
      2,
    ),
  );
  if (issues.length > 0) throw new Error(`截图期间出现 ${issues.length} 条控制台错误`);
});