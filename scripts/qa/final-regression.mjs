/**
 * 第三轮终验：工程评审修复项的独立复核（a–i，浏览器侧）。
 * 全部通过 CDP 真实交互 + localStorage/DOM 断言；不读代码下结论。
 *
 * Tauri 文件持久化侧（a-ii / b / c-restart）由 scripts/qa/app-boot.sh 覆盖。
 */
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/final-regression';
const DL = '/tmp/textura-final-downloads';

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
}

const ROUTE_BY_LABEL = { 今日: 'dashboard', OKR: 'okr', GTD: 'gtd', 甘特: 'gantt', SOP: 'sop', 设置: 'settings' };

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
  await sleep(400);
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
  if (!ok) throw new Error(`button not found: ${text}`);
  await sleep(250);
}

const ORIGIN = new URL(BASE_URL).origin;

async function clearAndReset(page, route) {
  // 初始页是 about:blank（opaque origin，localStorage 不可访问），先进入应用源。
  let onApp = false;
  try {
    onApp = await page.eval(`return location.origin === ${JSON.stringify(ORIGIN)};`);
  } catch {
    onApp = false;
  }
  if (!onApp) {
    await page.goto(`${BASE_URL}/?route=${route}`, { route });
  }
  await page.eval(`localStorage.clear(); return true;`);
  await page.goto(`${BASE_URL}/?route=${route}`, { route });
  await sleep(400);
}

/** 重新加载，允许出现错误屏（不强制 .shell 存在）。 */
async function reloadRaw(page) {
  page.resetIssues();
  await page.cdp.send('Page.reload', { ignoreCache: false });
  await page.waitFor(`document.readyState === 'complete'`, { label: 'reload ready' });
  await page.waitFor(`!!document.querySelector('.shell, .loading-screen')`, { label: 'shell or error screen' });
  await sleep(700);
}

async function setWorkspace(page, ws) {
  await page.eval(`
    localStorage.setItem(${JSON.stringify(KEY)}, ${JSON.stringify(JSON.stringify(ws))});
    return true;
  `);
}

