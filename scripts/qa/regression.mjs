/**
 * 第二轮修复回归（a–e）。全部通过 CDP 真实交互 + DOM/存储断言，不做代码推断。
 *
 *   a. 甘特完成态进度口径（左树 / 条 / Inspector / aria-label）且不写回 gantt.progress
 *   b. 甘特页头 h1 与 1024×720 溢出
 *   c. SOP 初始可读视口 + 竖向铺开 + 「适应画布」一次看全
 *   d. 设置导入 / 撤销 / 重置 / 非法导入 / 保存态
 *   e. 深色主题关键元素对比度（WCAG 2.1）
 */
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const WORKSPACE_KEY = 'textura.workspace.v1';
const DOWNLOAD_DIR = '/tmp/textura-qa-downloads-2';
const OUT_DIR = 'docs/screenshots/regression';

const results = [];
let failures = 0;
let auditFindings = 0;

/**
 * kind='assert'  → 修复回归断言，失败应视为回归（退出码 1）
 * kind='audit'   → WCAG 对比度审计：低于阈值属于「发现的问题」，记录但不使回归失败
 */
function check(flow, label, ok, detail, kind = 'assert') {
  results.push({ flow, label, ok, detail, kind });
  if (!ok) {
    if (kind === 'audit') auditFindings += 1;
    else failures += 1;
  }
  console.log(`${ok ? 'PASS' : kind === 'audit' ? 'AUDIT' : 'FAIL'}  [${flow}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
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
  await sleep(350);
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

async function capture(page, text) {
  await page.eval(`
    const button = [...document.querySelectorAll('.topbar button')].find((el) => el.textContent.trim() === '快速收集');
    if (!button) throw new Error('topbar 快速收集 missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('#quick-capture-input')`, { label: 'capture modal' });
  await page.insertText(text);
  await sleep(220);
  await page.pressKey('Enter', { code: 'Enter', vk: 13 });
  await sleep(420);
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(320);
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
    { label: 'storage 已保存', timeout: 6000 },
  );
}

/* ------------------------------------------------------------------ a ---- */
async function flowA(page) {
  const flow = 'a-gantt-done-progress';
  await page.reset('dashboard');
  await capture(page, '进度口径核对 /明天');

  await navTo(page, 'GTD');
  const opened = await page.eval(`
    const row = [...document.querySelectorAll('.gtd-inbox-row .gtd-row-title')].find((el) => el.textContent.trim() === '进度口径核对');
    if (!row) return false;
    row.click();
    return true;
  `);
  check(flow, '新建条目进入收件箱并可澄清', opened);
  await page.waitFor(`!!document.querySelector('#gtd-clarify-form')`, { label: 'clarify form' });
  await clickText(page, '完成澄清');
  await sleep(500);

  await navTo(page, '甘特');
  await sleep(500);
  const located = await page.eval(`
    const bars = [...document.querySelectorAll('.gantt-bar[aria-label]')];
    const index = bars.findIndex((el) => el.getAttribute('aria-label').startsWith('进度口径核对'));
    return index >= 0 ? { index, label: bars[index].getAttribute('aria-label') } : null;
  `);
  check(flow, '甘特中找到该任务条', Boolean(located), located);
  // 选中依赖 pointerdown（GanttBar 的 onClick 只阻止冒泡），必须用真实鼠标点击
  await page.click('.gantt-bar[aria-label]', located.index);
  await sleep(500);
  const selected = await page.eval(`return [...document.querySelectorAll('.gantt-bar.is-selected')].map((el) => el.getAttribute('aria-label'));`);
  check(flow, '点击任务条后进入选中态', selected.some((label) => label.startsWith('进度口径核对')), { selected });

  // 检查器默认收起，先打开「详情」
  await clickText(page, '详情');
  await page.waitFor(`!!document.querySelector('.gantt-progress-range')`, { label: 'gantt inspector progress range' });
  await sleep(300);

  // 用真实键盘把进度调到 40%（step=5，ArrowRight × 8）
  await page.eval(`
    const range = document.querySelector('.gantt-progress-range');
    if (!range) throw new Error('progress range missing');
    range.focus();
    return true;
  `);
  for (let index = 0; index < 8; index += 1) {
    await page.pressKey('ArrowRight', { code: 'ArrowRight', vk: 39 });
    await sleep(90);
  }
  await sleep(500);
  const beforeDone = await page.eval(`
    const range = document.querySelector('.gantt-progress-range');
    return {
      rangeValue: range ? Number(range.value) : null,
      disabled: range ? range.disabled : null,
      shown: document.querySelector('.gantt-progress-value')?.textContent.trim() ?? null,
    };
  `);
  const wsBefore = await readWorkspace(page);
  const itemBefore = wsBefore.items.find((item) => item.title === '进度口径核对');
  check(flow, '先把进度改为 40%（滑块可编辑、未完成）', beforeDone.rangeValue === 40 && beforeDone.disabled === false && itemBefore?.gantt?.progress === 40, { beforeDone, stored: itemBefore?.gantt?.progress });

  // 在 GTD 勾选完成
  await navTo(page, 'GTD');
  const done = await page.eval(`
    const button = document.querySelector('button[aria-label="完成「进度口径核对」"]');
    if (!button) return false;
    button.scrollIntoView({ block: 'center' });
    button.click();
    return true;
  `);
  check(flow, 'GTD 勾选完成', done === true);
  await sleep(600);

  await navTo(page, '甘特');
  await sleep(500);
  const tree = await page.eval(`
    const row = [...document.querySelectorAll('.gantt-tree-row.is-item')].find((el) => el.textContent.includes('进度口径核对'));
    if (!row) return null;
    const bar = [...document.querySelectorAll('.gantt-bar[aria-label]')].find((el) => el.getAttribute('aria-label').startsWith('进度口径核对'));
    const fill = bar?.querySelector('.gantt-bar-fill');
    const styleWidth = fill ? fill.style.width : null;
    row.click();
    return {
      treeProgress: row.querySelector('.gantt-item-progress')?.textContent.trim() ?? null,
      barLabel: bar?.getAttribute('aria-label') ?? null,
      fillWidth: styleWidth,
      fillComputed: fill ? getComputedStyle(fill).width : null,
      barWidth: bar ? getComputedStyle(bar).width : null,
    };
  `);
  check(flow, '左树显示 100%', tree?.treeProgress === '100%', tree);
  check(flow, '任务条 aria-label 显示进度 100%', Boolean(tree?.barLabel?.includes('进度 100%')), { barLabel: tree?.barLabel });
  check(flow, '任务条填充宽度 100%', tree?.fillWidth === '100%', { fillWidth: tree?.fillWidth });

  await sleep(500);
  const inspector = await page.eval(`
    const range = document.querySelector('.gantt-progress-range');
    return {
      exists: Boolean(range),
      disabled: range ? range.disabled : null,
      value: range ? Number(range.value) : null,
      shown: document.querySelector('.gantt-progress-value')?.textContent.trim() ?? null,
      note: document.getElementById('gantt-progress-note')?.textContent.trim() ?? null,
    };
  `);
  check(flow, 'Inspector 显示 100%', inspector.shown === '100%', inspector);
  check(flow, 'Inspector 进度滑块在 done 时禁用', inspector.disabled === true, inspector);

  const wsAfter = await readWorkspace(page);
  const itemAfter = wsAfter.items.find((item) => item.title === '进度口径核对');
  check(
    flow,
    '底层 gantt.progress 未被改写（仍为 40）',
    itemAfter?.gantt?.progress === 40 && itemAfter?.status === 'done',
    { progress: itemAfter?.gantt?.progress, status: itemAfter?.status },
  );

  await page.screenshot(`${OUT_DIR}/a-gantt-done-progress.png`);
}

/* ------------------------------------------------------------------ b ---- */
async function flowB(page) {
  const flow = 'b-gantt-header';
  await page.setViewport(1440, 900);
  await page.reset('gantt');
  await sleep(400);

  const header = await page.eval(`
    const pick = (root) => {
      const el = document.querySelector(root + ' .page-header');
      if (!el) return null;
      const h1 = el.querySelector('h1');
      const style = getComputedStyle(el);
      const h1Style = h1 ? getComputedStyle(h1) : null;
      return {
        text: h1 ? h1.textContent.trim() : null,
        display: style.display,
        gap: style.gap,
        padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].join(' '),
        marginBottom: style.marginBottom,
        fontFamily: h1Style ? h1Style.fontFamily : null,
        fontSize: h1Style ? h1Style.fontSize : null,
        fontWeight: h1Style ? h1Style.fontWeight : null,
        lineHeight: h1Style ? h1Style.lineHeight : null,
        color: h1Style ? h1Style.color : null,
      };
    };
    return { gantt: pick('.gantt-page'), h1: document.querySelector('h1')?.textContent.trim() ?? null };
  `);
  check(flow, '甘特存在 .page-header 且 h1 = 甘特', header.h1 === '甘特' && header.gantt?.text === '甘特', header);

  await navTo(page, 'OKR');
  await sleep(400);
  const okrHeader = await page.eval(`
    const el = document.querySelector('.okr-page .page-header') || document.querySelector('.page-header');
    const h1 = el.querySelector('h1');
    const style = getComputedStyle(el);
    const h1Style = getComputedStyle(h1);
    return {
      text: h1.textContent.trim(),
      display: style.display,
      gap: style.gap,
      padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].join(' '),
      marginBottom: style.marginBottom,
      fontFamily: h1Style.fontFamily,
      fontSize: h1Style.fontSize,
      fontWeight: h1Style.fontWeight,
      lineHeight: h1Style.lineHeight,
      color: h1Style.color,
    };
  `);
  check(
    flow,
    '与其余页 .page-header 结构/字体一致（display/gap/padding/h1 字号字重行高）',
    ['display', 'gap', 'padding', 'marginBottom', 'fontFamily', 'fontSize', 'fontWeight', 'lineHeight'].every(
      (key) => header.gantt[key] === okrHeader[key],
    ),
    { gantt: header.gantt, okr: okrHeader },
  );

  await page.setViewport(1024, 720);
  await page.goto(`${BASE_URL}/?route=gantt`, { route: 'gantt' });
  await sleep(700);
  const narrow = await page.eval(`
    const de = document.documentElement;
    const vw = de.clientWidth;
    const offenders = [];
    for (const el of document.querySelectorAll('body *')) {
      const style = getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.position === 'fixed') continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      if (r.right <= vw + 1 && r.left >= -1) continue;
      let p = el.parentElement, scrollable = false;
      while (p && p !== document.body) {
        const ps = getComputedStyle(p);
        if (ps.overflowX === 'auto' || ps.overflowX === 'scroll') { scrollable = true; break; }
        p = p.parentElement;
      }
      if (scrollable) continue;
      offenders.push(String(el.className || el.tagName).slice(0, 60));
    }
    return { overflowX: de.scrollWidth - de.clientWidth, offenders: offenders.slice(0, 8), h1: document.querySelector('h1')?.textContent.trim() ?? null };
  `);
  check(flow, '1024×720 无横向溢出/越界元素', narrow.overflowX === 0 && narrow.offenders.length === 0 && narrow.h1 === '甘特', narrow);
  await page.screenshot(`${OUT_DIR}/b-gantt-1024.png`);
  await page.setViewport(1440, 900);
}

/* ------------------------------------------------------------------ c ---- */
async function flowC(page) {
  const flow = 'c-sop-readableViewport';
  const measure = async () => page.eval(`
    const viewport = document.querySelector('.react-flow__viewport');
    const m = new DOMMatrixReadOnly(getComputedStyle(viewport).transform);
    const zoom = m.a;
    const canvas = document.querySelector('.sop-canvas').getBoundingClientRect();
    const nodes = [...document.querySelectorAll('.react-flow__node')];
    const title = document.querySelector('.sop-node-title');
    const titleFont = title ? parseFloat(getComputedStyle(title).fontSize) : null;
    let top = Infinity, bottom = -Infinity, left = Infinity, right = -Infinity;
    for (const node of nodes) {
      const r = node.getBoundingClientRect();
      top = Math.min(top, r.top); bottom = Math.max(bottom, r.bottom);
      left = Math.min(left, r.left); right = Math.max(right, r.right);
    }
    return {
      zoom: Number(zoom.toFixed(3)),
      canvas: { x: canvas.x, y: canvas.y, w: canvas.width, h: canvas.height },
      band: { top, bottom, left, right, h: bottom - top, w: right - left },
      vUtilization: Number(((bottom - top) / canvas.height).toFixed(3)),
      hUtilization: Number(((right - left) / canvas.width).toFixed(3)),
      titleFontPx: titleFont,
      titleRenderedPx: titleFont ? Number((titleFont * zoom).toFixed(2)) : null,
      nodeCount: nodes.length,
    };
  `);

  await page.setViewport(1440, 900);
  await page.reset('sop');
  await sleep(1600);
  const wide = await measure();
  check(flow, '1440×900 初始 zoom ≥ 0.7', wide.zoom >= 0.7, { zoom: wide.zoom });
  check(flow, '节点标题渲染字号 ≥ 9px', (wide.titleRenderedPx ?? 0) >= 9, {
    fontSize: wide.titleFontPx,
    zoom: wide.zoom,
    rendered: wide.titleRenderedPx,
  });
  check(flow, '节点带竖向铺开（视口高度利用率 > 60%）', wide.vUtilization > 0.6, {
    vUtilization: wide.vUtilization,
    bandHeight: Math.round(wide.band.h),
    canvasHeight: Math.round(wide.canvas.h),
    hUtilization: wide.hUtilization,
  });
  await page.screenshot(`${OUT_DIR}/c-sop-1440.png`);

  await page.setViewport(1024, 720);
  await page.goto(`${BASE_URL}/?route=sop`, { route: 'sop' });
  await sleep(1800);
  const narrow = await measure();
  check(flow, '1024×720 初始 zoom ≥ 0.7', narrow.zoom >= 0.7, { zoom: narrow.zoom });
  await page.screenshot(`${OUT_DIR}/c-sop-1024.png`);

  // 「适应画布」仍要能一次看全（允许低于可读下限）
  await page.setViewport(1440, 900);
  await page.goto(`${BASE_URL}/?route=sop`, { route: 'sop' });
  await sleep(1500);
  const fitLabel = await page.eval(`
    const button = [...document.querySelectorAll('button[aria-label]')].find((el) => el.getAttribute('aria-label').startsWith('适应画布'));
    if (!button) return null;
    button.click();
    return button.getAttribute('aria-label');
  `);
  await sleep(900);
  const afterFit = await measure();
  const allInside =
    afterFit.band.top >= afterFit.canvas.y - 2 &&
    afterFit.band.bottom <= afterFit.canvas.y + afterFit.canvas.h + 2 &&
    afterFit.band.left >= afterFit.canvas.x - 2 &&
    afterFit.band.right <= afterFit.canvas.x + afterFit.canvas.w + 2;
  check(flow, '「适应画布」一次看全所有节点', Boolean(fitLabel) && allInside, {
    fitLabel,
    zoomAfterFit: afterFit.zoom,
    renderedAfterFit: afterFit.titleRenderedPx,
    band: afterFit.band,
    canvas: afterFit.canvas,
  });
  await page.screenshot(`${OUT_DIR}/c-sop-fit.png`);
}

/* ------------------------------------------------------------------ d ---- */
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

async function flowD(page) {
  const flow = 'd-settings-import';
  rmSync(DOWNLOAD_DIR, { recursive: true, force: true });
  mkdirSync(DOWNLOAD_DIR, { recursive: true });
  try {
    await page.cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: DOWNLOAD_DIR, eventsEnabled: true });
  } catch {
    await page.cdp.send('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: DOWNLOAD_DIR });
  }

  await page.setViewport(1440, 900);
  await page.reset('settings');
  await clickText(page, '导出 JSON');
  let files = [];
  for (let attempt = 0; attempt < 40; attempt += 1) {
    files = readdirSync(DOWNLOAD_DIR).filter((name) => name.endsWith('.json'));
    if (files.length) break;
    await sleep(250);
  }
  const exportPath = files.length ? `${DOWNLOAD_DIR}/${files[0]}` : null;
  const exported = exportPath ? JSON.parse(readFileSync(exportPath, 'utf8')) : null;
  check(flow, '导出得到 JSON', Boolean(exported && exported.items?.length === 30), { exportPath, items: exported?.items?.length ?? null });

  // 改数据：收集一条新条目 → 31 条
  await navTo(page, '今日');
  await capture(page, '导入撤销核对 /明天');
  const modified = await readWorkspace(page);
  check(flow, '修改后工作区为 31 条', modified.items.length === 31, { items: modified.items.length });

  // 导入（整份替换回 30 条）
  await navTo(page, '设置');
  await clickText(page, '导入 JSON…');
  await setFileInput(page, exportPath);
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'import confirm dialog' });
  const summary = await page.eval(`return [...document.querySelectorAll('[role="dialog"] .settings-import-stats dd')].map((el) => el.textContent.trim());`);
  check(flow, '导入前展示摘要（条目/区域/边/运行/版本）', summary.length === 5, { summary });
  await clickText(page, '覆盖并导入');
  await sleep(800);
  const imported = await readWorkspace(page);
  check(flow, '导入后整份替换为 30 条且新条目消失', imported.items.length === 30 && !imported.items.some((item) => item.title === '导入撤销核对'), {
    items: imported.items.length,
  });
  await waitSaved(page);
  const saveAfterImport = await page.text('.storage-status');
  check(flow, '导入后立即保存（侧栏「已保存」）', saveAfterImport === '已保存', { saveAfterImport });

  // Ctrl+Z 回退整次导入
  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(900);
  const undone = await readWorkspace(page);
  check(
    flow,
    'Ctrl+Z 回退整次导入（恢复 31 条与新条目）',
    undone.items.length === 31 && undone.items.some((item) => item.title === '导入撤销核对'),
    { items: undone.items.length, restored: undone.items.some((item) => item.title === '导入撤销核对') },
  );

  // 重置为演示数据 → Ctrl+Z 回退
  await clickText(page, '重置为演示数据');
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'reset dialog' });
  await clickText(page, '覆盖并重置');
  await sleep(900);
  const reset = await readWorkspace(page);
  check(flow, '重置为演示数据（30 条、收件箱 6）', reset.items.length === 30 && reset.items.filter((item) => item.status === 'inbox').length === 6, {
    items: reset.items.length,
    inbox: reset.items.filter((item) => item.status === 'inbox').length,
  });

  await page.eval(`document.activeElement?.blur(); return true;`);
  await page.pressKey('z', { modifiers: 2, code: 'KeyZ', vk: 90 });
  await sleep(900);
  const resetUndone = await readWorkspace(page);
  check(flow, 'Ctrl+Z 回退整次重置（回到 31 条）', resetUndone.items.length === 31, { items: resetUndone.items.length });

  // 非法导入 {"foo":1}
  const beforeInvalid = await readWorkspace(page);
  const invalidPath = '/tmp/textura-invalid-workspace.json';
  writeFileSync(invalidPath, JSON.stringify({ foo: 1 }), 'utf8');
  await clickText(page, '导入 JSON…');
  await setFileInput(page, invalidPath);
  await sleep(700);
  const invalid = await page.eval(`
    return {
      notices: [...document.querySelectorAll('.notice')].map((el) => el.textContent.trim()),
      modal: Boolean(document.querySelector('[role="dialog"]')),
    };
  `);
  const invalidWs = await readWorkspace(page);
  check(
    flow,
    '非法 JSON 有可读错误且数据不变',
    invalid.notices.some((text) => text.includes('导入失败') && text.includes('不是 Textura 工作区')) &&
      invalidWs.items.length === beforeInvalid.items.length &&
      invalid.modal === false,
    { notices: invalid.notices, before: beforeInvalid.items.length, after: invalidWs.items.length },
  );
  await page.screenshot(`${OUT_DIR}/d-settings-invalid-import.png`);

  // 保存态 + 刷新保持
  await waitSaved(page);
  await page.reload({ route: 'settings' });
  await sleep(900);
  const afterReload = await readWorkspace(page);
  check(
    flow,
    '刷新后数据保持（31 条且含新条目）',
    afterReload.items.length === 31 && afterReload.items.some((item) => item.title === '导入撤销核对'),
    { items: afterReload.items.length },
  );
  await page.screenshot(`${OUT_DIR}/d-settings-after-reload.png`);
}

