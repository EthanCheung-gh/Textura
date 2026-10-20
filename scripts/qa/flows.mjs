/**
 * Cross-module integration flows (a–h from the QA brief) driven through CDP.
 * Every flow starts from a freshly seeded workspace (localStorage cleared).
 */
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { BASE_URL, diffDays, parseDateRange, sleep, withPage } from './lib.mjs';

const DOWNLOAD_DIR = '/tmp/textura-qa-downloads';
const FAIL_DIR = 'docs/screenshots/flows';
const WORKSPACE_KEY = 'textura.workspace.v1';

const ROUTE_BY_LABEL = {
  今日: 'dashboard',
  OKR: 'okr',
  GTD: 'gtd',
  甘特: 'gantt',
  SOP: 'sop',
  设置: 'settings',
};

const results = [];
let currentFlow = null;
let flowFailures = 0;

async function navTo(page, label) {
  const route = ROUTE_BY_LABEL[label];
  await page.eval(`
    const button = [...document.querySelectorAll('.sidebar-nav .sidebar-link')]
      .find((el) => el.textContent.trim().startsWith(${JSON.stringify(label)}));
    if (!button) throw new Error('sidebar link not found: ' + ${JSON.stringify(label)});
    button.click();
    return true;
  `);
  await page.waitFor(`document.documentElement.dataset.route === ${JSON.stringify(route)}`, {
    label: `route ${route}`,
  });
  await sleep(250);
  return route;
}

async function clickButtonByText(page, text, scope = 'body') {
  const clicked = await page.eval(`
    const buttons = [...document.querySelectorAll(${JSON.stringify(scope)} + ' button')];
    const target = buttons.find((el) => el.textContent.trim() === ${JSON.stringify(text)});
    if (!target) return false;
    target.scrollIntoView({ block: 'center' });
    target.click();
    return true;
  `);
  if (!clicked) throw new Error(`button not found: ${text} (scope ${scope})`);
  await sleep(200);
}

