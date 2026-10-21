/**
 * 第四轮：日历视图 + 快速收集归属 + OKR 页头 验收（a–i）。
 * 全部通过 CDP 真实交互 + DOM/localStorage 断言。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/calendar-acceptance';
const ORIGIN = new URL(BASE_URL).origin;

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
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
  await sleep(450);
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
  await sleep(300);
}

async function clearAndReset(page, route) {
  let onApp = false;
  try {
    onApp = await page.eval(`return location.origin === ${JSON.stringify(ORIGIN)};`);
  } catch {
    onApp = false;
  }
  if (!onApp) await page.goto(`${BASE_URL}/?route=${route}`, { route });
  await page.eval(`localStorage.clear(); return true;`);
  await page.goto(`${BASE_URL}/?route=${route}`, { route });
  await sleep(500);
}

async function readWorkspace(page) {
  return page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(KEY)});
    return raw ? JSON.parse(raw) : null;
  `);
}

async function setSelect(page, ariaLabel, value) {
  await page.eval(`
    const el = document.querySelector('select[aria-label=' + JSON.stringify(${JSON.stringify(ariaLabel)}) + ']');
    if (!el) throw new Error('select not found: ' + ${JSON.stringify(ariaLabel)});
    const setter = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, 'value').set;
    setter.call(el, ${JSON.stringify(value)});
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  `);
  await sleep(500);
}

async function cellInfo(page, date) {
  return page.eval(`
    const el = document.querySelector('[data-date="${date}"]');
    if (!el) return null;
    return {
      date: el.dataset.date,
      aria: el.getAttribute('aria-label'),
      lunar: el.querySelector('.cal-lunar')?.textContent.trim() ?? null,
      lunarClass: el.querySelector('.cal-lunar')?.className ?? null,
      daynum: el.querySelector('.cal-daynum')?.textContent.trim() ?? null,
      today: el.classList.contains('is-today'),
      selected: el.classList.contains('is-selected'),
      outside: el.classList.contains('is-outside'),
      dots: el.querySelectorAll('.cal-dot').length,
      more: el.querySelector('.cal-dot-more')?.textContent.trim() ?? null,
    };
  `);
}

async function selectDate(page, date) {
  const ok = await page.eval(`
    const el = document.querySelector('[data-date="${date}"]');
    if (!el) return false;
    el.click();
    return true;
  `);
  if (!ok) throw new Error(`cell not found: ${date}`);
  await sleep(450);
}

/** Enter 需要完整 keyDown（带 text）才会触发原生表单提交。 */
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