/* ------------------------------------------------------------------ e ---- */
const CONTRAST_HELPERS = `
  const parse = (value) => {
    const m = value.match(/rgba?\\(([^)]+)\\)/);
    if (!m) return { r: 0, g: 0, b: 0, a: 0 };
    const parts = m[1].split(/[,\\s\\/]+/).filter(Boolean).map(Number);
    return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
  };
  const over = (fg, bg) => ({
    r: fg.r * fg.a + bg.r * (1 - fg.a),
    g: fg.g * fg.a + bg.g * (1 - fg.a),
    b: fg.b * fg.a + bg.b * (1 - fg.a),
    a: 1,
  });
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
    const channel = (v) => {
      const s = v / 255;
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  };
  const ratio = (a, b) => {
    const la = lum(a), lb = lum(b);
    return Number(((Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)).toFixed(2));
  };
  const measure = (el) => {
    const style = getComputedStyle(el);
    const fg = parse(style.color);
    const bg = effectiveBg(el);
    const text = over(fg, bg);
    return {
      text: el.textContent.trim().slice(0, 24),
      color: style.color,
      bg: 'rgb(' + Math.round(bg.r) + ', ' + Math.round(bg.g) + ', ' + Math.round(bg.b) + ')',
      ratio: ratio(text, bg),
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
    };
  };
`;