async function readWorkspace(page) {
  return page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(KEY)});
    return raw ? JSON.parse(raw) : null;
  `);
}

async function setFileInput(page, path) {
  await page.cdp.send('DOM.enable');
  const { root } = await page.cdp.send('DOM.getDocument', { depth: 1 });
  const { nodeId } = await page.cdp.send('DOM.querySelector', {
    nodeId: root.nodeId,
    selector: 'input[aria-label="选择要导入的 JSON 文件"]',
  });
  if (!nodeId) throw new Error('file input not found');
  await page.cdp.send('DOM.setFileInputFiles', { files: [path], nodeId });
  await sleep(700);
}

async function importFile(page, path, { confirm = true } = {}) {
  await clickText(page, '导入 JSON…');
  await setFileInput(page, path);
  if (!confirm) return;
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'import dialog' });
  await clickText(page, '覆盖并导入');
  await sleep(900);
}

function writeJson(path, value) {
  writeFileSync(path, JSON.stringify(value, null, 2), 'utf8');
  return path;
}

const CYCLE_WS = {
  version: 1,
  updatedAt: '2026-10-21T00:00:00.000Z',
  areas: [],
  edges: [],
  runs: [],
  items: [
    { id: 'cyc_a', kind: 'action', title: '环A', status: 'next', parentId: 'cyc_b' },
    { id: 'cyc_b', kind: 'action', title: '环B', status: 'next', parentId: 'cyc_a' },
  ],
};

/* ------------------------------------------------------------------ a --- */
async function flowA(page) {
  const flow = 'a-parent-cycle';
  // (i) 导入被拒绝
  await clearAndReset(page, 'settings');
  const cyclePath = writeJson('/tmp/textura-cycle.json', CYCLE_WS);
  await importFile(page, cyclePath, { confirm: false });
  await sleep(600);
  const rejected = await page.eval(`
    return {
      notices: [...document.querySelectorAll('.notice')].map((el) => el.textContent.trim()),
      modal: Boolean(document.querySelector('[role="dialog"]')),
      items: JSON.parse(localStorage.getItem(${JSON.stringify(KEY)})).items.length,
    };
  `);
  check(
    flow,
    '导入含环 JSON 被拒绝且错误可读',
    rejected.notices.some((text) => text.includes('导入失败') && text.includes('父子环') && text.includes('环A') && text.includes('环B')) &&
      rejected.modal === false &&
      rejected.items === 30,
    rejected,
  );
  await page.screenshot(`${OUT}/a-cycle-import-rejected.png`);

  // (ii) 直接把环写进 localStorage 后加载（等价于坏 workspace.json）
  await setWorkspace(page, CYCLE_WS);
  await reloadRaw(page);
  const loaded = await page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(KEY)});
    const ws = JSON.parse(raw);
    return {
      shell: Boolean(document.querySelector('.shell')),
      sidebarLinks: document.querySelectorAll('.sidebar-nav .sidebar-link').length,
      notices: [...document.querySelectorAll('.notice')].map((el) => el.textContent.trim()),
      mainText: (document.querySelector('.shell-content')?.innerText || '').trim().length,
      storedItems: ws.items.length,
      storedParentA: ws.items.find((i) => i.id === 'cyc_a')?.parentId ?? null,
      storedParentB: ws.items.find((i) => i.id === 'cyc_b')?.parentId ?? null,
    };
  `);
  const warn = page.issues.filter((issue) => issue.level === 'warning' && issue.text.includes('检测到父子环'));
  check(flow, '含环数据加载：不白屏、外壳可用、渲染出数据', loaded.shell && loaded.sidebarLinks === 6 && loaded.mainText > 20, loaded);
  check(flow, '含环数据加载：console.warn 记录切断动作', warn.length >= 1, { warn: warn.map((w) => w.text.slice(0, 160)) });
  check(
    flow,
    '含环数据加载：出现可读提示（已切断 parentId）',
    loaded.notices.some((text) => text.includes('检测到父子环') && text.includes('已自动切断 parentId')),
    { notices: loaded.notices },
  );
  check(
    flow,
    '原数据未被覆盖（localStorage 中环仍存在）',
    loaded.storedItems === 2 && loaded.storedParentA === 'cyc_b' && loaded.storedParentB === 'cyc_a',
    { storedItems: loaded.storedItems, storedParentA: loaded.storedParentA, storedParentB: loaded.storedParentB },
  );

  await navTo(page, 'GTD');
  const nextCount = await page.eval(`
    const card = document.querySelectorAll('.gtd-flow-card')[1];
    return card ? card.querySelector('.gtd-flow-card-value')?.textContent.trim() : null;
  `);
  check(flow, '切断后两条 action 仍可用（GTD 下一步 = 2）', nextCount === '2', { nextCount });
  await page.screenshot(`${OUT}/a-cycle-load-rendered.png`);
}

/* ------------------------------------------------------------------ b --- */
async function flowB(page) {
  const flow = 'b-future-version';
  await clearAndReset(page, 'dashboard');
  const future = JSON.parse(JSON.stringify((await readWorkspace(page))));
  future.version = 99;
  await setWorkspace(page, future);
  await reloadRaw(page);

  const screen = await page.eval(`
    const alert = document.querySelector('.loading-screen[role="alert"]');
    const stored = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return {
      hasAlert: Boolean(alert),
      text: alert ? alert.innerText.trim() : null,
      shell: Boolean(document.querySelector('.shell')),
      storedVersion: stored?.version ?? null,
      storedItems: stored?.items?.length ?? null,
    };
  `);
  check(flow, 'future version 启动被拒绝并显示错误屏（不白屏）', screen.hasAlert && !screen.shell, {
    hasAlert: screen.hasAlert,
    shell: screen.shell,
  });
  check(
    flow,
    '错误文案可读且含版本号',
    Boolean(screen.text && screen.text.includes('工作区加载失败') && screen.text.includes('99') && screen.text.includes('高于当前应用支持的版本')),
    { text: screen.text },
  );
  check(flow, '主数据未被改写（仍为 version 99 / 30 条）', screen.storedVersion === 99 && screen.storedItems === 30, screen);
  await page.screenshot(`${OUT}/b-future-version.png`);
}

