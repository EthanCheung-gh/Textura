/**
 * Route smoke: screenshots at 1440x900 (+ 1024x720 for dashboard/gantt),
 * console error collection, horizontal overflow and layout metrics.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const ROUTES = ['dashboard', 'calendar', 'okr', 'gtd', 'gantt', 'sop', 'settings'];
const SHOT_DIR = 'docs/screenshots';

const LAYOUT_PROBE = `
  const de = document.documentElement;
  const vw = de.clientWidth;
  const vh = de.clientHeight;

  const isScrollableContainer = (el) => {
    let p = el.parentElement;
    while (p && p !== document.body) {
      const ps = getComputedStyle(p);
      if (ps.overflowX === 'auto' || ps.overflowX === 'scroll') return true;
      p = p.parentElement;
    }
    return false;
  };

  const offenders = [];
  for (const el of document.querySelectorAll('body *')) {
    const style = getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || style.position === 'fixed') continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    if (r.right <= vw + 1 && r.left >= -1) continue;
    if (isScrollableContainer(el)) continue;
    offenders.push({
      tag: el.tagName.toLowerCase(),
      cls: String(el.className || '').slice(0, 70),
      left: Math.round(r.left),
      right: Math.round(r.right),
      width: Math.round(r.width),
    });
  }

  const clipped = [];
  for (const el of document.querySelectorAll('h1,h2,h3,p,span,button,label,li')) {
    const style = getComputedStyle(el);
    if (style.overflowY !== 'hidden' && style.overflow !== 'hidden') continue;
    if (el.clientHeight <= 0) continue;
    if (el.scrollHeight > el.clientHeight + 3 && el.textContent.trim().length > 0) {
      clipped.push({
        tag: el.tagName.toLowerCase(),
        cls: String(el.className || '').slice(0, 70),
        text: el.textContent.trim().slice(0, 50),
        scrollHeight: el.scrollHeight,
        clientHeight: el.clientHeight,
      });
    }
  }

  let ellipsis = 0;
  for (const el of document.querySelectorAll('body *')) {
    const style = getComputedStyle(el);
    if (style.textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1) ellipsis += 1;
  }

  const main = document.querySelector('.shell-content') || document.querySelector('main');
  const mainText = main ? main.innerText.trim() : '';
  const header = document.querySelector('.page-header');
  const h1 = document.querySelector('.shell-content h1, main h1');
  const headerStyle = header ? getComputedStyle(header) : null;
  const h1Style = h1 ? getComputedStyle(h1) : null;
  const bodyStyle = getComputedStyle(document.body);

  return {
    route: de.dataset.route,
    theme: de.dataset.theme,
    viewport: { width: vw, height: vh },
    docScrollWidth: de.scrollWidth,
    docClientWidth: de.clientWidth,
    docOverflowX: de.scrollWidth - de.clientWidth,
    docOverflowY: de.scrollHeight - de.clientHeight,
    bodyOverflowX: document.body.scrollWidth - de.clientWidth,
    offenders: offenders.slice(0, 12),
    offenderCount: offenders.length,
    clipped: clipped.slice(0, 10),
    clippedCount: clipped.length,
    ellipsisCount: ellipsis,
    mainTextLength: mainText.length,
    mainTextHead: mainText.slice(0, 180),
    header: headerStyle
      ? {
          display: headerStyle.display,
          padding: [headerStyle.paddingTop, headerStyle.paddingRight, headerStyle.paddingBottom, headerStyle.paddingLeft].join(' '),
          gap: headerStyle.gap,
          marginBottom: headerStyle.marginBottom,
          h1FontSize: h1Style ? h1Style.fontSize : null,
          h1FontWeight: h1Style ? h1Style.fontWeight : null,
          bodyFontFamily: bodyStyle.fontFamily.split(',')[0],
        }
      : null,
    counts: {
      h1: document.querySelectorAll('.shell-content h1, main h1').length,
      buttons: document.querySelectorAll('button').length,
      modals: document.querySelectorAll('[role="dialog"]').length,
    },
  };
`;

async function run() {
  mkdirSync(SHOT_DIR, { recursive: true });
  const summary = { routes: [], narrow: [], extras: [], consoleIssues: [], chrome: null };

  await withPage(async (page, chrome) => {
    summary.chrome = chrome.browserVersion;

    for (const route of ROUTES) {
      await page.setViewport(1440, 900);
      await page.goto(`${BASE_URL}/?route=${route}`, { route });
      await sleep(900); // let charts/fonts/save-debounce settle
      const shot = await page.screenshot(`${SHOT_DIR}/${route}.png`);
      const layout = await page.eval(LAYOUT_PROBE);
      const issues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
      summary.routes.push({ route, shot, layout, issues });
      if (issues.length) summary.consoleIssues.push({ route, issues });
      console.log(`[smoke] ${route} captured -> ${shot} (errors: ${issues.length})`);
    }

    for (const route of ['dashboard', 'gantt']) {
      await page.setViewport(1024, 720);
      await page.goto(`${BASE_URL}/?route=${route}`, { route });
      await sleep(900);
      const shot = await page.screenshot(`${SHOT_DIR}/${route}-1024.png`);
      const layout = await page.eval(LAYOUT_PROBE);
      const issues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
      summary.narrow.push({ route, shot, layout, issues });
      if (issues.length) summary.consoleIssues.push({ route: `${route}@1024`, issues });
      console.log(`[smoke] ${route}@1024 captured -> ${shot} (errors: ${issues.length})`);
    }

    /* ---- extras used by README / 用户手册 ---- */
    await page.setViewport(1440, 900);

    // 深色主题（真实点击切换，且在 dashboard 上取图）
    await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
    await sleep(700);
    await page.eval(`
      const button = document.querySelector('button[aria-label="切换到深色主题"]');
      if (!button) throw new Error('theme toggle missing');
      button.click();
      return true;
    `);
    await sleep(700);
    const darkShot = await page.screenshot(`${SHOT_DIR}/dashboard-dark.png`);
    const darkLayout = await page.eval(LAYOUT_PROBE);
    const darkIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
    summary.extras.push({ name: 'dashboard-dark', shot: darkShot, layout: darkLayout, issues: darkIssues });
    console.log(`[smoke] dashboard-dark captured -> ${darkShot} (errors: ${darkIssues.length})`);
    await page.eval(`const b=document.querySelector('button[aria-label="切换到浅色主题"]'); if(b) b.click(); return true;`);

    // SOP 运行模式
    await page.goto(`${BASE_URL}/?route=sop`, { route: 'sop' });
    await sleep(1400);
    const runStarted = await page.eval(`
      const button = [...document.querySelectorAll('button')].find((el) => el.textContent.trim() === '运行');
      if (!button) return false;
      button.click();
      return true;
    `);
    if (!runStarted) throw new Error('SOP 运行按钮缺失');
    await page.waitFor(`!!document.querySelector('.sop-runbar')`, { label: 'SOP run bar' });
    await sleep(900);
    const step = await page.text('.sop-runbar-progress');
    const runShot = await page.screenshot(`${SHOT_DIR}/sop-run.png`);
    const runIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
    summary.extras.push({ name: 'sop-run', shot: runShot, detail: { step }, issues: runIssues });
    console.log(`[smoke] sop-run captured -> ${runShot} (step=${step}, errors: ${runIssues.length})`);

    // 甘特依赖线：选中「前端搭建」（同时是两条 depends 边的 from / to）让连线高亮并显示标签
    await page.goto(`${BASE_URL}/?route=gantt`, { route: 'gantt' });
    await sleep(1100);
    const barIndex = await page.eval(`
      const bars = [...document.querySelectorAll('.gantt-bar[aria-label]')];
      return bars.findIndex((el) => el.getAttribute('aria-label').startsWith('前端搭建'));
    `);
    if (barIndex < 0) throw new Error('找不到「前端搭建」任务条');
    await page.click('.gantt-bar[aria-label]', barIndex);
    await sleep(700);
    const deps = await page.eval(`
      const paths = [...document.querySelectorAll('.gantt-deps .gantt-dep-path')];
      const svg = document.querySelector('.gantt-deps');
      return {
        pathCount: paths.length,
        hotCount: document.querySelectorAll('.gantt-dep-path.is-hot').length,
        hotLabels: [...document.querySelectorAll('.gantt-deps text')].map((el) => el.textContent.trim()).filter(Boolean),
        svgVisible: svg ? getComputedStyle(svg).display !== 'none' : false,
        selected: [...document.querySelectorAll('.gantt-bar.is-selected')].map((el) => el.getAttribute('aria-label')),
      };
    `);
    const depsShot = await page.screenshot(`${SHOT_DIR}/gantt-deps.png`);
    const depsIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
    summary.extras.push({ name: 'gantt-deps', shot: depsShot, detail: deps, issues: depsIssues });
    console.log(
      `[smoke] gantt-deps captured -> ${depsShot} (paths=${deps.pathCount}, hot=${deps.hotCount}, errors: ${depsIssues.length})`,
    );
    if (deps.pathCount < 2 || deps.hotCount < 2) {
      throw new Error(`依赖线高亮异常: paths=${deps.pathCount} hot=${deps.hotCount}`);
    }

    // 日历 · 周视图
    await page.goto(`${BASE_URL}/?route=calendar`, { route: 'calendar' });
    await sleep(900);
    await page.eval(`
      const option = [...document.querySelectorAll('.cal-toolbar button')].find((el) => el.textContent.trim() === '周');
      if (!option) throw new Error('日历周视图按钮缺失');
      option.click();
      return true;
    `);
    await sleep(900);
    const weekShot = await page.screenshot(`${SHOT_DIR}/calendar-week.png`);
    const weekDetail = await page.eval(`
      const cols = [...document.querySelectorAll('.cal-week-col')];
      return {
        cols: cols.length,
        cards: document.querySelectorAll('.cal-week-card').length,
        spans: [...document.querySelectorAll('.cal-week-card-span')].slice(0, 4).map((el) => el.textContent.trim()),
        overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      };
    `);
    const weekIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
    summary.extras.push({ name: 'calendar-week', shot: weekShot, detail: weekDetail, issues: weekIssues });
    console.log(`[smoke] calendar-week captured -> ${weekShot} (cols=${weekDetail.cols}, errors: ${weekIssues.length})`);
    if (weekDetail.cols !== 7) throw new Error(`周视图列数异常: ${weekDetail.cols}`);

    // 日历 · 深色月视图
    await page.eval(`
      const option = [...document.querySelectorAll('.cal-toolbar button')].find((el) => el.textContent.trim() === '月');
      if (!option) throw new Error('日历月视图按钮缺失');
      option.click();
      return true;
    `);
    await sleep(700);
    await page.eval(`
      const button = document.querySelector('button[aria-label="切换到深色主题"]');
      if (!button) throw new Error('theme toggle missing');
      button.click();
      return true;
    `);
    await sleep(800);
    const calDarkShot = await page.screenshot(`${SHOT_DIR}/calendar-dark.png`);
    const calDarkLayout = await page.eval(LAYOUT_PROBE);
    const calDarkIssues = page.issues.filter((issue) => issue.level === 'error' || issue.level === 'warning');
    summary.extras.push({ name: 'calendar-dark', shot: calDarkShot, layout: calDarkLayout, issues: calDarkIssues });
    console.log(`[smoke] calendar-dark captured -> ${calDarkShot} (errors: ${calDarkIssues.length})`);
    await page.eval(`const b=document.querySelector('button[aria-label="切换到浅色主题"]'); if(b) b.click(); return true;`);
  });

  writeFileSync('docs/screenshots/smoke-report.json', JSON.stringify(summary, null, 2));

  console.log('\n=== SMOKE SUMMARY ===');
  console.log(`Chrome: ${summary.chrome}`);
  for (const entry of [...summary.routes, ...summary.narrow, ...summary.extras]) {
    const { route, name, shot, layout, issues } = entry;
    const label = route ?? name;
    console.log(
      [
        label.padEnd(14),
        `shot=${shot}`,
        `errors=${issues.length}`,
        layout ? `overflowX=${layout.docOverflowX}` : '',
        layout ? `offenders=${layout.offenderCount}` : '',
        layout ? `clipped=${layout.clippedCount}` : '',
        layout ? `mainText=${layout.mainTextLength}` : '',
      ]
        .filter(Boolean)
        .join('  '),
    );
    for (const issue of issues) {
      console.log(`    [${issue.level}] ${issue.source}: ${issue.text.slice(0, 300)}`);
    }
    for (const offender of layout?.offenders ?? []) {
      console.log(`    overflow: <${offender.tag} class="${offender.cls}"> left=${offender.left} right=${offender.right}`);
    }
    for (const clip of layout?.clipped ?? []) {
      console.log(`    clipped: <${clip.tag} class="${clip.cls}"> "${clip.text}" ${clip.scrollHeight}>${clip.clientHeight}`);
    }
  }
  console.log('\nreport written to docs/screenshots/smoke-report.json');
}

run().catch((error) => {
  console.error('SMOKE FAILED:', error);
  process.exit(1);
});