/* ------------------------------------------------------------------ a --- */
async function flowA(page) {
  const flow = 'a-quick-capture-placement';
  await clearAndReset(page, 'dashboard');

  const perRoute = {};
  for (const label of ['今日', '日历', 'OKR', 'GTD', '甘特', 'SOP', '设置']) {
    await navTo(page, label);
    perRoute[label] = await page.eval(`
      const topbar = document.querySelector('.topbar');
      const hits = [...topbar.querySelectorAll('button')].filter((el) =>
        (el.textContent + ' ' + (el.getAttribute('aria-label') || '')).includes('快速收集'),
      );
      return { topbarCaptureButtons: hits.length, topbarButtons: [...topbar.querySelectorAll('button')].map((el) => (el.getAttribute('aria-label') || el.textContent).trim().slice(0, 18)) };
    `);
  }
  check(
    flow,
    '所有路由顶栏均无「快速收集」按钮',
    Object.values(perRoute).every((entry) => entry.topbarCaptureButtons === 0),
    perRoute,
  );

  await navTo(page, '今日');
  const dashboardHeader = await page.eval(`
    const header = document.querySelector('.page-header');
    return {
      buttons: [...header.querySelectorAll('button')].map((el) => el.textContent.trim()),
      captureHits: [...header.querySelectorAll('button')].filter((el) => (el.textContent + ' ' + (el.getAttribute('aria-label') || '')).includes('快速收集')).length,
    };
  `);
  check(flow, '今日页页头无收集入口', dashboardHeader.captureHits === 0, dashboardHeader);

  await navTo(page, 'GTD');
  const gtdHeader = await page.eval(`
    const header = document.querySelector('.page-header');
    const button = [...header.querySelectorAll('button')].find((el) => el.textContent.trim() === '快速收集');
    if (!button) return { found: false };
    const rect = button.getBoundingClientRect();
    return {
      found: true,
      primary: button.classList.contains('btn--primary'),
      aria: button.getAttribute('aria-label'),
      title: button.getAttribute('title'),
      rect: { w: Math.round(rect.width), h: Math.round(rect.height) },
    };
  `);
  check(flow, 'GTD 页头有 primary「快速收集」', gtdHeader.found === true && gtdHeader.primary === true, gtdHeader);

  await clickText(page, '快速收集', '.gtd-page .page-header');
  await page.waitFor(`!!document.querySelector('.modal')`, { label: 'capture modal' });
  await sleep(300);
  const dialog = await page.eval(`
    const modal = document.querySelector('.modal');
    return {
      title: modal.querySelector('.modal-title')?.textContent.trim() ?? null,
      focused: document.activeElement?.id ?? null,
    };
  `);
  check(flow, '弹窗标题为「收集到 GTD 收件箱」', dialog.title === '收集到 GTD 收件箱', dialog);

  const before = await page.eval(`
    const card = document.querySelectorAll('.gtd-flow-card')[0];
    return Number(card?.querySelector('.gtd-flow-card-value')?.textContent.trim() ?? -1);
  `);
  await page.insertText('#qa @电话 测试收集');
  await sleep(300);
  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(600);
  const after = await page.eval(`
    const card = document.querySelectorAll('.gtd-flow-card')[0];
    return {
      inbox: Number(card?.querySelector('.gtd-flow-card-value')?.textContent.trim() ?? -1),
      sidebar: Number(document.querySelector('.sidebar-link-count')?.textContent.trim() ?? -1),
    };
  `);
  const ws = await readWorkspace(page);
  const created = ws.items.find((item) => item.title === '测试收集');
  check(flow, '收集后 GTD 收件箱计数 +1', after.inbox === before + 1, { before, after });
  check(
    flow,
    '字段正确：tags=[qa] context=电话 status=inbox clarified=false',
    Boolean(created) &&
      created.tags.includes('qa') &&
      created.gtd?.context === '电话' &&
      created.status === 'inbox' &&
      created.gtd?.clarified === false,
    created ? { tags: created.tags, context: created.gtd?.context, status: created.status, clarified: created.gtd?.clarified } : null,
  );
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);

  // ⌘/Ctrl+N 仍全局可用（headless 会吞掉 Ctrl+N，退回合成事件验证绑定）
  page.resetIssues();
  await page.shortcut('n');
  await sleep(500);
  let opened = await page.eval(`return !!document.querySelector('#quick-capture-input');`);
  let method = 'ctrl+n(cdp)';
  if (!opened) {
    await page.eval(`
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'n', code: 'KeyN', ctrlKey: true, bubbles: true, cancelable: true }));
      return true;
    `);
    await sleep(500);
    opened = await page.eval(`return !!document.querySelector('#quick-capture-input');`);
    method = 'synthetic ctrl+n';
  }
  check(flow, '⌘/Ctrl+N 仍可全局打开收集弹窗', opened === true, { method });
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await page.screenshot(`${OUT}/a-gtd-capture.png`);
}

/* ------------------------------------------------------------------ b --- */
async function flowB(page) {
  const flow = 'b-dashboard-empty';
  await clearAndReset(page, 'dashboard');
  await page.eval(`localStorage.setItem(${JSON.stringify(KEY)}, JSON.stringify({ version: 1, items: [], edges: [], areas: [], runs: [] })); return true;`);
  await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
  await sleep(700);

  const empty = await page.eval(`
    const header = document.querySelector('.page-header');
    return {
      buttons: [...document.querySelectorAll('.shell-content button')].map((el) => el.textContent.trim()).filter(Boolean),
      headerButtons: [...header.querySelectorAll('button')].map((el) => el.textContent.trim()),
    };
  `);
  check(
    flow,
    '空工作区按钮为「去 GTD 收集 / 创建第一个目标 / 创建第一个 SOP」',
    ['去 GTD 收集', '创建第一个目标', '创建第一个 SOP'].every((text) => empty.buttons.includes(text)),
    empty,
  );

  await clickText(page, '去 GTD 收集');
  await sleep(500);
  const state = await page.eval(`
    return {
      route: document.documentElement.dataset.route,
      modal: Boolean(document.querySelector('#quick-capture-input')),
      title: document.querySelector('.modal-title')?.textContent.trim() ?? null,
    };
  `);
  check(flow, '点「去 GTD 收集」→ route=gtd 且打开收集弹窗', state.route === 'gtd' && state.modal === true, state);
  await page.screenshot(`${OUT}/b-dashboard-empty.png`);
}