/* ------------------------------------------------------------------ c --- */
async function flowC(page) {
  const flow = 'c-empty-workspace';
  await clearAndReset(page, 'settings');
  const emptyPath = writeJson('/tmp/textura-empty.json', { version: 1, items: [], edges: [], areas: [], runs: [] });
  await importFile(page, emptyPath);
  const afterImport = await readWorkspace(page);
  check(flow, '导入空工作区成功（items=0）', afterImport.items.length === 0, { items: afterImport.items.length });

  await page.reload({ route: 'settings' });
  await sleep(900);
  const afterReload = await readWorkspace(page);
  check(flow, '刷新后仍为空（未被演示数据覆盖）', afterReload.items.length === 0 && afterReload.areas.length === 0, {
    items: afterReload.items.length,
    areas: afterReload.areas.length,
    runs: afterReload.runs.length,
  });

  await navTo(page, '今日');
  await sleep(500);
  const dashboard = await page.eval(`
    return {
      stats: [...document.querySelectorAll('.dash-stat')].map((el) => ({
        label: el.querySelector('.dash-stat-label')?.textContent.trim(),
        value: el.querySelector('.dash-stat-value')?.textContent.trim(),
      })),
      text: (document.querySelector('.shell-content')?.innerText || '').trim(),
    };
  `);
  // 空工作区：今日页改为空状态（不渲染指标卡），文案引导收集/建目标。
  check(
    flow,
    '空工作区下今日页显示空状态（0 指标卡、有引导文案、不报错）',
    dashboard.stats.length === 0 &&
      dashboard.text.includes('工作区还是空的') &&
      dashboard.text.includes('从第一条记录开始'),
    { stats: dashboard.stats, text: dashboard.text.slice(0, 160) },
  );
  await page.screenshot(`${OUT}/c-empty-workspace.png`);
}

/* ------------------------------------------------------------------ d --- */
async function flowD(page) {
  const flow = 'd-normalization';
  await clearAndReset(page, 'settings');
  const messy = {
    version: 1,
    updatedAt: '2026-10-21T00:00:00.000Z',
    edges: [],
    runs: [],
    areas: [{ id: 'area_demo', name: '演示', color: '#C0663A', order: 0 }],
    items: [
      {
        id: 'obj_norm',
        kind: 'objective',
        title: '归一化目标',
        status: 'active',
        areaId: 'area_demo',
        okr: { period: '2026-Q4', confidence: 5 },
      },
      {
        id: 'norm_kr',
        kind: 'keyresult',
        title: '归一化 KR',
        parentId: 'obj_norm',
        status: 'bogus-status',
        areaId: 'area_demo',
        okr: { period: '2026-Q4', confidence: 999, metric: { start: 0, target: 100, current: 50, unit: '%' } },
      },
      {
        id: 'norm_act',
        kind: 'action',
        title: '归一化行动',
        status: 'next',
        gantt: { start: '2026-10-20', end: '2026-10-25', progress: 'half' },
      },
    ],
  };
  const messyPath = writeJson('/tmp/textura-messy.json', messy);
  await importFile(page, messyPath);

  const stored = await readWorkspace(page);
  const kr = stored.items.find((item) => item.id === 'norm_kr');
  const act = stored.items.find((item) => item.id === 'norm_act');
  const saveLabel = await page.text('.storage-status');
  check(flow, '归一化后保存成功（侧栏「已保存」）', saveLabel === '已保存', { saveLabel });
  check(flow, 'confidence 999 → 夹紧为 10', kr?.okr?.confidence === 10, { confidence: kr?.okr?.confidence });
  check(flow, 'progress "half" → 0', act?.gantt?.progress === 0, { progress: act?.gantt?.progress });
  check(flow, '非法 status → 回退 next', kr?.status === 'next', { status: kr?.status });
  check(flow, '其它字段保留（日期/指标/区域）', act?.gantt?.start === '2026-10-20' && kr?.okr?.metric?.current === 50 && kr?.areaId === 'area_demo', {
    start: act?.gantt?.start,
    current: kr?.okr?.metric?.current,
    areaId: kr?.areaId,
  });

  await page.reload({ route: 'settings' });
  await sleep(900);
  const afterReload = await readWorkspace(page);
  const kr2 = afterReload.items.find((item) => item.id === 'norm_kr');
  check(
    flow,
    '刷新后数据可读且值仍被夹紧',
    kr2?.okr?.confidence === 10 && kr2?.status === 'next' && afterReload.items.length === 3,
    { confidence: kr2?.okr?.confidence, status: kr2?.status, items: afterReload.items.length },
  );
  await navTo(page, 'OKR');
  await sleep(700);
  const okrRender = await page.eval(`
    const row = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('归一化 KR'));
    return {
      found: Boolean(row),
      pct: row?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
      objective: document.querySelector('.okr-objective')?.getAttribute('aria-label') ?? null,
      crashered: Boolean(document.querySelector('.route-error')),
    };
  `);
  check(
    flow,
    'OKR 视图渲染归一化后的 KR（进度 50%，无崩溃）',
    okrRender.found && okrRender.pct === '50%' && okrRender.crashered === false,
    okrRender,
  );
  await page.screenshot(`${OUT}/d-normalization.png`);
}

