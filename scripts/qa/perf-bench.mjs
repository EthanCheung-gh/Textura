/**
 * 性能专项基准：生产构建（python3 -m http.server 服务 dist）+ 10,000 条数据。
 *
 * 前置：npm run build；node scripts/qa/perf/generate-workspace.mjs；
 *      (cd dist && python3 -m http.server 4180 --bind 127.0.0.1)
 *
 * 覆盖：首屏 / 路由切换 / 编辑与撤销延迟 / 内存 / DOM 规模 / 保存 longtask。
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

const report = { generatedAt: new Date().toISOString(), baseUrl: PERF_BASE, workspace: { path: WORKSPACE_PATH } };

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const round = (value, digits = 1) => (value === null || value === undefined ? null : Number(value.toFixed(digits)));

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

async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const json = readFileSync(WORKSPACE_PATH, 'utf8');
  report.workspace.bytes = Buffer.byteLength(json);

  const chrome = await launchChrome({
    port: 9333,
    width: 1440,
    height: 900,
    extraArgs: ['--enable-precise-memory-info', '--js-flags=--expose-gc'],
  });
  const cdp = await Cdp.connect(chrome.wsUrl);
  const page = await Page.create(cdp);
  try {
    await page.setViewport(1440, 900);

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
    for (let index = 0; index < 3; index += 1) {
      const value = String(60 + index);
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
    await page.eval(`if (window.__gc) { window.__gc(); } return true;`);
    const memoryBefore = await page.eval(`return performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null;`);
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
    await page.eval(`if (window.__gc) { window.__gc(); } return true;`);
    const memoryAfter = await page.eval(`return performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null;`);
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
    await page.eval(`if (window.__gc) { window.__gc(); } return true;`);
    const memoryAfter2 = await page.eval(`return performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null;`);
    report.memory = {
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
  } finally {
    cdp.close();
    await chrome.close();
  }

  writeFileSync(`${OUT_DIR}/perf-report.json`, JSON.stringify(report, null, 2));

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