async function readWorkspace(page) {
  return page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)});
    return raw ? JSON.parse(raw) : null;
  `);
}

async function waitSaved(page) {
  await page.waitFor(
    `[...document.querySelectorAll('.storage-status')].some((el) => el.textContent.includes('已保存'))`,
    { label: 'save indicator 已保存', timeout: 5000 },
  );
}

/**
 * 打开快速收集：优先真实按 Ctrl+N；headless Chrome 会把 Ctrl+N 当作浏览器「新建标签页」
 * 快捷键吞掉，此时退回点击顶栏「快速收集」按钮，并记录实际路径。
 */
async function openCapture(page) {
  await page.shortcut('n');
  await sleep(450);
  const opened = await page.eval(`return !!document.querySelector('#quick-capture-input');`);
  if (opened) return 'ctrl+n';
  const clicked = await page.eval(`
    const button = [...document.querySelectorAll('.topbar button')].find((el) => el.textContent.trim() === '快速收集');
    if (!button) throw new Error('topbar 快速收集 button missing');
    button.click();
    return true;
  `);
  await sleep(450);
  return clicked ? 'topbar-button' : 'none';
}

/** Real typing first; verify; fall back to a native setter + input event if the caret disagreed. */
async function setInputValue(page, selector, value) {
  await page.click(selector);
  await page.selectAll();
  await page.insertText(value);
  await sleep(150);
  const actual = await page.eval(`
    const el = document.querySelector(${JSON.stringify(selector)});
    return el ? el.value : null;
  `);
  if (actual === value) return { mode: 'typed', actual };
  await page.eval(`
    const el = document.querySelector(${JSON.stringify(selector)});
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(el, ${JSON.stringify(value)});
    el.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  `);
  await sleep(150);
  const retried = await page.eval(`
    const el = document.querySelector(${JSON.stringify(selector)});
    return el ? el.value : null;
  `);
  return { mode: 'native-setter', actual: retried, typedValue: actual };
}

async function flow(name, fn) {
  currentFlow = { name, steps: [], issues: [], screenshots: [] };
  results.push(currentFlow);
  console.log(`\n===== FLOW ${name} =====`);
  const check = (label, ok, detail) => {
    currentFlow.steps.push({ label, ok, detail });
    if (!ok) flowFailures += 1;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
    return ok;
  };
  const failShot = async (page, tag) => {
    const path = `${FAIL_DIR}/${name}-${tag}.png`;
    await page.screenshot(path).catch(() => {});
    currentFlow.screenshots.push(path);
    console.log(`      screenshot -> ${path}`);
    return path;
  };
  try {
    await fn(check, failShot);
  } catch (error) {
    check(`flow threw: ${error.message.split('\n')[0]}`, false, {
      error: error.message.split('\n').slice(0, 3).join(' | '),
    });
  }
}

function toCount(value) {
  const match = String(value ?? '').match(/\d+/);
  return match ? Number(match[0]) : NaN;
}

async function statCard(page, label) {
  return page.eval(`
    const cards = [...document.querySelectorAll('.dash-stat')];
    const card = cards.find((el) => el.querySelector('.dash-stat-label')?.textContent.trim() === ${JSON.stringify(label)});
    return card ? card.querySelector('.dash-stat-value')?.textContent.trim() : null;
  `);
}

async function flowA(page, check, failShot) {
  await page.reset('gtd');
  const before = await page.eval(`
    return {
      sidebar: Number(document.querySelector('.sidebar-link-count')?.textContent.trim() ?? -1),
      card: Number(document.querySelector('.gtd-flow-card--accent .gtd-flow-card-value')?.textContent.trim() ?? -1),
      next: Number(document.querySelectorAll('.gtd-flow-card')[1]?.querySelector('.gtd-flow-card-value')?.textContent.trim() ?? -1),
    };
  `);
  check('baseline inbox count is 6', before.sidebar === 6 && before.card === 6, before);

  await page.shortcut('n');
  await sleep(450);
  const ctrlNOpened = await page.eval(`return !!document.querySelector('#quick-capture-input');`);
  if (!ctrlNOpened) {
    // headless Chrome reserves Ctrl+N for "new tab"; fall back to the top-bar button.
    await openCapture(page);
  }
  await page.waitFor(`!!document.querySelector('#quick-capture-input')`, { label: 'quick capture modal' });
  await sleep(250);
  const focused = await page.eval(`return document.activeElement?.id ?? null;`);
  check(
    `快速收集弹窗打开并聚焦输入框（快捷键路径=${ctrlNOpened ? 'Ctrl+N' : '顶栏按钮，headless 吞掉了 Ctrl+N'}）`,
    focused === 'quick-capture-input',
    { focused, viaCtrlN: ctrlNOpened },
  );

  // exact token-only input from the brief
  await page.insertText('#qa @电脑');
  await sleep(250);
  const tokenOnly = await page.eval(`
    const dialog = document.querySelector('[role="dialog"]');
    const collect = [...dialog.querySelectorAll('button')].find((b) => b.textContent.trim() === '收集');
    return {
      disabled: collect ? collect.disabled : null,
      chips: [...dialog.querySelectorAll('.capture-chip')].map((c) => c.textContent.trim()),
    };
  `);
  check('仅 #qa @电脑（无标题）时「收集」禁用且解析出标签/场景', tokenOnly.disabled === true && tokenOnly.chips.some((c) => c.includes('#qa')) && tokenOnly.chips.some((c) => c.includes('@电脑')), tokenOnly);

  await page.selectAll();
  await page.insertText('QA 冒烟核对 #qa @电脑');
  await sleep(250);
  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(500);

  const after = await page.eval(`
    return {
      sidebar: Number(document.querySelector('.sidebar-link-count')?.textContent.trim() ?? -1),
      card: Number(document.querySelector('.gtd-flow-card--accent .gtd-flow-card-value')?.textContent.trim() ?? -1),
      session: [...document.querySelectorAll('.capture-session-row')].map((r) => r.textContent.trim()),
    };
  `);
  check('收件箱计数 +1（侧栏与流程卡）', after.sidebar === before.sidebar + 1 && after.card === before.card + 1, after);

  const stored = await readWorkspace(page);
  const created = stored.items.find((item) => item.title === 'QA 冒烟核对');
  check(
    '条目写入：tags=[qa] context=电脑 status=inbox clarified=false',
    Boolean(created) &&
      created.tags.includes('qa') &&
      created.gtd?.context === '电脑' &&
      created.status === 'inbox' &&
      created.gtd?.clarified === false,
    created ? { id: created.id, tags: created.tags, context: created.gtd?.context, status: created.status, clarified: created.gtd?.clarified } : null,
  );

  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);

  const rowClicked = await page.eval(`
    const row = [...document.querySelectorAll('.gtd-inbox-row .gtd-row-title')]
      .find((el) => el.textContent.trim() === 'QA 冒烟核对');
    if (!row) return false;
    row.click();
    return true;
  `);
  if (!rowClicked) {
    await failShot(page, 'clarify-row-missing');
    check('收件箱中出现新条目并可打开澄清', false);
    return;
  }
  await page.waitFor(`!!document.querySelector('#gtd-clarify-form')`, { label: 'clarify dialog' });
  await sleep(250);
  const clarifyDefaults = await page.eval(`
    const type = document.querySelector('#gtd-clarify-type');
    const title = document.querySelector('#gtd-clarify-title');
    const context = document.querySelector('#gtd-clarify-context');
    return { type: type?.value, title: title?.value, context: context?.value };
  `);
  check('澄清弹窗默认类型=next 且保留标题/场景', clarifyDefaults.type === 'next' && clarifyDefaults.title === 'QA 冒烟核对' && clarifyDefaults.context === '电脑', clarifyDefaults);

  await clickButtonByText(page, '完成澄清');
  await sleep(600);

  const afterClarify = await page.eval(`
    return {
      sidebar: Number(document.querySelector('.sidebar-link-count')?.textContent.trim() ?? -1),
      inbox: Number(document.querySelector('.gtd-flow-card--accent .gtd-flow-card-value')?.textContent.trim() ?? -1),
      next: Number(document.querySelectorAll('.gtd-flow-card')[1]?.querySelector('.gtd-flow-card-value')?.textContent.trim() ?? -1),
    };
  `);
  const stored2 = await readWorkspace(page);
  const clarified = stored2.items.find((item) => item.title === 'QA 冒烟核对');
  check(
    '澄清后：收件箱 -1、下一步 +1',
    afterClarify.inbox === before.card && afterClarify.sidebar === before.sidebar && afterClarify.next === before.next + 1,
    { before, afterClarify },
  );
  check(
    '澄清后条目 status=next、clarified=true、标签/场景保留',
    clarified?.status === 'next' && clarified?.gtd?.clarified === true && clarified?.tags.includes('qa') && clarified?.gtd?.context === '电脑',
    clarified ? { status: clarified.status, clarified: clarified.gtd?.clarified, tags: clarified.tags, context: clarified.gtd?.context } : null,
  );
  await failShot(page, 'final-state');
}

async function flowB(page, check, failShot) {
  await page.reset('gantt');
  await sleep(800); // let the timeline measure its viewport before interacting
  const first = await page.eval(`
    const bars = [...document.querySelectorAll('.gantt-bar:not(.is-milestone)')].filter((el) => el.getAttribute('aria-label'));
    const bar = bars[0];
    if (!bar) return null;
    return { label: bar.getAttribute('aria-label'), cls: bar.className, id: bar.closest('[data-row-id]')?.dataset.rowId ?? null };
  `);
  check('甘特存在可拖动任务条', Boolean(first && parseDateRange(first.label)), first);
  if (!first) return;
  const beforeRange = parseDateRange(first.label);
  const title = first.label.split('，')[0];

  await page.drag('.gantt-bar[aria-label]:not(.is-milestone)', 56, 0, { steps: 10 });
  await sleep(300);
  const draggedLabel = await page.eval(`
    const bar = [...document.querySelectorAll('.gantt-bar:not(.is-milestone)')].find((el) => (el.getAttribute('aria-label') || '').startsWith(${JSON.stringify(title)}));
    return bar ? bar.getAttribute('aria-label') : null;
  `);
  const afterRange = parseDateRange(draggedLabel ?? '');
  check('拖动后任务条日期变化', Boolean(afterRange) && afterRange.start !== beforeRange.start, { beforeRange, afterRange, title });

  await waitSaved(page);
  const saveLabel = await page.text('.storage-status');
  check('400ms 后侧栏显示「已保存」', saveLabel === '已保存', { saveLabel });

  await sleep(600);
  const persistedBeforeReload = await readWorkspace(page);
  const persistedItem = persistedBeforeReload.items.find((item) => item.title === title);
  check(
    'localStorage 中 gantt 起止日期已更新',
    persistedItem?.gantt?.start === afterRange.start && persistedItem?.gantt?.end === afterRange.end,
    persistedItem ? { start: persistedItem.gantt?.start, end: persistedItem.gantt?.end } : null,
  );

  await page.reload({ route: 'gantt' });
  await sleep(700);
  const reloadedLabel = await page.eval(`
    const bar = [...document.querySelectorAll('.gantt-bar:not(.is-milestone)')].find((el) => (el.getAttribute('aria-label') || '').startsWith(${JSON.stringify(title)}));
    return bar ? bar.getAttribute('aria-label') : null;
  `);
  const reloadRange = parseDateRange(reloadedLabel ?? '');
  check(
    '刷新后日期保留',
    reloadRange?.start === afterRange.start && reloadRange?.end === afterRange.end,
    { reloadedLabel, reloadRange, expected: afterRange },
  );
  check('拖动位移=+2 天（week 缩放 28px/天）', diffDays(afterRange.start, beforeRange.start) === 2, {
    deltaDays: diffDays(afterRange.start, beforeRange.start),
  });
  await failShot(page, 'final-state');
}

async function flowC(page, check, failShot) {
  await page.reset('okr');
  const before = await page.eval(`
    const stats = [...document.querySelectorAll('.okr-stat')];
    const avg = stats.find((el) => el.querySelector('.okr-stat-label')?.textContent.trim() === '平均进度');
    const krRows = [...document.querySelectorAll('.okr-kr')];
    const nps = krRows.find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return {
      avg: avg?.querySelector('.okr-stat-value')?.textContent.trim() ?? null,
      krPct: nps?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
      current: document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')?.value ?? null,
      target: document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标目标值"]')?.value ?? null,
    };
  `);
  check('初始 NPS 当前值 47 / 目标 60，KR 进度 28%', before.current === '47' && before.target === '60' && before.krPct === '28%', before);

  const setResult = await setInputValue(page, 'input[aria-label="NPS 从 42 提升到 60 指标当前值"]', '60');
  await sleep(500);

  const after = await page.eval(`
    const stats = [...document.querySelectorAll('.okr-stat')];
    const avg = stats.find((el) => el.querySelector('.okr-stat-label')?.textContent.trim() === '平均进度');
    const nps = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return {
      avg: avg?.querySelector('.okr-stat-value')?.textContent.trim() ?? null,
      krPct: nps?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
      current: document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')?.value ?? null,
      inputMode: ${JSON.stringify(setResult.mode)},
    };
  `);
  check('当前值改为目标值后 KR 进度 100%', after.krPct === '100%' && after.current === '60', after);
  const avgBeforeNum = Number(String(before.avg).replace('%', ''));
  const avgAfterNum = Number(String(after.avg).replace('%', ''));
  check('目标平均进度上升', avgAfterNum > avgBeforeNum, { before: before.avg, after: after.avg });

  await waitSaved(page);
  await page.reload({ route: 'okr' });
  await sleep(700);
  const reloaded = await page.eval(`
    const nps = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return {
      current: document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')?.value ?? null,
      krPct: nps?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
    };
  `);
  check('刷新后 60 与 100% 保留', reloaded.current === '60' && reloaded.krPct === '100%', reloaded);
  await failShot(page, 'final-state');
}

async function flowD(page, check, failShot) {
  await page.reset('dashboard');
  const beforeWeekly = await statCard(page, '近 7 天完成');
  check('今日页读取「近 7 天完成」', beforeWeekly !== null, { beforeWeekly });

  // 1) create a next action that also has a gantt due date
  const captureVia = await openCapture(page);
  await page.waitFor(`!!document.querySelector('#quick-capture-input')`, { label: 'capture modal' });
  await page.insertText('联调核对 /明天');
  await sleep(250);
  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(400);
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);

  await navTo(page, 'GTD');
  const rowOpened = await page.eval(`
    const row = [...document.querySelectorAll('.gtd-inbox-row .gtd-row-title')].find((el) => el.textContent.trim() === '联调核对');
    if (!row) return false;
    row.click();
    return true;
  `);
  check('新建条目进入 GTD 收件箱', rowOpened);
  await page.waitFor(`!!document.querySelector('#gtd-clarify-form')`, { label: 'clarify dialog' });
  const dueValue = await page.eval(`return document.querySelector('#gtd-clarify-due')?.value ?? null;`);
  check('澄清表单带出 /明天 的截止日期', Boolean(dueValue), { dueValue });
  await clickButtonByText(page, '完成澄清');
  await sleep(600);
  const afterClarifyWs = await readWorkspace(page);
  const action = afterClarifyWs.items.find((item) => item.title === '联调核对');
  check('条目澄清为下一步且带 gantt.end', action?.status === 'next' && Boolean(action?.gantt?.end), action ? { status: action.status, end: action.gantt?.end } : null);

  // 2) link it to the NPS key result through the OKR dialog
  await navTo(page, 'OKR');
  await page.eval(`
    const button = [...document.querySelectorAll('button[aria-label]')]
      .find((el) => el.getAttribute('aria-label') === '关联「NPS 从 42 提升到 60」的执行项');
    if (!button) throw new Error('OKR link button missing');
    button.scrollIntoView({ block: 'center' });
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('input[aria-label="关联「联调核对」"]')`, { label: 'link dialog row' });
  await sleep(200);
  await page.click('input[aria-label="关联「联调核对」"]');
  await sleep(150);
  await clickButtonByText(page, '关联所选');
  await sleep(600);
  const linkedText = await page.eval(`
    const kr = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return kr ? kr.textContent.includes('联调核对') : false;
  `);
  check('OKR 关联后 KR 执行项列表出现该条目', linkedText === true, { linkedText });

  // 3) complete it from GTD
  await navTo(page, 'GTD');
  const completed = await page.eval(`
    const button = document.querySelector('button[aria-label="完成「联调核对」"]');
    if (!button) return false;
    button.scrollIntoView({ block: 'center' });
    button.click();
    return true;
  `);
  check('GTD 下一步中出现该条目并点击完成', completed === true);
  await sleep(600);
  const afterDoneWs = await readWorkspace(page);
  const doneItem = afterDoneWs.items.find((item) => item.title === '联调核对');
  check('完成状态写回 store（status=done + completedAt）', doneItem?.status === 'done' && Boolean(doneItem?.completedAt), doneItem ? { status: doneItem.status, completedAt: doneItem.completedAt } : null);

  // 4) dashboard weekly counter
  await navTo(page, '今日');
  const afterWeekly = await statCard(page, '近 7 天完成');
  check('今日页「近 7 天完成」+1', toCount(afterWeekly) === toCount(beforeWeekly) + 1, { beforeWeekly, afterWeekly });

  // 5) gantt reflects done
  await navTo(page, '甘特');
  const ganttBar = await page.eval(`
    const bar = [...document.querySelectorAll('.gantt-bar')].find((el) => (el.getAttribute('aria-label') || '').startsWith('联调核对'));
    return bar ? { cls: bar.className, label: bar.getAttribute('aria-label') } : null;
  `);
  check('甘特中该条目状态同步为已完成（is-done）', Boolean(ganttBar && ganttBar.cls.includes('is-done')), ganttBar);

  // 6) OKR reflects done in execution list
  await navTo(page, 'OKR');
  const okrReflect = await page.eval(`
    const kr = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    if (!kr) return null;
    const rows = [...kr.querySelectorAll('li')].filter((li) => li.textContent.includes('联调核对'));
    return { found: rows.length > 0, text: rows[0]?.textContent.trim().slice(0, 120) ?? null };
  `);
  check('OKR 执行项中显示已完成状态', Boolean(okrReflect?.found && okrReflect.text.includes('已完成')), okrReflect);
  await failShot(page, 'final-state');
}

async function flowE(page, check, failShot) {
  await page.reset('sop');
  await sleep(900);
  const nodeInfo = await page.eval(`
    const el = document.querySelector('.react-flow__node');
    if (!el) return null;
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)}));
    const id = el.getAttribute('data-id');
    const item = ws.items.find((entry) => entry.id === id);
    const r = el.getBoundingClientRect();
    return { id, title: item?.title ?? null, canvas: item?.sop?.canvas ?? null, rect: { x: r.x, y: r.y, w: r.width, h: r.height } };
  `);
  check('SOP 画布渲染出节点', Boolean(nodeInfo?.id), nodeInfo ? { id: nodeInfo.id, title: nodeInfo.title, canvas: nodeInfo.canvas, rect: nodeInfo.rect } : null);
  if (!nodeInfo) return;

  await page.drag(`.react-flow__node[data-id="${nodeInfo.id}"]`, 130, 70, { steps: 16, settle: 400 });
  await sleep(700);
  const dragged = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)}));
    const item = ws.items.find((entry) => entry.id === ${JSON.stringify(nodeInfo.id)});
    return item?.sop?.canvas ?? null;
  `);
  check(
    '拖动节点后 canvas 坐标变化（+x / +y）',
    Boolean(dragged) && dragged.x !== nodeInfo.canvas.x && dragged.y !== nodeInfo.canvas.y,
    { before: nodeInfo.canvas, after: dragged },
  );
  await waitSaved(page);

  await page.reload({ route: 'sop' });
  await sleep(1000);
  const afterReload = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)}));
    const item = ws.items.find((entry) => entry.id === ${JSON.stringify(nodeInfo.id)});
    const el = document.querySelector('.react-flow__node[data-id="${nodeInfo.id}"]');
    const transform = el ? getComputedStyle(el).transform : null;
    return { canvas: item?.sop?.canvas ?? null, transform, present: Boolean(el) };
  `);
  check(
    '刷新后节点位置保留',
    afterReload.canvas?.x === dragged?.x && afterReload.canvas?.y === dragged?.y && afterReload.present,
    afterReload,
  );

  const runStarted = await page.eval(`
    const button = [...document.querySelectorAll('button')].find((el) => el.textContent.trim() === '运行');
    if (!button) return false;
    button.scrollIntoView({ block: 'center' });
    button.click();
    return true;
  `);
  check('进入运行模式', runStarted === true);
  await page.waitFor(`!!document.querySelector('.sop-runbar')`, { label: 'run bar' });
  await sleep(300);
  const step1 = await page.text('.sop-runbar-progress');

  await clickButtonByText(page, '通过', '.sop-runbar-actions');
  await sleep(500);
  const step2 = await page.text('.sop-runbar-progress');
  await clickButtonByText(page, '通过', '.sop-runbar-actions');
  await sleep(600);
  const step3 = await page.text('.sop-runbar-progress');
  check('连点两次「通过」推进步骤', step1 !== step2 && step2 !== step3, { step1, step2, step3 });

  const runs = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)}));
    return { total: ws.runs.length, last: ws.runs.slice(-2).map((run) => run.result) };
  `);
  check('运行记录写入（+2 条 pass）', runs.total === 5 && runs.last.every((r) => r === 'pass'), runs);
  check('运行期间无 error 级 console 问题', page.issues.filter((i) => i.level === 'error').length === 0, page.issues.filter((i) => i.level === 'error'));
  await failShot(page, 'final-state');
}

