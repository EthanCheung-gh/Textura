/**
 * 性能专项基准：生产构建（python3 -m http.server 服务 dist）+ 10,000 条数据。
 *
 * 前置：npm run build；node scripts/qa/perf/generate-workspace.mjs；
 *      (cd dist && python3 -m http.server 4180 --bind 127.0.0.1)
 *
 * 覆盖：首屏 / 路由切换 / 编辑与撤销延迟 / 内存 / DOM 规模 / 保存 longtask。
 * 内存口径：读数前做多轮 GC（默认 3 次，`PERF_GC_PASSES` 可覆盖），避免单次 GC
 * 收不干净导致基线被抬高、delta 失真。
 * 结果写入 /tmp/textura-perf/perf-report.json，并输出两张证据截图到 docs/screenshots/。
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { BASE_URL, Cdp, Page, launchChrome, sleep } from './lib.mjs';

const PERF_BASE = process.env.PERF_BASE_URL || 'http://127.0.0.1:4180';
const WORKSPACE_PATH = process.env.PERF_WORKSPACE || '/tmp/textura-perf/workspace-10k.json';
const OUT_DIR = '/tmp/textura-perf';
const SHOT_DIR = 'docs/screenshots';
const KEY = 'textura.workspace.v1';
// 内存读数前的 GC 轮数：单次 GC 往往收不干净（增量标记 / 弱引用清理需要多轮），
// 会让基线偏高、delta 偏低。可用 PERF_GC_PASSES 覆盖，口径记录在 report.memory.gcPasses。
const GC_PASSES = (() => {
  const raw = Number.parseInt(process.env.PERF_GC_PASSES ?? '', 10);
  return Number.isFinite(raw) && raw > 0 ? raw : 3;
})();

const report = { generatedAt: new Date().toISOString(), baseUrl: PERF_BASE, workspace: { path: WORKSPACE_PATH } };

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const round = (value, digits = 1) => (value === null || value === undefined ? null : Number(value.toFixed(digits)));

/**
 * 稳定的内存读数：先循环 `passes` 轮 `window.__gc()`（每轮之间 sleep 150ms 让堆落定），
 * 最后一次性读 `performance.memory` 的 `{ used, total }`。
 * 轮数记录在 `report.memory.gcPasses`，便于跨版本对比时追溯口径。
 */
async function stableMemory(page, passes = GC_PASSES) {
  const rounds = Math.max(1, passes);
  for (let pass = 0; pass < rounds; pass += 1) {
    await page.eval(`if (window.__gc) { window.__gc(); } return true;`);
    await sleep(150);
  }
  return page.eval(
    `return performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null;`,
  );
}

async function timeRouteSwitch(page, label, root) {
  return page.eval(`
    const t0 = performance.now();
    const link = [...document.querySelectorAll('.sidebar-nav .sidebar-link')]
      .find((el) => el.textContent.trim().startsWith(${JSON.stringify(label)}));
    if (!link) throw new Error('sidebar link missing: ' + ${JSON.stringify(label)});
    link.click();
    await new Promise((resolve) => {
      if (document.querySelector(${JSON.stringify(root)})) return resolve();
      const obs = new MutationObserver(() => {
        if (document.querySelector(${JSON.stringify(root)})) { obs.disconnect(); resolve(); }
      });
      obs.observe(document.body, { childList: true, subtree: true });
    });
    return performance.now() - t0;
  `);
}

/**
 * 走到「KR 指标输入框已挂载」的状态（导航耗时不计入 edit / undo 计时区间）。
 *
 * 列表卡片自 c80b107 起只读（`okr-kr--readonly`）、011c518 引入编辑视图的
 * 「单编辑态」，`MetricEditor` 只在「目标编辑视图 → 某条 KR 的铅笔」之后才挂载，
 * 因此按真实用户路径走：
 *   目标卡「编辑」（aria-label 以「编辑目标：」开头，见 ObjectiveCard.tsx:176）
 *   → 目标编辑视图（role="region" aria-label="目标编辑"，ObjectiveEditor.tsx:91）
 *   → 第一条 KR 的铅笔（aria-label 以「编辑关键结果：」开头，KrRow.tsx:252）
 *   → 指标输入框（KrRow.tsx:337 → MetricEditor.tsx:249）。
 *
 * 已经在该状态时直接返回：第 2/3 次样本复用同一个单编辑态，不重复导航。
 */
