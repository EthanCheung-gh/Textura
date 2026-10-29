/**
 * 独立验收回归：7 条路由 + OKR 列表态控件 / 表格 / 对齐视图
 * + 快速收集 / 甘特拖拽 / 日历添加各抽测 1 条。
 *
 * 用法：TEXTURA_BASE_URL=http://localhost:1434 node scripts/qa/okr-editor-regression.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/okr-editor-acceptance';

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  const payload = detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${payload}`);
}

const ROUTE_BY_LABEL = {
  今日: 'dashboard',
  日历: 'calendar',
  OKR: 'okr',
  GTD: 'gtd',
  甘特: 'gantt',
  SOP: 'sop',
  设置: 'settings',
};

const ROUTE_LABEL = Object.fromEntries(Object.entries(ROUTE_BY_LABEL).map(([label, route]) => [route, label]));

const ROUTE_ROOT = {
  dashboard: '.dash-page',
  calendar: '.cal-page',
  okr: '.okr-page',
  gtd: '.gtd-page',
  gantt: '.gantt-page',
  sop: '.sop-page',
  settings: '.settings-page',
};

async function hardReset(page, route = 'dashboard') {
  await page.cdp.send('Page.navigate', { url: 'about:blank' });
  await page.waitFor(`document.readyState === 'complete'`, { label: 'about:blank ready' });
  await sleep(250);
  const { identifier } = await page.cdp.send('Page.addScriptToEvaluateOnNewDocument', {
    source: 'try { localStorage.clear(); } catch (error) {}',
  });
  try {
    await page.goto(`${BASE_URL}/?route=${route}`, { route });
  } finally {
    await page.cdp.send('Page.removeScriptToEvaluateOnNewDocument', { identifier }).catch(() => {});
  }
  await sleep(600);
}

async function navTo(page, label) {
  const route = ROUTE_BY_LABEL[label];
  await page.eval(`
    const button = [...document.querySelectorAll('.sidebar-nav .sidebar-link')]
      .find((el) => el.textContent.trim().startsWith(${JSON.stringify(label)}));
    if (!button) throw new Error('sidebar link not found: ' + ${JSON.stringify(label)});
    button.click();
    return true;
  `);
  await page.waitFor(`document.documentElement.dataset.route === ${JSON.stringify(route)}`, { label: `route ${route}` });
  await page.waitFor(`!!document.querySelector(${JSON.stringify(ROUTE_ROOT[route])})`, { label: `root ${ROUTE_ROOT[route]}` });
  await sleep(550);
  return route;
}

async function clickText(page, text, scope = 'body') {
  const ok = await page.eval(`
    const target = [...document.querySelectorAll(${JSON.stringify(scope)} + ' button')]
      .find((el) => el.textContent.trim() === ${JSON.stringify(text)});
    if (!target) return false;
    target.scrollIntoView({ block: 'center' });
    target.click();
    return true;
  `);
  if (!ok) throw new Error(`button not found: ${text} (scope ${scope})`);
  await sleep(450);
}

async function pressEnter(page) {
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyDown',
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
    text: '\r',
    unmodifiedText: '\r',
  });
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
  });
}

async function readWorkspace(page) {
  return page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(KEY)});
    return raw ? JSON.parse(raw) : null;
  `);
}

async function waitSaved(page, timeout = 6000) {
  await page.waitFor(
    `[...document.querySelectorAll('.storage-status')].some((el) => el.textContent.includes('已保存'))`,
    { label: 'storage status 已保存', timeout },
  );
}

function errorsSince(page, from) {
  return page.issues
    .slice(from)
    .filter((issue) => issue.level === 'error')
    .map((issue) => issue.text.slice(0, 200));
}

/* =========================================================== routes ==== */
async function flowRoutes(page) {
  const flow = '3-routes';
  await hardReset(page, 'dashboard');
  const report = {};
  for (const label of ['今日', '日历', 'OKR', 'GTD', '甘特', 'SOP', '设置']) {
    const from = page.issues.length;
    const route = await navTo(page, label);
    await sleep(350);
    const state = await page.eval(`
      return {
        route: document.documentElement.dataset.route,
        rootPresent: !!document.querySelector(${JSON.stringify(ROUTE_ROOT[route])}),
        overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        mainTextLength: (document.querySelector('.shell-content')?.innerText || '').trim().length,
        boundary: Boolean(document.querySelector('.route-error')),
      };
    `);
    report[label] = { ...state, errors: errorsSince(page, from) };
  }

  for (const [label, state] of Object.entries(report)) {
    check(
      flow,
      `${label}（${state.route}）console error = 0 且无横向溢出`,
      state.errors.length === 0 &&
        state.overflowX === 0 &&
        state.rootPresent === true &&
        state.boundary === false &&
        state.mainTextLength > 50,
      state,
    );
  }
}