async function flowF(page, check, failShot) {
  await page.reset('dashboard');
  await page.shortcut('k');
  await page.waitFor(`!!document.querySelector('.palette-input')`, { label: 'command palette' });
  await sleep(250);
  await page.insertText('前端搭建');
  await sleep(400);
  const rows = await page.eval(`
    return [...document.querySelectorAll('.palette-row')].slice(0, 5).map((row) => ({
      text: row.textContent.trim().slice(0, 80),
      active: row.dataset.active === 'true',
      group: row.previousElementSibling?.className === 'palette-group' ? row.previousElementSibling.textContent : null,
    }));
  `);
  check('命令面板搜到条目', rows.some((row) => row.text.includes('前端搭建')), { rows });

  await page.eval(`
    const row = [...document.querySelectorAll('.palette-row')].find((el) => el.textContent.includes('前端搭建'));
    if (!row) throw new Error('palette row missing');
    row.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
    return true;
  `);
  await sleep(150);
  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(700);

  const state = await page.eval(`
    const selectedBar = [...document.querySelectorAll('.gantt-bar.is-selected')].map((el) => el.getAttribute('aria-label'));
    const selectedTree = [...document.querySelectorAll('.gantt-tree-row.is-selected')].map((el) => el.textContent.trim());
    return {
      route: document.documentElement.dataset.route,
      url: location.search,
      selectedBar,
      selectedTree: selectedTree.map((t) => t.slice(0, 40)),
      paletteOpen: !!document.querySelector('.palette-input'),
    };
  `);
  check('Enter 后跳到甘特视图并关闭面板', state.route === 'gantt' && state.paletteOpen === false, { route: state.route, url: state.url, paletteOpen: state.paletteOpen });
  check(
    '目标条目处于选中态',
    state.selectedBar.some((label) => label.startsWith('前端搭建')) && state.selectedTree.some((text) => text.includes('前端搭建')),
    state,
  );
  await failShot(page, 'final-state');
}