async function ensureOkrMetricEditor(page) {
  const mounted = await page.eval(`return !!document.querySelector('input[aria-label$="指标当前值"]');`);
  if (mounted) return false;

  const entry = await page.eval(`
    if (document.querySelector('button[aria-label^="编辑目标："]')) return 'button[aria-label^="编辑目标："]';
    if (document.querySelector('[data-edit-objective]')) return '[data-edit-objective]';
    return null;
  `);
  if (!entry) throw new Error('okr objective edit entry not found: button[aria-label^="编辑目标："]');
  await page.click(entry);
  await page.waitFor(`!!document.querySelector('section[role="region"][aria-label="目标编辑"]')`, {
    label: 'okr objective editor view',
    timeout: 30000,
  });
  await page.waitFor(`!!document.querySelector('button[aria-label^="编辑关键结果："]')`, {
    label: 'okr editor kr rows',
    timeout: 30000,
  });
  await page.click('button[aria-label^="编辑关键结果："]');
  await page.waitFor(`!!document.querySelector('input[aria-label$="指标当前值"]')`, {
    label: 'okr metric input (kr single-edit state)',
    timeout: 30000,
  });
  await sleep(300);
  return true;
}

async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const json = readFileSync(WORKSPACE_PATH, 'utf8');
  report.workspace.bytes = Buffer.byteLength(json);

  const chrome = await launchChrome({
    port: 9333,
    width: 1920,
    height: 1280,
    extraArgs: ['--enable-precise-memory-info', '--js-flags=--expose-gc'],
  });
  const cdp = await Cdp.connect(chrome.wsUrl);
  const page = await Page.create(cdp);
  try {
    await page.setViewport(1920, 1280);

    console.log('[perf] step: demo load');
    /* ---------------- 首屏（演示数据冷启动） ---------------- */
    await page.goto(`${PERF_BASE}/?route=dashboard`, { route: 'dashboard' });
    await sleep(600);
    const demoPaint = await page.eval(`
      const paint = performance.getEntriesByType('paint');
      const fcp = paint.find((entry) => entry.name === 'first-contentful-paint');
      return { fcp: fcp ? fcp.startTime : null };
    `);
    report.firstPaintDemo = demoPaint;

    console.log('[perf] step: inject 10k');
    /* ---------------- 注入 10k + 重新加载 ---------------- */
    await page.eval(`
      localStorage.setItem(${JSON.stringify(KEY)}, ${JSON.stringify(json)});
      return true;
    `, { timeout: 120000 });
    console.log('[perf] step: reload with 10k (cold cache)');
    await page.cdp.send('Network.enable');
    await page.cdp.send('Network.clearBrowserCache');
    await page.cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    page.resetIssues();
    const navStart = Date.now();
    await page.cdp.send('Page.reload', { ignoreCache: true });
    await page.waitFor(`document.readyState === 'complete'`, { label: '10k reload ready' });
    await page.waitFor(`!!document.querySelector('.shell')`, { label: '10k shell' });
    await page.waitRouteRoot('dashboard', 60000);
    await sleep(800);
    report.reloadWallMs = Date.now() - navStart;

    console.log('[perf] step: first screen metrics');
    report.firstScreen = await page.eval(`
      const paint = performance.getEntriesByType('paint');
      const fcp = paint.find((entry) => entry.name === 'first-contentful-paint');
      const fp = paint.find((entry) => entry.name === 'first-paint');
      const nav = performance.getEntriesByType('navigation')[0];
      // 首屏 JS = 入口 + modulepreload 的 vendor chunk（懒加载视图 chunk 此时尚未请求）
      const scripts = performance.getEntriesByType('resource').filter((entry) => entry.name.includes('.js'));
      return {
        fcp: fcp ? fcp.startTime : null,
        firstPaint: fp ? fp.startTime : null,
        domContentLoaded: nav ? nav.domContentLoadedEventEnd : null,
        loadEventEnd: nav ? nav.loadEventEnd : null,
        scriptRequests: scripts.length,
        transferBytes: scripts.reduce((sum, entry) => sum + (entry.transferSize || 0), 0),
        encodedBytes: scripts.reduce((sum, entry) => sum + (entry.encodedBodySize || 0), 0),
        scripts: scripts.map((entry) => ({
          name: entry.name.split('/').pop(),
          initiatorType: entry.initiatorType,
          encodedBodySize: entry.encodedBodySize,
          duration: entry.duration,
        })),
      };
    `);
    await page.cdp.send('Network.setCacheDisabled', { cacheDisabled: false });

    // 首屏 JS 的 gzip 总量（http.server 不压缩，按 dist 文件现算）
    const gzipTable = [];
    for (const script of report.firstScreen.scripts) {
      const candidates = [join('dist/assets', script.name), join('dist', script.name)];
      let gzipBytes = null;
      for (const file of candidates) {
        if (!existsSync(file)) continue;
        gzipBytes = execFileSync('gzip', ['-c', file], { stdio: ['ignore', 'pipe', 'ignore'] }).length;
        break;
      }
      gzipTable.push({ file: script.name, raw: script.encodedBodySize, gzip: gzipBytes });
    }
    report.firstScreen.gzip = {
      raw: gzipTable.reduce((sum, entry) => sum + (entry.raw ?? 0), 0),
      gzip: gzipTable.reduce((sum, entry) => sum + (entry.gzip ?? 0), 0),
      files: gzipTable,
    };

    console.log('[perf] step: longtask observer');
    // 长任务收集器（供保存阶段使用）
    await page.eval(`
      window.__longTasks = [];
      try {
        new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) window.__longTasks.push({ start: entry.startTime, duration: entry.duration });
        }).observe({ type: 'longtask', buffered: true });
      } catch (error) {}
      window.__gc = typeof gc === 'function' ? gc : null;
      return true;
    `);

    /* ---------------- 路由切换（3 轮） ---------------- */
    const routeOrder = [
      ['OKR', '.okr-page'],
      ['GTD', '.gtd-page'],
      ['甘特', '.gantt-page'],
      ['SOP', '.sop-page'],
      ['日历', '.cal-page'],
      ['今日', '.dash-page'],
    ];
    console.log('[perf] step: route switches');
    const routeSamples = Object.fromEntries(routeOrder.map(([label]) => [label, []]));
    for (let roundIndex = 0; roundIndex < 3; roundIndex += 1) {
      for (const [label, root] of routeOrder) {
        const ms = await timeRouteSwitch(page, label, root);
        routeSamples[label].push(round(ms));
        await sleep(250);
      }
    }
    report.routeSwitch = Object.fromEntries(
      Object.entries(routeSamples).map(([label, samples]) => [
        label,
        { samples, warm: samples.slice(1), median: round(median(samples)), medianWarm: round(median(samples.slice(1))) },
      ]),
    );

    /* ---------------- 编辑 / 撤销延迟 ---------------- */
    // 1) GTD 完成一条下一步
    console.log('[perf] step: edits');
    const gtdEdit = [];
    const gtdUndo = [];
    for (let index = 0; index < 3; index += 1) {
      await timeRouteSwitch(page, 'GTD', '.gtd-page');
      await sleep(400);
      const edit = await page.eval(`
        const row = document.querySelector('.gtd-next-row');
        if (!row) throw new Error('no next row');
        const id = row.dataset.rowId;
        const t0 = performance.now();
        row.querySelector('.gtd-check').click();
        await new Promise((resolve) => {
          const done = () => !document.querySelector('.gtd-next-row[data-row-id="' + id + '"]');
          if (done()) return resolve();
          const obs = new MutationObserver(() => { if (done()) { obs.disconnect(); resolve(); } });
          obs.observe(document.body, { childList: true, subtree: true });
        });
        return { ms: performance.now() - t0, id };
      `);
      gtdEdit.push(round(edit.ms));
      await sleep(150);
      // 分页会立刻补位，行数不变；用「被完成的行重新出现」判定撤销生效
      gtdUndo.push(
        round(
          await page.eval(`
            const id = ${JSON.stringify(edit.id)};
            const t0 = performance.now();
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, bubbles: true, cancelable: true }));
            await new Promise((resolve) => {
              const done = () => Boolean(document.querySelector('.gtd-next-row[data-row-id="' + id + '"]'));
              if (done()) return resolve();
              const obs = new MutationObserver(() => { if (done()) { obs.disconnect(); resolve(); } });
              obs.observe(document.body, { childList: true, subtree: true });
            });
            return performance.now() - t0;
          `),
        ),
      );
      await sleep(200);
    }

    // 2) OKR 指标（Enter 立即 flush，排除 600ms 防抖）
    const okrEdit = [];
    const okrUndo = [];
    await timeRouteSwitch(page, 'OKR', '.okr-page');
    await sleep(500);
    // 首次进入编辑态（导航不计时），并打印被测 KR / 指标区间，便于失败时定位。
    await ensureOkrMetricEditor(page);
    console.log(
      '[perf] okr metric target:',
      JSON.stringify(
        await page.eval(`
          const input = document.querySelector('input[aria-label$="指标当前值"]');
          if (!input) return null;
          const row = input.closest('.okr-kr');
          const value = (suffix) => document.querySelector('input[aria-label$="' + suffix + '"]')?.value ?? null;
          return {
            label: input.getAttribute('aria-label'),
            start: value('指标起点'),
            current: value('指标当前值'),
            target: value('指标目标值'),
            pct: row?.querySelector('.okr-kr-pct')?.textContent.trim() ?? null,
          };
        `),
      ),
    );
    for (let index = 0; index < 3; index += 1) {
      const value = String(60 + index);
      // 编辑态已挂载时是 no-op；若被卸载（返回列表 / Esc），这里重新走一遍真实路径。
      await ensureOkrMetricEditor(page);
      await page.click('input[aria-label$="指标当前值"]');
      await page.selectAll();
      await page.insertText(value);
      await sleep(150);
      okrEdit.push(
        round(
          await page.eval(`
            const input = document.querySelector('input[aria-label$="指标当前值"]');
            const row = input.closest('.okr-kr');
            const pct = row.querySelector('.okr-kr-pct');
            const before = pct ? pct.textContent.trim() : '';
            const t0 = performance.now();
            input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
            await new Promise((resolve) => {
              const done = () => (row.querySelector('.okr-kr-pct')?.textContent.trim() ?? '') !== before;
              if (done()) return resolve();
              const obs = new MutationObserver(() => { if (done()) { obs.disconnect(); resolve(); } });
              obs.observe(row, { childList: true, subtree: true, characterData: true });
            });
            return performance.now() - t0;
          `),
        ),
      );
      await sleep(200);
      okrUndo.push(
        round(
          await page.eval(`
            const row = document.querySelector('.okr-kr');
            const before = row.querySelector('.okr-kr-pct')?.textContent.trim() ?? '';
            const t0 = performance.now();
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, bubbles: true, cancelable: true }));
            await new Promise((resolve) => {
              const done = () => (row.querySelector('.okr-kr-pct')?.textContent.trim() ?? '') !== before;
              if (done()) return resolve();
              const obs = new MutationObserver(() => { if (done()) { obs.disconnect(); resolve(); } });
              obs.observe(row, { childList: true, subtree: true, characterData: true });
            });
            return performance.now() - t0;
          `),
        ),
      );
      await sleep(200);
    }

    // 3) 甘特拖拽（pointerup → 双 rAF 提交+绘制）
    const ganttEdit = [];
    const ganttUndo = [];
    await timeRouteSwitch(page, '甘特', '.gantt-page');
    await sleep(700);
    for (let index = 0; index < 3; index += 1) {
      await page.eval(`
        window.__dragPerf = { up: null, frames: null };
        const handler = () => {
          window.__dragPerf.up = performance.now();
          requestAnimationFrame(() => requestAnimationFrame(() => { window.__dragPerf.frames = performance.now(); }));
          window.removeEventListener('pointerup', handler, true);
        };
        window.addEventListener('pointerup', handler, true);
        return true;
      `);
      const barCount = await page.eval(`return document.querySelectorAll('.gantt-bar[aria-label]').length;`);
      if (barCount === 0) throw new Error('no gantt bars');
      const labelBefore = await page.eval(`return document.querySelector('.gantt-bar[aria-label]')?.getAttribute('aria-label') ?? null;`);
      await page.drag('.gantt-bar[aria-label]', 28, 0, { steps: 6, settle: 100 });
      await sleep(250);
      ganttEdit.push(
        round(
          await page.eval(`
            const perf = window.__dragPerf;
            return perf && perf.up && perf.frames ? perf.frames - perf.up : null;
          `),
        ),
      );
      await sleep(150);
      ganttUndo.push(
        round(
          await page.eval(`
            const target = ${JSON.stringify(labelBefore)};
            const t0 = performance.now();
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, bubbles: true, cancelable: true }));
            await new Promise((resolve) => {
              const done = () => document.querySelector('.gantt-bar[aria-label]')?.getAttribute('aria-label') === target;
              if (done()) return resolve();
              const obs = new MutationObserver(() => { if (done()) { obs.disconnect(); resolve(); } });
              obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label', 'style', 'class'] });
            });
            return performance.now() - t0;
          `),
        ),
      );
      await sleep(200);
    }

    report.edits = {
      gtdComplete: { samples: gtdEdit, median: round(median(gtdEdit)) },
      okayMetric: { samples: okrEdit, median: round(median(okrEdit)) },
      ganttDrag: { samples: ganttEdit, median: round(median(ganttEdit)) },
    };
    report.undo = {
      gtdComplete: { samples: gtdUndo, median: round(median(gtdUndo)) },
      okayMetric: { samples: okrUndo, median: round(median(okrUndo)) },
      ganttDrag: { samples: ganttUndo, median: round(median(ganttUndo)) },
    };

    /* ---------------- DOM 规模 ---------------- */
    await timeRouteSwitch(page, '甘特', '.gantt-page');
    await sleep(700);
    console.log('[perf] step: dom');
    report.dom = report.dom ?? {};
    report.dom.gantt = await page.eval(`
      return {
        treeRows: document.querySelectorAll('.gantt-tree-row').length,
        headerCols: document.querySelectorAll('.gantt-header-col').length,
        bars: document.querySelectorAll('.gantt-bar').length,
        totalItemsText: document.querySelector('.gantt-tree-head-count')?.textContent.trim() ?? null,
      };
    `);
    // 等通知浮层（.notices > .notice，见 AppShell.tsx）自己消失再截图：甘特 3 次撤销
    // 各留一条「已撤销上一步」，TTL 3500ms，否则会被拍进证据图右下角。
    // 此处不在任何 performance.now() 计时区间内（保存 / 长任务观测在其后各自重新起算）。
    await page.waitFor(`!document.querySelector('.notices .notice')`, {
      timeout: 6000,
      label: 'notices cleared before gantt shot',
    });
    await page.screenshot(`${SHOT_DIR}/perf-gantt-2k.png`);

    await timeRouteSwitch(page, 'SOP', '.sop-page');
    await sleep(1200);
    report.dom.sop = await page.eval(`
      return {
        nodes: document.querySelectorAll('.react-flow__node').length,
        edges: document.querySelectorAll('.react-flow__edge').length,
      };
    `);

    await timeRouteSwitch(page, 'GTD', '.gtd-page');
    await sleep(700);
    report.dom.gtd = await page.eval(`
      return {
        nextRows: document.querySelectorAll('.gtd-next-row').length,
        inboxRows: document.querySelectorAll('.gtd-inbox-row').length,
        showMore: [...document.querySelectorAll('button')].filter((el) => el.textContent.includes('显示更多')).length,
        totalCounter: document.querySelector('.gtd-filter-count')?.textContent.trim() ?? null,
      };
    `);

    await timeRouteSwitch(page, '今日', '.dash-page');
    await sleep(700);
    report.dom.dashboard = await page.eval(`
      return {
        focusRows: document.querySelectorAll('.dash-focus-row').length,
        statCards: document.querySelectorAll('.dash-stat').length,
        showMore: [...document.querySelectorAll('button')].filter((el) => el.textContent.includes('显示更多')).length,
      };
    `);
    // 同上：截图前等通知浮层清空，避免把 toast 拍进证据图。
    // 保存 / 内存步骤在这之后执行，各自从自己的 t0 重新计时，不受这段等待影响。
    await page.waitFor(`!document.querySelector('.notices .notice')`, {
      timeout: 6000,
      label: 'notices cleared before dashboard shot',
    });
    await page.screenshot(`${SHOT_DIR}/perf-10k-dashboard.png`);

    /* ---------------- 保存 + 长任务 ---------------- */
    await timeRouteSwitch(page, 'GTD', '.gtd-page');
    await sleep(500);
    console.log('[perf] step: save');
    const savePerf = await page.eval(`
      const status = document.querySelector('.storage-status');
      const t0 = performance.now();
      window.__longTasks = [];
      let savingAt = null;
      let doneAt = null;
      const obs = new MutationObserver(() => {
        const text = status.textContent || '';
        if (text.includes('正在保存') && savingAt === null) savingAt = performance.now();
        if (text.includes('已保存') && savingAt !== null && doneAt === null) {
          doneAt = performance.now();
          obs.disconnect();
        }
      });
      obs.observe(status, { childList: true, subtree: true, characterData: true });
      document.querySelector('.gtd-next-row .gtd-check')?.click();
      const deadline = Date.now() + 8000;
      await new Promise((resolve) => {
        const timer = setInterval(() => {
          if (doneAt !== null || Date.now() > deadline) { clearInterval(timer); resolve(); }
        }, 20);
      });
      const tasks = (window.__longTasks || []).filter((entry) => entry.start >= t0);
      return {
        debounceToSaving: savingAt ? savingAt - t0 : null,
        saveDuration: savingAt && doneAt ? doneAt - savingAt : null,
        total: doneAt ? doneAt - t0 : null,
        longTasks: tasks,
        maxLongTask: tasks.length ? Math.max(...tasks.map((entry) => entry.duration)) : 0,
        statusText: status.textContent.trim(),
      };
    `);
    report.save = savePerf;

    console.log('[perf] step: memory');
    /* ---------------- 内存：50 次编辑 ---------------- */
    const memoryBefore = await stableMemory(page);
    const editsDone = await page.eval(`
      let count = 0;
      for (let index = 0; index < 50; index += 1) {
        const button = document.querySelector('.gtd-next-row .gtd-check');
        if (!button) break;
        button.click();
        count += 1;
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      return count;
    `);
    await sleep(600);
    const memoryAfter = await stableMemory(page);
    // 第二轮：再 50 次编辑，观察增量是否累积（GC 噪声下应保持平稳）
    const secondEdits = await page.eval(`
      let count = 0;
      for (let index = 0; index < 50; index += 1) {
        const button = document.querySelector('.gtd-next-row .gtd-check');
        if (!button) break;
        button.click();
        count += 1;
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      return count;
    `);
    await sleep(600);
    const memoryAfter2 = await stableMemory(page);
    report.memory = {
      gcPasses: GC_PASSES,
      edits: editsDone,
      secondEdits,
      before: memoryBefore,
      after: memoryAfter,
      afterSecond: memoryAfter2,
      deltaBytes: memoryBefore && memoryAfter ? memoryAfter.used - memoryBefore.used : null,
      deltaMB: memoryBefore && memoryAfter ? round((memoryAfter.used - memoryBefore.used) / 1048576, 2) : null,
      deltaSecondMB: memoryAfter && memoryAfter2 ? round((memoryAfter2.used - memoryAfter.used) / 1048576, 2) : null,
      totalDeltaMB: memoryBefore && memoryAfter2 ? round((memoryAfter2.used - memoryBefore.used) / 1048576, 2) : null,
    };

    report.consoleIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
  } catch (error) {
    // 失败也留下半份诊断数据：标记 failed / error（成功路径字段结构不变）。
    report.failed = true;
    report.error = {
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? (error.stack ?? null) : null,
    };
    throw error;
  } finally {
    cdp.close();
    await chrome.close();
    // 落盘放在 finally：中途抛错时 perf-report.json 仍然是可用数据。
    writeFileSync(`${OUT_DIR}/perf-report.json`, JSON.stringify(report, null, 2));
  }

  /* ---------------- 打印摘要 ---------------- */
  console.log('\n=== FIRST SCREEN ===');
  console.log(
    JSON.stringify(
      {
        fcp: report.firstScreen.fcp,
        wallReloadMs: report.reloadWallMs,
        scriptRequests: report.firstScreen.scriptRequests,
        firstScreenRaw: report.firstScreen.gzip.raw,
        firstScreenGzip: report.firstScreen.gzip.gzip,
        files: report.firstScreen.gzip.files,
      },
      null,
      1,
    ),
  );
  console.log('\n=== ROUTE SWITCH (ms) ===');
  for (const [label, entry] of Object.entries(report.routeSwitch)) {
    console.log(`${label.padEnd(6)} samples=${JSON.stringify(entry.samples)} median=${entry.median} medianWarm=${entry.medianWarm}`);
  }
  console.log('\n=== EDIT / UNDO (ms) ===');
  for (const key of Object.keys(report.edits)) {
    console.log(`${key.padEnd(14)} edit=${JSON.stringify(report.edits[key].samples)} median=${report.edits[key].median}  undo=${JSON.stringify(report.undo[key].samples)} median=${report.undo[key].median}`);
  }
  console.log('\n=== DOM ===');
  console.log(JSON.stringify(report.dom));
  console.log('\n=== SAVE ===');
  console.log(JSON.stringify(report.save));
  console.log('\n=== MEMORY ===');
  console.log(JSON.stringify(report.memory));
  console.log('\nconsole issues:', report.consoleIssues.length);
}

main().catch((error) => {
  console.error('PERF BENCH FAILED:', error);
  process.exit(1);
});