/* ------------------------------------------------------------------ e --- */
async function flowE(page) {
  const flow = 'e-error-boundaries';

  // e-1：坏 localStorage（store 加载抛错/回退）→ 不白屏
  await clearAndReset(page, 'dashboard');
  await page.eval(`localStorage.setItem(${JSON.stringify(KEY)}, '{not-json'); return true;`);
  await reloadRaw(page);
  const bad = await page.eval(`
    return {
      shell: Boolean(document.querySelector('.shell')),
      text: (document.body.innerText || '').trim().slice(0, 160),
      textLength: (document.body.innerText || '').trim().length,
    };
  `);
  const parseWarn = page.issues.filter((issue) => issue.level === 'warning' && issue.text.includes('无法读取'));
  check(flow, '损坏 localStorage：不白屏，回退为空库并渲染外壳', bad.shell && bad.textLength > 20, bad);
  check(flow, '损坏 localStorage：console.warn 说明回退', parseWarn.length >= 1, { warn: parseWarn.map((w) => w.text.slice(0, 120)) });

  // e-2：store 加载错误（future version）→ AppShell 错误屏
  await clearAndReset(page, 'dashboard');
  const ws = await readWorkspace(page);
  ws.version = 99;
  await setWorkspace(page, ws);
  await reloadRaw(page);
  const storeError = await page.eval(`
    const alert = document.querySelector('.loading-screen[role="alert"]');
    return {
      hasAlert: Boolean(alert),
      text: alert ? alert.innerText.trim() : null,
      retryButton: Boolean(alert && [...alert.querySelectorAll('button')].some((b) => b.textContent.trim() === '重试')),
    };
  `);
  check(flow, 'store 加载错误：显示可读错误屏且提供「重试」', storeError.hasAlert && storeError.retryButton, storeError);
  await page.screenshot(`${OUT}/e-load-error.png`);

  // e-3：路由渲染错误 → RouteErrorBoundary（外壳保留）
  await clearAndReset(page, 'dashboard');
  await page.eval(`
    window.__qaRealResizeObserver = window.ResizeObserver;
    delete window.ResizeObserver;
    return true;
  `);
  await navTo(page, '甘特');
  await sleep(900);
  const boundary = await page.eval(`
    const error = document.querySelector('.route-error');
    return {
      hasBoundary: Boolean(error),
      title: error?.querySelector('.route-error-title')?.textContent.trim() ?? null,
      description: error?.querySelector('.route-error-description')?.textContent.trim() ?? null,
      detail: error?.querySelector('.route-error-detail')?.textContent.trim() ?? null,
      actions: error ? [...error.querySelectorAll('button')].map((b) => b.textContent.trim()) : [],
      shellStillThere: Boolean(document.querySelector('.sidebar') && document.querySelector('.topbar')),
      whiteScreen: (document.body.innerText || '').trim().length < 10,
    };
  `);
  check(
    flow,
    '渲染异常：RouteErrorBoundary 呈现可读 fallback，外壳仍在',
    boundary.hasBoundary &&
      boundary.title === '这个视图暂时无法显示' &&
      boundary.actions.length === 3 &&
      boundary.shellStillThere &&
      boundary.whiteScreen === false,
    boundary,
  );
  await page.screenshot(`${OUT}/e-route-boundary.png`);

  // 恢复并验证可返回今日
  await page.eval(`
    if (window.__qaRealResizeObserver) window.ResizeObserver = window.__qaRealResizeObserver;
    return true;
  `);
  await clickText(page, '返回今日');
  await sleep(700);
  const recovered = await page.eval(`
    return {
      route: document.documentElement.dataset.route,
      boundary: Boolean(document.querySelector('.route-error')),
      stats: document.querySelectorAll('.dash-stat').length,
    };
  `);
  check(flow, '点击「返回今日」后恢复渲染', recovered.route === 'dashboard' && recovered.boundary === false && recovered.stats === 4, recovered);
}

