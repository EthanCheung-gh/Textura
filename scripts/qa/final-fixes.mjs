/**
 * 第五轮：两处 P2 修复的回归验证。
 *   a. 通知浮层 pointer-events: none —— 连续快速添加不被吞；SOP 检查器按钮在 2 条通知下可点击。
 *   b. 日历 ≤1180px —— 点日期自动展开、尊重手动收起、可再次展开、无横向溢出。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/final-fixes';

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`}`);
}

async function pressEnter(page) {
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyDown', key: 'Enter', code: 'Enter',
    windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r',
  });
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyUp', key: 'Enter', code: 'Enter',
    windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13,
  });
}

async function goto(page, route) {
  await page.goto(`${BASE_URL}/?route=${route}`, { route });
  await sleep(700);
}

async function addCalendarItem(page, date, title) {
  await page.eval(`
    const cell = document.querySelector('[data-date="${date}"]');
    if (!cell) throw new Error('cell not found: ${date}');
    cell.click();
    return true;
  `);
  await sleep(350);
  const before = await page.eval(`
    const input = document.querySelector('input[aria-label="添加到这一天的日程标题"]');
    const r = input.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return { hitTag: hit?.tagName ?? null, hitCls: String(hit?.className ?? ''), notices: document.querySelectorAll('.notice').length };
  `);
  await page.click('input[aria-label="添加到这一天的日程标题"]');
  await page.insertText(title);
  await sleep(150);
  await pressEnter(page);
  await sleep(650);
  const after = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const input = document.querySelector('input[aria-label="添加到这一天的日程标题"]');
    const r = input.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return {
      stored: ws.items.filter((item) => item.title === ${JSON.stringify(title)}).length,
      notices: document.querySelectorAll('.notice').length,
      hitTag: hit?.tagName ?? null,
      hitCls: String(hit?.className ?? ''),
      inputValue: input.value,
    };
  `);
  return { before, after };
}

/* ------------------------------------------------------------------ a --- */
async function flowA(page) {
  const flow = 'a-notice-pointer-events';
  await page.setViewport(1440, 900);
  await goto(page, 'calendar');

  // 连续添加 3 条：第 3 次点击输入框不能被通知浮层吞掉（修复前会命中 .notice）
  const steps = [];
  for (let index = 0; index < 3; index += 1) {
    const result = await addCalendarItem(page, '2026-11-04', `浮层回归${index}`);
    steps.push({ index, ...result });
  }
  const allCreated = steps.every((step) => step.after.stored === 1);
  const thirdHit = steps[2].before;
  check(
    flow,
    '连续添加 3 条全部成功（第 3 次点击未被吞）',
    allCreated && steps[2].after.stored === 1,
    steps.map((s) => ({ i: s.index, noticesBefore: s.before.notices, hitBefore: s.before.hitTag, stored: s.after.stored })),
  );
  check(
    flow,
    '第 3 次点击时 elementFromPoint 命中 input（此前为 .notice）',
    thirdHit.hitTag === 'INPUT' && steps[2].before.notices >= 2,
    { thirdHit, notices: steps[2].before.notices },
  );

  // 通知本身应为 pointer-events: none，且其中心点"穿透"到底层元素
  const passThrough = await page.eval(`
    const notices = [...document.querySelectorAll('.notice')];
    const sample = notices[notices.length - 1];
    if (!sample) return null;
    const r = sample.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return {
      count: notices.length,
      pointerEvents: getComputedStyle(sample).pointerEvents,
      noticeRect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
      hitTag: hit?.tagName ?? null,
      hitIsNotice: hit?.classList?.contains('notice') ?? false,
      hitCls: String(hit?.className ?? '').slice(0, 40),
    };
  `);
  check(
    flow,
    '通知卡片 pointer-events = none，中心点穿透到底层',
    passThrough && passThrough.pointerEvents === 'none' && passThrough.hitIsNotice === false,
    passThrough,
  );
  await page.screenshot(`${OUT}/a-calendar-toast-pass-through.png`);

  // SOP：2 条通知存在时，检查器底部「删除节点」仍可点击
  await goto(page, 'sop');
  await sleep(900);
  const sopSteps = [];
  for (let index = 0; index < 3; index += 1) {
    await page.eval(`
      const node = document.querySelector('.react-flow__node');
      if (!node) throw new Error('no sop node');
      node.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
      node.click();
      return true;
    `);
    await sleep(350);
    // 检查器正文可滚动：滚到底部才能看到「删除节点」
    await page.eval(`
      const body = document.querySelector('.sop-inspector-body');
      body.scrollTop = body.scrollHeight;
      return true;
    `);
    await sleep(300);
    const probe = await page.eval(`
      const body = document.querySelector('.sop-inspector-body');
      const button = [...document.querySelectorAll('.sop-side button')].find((el) => (el.getAttribute('aria-label') || el.textContent).includes('删除节点'));
      if (!button) return null;
      const r = button.getBoundingClientRect();
      const br = body.getBoundingClientRect();
      const cx = r.x + r.width / 2;
      const cy = r.y + r.height / 2;
      const hit = document.elementFromPoint(cx, cy);
      return {
        rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
        inBodyViewport: r.top >= br.top - 1 && r.bottom <= br.bottom + 1,
        bodyScroll: { top: Math.round(body.scrollTop), max: Math.round(body.scrollHeight - body.clientHeight) },
        cx: Math.round(cx),
        cy: Math.round(cy),
        hitTag: hit?.tagName ?? null,
        hitInsideButton: button.contains(hit),
        hitText: (hit?.getAttribute?.('aria-label') || hit?.textContent || '').trim().slice(0, 24),
        notices: document.querySelectorAll('.notice').length,
        nodes: document.querySelectorAll('.react-flow__node').length,
      };
    `);
    if (!probe) throw new Error('删除节点按钮缺失');
    const beforeSteps = await page.eval(`
      const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
      return ws.items.filter((item) => item.kind === 'step').length;
    `);
    // 真实鼠标点击（不是 DOM .click()），验证命中链路
    await page.clickAt(probe.cx, probe.cy);
    await sleep(550);
    const after = await page.eval(`
      const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
      return {
        nodes: document.querySelectorAll('.react-flow__node').length,
        steps: ws.items.filter((item) => item.kind === 'step').length,
        notices: document.querySelectorAll('.notice').length,
      };
    `);
    sopSteps.push({ index, probe, beforeSteps, after });
  }
  const third = sopSteps[2];
  check(
    flow,
    'SOP 检查器「删除节点」在 2 条通知下可点击（真实鼠标点击命中按钮并删除成功）',
    third.probe.notices >= 2 &&
      third.probe.inBodyViewport === true &&
      third.probe.hitInsideButton === true &&
      third.probe.hitText.includes('删除节点') &&
      third.after.steps === third.beforeSteps - 1,
    third,
  );
  await page.screenshot(`${OUT}/a-sop-inspector-with-notices.png`);
}