/* ======================================================= okr list ====== */
async function flowOkrList(page) {
  const flow = '3-okr-list-controls';
  const from = page.issues.length;
  await navTo(page, 'OKR');

  const controls = await page.eval(`
    const groups = [...document.querySelectorAll('.okr-header-actions [role="group"]')].map((el) => ({
      label: el.getAttribute('aria-label'),
      options: [...el.querySelectorAll('button')].map((b) => b.textContent.trim()),
      active: el.querySelector('button.is-active')?.textContent.trim() ?? null,
    }));
    const headerButtons = [...document.querySelectorAll('.okr-header-actions > button')].map((b) => b.textContent.trim());
    const periodButtons = [...document.querySelectorAll('.okr-periodbar button')].map((b) => b.textContent.replace(/\\s+/g, ' ').trim());
    return {
      groups,
      headerButtons,
      periodButtons,
      cards: document.querySelectorAll('.okr-objective').length,
      editButtons: document.querySelectorAll('[data-edit-objective]').length,
    };
  `);
  check(
    flow,
    'OKR 列表态视图切换（卡片/表格/对齐）仍在',
    controls.groups.some((group) => group.label === '切换 OKR 视图' && group.options.join('/') === '卡片/表格/对齐'),
    controls.groups,
  );
  check(
    flow,
    'OKR 列表态密度切换（紧凑/详细）仍在',
    controls.groups.some((group) => group.label === '切换卡片密度' && group.options.join('/') === '紧凑/详细'),
    controls.groups,
  );
  check(flow, '「新建目标」按钮仍在', controls.headerButtons.includes('新建目标'), { headerButtons: controls.headerButtons });
  check(flow, '「新建季度」按钮仍在', controls.periodButtons.some((text) => text.includes('新建季度')), { periodButtons: controls.periodButtons });
  check(flow, '列表卡片与编辑入口数量一致（1 目标 = 1 编辑按钮）', controls.cards === 1 && controls.editButtons === 1, {
    cards: controls.cards,
    editButtons: controls.editButtons,
  });

  // 密度切换：紧凑隐藏指标编辑器
  await clickText(page, '紧凑');
  const compact = await page.eval(`
    return {
      rows: document.querySelectorAll('.okr-kr--compact').length,
      metricInputs: document.querySelectorAll('.okr-metric-input').length,
    };
  `);
  check(flow, '密度「紧凑」隐藏指标输入', compact.rows === 3 && compact.metricInputs === 0, compact);
  await clickText(page, '详细');
  const detailed = await page.eval(`
    return {
      rows: document.querySelectorAll('.okr-kr--detailed').length,
      metricInputs: document.querySelectorAll('.okr-metric-input').length,
    };
  `);
  check(flow, '密度「详细」恢复指标输入（12 个）', detailed.rows === 3 && detailed.metricInputs === 12, detailed);

  // 表格视图
  await clickText(page, '表格');
  const table = await page.eval(`
    const root = document.querySelector('.okr-table');
    return {
      exists: Boolean(root),
      caption: root?.querySelector('caption')?.textContent.trim() ?? null,
      objectiveRows: document.querySelectorAll('.okr-table-objective').length,
      krRows: document.querySelectorAll('.okr-table-kr, .okr-table tbody tr').length,
      text: (root?.innerText || '').slice(0, 160),
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
  check(
    flow,
    '表格视图渲染目标与 3 条 KR，无横向溢出',
    table.exists && table.objectiveRows === 1 && table.text.includes('NPS 从 42 提升到 60') && table.overflowX === 0,
    table,
  );
  await page.screenshot(`${OUT}/3-okr-table.png`);

  // 对齐视图
  await clickText(page, '对齐');
  const alignment = await page.eval(`
    const root = document.querySelector('.okr-align');
    return {
      exists: Boolean(root),
      objectives: document.querySelectorAll('.okr-align-objective').length,
      krs: document.querySelectorAll('.okr-align-krs > li').length,
      text: (root?.innerText || '').slice(0, 160),
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
  check(
    flow,
    '对齐视图渲染目标与 3 条 KR，无横向溢出',
    alignment.exists && alignment.objectives === 1 && alignment.krs === 3 && alignment.overflowX === 0,
    alignment,
  );
  await page.screenshot(`${OUT}/3-okr-alignment.png`);

  await clickText(page, '卡片');
  check(flow, '切回卡片视图正常', (await page.eval(`return document.querySelectorAll('.okr-objective').length;`)) === 1);
  check(flow, 'OKR 列表态期间 console error = 0', errorsSince(page, from).length === 0, { errors: errorsSince(page, from) });
}

/* ==================================================== quick capture ==== */
async function flowQuickCapture(page) {
  const flow = '3-quick-capture';
  const from = page.issues.length;
  await navTo(page, 'GTD');
  await page.eval(`
    const button = [...document.querySelectorAll('.gtd-page .page-header button')].find((el) => el.textContent.trim() === '快速收集');
    if (!button) throw new Error('quick capture button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('#quick-capture-input')`, { label: 'quick capture modal' });
  await sleep(250);
  await page.insertText('验收快速收集 #qa @电脑');
  await sleep(200);
  await pressEnter(page);
  await sleep(900);
  const state = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const item = ws.items.find((entry) => entry.title === '验收快速收集');
    return {
      stored: item
        ? { id: item.id, kind: item.kind, status: item.status, tags: item.tags, context: item.gtd?.context ?? null, clarified: item.gtd?.clarified ?? null }
        : null,
      sessionRows: [...document.querySelectorAll('.capture-session-row')].map((row) => row.textContent.replace(/\\s+/g, ' ').trim()),
      open: Boolean(document.querySelector('#quick-capture-input')),
    };
  `);
  check(
    flow,
    '快速收集 1 条：action + inbox + 标签/场景解析',
    state.stored?.kind === 'action' && state.stored?.status === 'inbox' && state.stored?.tags.includes('qa') && state.stored?.context === '电脑',
    state.stored,
  );
  check(flow, '快速收集会话列表出现该条', state.sessionRows.some((text) => text.includes('验收快速收集')), { sessionRows: state.sessionRows });
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);
  check(flow, 'Esc 关闭快速收集弹窗', (await page.eval(`return !document.querySelector('#quick-capture-input');`)) === true);
  check(flow, '快速收集期间 console error = 0', errorsSince(page, from).length === 0, { errors: errorsSince(page, from) });
}

/* ======================================================== gantt drag === */
function parseDateRange(label) {
  const match = (label ?? '').match(/(\d{4}-\d{2}-\d{2}) 至 (\d{4}-\d{2}-\d{2})/);
  return match ? { start: match[1], end: match[2] } : null;
}

async function flowGantt(page) {
  const flow = '3-gantt-drag';
  const from = page.issues.length;
  await navTo(page, '甘特');
  await sleep(800);
  const before = await page.eval(`
    const bar = document.querySelector('.gantt-bar[aria-label]');
    return bar ? { label: bar.getAttribute('aria-label'), height: bar.getBoundingClientRect().height } : null;
  `);
  check(flow, '甘特存在可拖动任务条', Boolean(before && parseDateRange(before.label)), before);
  if (!before) return;
  const beforeRange = parseDateRange(before.label);
  const title = before.label.split('，')[0];

  await page.drag('.gantt-bar[aria-label]', 56, 0, { steps: 8 });
  await sleep(700);
  await waitSaved(page);
  const after = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const item = ws.items.find((entry) => entry.title === ${JSON.stringify(title)});
    const bar = [...document.querySelectorAll('.gantt-bar[aria-label]')].find((el) => el.getAttribute('aria-label').startsWith(${JSON.stringify(title)}));
    return {
      storedStart: item?.gantt?.start ?? null,
      storedEnd: item?.gantt?.end ?? null,
      label: bar?.getAttribute('aria-label') ?? null,
      selected: bar?.classList.contains('is-selected') ?? null,
    };
  `);
  const afterRange = parseDateRange(after.label);
  check(
    flow,
    '甘特拖拽后日期变化并写入 localStorage',
    Boolean(afterRange) && afterRange.start !== beforeRange.start && after.storedStart === afterRange.start && after.storedEnd === afterRange.end,
    { beforeRange, afterRange, storedStart: after.storedStart, storedEnd: after.storedEnd },
  );

  await page.reload({ route: 'gantt' });
  await page.waitFor(`!!document.querySelector('.gantt-page')`, { label: 'gantt after reload' });
  await sleep(800);
  const reloaded = await page.eval(`
    const bar = [...document.querySelectorAll('.gantt-bar[aria-label]')].find((el) => el.getAttribute('aria-label').startsWith(${JSON.stringify(title)}));
    return bar?.getAttribute('aria-label') ?? null;
  `);
  const reloadRange = parseDateRange(reloaded);
  check(
    flow,
    '刷新后甘特日期保留',
    reloadRange?.start === afterRange?.start && reloadRange?.end === afterRange?.end,
    { reloaded, reloadRange },
  );
  check(flow, '甘特拖拽期间 console error = 0', errorsSince(page, from).length === 0, { errors: errorsSince(page, from) });
}

/* ===================================================== calendar add ==== */
async function flowCalendar(page) {
  const flow = '3-calendar-add';
  const from = page.issues.length;
  await navTo(page, '日历');
  await sleep(700);
  const today = await page.eval(`return new Date().toISOString().slice(0, 10);`);
  const cellSelected = await page.eval(`
    const cell = document.querySelector('[data-date="${today}"]');
    if (!cell) return false;
    cell.click();
    return true;
  `);
  check(flow, `日历存在今天（${today}）的日期格`, cellSelected === true);
  await sleep(500);
  await page.click('input[aria-label="添加到这一天的日程标题"]');
  await page.insertText('验收日历添加');
  await sleep(200);
  await pressEnter(page);
  await sleep(1000);
  const state = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const item = ws.items.find((entry) => entry.title === '验收日历添加');
    return {
      stored: item
        ? { id: item.id, kind: item.kind, status: item.status, start: item.gantt?.start ?? null, end: item.gantt?.end ?? null }
        : null,
      inPanel: [...document.querySelectorAll('.cal-item-title')].some((el) => el.textContent.trim() === '验收日历添加'),
      cellDots: document.querySelector('[data-date="${today}"]')?.querySelectorAll('.cal-dot').length ?? null,
    };
  `);
  check(
    flow,
    '日历添加 1 条：action + next + start=end=今天',
    state.stored?.kind === 'action' && state.stored?.status === 'next' && state.stored?.start === today && state.stored?.end === today,
    state.stored,
  );
  check(flow, '新条目出现在当天面板', state.inPanel === true, { inPanel: state.inPanel, cellDots: state.cellDots });
  check(flow, '日历添加期间 console error = 0', errorsSince(page, from).length === 0, { errors: errorsSince(page, from) });
}

async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    for (const flow of [flowRoutes, flowOkrList, flowQuickCapture, flowGantt, flowCalendar]) {
      try {
        await flow(page);
      } catch (error) {
        check(flow.name, `流程异常：${error.message.split('\n')[0]}`, false, {
          error: error.message.split('\n').slice(0, 3).join(' | '),
        });
        await page.screenshot(`${OUT}/${flow.name}-failed.png`).catch(() => {});
      }
    }
  });

  writeFileSync(`${OUT}/regression-report.json`, JSON.stringify({ baseUrl: BASE_URL, results }, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== OKR EDITOR REGRESSION SUMMARY ===');
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
  console.error('OKR EDITOR REGRESSION FAILED:', error);
  process.exit(1);
});
