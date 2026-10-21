/**
 * 性能证据截图（干净状态，无通知浮层）：
 *   perf-10k-dashboard.png —— 10k 数据下的今日视图
 *   perf-gantt-2k.png      —— 10k 数据下的甘特（2,001 条带日期，DOM 虚拟化）
 */
import { readFileSync } from 'node:fs';
import { BASE_URL, Cdp, Page, launchChrome, sleep } from './lib.mjs';

const json = readFileSync('/tmp/textura-perf/workspace-10k.json', 'utf8');
const KEY = 'textura.workspace.v1';
const issues = [];

const chrome = await launchChrome({ port: 9333, width: 1440, height: 900 });
const cdp = await Cdp.connect(chrome.wsUrl);
const page = await Page.create(cdp);
try {
  await page.setViewport(1440, 900);
  await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
  await page.eval(`localStorage.setItem(${JSON.stringify(KEY)}, ${JSON.stringify(json)}); return true;`, { timeout: 120000 });
  await page.cdp.send('Page.reload', { ignoreCache: false });
  await page.waitFor(`!!document.querySelector('.shell')`, { label: 'shell', timeout: 60000 });
  await page.waitRouteRoot('dashboard', 60000);
  await sleep(1200);

  const dash = await page.eval(`
    return {
      rows: document.querySelectorAll('.dash-focus-row').length,
      stats: [...document.querySelectorAll('.dash-stat')].map((el) => el.querySelector('.dash-stat-label')?.textContent.trim() + '=' + el.querySelector('.dash-stat-value')?.textContent.trim()),
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
  await page.screenshot('docs/screenshots/perf-10k-dashboard.png');
  console.log('perf-10k-dashboard.png', JSON.stringify(dash), 'errors=', page.issues.filter((i) => i.level === 'error').length);

  page.resetIssues();
  await page.eval(`
    [...document.querySelectorAll('.sidebar-nav .sidebar-link')].find((el) => el.textContent.trim().startsWith('甘特')).click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('.gantt-page')`, { label: 'gantt root', timeout: 30000 });
  await sleep(1200);
  const gantt = await page.eval(`
    return {
      treeRows: document.querySelectorAll('.gantt-tree-row').length,
      headerCols: document.querySelectorAll('.gantt-header-col').length,
      bars: document.querySelectorAll('.gantt-bar').length,
      total: document.querySelector('.gantt-tree-head-count')?.textContent.trim() ?? null,
      scheduled: document.querySelector('.gantt-count')?.textContent.trim() ?? null,
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
  await page.screenshot('docs/screenshots/perf-gantt-2k.png');
  const errors = page.issues.filter((i) => i.level === 'error');
  console.log('perf-gantt-2k.png', JSON.stringify(gantt), 'errors=', errors.length);
  if (errors.length) {
    issues.push(...errors);
    console.log(errors.map((e) => e.text.slice(0, 200)));
  }
  if (dash.overflowX !== 0 || gantt.overflowX !== 0) issues.push({ label: 'overflow' });
} finally {
  cdp.close();
  await chrome.close();
}
console.log(`problems: ${issues.length}`);
if (issues.length) process.exitCode = 1;
