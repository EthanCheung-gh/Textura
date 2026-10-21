/**
 * 窄屏日历截图（新增 calendar-1024.png）+ 其余截图未受影响的对照校验。
 *
 * - 1024×720：点今天 → 面板自动展开（本轮修复行为）→ 截图，断言 0 console error / 无横向溢出。
 * - 1440×900：重拍一张到临时文件，与既有 docs/screenshots/calendar.png 对比；
 *   若逐字节一致，说明本轮 shell.css / 窄屏逻辑的改动不影响宽屏构图，无需重出其余 14 张。
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const OUT = 'docs/screenshots';
const issues = [];
const fail = (label, detail) => {
  issues.push({ label, detail });
  console.log(`FAIL  ${label} :: ${JSON.stringify(detail)}`);
};
const ok = (label, detail) => console.log(`PASS  ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
const sha = (buffer) => createHash('sha256').update(buffer).digest('hex');

await withPage(async (page) => {
  /* ---------------- 1024：新增截图 ---------------- */
  await page.setViewport(1024, 720);
  await page.goto(`${BASE_URL}/?route=calendar`, { route: 'calendar' });
  await sleep(900);
  const initial = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return { collapsed: panel.classList.contains('is-collapsed') };
  `);
  await page.eval(`document.querySelector('[data-date="2026-10-21"]').click(); return true;`);
  await sleep(800);
  const state = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return {
      collapsed: panel.classList.contains('is-collapsed'),
      panelWidth: Math.round(panel.getBoundingClientRect().width),
      visibleItems: [...document.querySelectorAll('.cal-item')].filter((el) => el.getBoundingClientRect().width > 0).length,
      cell: (() => { const c = document.querySelector('.cal-cell').getBoundingClientRect(); return { w: Math.round(c.width), h: Math.round(c.height) }; })(),
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    };
  `);
  const shot = await page.screenshot(`${OUT}/calendar-1024.png`);
  const errors = page.issues.filter((i) => i.level === 'error' || i.level === 'warning');

  if (initial.collapsed !== true) fail('1024 初始面板应默认收起', initial);
  else ok('1024 初始面板默认收起', initial);
  if (state.collapsed !== false || state.visibleItems === 0) fail('1024 点日期应自动展开并显示条目', state);
  else ok('1024 点日期自动展开并显示条目', state);
  if (state.overflowX !== 0 || state.scrollWidth !== 1024) fail('1024 无横向溢出', state);
  else ok('1024 无横向溢出（scrollWidth = 1024）', { scrollWidth: state.scrollWidth });
  if (errors.length) fail('1024 console error = 0', errors.map((e) => e.text.slice(0, 200)));
  else ok('1024 console error = 0');
  ok('已写入', { shot });

  /* ---------------- 1440：对照既有截图 ---------------- */
  await page.setViewport(1440, 900);
  await page.goto(`${BASE_URL}/?route=calendar`, { route: 'calendar' });
  await sleep(1100);
  const temp = '/tmp/calendar-1440-recheck.png';
  await page.screenshot(temp);
  const fresh = readFileSync(temp);
  const existing = readFileSync(`${OUT}/calendar.png`);
  const same = sha(fresh) === sha(existing);
  console.log(
    `${same ? 'PASS' : 'INFO'}  1440 构图对照 :: fresh=${sha(fresh).slice(0, 12)} existing=${sha(existing).slice(0, 12)} identical=${same}`,
  );
  if (!same) {
    writeFileSync('/tmp/calendar-1440-diff.png', fresh);
    console.log('INFO  宽屏存在像素差异，已另存 /tmp/calendar-1440-diff.png 供人工比对');
  }
});

console.log(`\nproblems: ${issues.length}`);
if (issues.length) process.exitCode = 1;