async function flowG(page, check, failShot) {
  await page.reset('dashboard');
  const beforeTheme = await page.eval(`
    return { dataset: document.documentElement.dataset.theme, stored: localStorage.getItem('textura.theme') };
  `);
  check('初始为浅色且未写入 localStorage', beforeTheme.dataset === 'light' && beforeTheme.stored === null, beforeTheme);

  const clicked = await page.eval(`
    const button = document.querySelector('button[aria-label="切换到深色主题"]');
    if (!button) return false;
    button.click();
    return true;
  `);
  check('点击主题切换按钮', clicked === true);
  await sleep(400);
  const afterToggle = await page.eval(`
    return { dataset: document.documentElement.dataset.theme, stored: localStorage.getItem('textura.theme') };
  `);
  check('切换后 dataset.theme=dark 且 localStorage textura.theme=dark', afterToggle.dataset === 'dark' && afterToggle.stored === 'dark', afterToggle);
  await page.screenshot('docs/screenshots/dashboard-dark.png');

  await page.reload({ route: 'dashboard' });
  await sleep(600);
  const afterReload = await page.eval(`
    return { dataset: document.documentElement.dataset.theme, stored: localStorage.getItem('textura.theme') };
  `);
  check('刷新后保持深色主题', afterReload.dataset === 'dark' && afterReload.stored === 'dark', afterReload);

  await page.eval(`
    const button = document.querySelector('button[aria-label="切换到浅色主题"]');
    if (!button) throw new Error('theme toggle missing after reload');
    button.click();
    return true;
  `);
  await sleep(300);
  const restored = await page.eval(`
    return { dataset: document.documentElement.dataset.theme, stored: localStorage.getItem('textura.theme') };
  `);
  check('可以切回浅色', restored.dataset === 'light' && restored.stored === 'light', restored);
  await failShot(page, 'final-state');
}