async function flowE(page) {
  const flow = 'e-dark-contrast';
  await page.setViewport(1440, 900);
  await page.reset('okr');
  await page.eval(`
    const button = document.querySelector('button[aria-label="切换到深色主题"]');
    if (!button) throw new Error('theme toggle missing');
    button.click();
    return true;
  `);
  await sleep(600);
  const theme = await page.eval(`return { theme: document.documentElement.dataset.theme, stored: localStorage.getItem('textura.theme') };`);
  check(flow, '已切到深色主题', theme.theme === 'dark' && theme.stored === 'dark', theme);

  // 让「落后」徽标必然出现：把 NPS 当前值压回起点 42（进度 0%，必然落后于季度时间进度）
  await page.typeInto('input[aria-label="NPS 从 42 提升到 60 指标当前值"]', '42');
  await sleep(700);

  const okr = await page.eval(`
    ${CONTRAST_HELPERS}
    const badges = [...document.querySelectorAll('.okr-kr .badge')];
    const behind = badges.find((el) => el.textContent.trim() === '落后');
    if (!behind) return { found: false, all: badges.map((el) => el.textContent.trim()) };
    const pct = document.querySelector('.okr-kr-pct');
    return {
      found: true,
      badge: measure(behind),
      badgeClass: String(behind.className),
      pct: pct ? measure(pct) : null,
      all: badges.map((el) => el.textContent.trim()),
    };
  `);
  check(flow, 'OKR「落后」徽标对比度 ≥ 4.5', Boolean(okr.found && okr.badge.ratio >= 4.5), okr);

  await navTo(page, '甘特');
  await sleep(700);
  const gantt = await page.eval(`
    ${CONTRAST_HELPERS}
    const bars = [...document.querySelectorAll('.gantt-bar[aria-label]')];
    const results = bars.slice(0, 6).map((bar) => {
      const label = bar.querySelector('.gantt-bar-label');
      if (!label) return null;
      const m = measure(label);
      return { ...m, status: bar.className };
    }).filter(Boolean);
    const treeTitle = document.querySelector('.gantt-item-title');
    return { bars: results, minRatio: results.length ? Math.min(...results.map((r) => r.ratio)) : null, treeTitle: treeTitle ? measure(treeTitle) : null };
  `);
  check(flow, '甘特任务条标签对比度全部 ≥ 4.5', Boolean(gantt && gantt.bars.length >= 4 && gantt.minRatio >= 4.5), gantt);

  await navTo(page, 'SOP');
  await sleep(1500);
  const sop = await page.eval(`
    ${CONTRAST_HELPERS}
    const titles = [...document.querySelectorAll('.sop-node-title')].map((el) => measure(el));
    const metaSpans = [...document.querySelectorAll('.sop-node-meta span')]
      .filter((el) => el.getAttribute('aria-hidden') !== 'true' && el.textContent.trim() !== '·');
    const metas = metaSpans.slice(0, 12).map((el) => measure(el));
    const separators = [...document.querySelectorAll('.sop-node-sep')].slice(0, 2).map((el) => ({
      ...measure(el),
      ariaHidden: el.getAttribute('aria-hidden'),
    }));
    return {
      titles,
      metas,
      separators,
      minTitle: titles.length ? Math.min(...titles.map((t) => t.ratio)) : null,
      minMeta: metas.length ? Math.min(...metas.map((t) => t.ratio)) : null,
    };
  `);
  check(flow, 'SOP 节点标题对比度全部 ≥ 4.5', Boolean(sop && sop.titles.length >= 5 && sop.minTitle >= 4.5), { minTitle: sop?.minTitle, sample: sop?.titles?.slice(0, 3) });
  check(flow, 'SOP 节点次要信息对比度 ≥ 4.5（排除 aria-hidden 装饰分隔符）', sop.minMeta >= 4.5, {
    minMeta: sop?.minMeta,
    sample: sop?.metas?.slice(0, 4),
    decorativeSeparators: sop?.separators,
  }, 'audit');

  await navTo(page, 'GTD');
  await sleep(600);
  const gtd = await page.eval(`
    ${CONTRAST_HELPERS}
    const badges = [...document.querySelectorAll('.gtd-row .badge')].slice(0, 12).map((el) => measure(el));
    const toneGroups = {};
    for (const el of [...document.querySelectorAll('.gtd-row .badge')]) {
      const tone = el.getAttribute('data-tone') || el.className;
      if (toneGroups[tone]) continue;
      toneGroups[tone] = measure(el);
    }
    return { badges, groups: toneGroups, minRatio: badges.length ? Math.min(...badges.map((b) => b.ratio)) : null };
  `);
  check(flow, 'GTD 徽标对比度全部 ≥ 4.5', Boolean(gtd && gtd.badges.length >= 3 && gtd.minRatio >= 4.5), gtd);

  // 附：主按钮（--accent 背景 + 白字）在深色下的对比度，属于 token 级审计项
  const primary = await page.eval(`
    ${CONTRAST_HELPERS}
    const button = document.querySelector('.topbar .btn--primary');
    if (!button) return null;
    const label = button.querySelector('.btn-label') || button;
    const style = getComputedStyle(button);
    return { ...measure(label), buttonBg: style.backgroundColor, buttonColor: style.color };
  `);
  check(flow, '主按钮标签对比度 ≥ 4.5（--accent 背景）', Boolean(primary && primary.ratio >= 4.5), primary, 'audit');

  await page.screenshot(`${OUT_DIR}/e-dark-gtd.png`);
  await page.eval(`const b=document.querySelector('button[aria-label="切换到浅色主题"]'); if(b) b.click(); return true;`);
}

/* ------------------------------------------------------------------ run -- */
async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  await withPage(async (page) => {
    await flowA(page);
    await flowB(page);
    await flowC(page);
    await flowD(page);
    await flowE(page);
  });

  writeFileSync(`${OUT_DIR}/regression-report.json`, JSON.stringify(results, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== REGRESSION SUMMARY ===');
  for (const flow of flows) {
    const entries = results.filter((entry) => entry.flow === flow);
    const failed = entries.filter((entry) => !entry.ok && entry.kind !== 'audit');
    console.log(`${failed.length ? 'FAIL' : 'PASS'}  ${flow}  (${entries.length - failed.length}/${entries.length})`);
    for (const entry of failed) console.log(`      - ${entry.label}`);
  }
  const audits = results.filter((entry) => entry.kind === 'audit' && !entry.ok);
  console.log(`\n断言失败: ${failures}　审计发现（低于 AA，非回归）: ${auditFindings}`);
  for (const entry of audits) console.log(`  AUDIT  ${entry.label}`);
  if (failures) process.exitCode = 1;
}

main().catch((error) => {
  console.error('REGRESSION FAILED:', error);
  process.exit(1);
});