/* ------------------------------------------------------------------ f --- */
async function canvasMap(page) {
  return page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const steps = ws.items.filter((item) => item.kind === 'step' && item.sop?.canvas);
    const map = {};
    for (const item of steps) map[item.id] = { x: item.sop.canvas.x, y: item.sop.canvas.y };
    return map;
  `);
}

async function flowF(page) {
  const flow = 'f-sop-undo-granularity';
  await clearAndReset(page, 'sop');
  await sleep(1200);
  const initial = await canvasMap(page);
  const ids = Object.keys(initial);
  check(flow, '读取初始 7 个 step 坐标（不含 SOP 容器）', ids.length === 7, { count: ids.length });

  // 首屏是「纵向预览布局」，stored canvas 仍是旧的横向坐标；因此首次拖拽会把
  // 预览后的整张布局与拖拽一起写成一条历史 —— 断言的正是「一次撤销整体回退」。
  await page.drag('.react-flow__node[data-id="step_start"]', 120, 80, { steps: 12, settle: 500 });
  await sleep(900);
  const afterDrag = await canvasMap(page);
  const movedIds = ids.filter((id) => afterDrag[id].x !== initial[id].x || afterDrag[id].y !== initial[id].y);
  check(flow, '拖拽后坐标写入（含预览布局的整张提交）', movedIds.length >= 1 && afterDrag.step_start.x !== initial.step_start.x, {
    movedCount: movedIds.length,
  });

  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(700);
  const afterUndo = await canvasMap(page);
  const diffAfterUndo = ids.filter((id) => afterUndo[id].x !== initial[id].x || afterUndo[id].y !== initial[id].y);
  check(flow, '一次 Ctrl+Z 全部坐标回到拖拽前（无混合布局）', diffAfterUndo.length === 0, {
    diffAfterUndo,
    restored: Object.keys(afterUndo).length,
  });

  // 自动布局 → 一次 Ctrl+Z 全部回退
  await clickText(page, '自动布局');
  await sleep(1200);
  const afterLayout = await canvasMap(page);
  const layoutMoved = ids.filter((id) => afterLayout[id].x !== afterUndo[id].x || afterLayout[id].y !== afterUndo[id].y);
  check(flow, '自动布局改变多个节点坐标', layoutMoved.length >= 3, { layoutMoved: layoutMoved.length });

  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(800);
  const afterLayoutUndo = await canvasMap(page);
  const diffLayoutUndo = ids.filter(
    (id) => afterLayoutUndo[id].x !== afterUndo[id].x || afterLayoutUndo[id].y !== afterUndo[id].y,
  );
  check(flow, '一次 Ctrl+Z 撤销整次自动布局（回到拖拽前坐标）', diffLayoutUndo.length === 0, { diffLayoutUndo });
  await page.screenshot(`${OUT}/f-sop-undo.png`);
}

/* ------------------------------------------------------------------ g --- */
async function metricState(page) {
  return page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const kr = ws.items.find((item) => item.id === 'kr_nps');
    const row = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return {
      current: kr?.okr?.metric?.current ?? null,
      start: kr?.okr?.metric?.start ?? null,
      target: kr?.okr?.metric?.target ?? null,
      pct: row?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
      convertText: (row?.querySelector('.okr-metric-summary')?.textContent || '').trim() ?? null,
    };
  `);
}