async function flowH(page, check, failShot) {
  rmSync(DOWNLOAD_DIR, { recursive: true, force: true });
  mkdirSync(DOWNLOAD_DIR, { recursive: true });
  try {
    await page.cdp.send('Browser.setDownloadBehavior', {
      behavior: 'allow',
      downloadPath: DOWNLOAD_DIR,
      eventsEnabled: true,
    });
  } catch (error) {
    await page.cdp.send('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: DOWNLOAD_DIR });
  }

  await page.reset('settings');
  const settingsText = await page.eval(`return document.body.innerText.includes('浏览器调试模式');`);
  check('设置页识别为浏览器调试模式', settingsText === true);

  await clickButtonByText(page, '导出 JSON');
  let files = [];
  for (let attempt = 0; attempt < 40; attempt += 1) {
    files = readdirSync(DOWNLOAD_DIR).filter((name) => name.endsWith('.json'));
    if (files.length > 0) break;
    await sleep(250);
  }
  check('浏览器下载分支产出 JSON 文件', files.length > 0, { files });
  if (files.length > 0) {
    const raw = readFileSync(`${DOWNLOAD_DIR}/${files[0]}`, 'utf8');
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch {
      /* handled below */
    }
    check(
      '导出 JSON 可解析且包含完整工作区',
      Boolean(parsed) && parsed.version === 1 && parsed.items.length === 30 && parsed.areas.length === 3 && parsed.runs.length === 3,
      parsed ? { version: parsed.version, items: parsed.items.length, areas: parsed.areas.length, runs: parsed.runs.length, bytes: raw.length } : { error: 'parse failed' },
    );
  }

  // reseed: clear the workspace key only, then reload
  await page.eval(`localStorage.removeItem(${JSON.stringify(WORKSPACE_KEY)}); return true;`);
  await page.reload({ route: 'settings' });
  await sleep(900);
  const reseeded = await page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)});
    const ws = raw ? JSON.parse(raw) : null;
    return {
      items: ws ? ws.items.length : 0,
      inbox: ws ? ws.items.filter((i) => i.status === 'inbox').length : 0,
      areas: ws ? ws.areas.length : 0,
      runs: ws ? ws.runs.length : 0,
      sidebarCount: document.querySelector('.sidebar-link-count')?.textContent.trim() ?? null,
    };
  `);
  check(
    '清空 textura.workspace.v1 后刷新重新播种演示数据',
    reseeded.items === 30 && reseeded.inbox === 6 && reseeded.areas === 3 && reseeded.runs === 3,
    reseeded,
  );

  // leave a clean seeded state
  await page.eval(`localStorage.removeItem(${JSON.stringify(WORKSPACE_KEY)}); return true;`);
  await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
  await sleep(900);
  const clean = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(WORKSPACE_KEY)}));
    return { items: ws.items.length, inbox: ws.items.filter((i) => i.status === 'inbox').length, route: document.documentElement.dataset.route };
  `);
  check('收尾：演示数据恢复为干净初始状态', clean.items === 30 && clean.inbox === 6, clean);
  await failShot(page, 'final-state');
}

