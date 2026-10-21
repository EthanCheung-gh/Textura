/**
 * 性能优化后的功能回归（生产构建 + 懒加载路由）。
 * 覆盖：7 路由 console/溢出、快速收集→澄清、OKR 提交与视图切换、甘特拖拽写回、
 *      SOP 运行 3 步、日历快速添加、撤销/重做、分页阈值、懒加载骨架、错误边界恢复。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/perf-regression';
const ORIGIN = new URL(BASE_URL).origin;

const results = [];
let failures = 0;
function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
}

const ROUTE_BY_LABEL = { 今日: 'dashboard', 日历: 'calendar', OKR: 'okr', GTD: 'gtd', 甘特: 'gantt', SOP: 'sop', 设置: 'settings' };
const ROOT = { dashboard: '.dash-page', calendar: '.cal-page', okr: '.okr-page', gtd: '.gtd-page', gantt: '.gantt-page', sop: '.sop-page', settings: '.settings-page' };

async function navTo(page, label) {
  const route = ROUTE_BY_LABEL[label];
  await page.eval(`
    const link = [...document.querySelectorAll('.sidebar-nav .sidebar-link')]
      .find((el) => el.textContent.trim().startsWith(${JSON.stringify(label)}));
    if (!link) throw new Error('nav missing: ' + ${JSON.stringify(label)});
    link.click();
    return true;
  `);
  await page.waitFor(`document.documentElement.dataset.route === ${JSON.stringify(route)}`, { label: `route ${route}` });
  await page.waitFor(`!!document.querySelector(${JSON.stringify(ROOT[route])})`, { label: `root ${ROOT[route]}`, timeout: 20000 });
  await sleep(350);
  return route;
}

async function pressEnter(page) {
  await page.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r' });
  await page.cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
}

async function readWorkspace(page) {
  return page.eval(`const raw = localStorage.getItem(${JSON.stringify(KEY)}); return raw ? JSON.parse(raw) : null;`);
}

async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
    await sleep(700);

    /* ---------- 1) 7 路由 console / 溢出 ---------- */
    const routeReport = {};
    for (const label of ['今日', '日历', 'OKR', 'GTD', '甘特', 'SOP', '设置']) {
      page.resetIssues();
      await navTo(page, label);
      await sleep(500);
      routeReport[label] = await page.eval(`
        return {
          route: document.documentElement.dataset.route,
          overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          mainText: (document.querySelector('.shell-content')?.innerText || '').trim().length,
        };
      `);
      routeReport[label].errors = page.issues.filter((i) => i.level === 'error').map((i) => i.text.slice(0, 160));
    }
    check(
      'routes',
      '7 条路由 console error = 0、无横向溢出',
      Object.values(routeReport).every((entry) => entry.errors.length === 0 && entry.overflowX === 0 && entry.mainText > 50),
      routeReport,
    );

    /* ---------- 2) 快速收集 → 收件箱 → 澄清 → 下一步 ---------- */
    await navTo(page, 'GTD');
    const beforeInbox = await page.text('.gtd-flow-card--accent .gtd-flow-card-value');
    await page.eval(`
      const button = [...document.querySelectorAll('.gtd-page .page-header button')].find((el) => el.textContent.trim() === '快速收集');
      button.click();
      return true;
    `);
    await page.waitFor(`!!document.querySelector('#quick-capture-input')`, { label: 'capture modal' });
    await page.insertText('#perf @电脑 回归收集');
    await sleep(200);
    await pressEnter(page);
    await sleep(600);
    await page.pressKey('Escape', { code: 'Escape', vk: 27 });
    await sleep(300);
    const afterInbox = await page.text('.gtd-flow-card--accent .gtd-flow-card-value');
    check('capture', '快速收集后收件箱 +1', Number(afterInbox) === Number(beforeInbox) + 1, { beforeInbox, afterInbox });

    const opened = await page.eval(`
      const row = [...document.querySelectorAll('.gtd-inbox-row .gtd-row-title')].find((el) => el.textContent.trim() === '回归收集');
      if (!row) return false;
      row.click();
      return true;
    `);
    await page.waitFor(`!!document.querySelector('#gtd-clarify-form')`, { label: 'clarify form' });
    await page.eval(`const b=[...document.querySelectorAll('[role="dialog"] button')].find(el=>el.textContent.trim()==='完成澄清'); b.click(); return true;`);
    await sleep(700);
    const clarified = (await readWorkspace(page)).items.find((item) => item.title === '回归收集');
    check('capture', '澄清后进入下一步（status=next / clarified=true）', opened && clarified?.status === 'next' && clarified?.gtd?.clarified === true, clarified ? { status: clarified.status, clarified: clarified.gtd?.clarified } : null);

    /* ---------- 3) OKR 指标提交 + 切视图不丢 ---------- */
    await navTo(page, 'OKR');
    await page.click('input[aria-label$="指标当前值"]');
    await page.selectAll();
    await page.insertText('66');
    // 600ms 输入防抖：等 KR 进度变成 100%（66 >= target 60）再等保存落盘
    await page.waitFor(
      `(() => { const row = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60')); return row?.querySelector('.okr-kr-pct')?.textContent.trim() === '100%'; })()`,
      { label: 'okr metric committed', timeout: 6000 },
    );
    await page.waitFor(
      `[...document.querySelectorAll('.storage-status')].some((el) => el.textContent.includes('已保存'))`,
      { label: 'okr metric saved', timeout: 6000 },
    );
    await sleep(300);
    const metricAfterType = (await readWorkspace(page)).items.find((item) => item.id === 'kr_nps')?.okr?.metric?.current;
    await page.eval(`[...document.querySelectorAll('button')].find(el => el.textContent.trim() === '表格').click(); return true;`);
    await sleep(600);
    await page.eval(`[...document.querySelectorAll('button')].find(el => el.textContent.trim() === '卡片').click(); return true;`);
    await sleep(600);
    const cardValue = await page.eval(`return document.querySelector('input[aria-label$="指标当前值"]')?.value ?? null;`);
    check('okr', 'OKR 指标提交（600ms 防抖）并切表格/卡片不丢', metricAfterType === 66 && cardValue === '66', { metricAfterType, cardValue });

    /* ---------- 4) 甘特拖拽写回 ---------- */
    await navTo(page, '甘特');
    const label = await page.eval(`return document.querySelector('.gantt-bar[aria-label]')?.getAttribute('aria-label') ?? null;`);
    const title = (label ?? '').split('，')[0];
    await page.drag('.gantt-bar[aria-label]', 56, 0, { steps: 8 });
    await sleep(700);
    await page.reload({ route: 'gantt' });
    await sleep(800);
    const afterReloadLabel = await page.eval(`
      const bar = [...document.querySelectorAll('.gantt-bar[aria-label]')].find((el) => el.getAttribute('aria-label').startsWith(${JSON.stringify(title)}));
      return bar ? bar.getAttribute('aria-label') : null;
    `);
    check('gantt', '甘特拖拽改期并刷新后保留', Boolean(afterReloadLabel) && afterReloadLabel !== label, { before: label, after: afterReloadLabel });

    /* ---------- 5) SOP 运行 3 步 ---------- */
    await navTo(page, 'SOP');
    await page.eval(`[...document.querySelectorAll('button')].find(el => el.textContent.trim() === '运行').click(); return true;`);
    await page.waitFor(`!!document.querySelector('.sop-runbar')`, { label: 'run bar' });
    await sleep(400);
    const steps = [await page.text('.sop-runbar-progress')];
    for (let index = 0; index < 3; index += 1) {
      await page.eval(`
        const button = [...document.querySelectorAll('.sop-runbar-actions button')].find((el) => el.textContent.trim() === '通过');
        if (!button) throw new Error('通过 missing');
        button.click();
        return true;
      `);
      await sleep(500);
      steps.push(await page.text('.sop-runbar-progress'));
    }
    check('sop', 'SOP 运行模式连续 3 步推进', new Set(steps).size === 4, { steps });

    /* ---------- 6) 日历快速添加 ---------- */
    await navTo(page, '日历');
    await page.eval(`document.querySelector('[data-date="2026-10-21"]').click(); return true;`);
    await sleep(400);
    await page.click('input[aria-label="添加到这一天的日程标题"]');
    await page.insertText('性能回归日程');
    await sleep(150);
    await pressEnter(page);
    await sleep(800);
    const calendarItem = (await readWorkspace(page)).items.find((item) => item.title === '性能回归日程');
    const inPanel = await page.eval(`return [...document.querySelectorAll('.cal-item-title')].some((el) => el.textContent.trim() === '性能回归日程');`);
    check('calendar', '日历快速添加 1 条并出现在面板', calendarItem?.gantt?.start === '2026-10-21' && calendarItem?.status === 'next' && inPanel, calendarItem ? { start: calendarItem.gantt?.start, status: calendarItem.status, inPanel } : null);

    /* ---------- 7) 撤销 / 重做跨视图 ---------- */
    await navTo(page, 'GTD');
    const nextBefore = await page.text('.gtd-flow-card:nth-child(2) .gtd-flow-card-value');
    await page.eval(`document.querySelector('.gtd-next-row .gtd-check').click(); return true;`);
    await sleep(600);
    await navTo(page, '今日');
    const completedAfter = await page.eval(`
      const card = [...document.querySelectorAll('.dash-stat')].find((el) => el.querySelector('.dash-stat-label')?.textContent.trim() === '近 7 天完成');
      return Number((card?.querySelector('.dash-stat-value')?.textContent || '').replace(/\\D/g, ''));
    `);
    await page.eval(`document.activeElement?.blur(); window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, bubbles: true, cancelable: true })); return true;`);
    await sleep(700);
    const completedAfterUndo = await page.eval(`
      const card = [...document.querySelectorAll('.dash-stat')].find((el) => el.querySelector('.dash-stat-label')?.textContent.trim() === '近 7 天完成');
      return Number((card?.querySelector('.dash-stat-value')?.textContent || '').replace(/\\D/g, ''));
    `);
    await page.eval(`window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true })); return true;`);
    await sleep(700);
    const completedAfterRedo = await page.eval(`
      const card = [...document.querySelectorAll('.dash-stat')].find((el) => el.querySelector('.dash-stat-label')?.textContent.trim() === '近 7 天完成');
      return Number((card?.querySelector('.dash-stat-value')?.textContent || '').replace(/\\D/g, ''));
    `);
    check(
      'undo-redo',
      '撤销/重做跨视图一致（今日完成数）',
      completedAfter === completedAfterRedo && completedAfterUndo === completedAfter - 1,
      { nextBefore, completedAfter, completedAfterUndo, completedAfterRedo },
    );

    /* ---------- 8) 演示数据下分页不出现 ---------- */
    const pagination = {};
    for (const [label, route] of [['GTD', 'gtd'], ['OKR', 'okr'], ['今日', 'dashboard']]) {
      await navTo(page, label);
      if (route === 'okr') {
        await page.eval(`[...document.querySelectorAll('button')].find(el => el.textContent.trim() === '表格').click(); return true;`);
        await sleep(500);
      }
      pagination[label] = await page.eval(`return [...document.querySelectorAll('button')].filter((el) => el.textContent.includes('显示更多')).length;`);
    }
    check('pagination', '演示数据（30 条）下 GTD/OKR/今日 均无「显示更多」', Object.values(pagination).every((count) => count === 0), pagination);

    /* ---------- 9) 懒加载骨架 + 错误边界恢复 ---------- */
    await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
    await sleep(500);
    const skeleton = await page.eval(`
      window.__sawSkeleton = false;
      window.__skeletonRole = null;
      const obs = new MutationObserver(() => {
        const node = document.querySelector('.route-loading');
        if (node) {
          window.__sawSkeleton = true;
          window.__skeletonRole = node.getAttribute('role');
        }
      });
      obs.observe(document.body, { childList: true, subtree: true });
      const link = [...document.querySelectorAll('.sidebar-nav .sidebar-link')].find((el) => el.textContent.trim().startsWith('SOP'));
      link.click();
      await new Promise((resolve) => {
        const timer = setInterval(() => {
          if (document.querySelector('.sop-page')) { clearInterval(timer); obs.disconnect(); resolve(); }
        }, 10);
        setTimeout(() => { clearInterval(timer); obs.disconnect(); resolve(); }, 10000);
      });
      return { sawSkeleton: window.__sawSkeleton, role: window.__skeletonRole, canvas: Boolean(document.querySelector('.react-flow__canvas, .sop-canvas')) };
    `);
    check('skeleton', '首次进入 SOP：role=status 骨架出现后画布渲染', skeleton.sawSkeleton === true && skeleton.role === 'status' && skeleton.canvas === true, skeleton);

    await page.eval(`
      window.__qaRO = window.ResizeObserver;
      delete window.ResizeObserver;
      return true;
    `);
    await navTo(page, '甘特').catch(() => {});
    await sleep(800);
    const boundary = await page.eval(`
      const error = document.querySelector('.route-error');
      return {
        hasBoundary: Boolean(error),
        title: error?.querySelector('.route-error-title')?.textContent.trim() ?? null,
        shell: Boolean(document.querySelector('.sidebar') && document.querySelector('.topbar')),
      };
    `);
    await page.eval(`if (window.__qaRO) window.ResizeObserver = window.__qaRO; return true;`);
    await page.eval(`const b=[...document.querySelectorAll('.route-error button')].find(el=>el.textContent.trim()==='返回今日'); if (b) b.click(); return true;`);
    await sleep(900);
    const recovered = await page.eval(`
      return { route: document.documentElement.dataset.route, boundary: Boolean(document.querySelector('.route-error')), stats: document.querySelectorAll('.dash-stat').length };
    `);
    check('boundary', 'RouteErrorBoundary 呈现并可恢复', boundary.hasBoundary === true && boundary.shell === true && recovered.boundary === false && recovered.stats === 4, { boundary, recovered });
    await page.screenshot(`${OUT}/regression-final.png`);
  });

  writeFileSync(`${OUT}/regression-report.json`, JSON.stringify(results, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== PERF REGRESSION SUMMARY ===');
  for (const flow of flows) {
    const entries = results.filter((entry) => entry.flow === flow);
    const failed = entries.filter((entry) => !entry.ok);
    console.log(`${failed.length ? 'FAIL' : 'PASS'}  ${flow}  (${entries.length - failed.length}/${entries.length})`);
    for (const entry of failed) console.log(`      - ${entry.label}`);
  }
  console.log(`\n断言失败总数：${failures}`);
  if (failures) process.exitCode = 1;
}

main().catch((error) => {
  console.error('PERF REGRESSION FAILED:', error);
  process.exit(1);
});