async function flowG(page) {
  const flow = 'g-okr-undo';
  await clearAndReset(page, 'okr');
  await sleep(500);
  const before = await metricState(page);
  check(flow, '初始 NPS 47 / 28%', before.current === 47 && before.pct === '28%', before);

  // g-1：连续输入 6 → 60，一次 Ctrl+Z 回原值
  await page.click('input[aria-label="NPS 从 42 提升到 60 指标当前值"]');
  await page.selectAll();
  await page.insertText('6');
  await sleep(120);
  await page.insertText('0');
  await sleep(300);
  await page.waitFor(
    `[...document.querySelectorAll('.storage-status')].some((el) => el.textContent.includes('已保存'))`,
    { label: 'save after metric input', timeout: 6000 },
  );
  await sleep(200);
  const typed = await metricState(page);
  check(flow, '连续输入后当前值 = 60（进度 100%）', typed.current === 60 && typed.pct === '100%', typed);

  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(700);
  const undone = await metricState(page);
  check(flow, '一次 Ctrl+Z 回到 47（不是 6）', undone.current === 47 && undone.pct === '28%', undone);

  // g-2：移动到其他季度 → 一次 Ctrl+Z 整体回退
  const openMenu = await page.eval(`
    const button = [...document.querySelectorAll('button[aria-label]')].find((el) => el.getAttribute('aria-label').endsWith('更多操作'));
    if (!button) return false;
    button.click();
    return true;
  `);
  check(flow, '打开目标操作菜单', openMenu === true);
  await sleep(300);
  await clickText(page, '移动到其他季度');
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'quarter dialog' });
  await sleep(300);
  await clickText(page, '移动', '[role="dialog"]');
  await sleep(900);
  const moved = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const obj = ws.items.find((item) => item.id === 'obj_activation');
    const krs = ws.items.filter((item) => item.kind === 'keyresult' && item.parentId === 'obj_activation');
    return { period: obj?.okr?.period ?? null, krPeriods: [...new Set(krs.map((kr) => kr.okr?.period))] };
  `);
  check(flow, '目标与全部 KR 一起移动季度', Boolean(moved.period && moved.period !== '2026-Q4') && moved.krPeriods.length === 1 && moved.krPeriods[0] === moved.period, moved);

  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(900);
  const movedUndo = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const obj = ws.items.find((item) => item.id === 'obj_activation');
    const krs = ws.items.filter((item) => item.kind === 'keyresult' && item.parentId === 'obj_activation');
    return { period: obj?.okr?.period ?? null, krPeriods: [...new Set(krs.map((kr) => kr.okr?.period))] };
  `);
  check(flow, '一次 Ctrl+Z 整体回退到原季度', movedUndo.period === '2026-Q4' && movedUndo.krPeriods.length === 1 && movedUndo.krPeriods[0] === '2026-Q4', movedUndo);

  // 撤销只回退数据，ui.okrPeriod 仍停在新季度；重新加载回到当前季度再做 g-3
  await page.reload({ route: 'okr' });
  await sleep(800);

  // g-3：起点 == 目标 → 不出现「换算 100%」
  await page.typeInto('input[aria-label="NPS 从 42 提升到 60 指标目标值"]', '42');
  await sleep(800);
  const flat = await page.eval(`
    const row = [...document.querySelectorAll('.okr-kr')].find((el) => el.textContent.includes('NPS 从 42 提升到 60'));
    return {
      summary: (row?.querySelector('.okr-metric-summary')?.innerText || '').trim(),
      hint: [...row.querySelectorAll('*')].map((el) => el.textContent.trim()).find((t) => t.includes('起点与目标相同')) ?? null,
      pct: row?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
    };
  `);
  check(flow, '起点==目标：不显示「换算 100%」且给出可读说明', !flat.summary.includes('换算 100%') && Boolean(flat.hint), flat);
  await page.screenshot(`${OUT}/g-okr-flat-metric.png`);
}