async function main() {
  mkdirSync(FAIL_DIR, { recursive: true });
  await withPage(async (page) => {
    await flow('a-quick-capture-clarify', (check, shot) => flowA(page, check, shot));
    await flow('b-gantt-drag-persist', (check, shot) => flowB(page, check, shot));
    await flow('c-okr-metric-progress', (check, shot) => flowC(page, check, shot));
    await flow('d-gtd-complete-sync', (check, shot) => flowD(page, check, shot));
    await flow('e-sop-drag-run', (check, shot) => flowE(page, check, shot));
    await flow('f-command-palette', (check, shot) => flowF(page, check, shot));
    await flow('g-theme-persist', (check, shot) => flowG(page, check, shot));
    await flow('h-settings-export-reseed', (check, shot) => flowH(page, check, shot));
  });

  const summary = results.map((entry) => ({
    flow: entry.name,
    passed: entry.steps.filter((step) => step.ok).length,
    failed: entry.steps.filter((step) => !step.ok).length,
    steps: entry.steps,
    screenshots: entry.screenshots,
  }));
  writeFileSync('docs/screenshots/flows-report.json', JSON.stringify(summary, null, 2));

  console.log('\n=== FLOW SUMMARY ===');
  for (const entry of summary) {
    console.log(`${entry.failed === 0 ? 'PASS' : 'FAIL'}  ${entry.flow}  (${entry.passed}/${entry.passed + entry.failed})`);
    for (const step of entry.steps.filter((s) => !s.ok)) console.log(`      - ${step.label}`);
  }
  if (flowFailures > 0) process.exitCode = 2;
}

main().catch((error) => {
  console.error('FLOWS FAILED:', error);
  process.exit(1);
});