/* ------------------------------------------------------------------ c --- */
async function okrHeader(page) {
  return page.eval(`
    const header = document.querySelector('.okr-page .page-header');
    const actions = header.querySelector('.okr-header-actions');
    const children = [...actions.children].map((el) => {
      const rect = el.getBoundingClientRect();
      return {
        tag: el.tagName.toLowerCase(),
        cls: String(el.className).slice(0, 40),
        text: el.textContent.trim().replace(/\\s+/g, ' ').slice(0, 40),
        left: Math.round(rect.left),
        right: Math.round(rect.right),
        clipped: el.scrollWidth > el.clientWidth + 1,
      };
    });
    const periodbar = document.querySelector('.okr-periodbar');
    return {
      children,
      order: children.map((c) => c.text),
      periodBarControls: [...periodbar.querySelectorAll('[role="radio"], button')].map((el) => el.textContent.trim()).filter((t) => ['卡片', '表格', '对齐', '紧凑', '详细'].includes(t)),
      headerScroll: header.scrollWidth - header.clientWidth,
      docOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
}

async function flowC(page) {
  const flow = 'c-okr-header';
  for (const width of [1440, 1024]) {
    await page.setViewport(width, 900);
    await clearAndReset(page, 'okr');
    await sleep(500);
    const cards = await okrHeader(page);
    const texts = cards.children.map((c) => c.text);
    const densityIndex = texts.findIndex((t) => t.includes('紧凑'));
    const viewIndex = texts.findIndex((t) => t.includes('卡片'));
    const createIndex = texts.findIndex((t) => t.includes('新建目标'));
    check(
      flow,
      `${width}: 顺序为 紧凑/详细 → 卡片/表格/对齐 → 新建目标`,
      densityIndex >= 0 && viewIndex > densityIndex && createIndex > viewIndex,
      { order: texts },
    );
    check(flow, `${width}: 无横向溢出 / 无按钮裁切`, cards.headerScroll === 0 && cards.docOverflow === 0 && cards.children.every((c) => !c.clipped), {
      headerScroll: cards.headerScroll,
      docOverflow: cards.docOverflow,
      clipped: cards.children.filter((c) => c.clipped).map((c) => c.text),
    });
    check(flow, `${width}: 季度条内无视图/密度控件`, cards.periodBarControls.length === 0, { periodBarControls: cards.periodBarControls });
  }

  await page.setViewport(1440, 900);
  await clearAndReset(page, 'okr');
  await sleep(400);
  const densityBefore = (await okrHeader(page)).children.length;
  await clickText(page, '表格');
  await sleep(600);
  const table = await okrHeader(page);
  check(
    flow,
    '切到表格后密度控件消失且无空洞（容器只剩 视图 + 新建目标）',
    table.children.length === densityBefore - 1 && table.children[0].text.includes('卡片') && table.children[1].text.includes('新建目标'),
    { children: table.children },
  );
  await clickText(page, '对齐');
  await sleep(600);
  const align = await okrHeader(page);
  check(flow, '对齐视图同样无密度控件', align.children.length === 2 && align.children[0].text.includes('卡片'), { children: align.children });
  await clickText(page, '卡片');
  await sleep(500);
  const back = await okrHeader(page);
  check(flow, '切回卡片后密度控件恢复', back.children.length === densityBefore && back.children[0].text.includes('紧凑'), { children: back.children });
  await page.setViewport(1024, 720);
  await sleep(400);
  await page.screenshot(`${OUT}/c-okr-header-1024.png`);
  await page.setViewport(1440, 900);
}

/* ------------------------------------------------------------------ d --- */
async function flowD(page) {
  const flow = 'd-calendar-month';
  await clearAndReset(page, 'calendar');
  await sleep(800);

  const grid = await page.eval(`
    const cells = [...document.querySelectorAll('.cal-cell')];
    const headers = [...document.querySelectorAll('.cal-grid-headcell')].map((el) => el.textContent.trim());
    return {
      count: cells.length,
      headers,
      first: cells[0]?.dataset.date ?? null,
      firstWeekday: cells[0] ? new Date(cells[0].dataset.date + 'T00:00:00').getDay() : null,
      rows: document.querySelectorAll('.cal-week').length,
      title: document.querySelector('.cal-subtitle')?.textContent.trim() ?? null,
    };
  `);
  check(flow, '42 格 / 6 行 / 周一起始', grid.count === 42 && grid.rows === 6 && grid.firstWeekday === 1 && grid.headers[0] === '一', grid);

  const today = await cellInfo(page, '2026-10-21');
  const todayPanel = await page.eval(`return document.querySelector('.cal-panel-lunar')?.textContent.trim() ?? null;`);
  check(
    flow,
    '今天 2026-10-21 高亮且为农历九月十二',
    today.today === true &&
      today.lunar === '十二' &&
      today.aria.includes('农历九月十二') &&
      (todayPanel ?? '').includes('九月十二'),
    { today, todayPanel },
  );

  const specials = await page.eval(`
    return {
      festivals: [...document.querySelectorAll('.cal-lunar--festival')].map((el) => ({ text: el.textContent.trim(), date: el.closest('.cal-cell')?.dataset.date })),
      terms: [...document.querySelectorAll('.cal-lunar--term')].map((el) => ({ text: el.textContent.trim(), date: el.closest('.cal-cell')?.dataset.date })),
      dots: document.querySelectorAll('.cal-dot').length,
    };
  `);
  const specialTexts = [...specials.festivals, ...specials.terms].map((entry) => entry.text);
  check(
    flow,
    '月内可见节日/节气标签（含寒露/霜降/重阳）',
    ['寒露', '霜降', '重阳'].every((text) => specialTexts.includes(text)),
    specials,
  );
  check(flow, '带日期条目在月格出现圆点', specials.dots > 0, { dots: specials.dots });

  // 点击日期 → 右侧面板显示该日条目
  await selectDate(page, '2026-10-21');
  const panel = await page.eval(`
    return {
      date: document.querySelector('.cal-panel-date')?.textContent.trim() ?? null,
      lunar: document.querySelector('.cal-panel-lunar')?.textContent.trim() ?? null,
      items: [...document.querySelectorAll('.cal-item .cal-item-title')].map((el) => el.textContent.trim()),
      count: document.querySelectorAll('.cal-item').length,
    };
  `);
  check(flow, '点击日期后右侧面板显示该日条目', panel.date.includes('10月21日') && panel.items.length > 0, panel);

  // 键盘导航
  await page.eval(`document.querySelector('[data-date="2026-10-21"]').focus(); return true;`);
  const keys = [
    ['ArrowRight', '2026-10-22', 'code'],
    ['ArrowLeft', '2026-10-21', 'code'],
    ['ArrowUp', '2026-10-14', 'code'],
    ['ArrowDown', '2026-10-21', 'code'],
    ['Home', '2026-10-19', 'code'],
    ['End', '2026-10-25', 'code'],
  ];
  const keyResults = [];
  for (const [key, expected] of keys) {
    await page.pressKey(key, { code: key, vk: 0 });
    await sleep(300);
    const state = await page.eval(`
      const selected = document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null;
      const focused = document.activeElement?.dataset?.date ?? null;
      return { selected, focused };
    `);
    keyResults.push({ key, expected, ...state, ok: state.selected === expected });
  }
  check(flow, '方向键 / Home / End 导航正确并移动焦点', keyResults.every((r) => r.ok && r.focused === r.expected), keyResults);

  const beforePageDown = await page.eval(`return document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null;`);
  await page.pressKey('PageDown', { code: 'PageDown', vk: 34 });
  await sleep(500);
  const afterPageDown = await page.eval(`
    return {
      selected: document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null,
      month: document.querySelector('select[aria-label="月份"]')?.value ?? null,
    };
  `);
  await page.pressKey('PageUp', { code: 'PageUp', vk: 33 });
  await sleep(500);
  const afterPageUp = await page.eval(`
    return {
      selected: document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null,
      month: document.querySelector('select[aria-label="月份"]')?.value ?? null,
    };
  `);
  check(
    flow,
    'PageDown/PageUp 切换月份并保持日期',
    afterPageDown.month === '11' && afterPageUp.month === '10' && afterPageDown.selected === '2026-11-25' && afterPageUp.selected === beforePageDown,
    { beforePageDown, afterPageDown, afterPageUp },
  );

  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(400);
  const focusedPanel = await page.eval(`return { active: document.activeElement?.className ?? '', isPanel: document.activeElement?.classList.contains('cal-panel') ?? false };`);
  check(flow, 'Enter 聚焦日程面板', focusedPanel.isPanel === true, focusedPanel);
  await page.screenshot(`${OUT}/d-calendar-month.png`);
}

/* ------------------------------------------------------------------ e --- */
const LUNAR_CASES = [
  { year: '2026', month: '2', date: '2026-02-17', text: '春节', aria: '正月初一' },
  { year: '2026', month: '2', date: '2026-02-16', text: '除夕', aria: '腊月' },
  { year: '2026', month: '9', date: '2026-09-25', text: '中秋', aria: '八月十五' },
  { year: '2026', month: '12', date: '2026-12-22', text: '冬至', aria: '冬至' },
  { year: '2025', month: '7', date: '2025-07-25', text: '闰六月', aria: '闰六月初一' },
  { year: '2023', month: '3', date: '2023-03-22', text: '闰二月', aria: '闰二月初一' },
];

async function flowE(page) {
  const flow = 'e-lunar-accuracy';
  await clearAndReset(page, 'calendar');
  await sleep(600);
  for (const item of LUNAR_CASES) {
    await setSelect(page, '年份', item.year);
    await setSelect(page, '月份', item.month);
    const info = await cellInfo(page, item.date);
    check(
      flow,
      `${item.date} 显示「${item.text}」，aria-label 含农历「${item.aria}」`,
      Boolean(info) && info.lunar === item.text && Boolean(info.aria.includes(item.aria)),
      info,
    );
  }
  await page.screenshot(`${OUT}/e-lunar-festivals.png`);
}

/* ------------------------------------------------------------------ f --- */
async function flowF(page) {
  const flow = 'f-calendar-week';
  await clearAndReset(page, 'calendar');
  await sleep(600);
  await clickText(page, '周');
  await sleep(700);
  const week = await page.eval(`
    const cols = [...document.querySelectorAll('.cal-week-col')];
    return {
      cols: cols.length,
      headers: cols.map((col) => ({
        weekday: col.querySelector('.cal-week-head-weekday')?.textContent.trim() ?? null,
        day: col.querySelector('.cal-week-head-day')?.textContent.trim() ?? null,
        lunar: col.querySelector('.cal-week-head-lunar')?.textContent.trim() ?? null,
        aria: col.getAttribute('aria-label'),
      })),
      spanTexts: [...document.querySelectorAll('.cal-week-card-span')].map((el) => el.textContent.trim()),
      cards: [...document.querySelectorAll('.cal-week-card')].map((el) => el.textContent.trim().slice(0, 30)),
    };
  `);
  check(flow, '周视图 7 列且表头含农历/节日', week.cols === 7 && week.headers.every((h) => h.lunar && h.lunar.length > 0), week.headers);
  check(flow, '跨天条目显示「第 n 天」', week.spanTexts.some((text) => /第 \d+(\/\d+)? 天/.test(text)), { spanTexts: week.spanTexts });

  // 行动卡片：跳到甘特并选中对应任务条
  const actionCard = await page.eval(`
    const card = [...document.querySelectorAll('.cal-week-card')].find((el) => el.querySelector('.cal-week-card-title')?.textContent.includes('视觉稿评审'));
    if (!card) return null;
    card.click();
    return card.textContent.trim();
  `);
  await page.waitFor(`document.documentElement.dataset.route === 'gantt'`, { label: 'route gantt (action card)' });
  await sleep(700);
  const actionSelected = await page.eval(`
    return {
      route: document.documentElement.dataset.route,
      bars: [...document.querySelectorAll('.gantt-bar.is-selected')].map((el) => el.getAttribute('aria-label')),
    };
  `);
  check(
    flow,
    '点击行动卡片跳到甘特并选中该任务条',
    actionSelected.route === 'gantt' && actionSelected.bars.some((label) => label?.startsWith('视觉稿评审')),
    { actionCard, actionSelected },
  );

  // 项目卡片：跳到甘特并选中分组行（汇总条为 .gantt-summary-bar）
  await navTo(page, '日历');
  await sleep(600);
  const projectCard = await page.eval(`
    const card = [...document.querySelectorAll('.cal-week-card')].find((el) => el.querySelector('.cal-week-card-title')?.textContent.includes('官网改版'));
    if (!card) return null;
    card.click();
    return card.textContent.trim();
  `);
  await page.waitFor(`document.documentElement.dataset.route === 'gantt'`, { label: 'route gantt (project card)' });
  await sleep(700);
  const projectSelected = await page.eval(`
    return {
      route: document.documentElement.dataset.route,
      rows: [...document.querySelectorAll('.gantt-tree-row.is-selected')].map((el) => el.textContent.trim().slice(0, 30)),
      summary: [...document.querySelectorAll('.gantt-summary-bar.is-selected')].map((el) => el.getAttribute('aria-label')),
    };
  `);
  check(
    flow,
    '点击项目卡片跳到甘特并选中分组行/汇总条',
    projectSelected.route === 'gantt' &&
      (projectSelected.rows.some((text) => text.includes('官网改版')) || projectSelected.summary.some((label) => (label ?? '').includes('官网改版'))),
    { projectCard, projectSelected },
  );
  await page.screenshot(`${OUT}/f-calendar-week.png`);
}

/* ------------------------------------------------------------------ g --- */
async function flowG(page) {
  const flow = 'g-calendar-quick-add';
  await clearAndReset(page, 'calendar');
  await sleep(700);
  await selectDate(page, '2026-10-25');
  await page.click('input[aria-label="添加到这一天的日程标题"]');
  await page.insertText('日历验收任务');
  await sleep(250);
  await pressEnter(page);
  await sleep(900);

  const ws = await readWorkspace(page);
  const created = ws.items.find((item) => item.title === '日历验收任务');
  check(
    flow,
    '创建 action：gantt.start=end=当日、status=next',
    Boolean(created) &&
      created.kind === 'action' &&
      created.status === 'next' &&
      created.gantt?.start === '2026-10-25' &&
      created.gantt?.end === '2026-10-25',
    created ? { kind: created.kind, status: created.status, gantt: created.gantt } : null,
  );

  const panelHas = await page.eval(`
    return [...document.querySelectorAll('.cal-item-title')].some((el) => el.textContent.trim() === '日历验收任务');
  `);
  const cell = await cellInfo(page, '2026-10-25');
  check(flow, '出现在该日列表与月格圆点中', panelHas === true && cell.dots > 0, { panelHas, cell });

  // +N 逻辑：圆点最多 3 个，其余折叠为 +N
  const more = await page.eval(`
    const panelCount = document.querySelectorAll('.cal-item').length;
    const cell = document.querySelector('[data-date="2026-10-25"]');
    return {
      panelCount,
      dots: cell.querySelectorAll('.cal-dot').length,
      more: cell.querySelector('.cal-dot-more')?.textContent.trim() ?? null,
    };
  `);
  const expectedMore = more.panelCount > 3 ? `+${more.panelCount - 3}` : null;
  check(
    flow,
    '+N 折叠逻辑正确（最多 3 个圆点，其余显示 +N）',
    more.dots === Math.min(3, more.panelCount) && more.more === expectedMore,
    { ...more, expectedMore },
  );

  await page.reload({ route: 'calendar' });
  await sleep(900);
  const afterReload = await readWorkspace(page);
  const persists = afterReload.items.some((item) => item.title === '日历验收任务');
  await selectDate(page, '2026-10-25');
  const stillInPanel = await page.eval(`
    return [...document.querySelectorAll('.cal-item-title')].some((el) => el.textContent.trim() === '日历验收任务');
  `);
  check(flow, '刷新后仍在（持久化 + 面板可见）', persists && stillInPanel, { persists, stillInPanel });
  await page.screenshot(`${OUT}/g-calendar-quick-add.png`);
}

/* ------------------------------------------------------------------ h --- */
async function flowH(page) {
  const flow = 'h-calendar-boundary';
  await clearAndReset(page, 'calendar');
  await sleep(600);

  await setSelect(page, '年份', '1900');
  await setSelect(page, '月份', '1');
  const jan1900 = await page.eval(`
    const cells = [...document.querySelectorAll('.cal-cell')];
    const selected = document.querySelector('.cal-cell.is-selected');
    return {
      count: cells.length,
      subtitle: document.querySelector('.cal-subtitle')?.textContent.trim() ?? null,
      firstCell: cells[0] ? { date: cells[0].dataset.date, lunar: cells[0].querySelector('.cal-lunar')?.textContent.trim() ?? null } : null,
      anyNullText: /null|undefined|NaN/.test(document.querySelector('.cal-grid').innerText),
      panel: document.querySelector('.cal-panel-lunar')?.textContent.trim() ?? null,
      selectedDate: selected?.dataset.date ?? null,
    };
  `);
  check(
    flow,
    '1900-01：不崩溃、范围外农历降级（无 null 文本）',
    jan1900.count === 42 && jan1900.anyNullText === false && jan1900.subtitle.includes('农历数据仅支持 1900–2100'),
    jan1900,
  );

  const dec2100 = await (async () => {
    await setSelect(page, '年份', '2100');
    await setSelect(page, '月份', '12');
    return page.eval(`
      const cells = [...document.querySelectorAll('.cal-cell')];
      const last = document.querySelector('[data-date="2100-12-31"]');
      return {
        count: cells.length,
        lastLunar: last?.querySelector('.cal-lunar')?.textContent.trim() ?? null,
        lastAria: last?.getAttribute('aria-label') ?? null,
        anyNullText: /null|undefined|NaN/.test(document.querySelector('.cal-grid').innerText),
        errors: [...document.querySelectorAll('.cal-cell')].length,
      };
    `);
  })();
  check(
    flow,
    '2100-12：不崩溃，12-31 仍有农历',
    dec2100.count === 42 && dec2100.anyNullText === false && Boolean(dec2100.lastLunar),
    dec2100,
  );
  check(flow, '边界浏览期间 0 console error', page.issues.filter((i) => i.level === 'error').length === 0, page.issues.filter((i) => i.level === 'error'));
  await page.screenshot(`${OUT}/h-calendar-boundary.png`);
}

/* ------------------------------------------------------------------ i --- */
const CONTRAST_HELPERS = `
  const parse = (value) => {
    const m = value.match(/rgba?\\(([^)]+)\\)/);
    if (!m) return { r: 0, g: 0, b: 0, a: 0 };
    const parts = m[1].split(/[,\\s\\/]+/).filter(Boolean).map(Number);
    return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
  };
  const over = (fg, bg) => ({ r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a), a: 1 });
  const effectiveBg = (el) => {
    const layers = [];
    let node = el;
    while (node) {
      const color = parse(getComputedStyle(node).backgroundColor);
      if (color.a > 0) layers.push(color);
      node = node.parentElement;
    }
    let bg = layers.length ? layers[layers.length - 1] : { r: 255, g: 255, b: 255, a: 1 };
    for (let i = layers.length - 2; i >= 0; i -= 1) bg = over(layers[i], bg);
    return bg;
  };
  const lum = (c) => {
    const f = (v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => {
    const la = lum(a), lb = lum(b);
    return Number(((Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)).toFixed(2));
  };
  const measure = (el) => {
    const style = getComputedStyle(el);
    const bg = effectiveBg(el);
    return { text: el.textContent.trim().slice(0, 16), color: style.color, bg: 'rgb(' + Math.round(bg.r) + ',' + Math.round(bg.g) + ',' + Math.round(bg.b) + ')', ratio: ratio(over(parse(style.color), bg), bg), fontSize: style.fontSize };
  };
`;

async function flowI(page) {
  const flow = 'i-dark-1024';
  await page.setViewport(1440, 900);
  await clearAndReset(page, 'calendar');
  await sleep(700);
  await page.eval(`document.querySelector('button[aria-label="切换到深色主题"]').click(); return true;`);
  await sleep(700);

  const dark = await page.eval(`
    ${CONTRAST_HELPERS}
    const today = document.querySelector('.cal-daynum.is-today');
    const selected = document.querySelector('.cal-cell.is-selected');
    const festival = document.querySelector('.cal-lunar--festival') || document.querySelector('.cal-lunar--term');
    const panel = document.querySelector('.cal-panel-date');
    return {
      theme: document.documentElement.dataset.theme,
      today: today ? measure(today) : null,
      selectedCell: selected ? { bg: getComputedStyle(selected).backgroundColor, day: measure(selected.querySelector('.cal-daynum')), lunar: measure(selected.querySelector('.cal-lunar')) } : null,
      festival: festival ? measure(festival) : null,
      panelDate: panel ? measure(panel) : null,
    };
  `);
  const ratios = [dark.today?.ratio, dark.selectedCell?.day?.ratio, dark.selectedCell?.lunar?.ratio, dark.festival?.ratio, dark.panelDate?.ratio].filter((v) => typeof v === 'number');
  check(flow, '深色主题已生效', dark.theme === 'dark', { theme: dark.theme });
  check(flow, '深色下今日数字 / 选中格 / 节日节气标签对比度均 ≥ 4.5', ratios.length >= 4 && ratios.every((r) => r >= 4.5), dark);
  await page.screenshot(`${OUT}/i-calendar-dark.png`);

  // 1024：格子 ≥ 52px、面板可开关、无横向溢出
  await page.setViewport(1024, 720);
  await page.goto(`${BASE_URL}/?route=calendar`, { route: 'calendar' });
  await sleep(900);
  await page.eval(`document.querySelector('button[aria-label="切换到浅色主题"]')?.click(); return true;`);
  await sleep(500);
  const narrow = await page.eval(`
    const cell = document.querySelector('.cal-cell');
    const rect = cell.getBoundingClientRect();
    return {
      cell: { w: Math.round(rect.width), h: Math.round(rect.height) },
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      panelCollapsed: document.querySelector('.cal-panel')?.classList.contains('is-collapsed') ?? null,
      toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim() ?? null,
    };
  `);
  check(flow, '1024×720 月格 ≥ 52px 且无横向溢出', narrow.cell.w >= 52 && narrow.cell.h >= 52 && narrow.overflowX === 0, narrow);

  if (narrow.panelCollapsed) {
    await page.eval(`document.querySelector('.cal-panel-toggle').click(); return true;`);
    await sleep(600);
  }
  const openedPanel = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return { collapsed: panel.classList.contains('is-collapsed'), visible: panel.getBoundingClientRect().width > 0, toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim() };
  `);
  check(flow, '1024 下面板可展开（默认收起）', openedPanel.collapsed === false && openedPanel.visible === true, openedPanel);

  await page.eval(`document.querySelector('.cal-panel-toggle').click(); return true;`);
  await sleep(600);
  const closedPanel = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return { collapsed: panel.classList.contains('is-collapsed'), toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim(), overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth };
  `);
  check(flow, '1024 下面板可再次收起且无溢出', closedPanel.collapsed === true && closedPanel.overflowX === 0, closedPanel);
  await page.screenshot(`${OUT}/i-calendar-1024.png`);
  await page.setViewport(1440, 900);
}

/* ------------------------------------------------------------------ run -- */
async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    for (const flow of [flowA, flowB, flowC, flowD, flowE, flowF, flowG, flowH, flowI]) {
      try {
        await flow(page);
      } catch (error) {
        check(flow.name, `流程异常：${error.message.split('\n')[0]}`, false, { error: error.message.split('\n').slice(0, 3).join(' | ') });
        await page.screenshot(`${OUT}/${flow.name}-failed.png`).catch(() => {});
      }
      const errors = page.issues.filter((i) => i.level === 'error');
      if (errors.length) {
        check(flow.name, '该流程 console error = 0', false, errors.map((e) => e.text.slice(0, 200)));
      }
    }
  });

  writeFileSync(`${OUT}/calendar-acceptance-report.json`, JSON.stringify(results, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== CALENDAR ACCEPTANCE SUMMARY ===');
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
  console.error('CALENDAR ACCEPTANCE FAILED:', error);
  process.exit(1);
});