/* ------------------------------------------------------------------ h --- */
async function flowH(page) {
  const flow = 'h-weekly-count-consistency';
  await clearAndReset(page, 'dashboard');
  // 让场景有区分度：先完成一条下一步
  await navTo(page, 'GTD');
  const completed = await page.eval(`
    const button = document.querySelector('button[aria-label="完成「整理本周复盘」"]');
    if (!button) return false;
    button.click();
    return true;
  `);
  check(flow, '完成一条下一步以产生完成记录', completed === true);
  await sleep(800);

  await navTo(page, '今日');
  await sleep(500);
  const dashboardCount = await page.eval(`
    const card = [...document.querySelectorAll('.dash-stat')].find((el) => el.querySelector('.dash-stat-label')?.textContent.trim() === '近 7 天完成');
    return card ? Number((card.querySelector('.dash-stat-value')?.textContent || '').replace(/\\D/g, '')) : null;
  `);

  await navTo(page, 'GTD');
  await sleep(400);
  await page.eval(`
    const option = [...document.querySelectorAll('[role="radio"], .segmented button, .segmented-option')].find((el) => el.textContent.trim() === '周回顾');
    if (!option) throw new Error('周回顾 segmented missing');
    option.click();
    return true;
  `);
  await sleep(700);
  const reviewCount = await page.eval(`
    const card = [...document.querySelectorAll('.gtd-review-card')].find((el) => el.querySelector('h3')?.textContent.trim() === '本周完成');
    return card ? Number((card.querySelector('.gtd-review-metric strong')?.textContent || '').replace(/\\D/g, '')) : null;
  `);
  check(flow, '周回顾「本周完成」与今日「近 7 天完成」计数一致', dashboardCount === reviewCount && dashboardCount !== null, {
    dashboardCount,
    reviewCount,
  });
  await page.screenshot(`${OUT}/h-weekly-review.png`);
}

/* ------------------------------------------------------------------ i --- */
async function flowI(page) {
  const flow = 'i-undated-bucket';
  await clearAndReset(page, 'dashboard');
  await sleep(600);
  const data = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const byTitle = new Map(ws.items.map((item) => [item.title, item]));
    const rows = [...document.querySelectorAll('.dash-focus-row')].map((row) => ({
      bucket: row.dataset.bucket,
      title: row.querySelector('.dash-focus-title')?.textContent.trim() ?? '',
    }));
    const summary = document.querySelector('.dash-card-sub')?.textContent.trim() ?? null;
    return {
      rows: rows.map((row) => {
        const item = byTitle.get(row.title);
        return {
          ...row,
          start: item?.gantt?.start ?? null,
          end: item?.gantt?.end ?? null,
          status: item?.status ?? null,
        };
      }),
      summary,
      counts: {
        overdue: rows.filter((row) => row.bucket === 'overdue').length,
        today: rows.filter((row) => row.bucket === 'today').length,
        undated: rows.filter((row) => row.bucket === 'undated').length,
      },
    };
  `);
  const undated = data.rows.filter((row) => row.bucket === 'undated');
  check(flow, '「无日期」桶非空（可用于验证）', undated.length > 0, { undatedCount: undated.length, rows: data.rows });
  check(
    flow,
    '「无日期」桶中没有带 start/end 的条目',
    undated.every((row) => row.start === null && row.end === null),
    { undated: undated.map((row) => ({ title: row.title, start: row.start, end: row.end })) },
  );
  check(
    flow,
    '有日期的条目都落在 overdue/today/upcoming 桶',
    data.rows.filter((row) => row.start || row.end).every((row) => row.bucket !== 'undated'),
    { dated: data.rows.filter((row) => row.start || row.end).map((row) => ({ title: row.title, bucket: row.bucket })) },
  );
  const summaryMatches = data.summary?.includes(`${data.counts.overdue} 超期`) && data.summary?.includes(`${data.counts.today} 今天`) && data.summary?.includes(`${data.counts.undated} 无日期`);
  check(flow, '聚焦摘要计数与实际分桶一致', Boolean(summaryMatches), { summary: data.summary, counts: data.counts });
  await page.screenshot(`${OUT}/i-undated-bucket.png`);
}

/* ------------------------------------------------------------------ run -- */
async function main() {
  mkdirSync(OUT, { recursive: true });
  rmSync(DL, { recursive: true, force: true });
  mkdirSync(DL, { recursive: true });

  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    try {
      await page.cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: DL, eventsEnabled: true });
    } catch {
      await page.cdp.send('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: DL });
    }
    for (const flow of [flowA, flowB, flowC, flowD, flowE, flowF, flowG, flowH, flowI]) {
      try {
        await flow(page);
      } catch (error) {
        check(flow.name, `流程异常：${error.message.split('\n')[0]}`, false, { error: error.message.split('\n').slice(0, 3).join(' | ') });
        await page.screenshot(`${OUT}/${flow.name}-failed.png`).catch(() => {});
      }
    }
  });

  writeFileSync(`${OUT}/final-regression-report.json`, JSON.stringify(results, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== FINAL REGRESSION SUMMARY ===');
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
  console.error('FINAL REGRESSION FAILED:', error);
  process.exit(1);
});