/* ------------------------------------------------------------------ b --- */
async function flowB(page) {
  const flow = 'b-calendar-narrow-panel';
  await page.setViewport(1024, 720);
  await goto(page, 'calendar');
  await sleep(600);

  const initial = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return {
      collapsed: panel.classList.contains('is-collapsed'),
      toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim() ?? null,
      width: Math.round(panel.getBoundingClientRect().width),
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    };
  `);
  check(flow, '1024 初始：面板收起、scrollWidth = 1024', initial.collapsed === true && initial.scrollWidth === 1024, initial);

  // 点击日期 → 自动展开并显示条目
  await page.eval(`document.querySelector('[data-date="2026-10-21"]').click(); return true;`);
  await sleep(700);
  const opened = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return {
      collapsed: panel.classList.contains('is-collapsed'),
      width: Math.round(panel.getBoundingClientRect().width),
      items: document.querySelectorAll('.cal-item').length,
      visibleItems: [...document.querySelectorAll('.cal-item')].filter((el) => el.getBoundingClientRect().width > 0).length,
      toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim() ?? null,
      scrollWidth: document.documentElement.scrollWidth,
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
  check(
    flow,
    '点日期自动展开面板并显示条目',
    opened.collapsed === false && opened.width > 0 && opened.visibleItems > 0 && opened.toggle === '收起日程',
    opened,
  );

  // 手动收起 → 再点日期保持收起
  await page.eval(`document.querySelector('.cal-panel-toggle').click(); return true;`);
  await sleep(500);
  const collapsed = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return { collapsed: panel.classList.contains('is-collapsed'), toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim() };
  `);
  await page.eval(`document.querySelector('[data-date="2026-10-22"]').click(); return true;`);
  await sleep(700);
  const afterManualCollapse = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    const selected = document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null;
    return {
      collapsed: panel.classList.contains('is-collapsed'),
      toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim(),
      selected,
      visibleItems: [...document.querySelectorAll('.cal-item')].filter((el) => el.getBoundingClientRect().width > 0).length,
    };
  `);
  check(
    flow,
    '手动收起后再点日期保持收起（尊重用户意图）',
    collapsed.collapsed === true && afterManualCollapse.collapsed === true && afterManualCollapse.selected === '2026-10-22',
    { collapsed, afterManualCollapse },
  );

  // 「展开日程」恢复
  await page.eval(`document.querySelector('.cal-panel-toggle').click(); return true;`);
  await sleep(600);
  const reopened = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return {
      collapsed: panel.classList.contains('is-collapsed'),
      width: Math.round(panel.getBoundingClientRect().width),
      visibleItems: [...document.querySelectorAll('.cal-item')].filter((el) => el.getBoundingClientRect().width > 0).length,
      toggle: document.querySelector('.cal-panel-toggle')?.textContent.trim(),
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    };
  `);
  check(
    flow,
    '点「展开日程」恢复面板且无横向溢出',
    reopened.collapsed === false && reopened.width > 0 && reopened.scrollWidth === 1024 && reopened.clientWidth === 1024,
    reopened,
  );

  // 恢复后再次点日期：保持展开
  await page.eval(`document.querySelector('[data-date="2026-10-23"]').click(); return true;`);
  await sleep(600);
  const stillOpen = await page.eval(`
    const panel = document.querySelector('.cal-panel');
    return { collapsed: panel.classList.contains('is-collapsed'), selected: document.querySelector('.cal-cell.is-selected')?.dataset.date ?? null };
  `);
  check(flow, '恢复后点日期保持展开', stillOpen.collapsed === false && stillOpen.selected === '2026-10-23', stillOpen);

  await page.screenshot(`${OUT}/b-calendar-1024-panel-open.png`);
}

/* ------------------------------------------------------------------ run -- */
async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    for (const flow of [flowA, flowB]) {
      try {
        await flow(page);
      } catch (error) {
        check(flow.name, `流程异常：${error.message.split('\n')[0]}`, false, { error: error.message.split('\n').slice(0, 3).join(' | ') });
        await page.screenshot(`${OUT}/${flow.name}-failed.png`).catch(() => {});
      }
      const errors = page.issues.filter((i) => i.level === 'error');
      if (errors.length) check(flow.name, 'console error = 0', false, errors.map((e) => e.text.slice(0, 200)));
    }
  });

  writeFileSync(`${OUT}/final-fixes-report.json`, JSON.stringify(results, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== FINAL FIXES SUMMARY ===');
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
  console.error('FINAL FIXES FAILED:', error);
  process.exit(1);
});
