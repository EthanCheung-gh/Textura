/**
 * Secondary view switches: OKR cards/table/alignment, GTD 流程台/周回顾,
 * Gantt inspector open/close, SOP list switch. Checks render + console + overflow.
 */
import { BASE_URL, sleep, withPage } from './lib.mjs';

const OVERFLOW_PROBE = `
  const de = document.documentElement;
  const vw = de.clientWidth;
  const offenders = [];
  for (const el of document.querySelectorAll('body *')) {
    const style = getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || style.position === 'fixed') continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    if (r.right <= vw + 1 && r.left >= -1) continue;
    let p = el.parentElement;
    let scrollable = false;
    while (p && p !== document.body) {
      const ps = getComputedStyle(p);
      if (ps.overflowX === 'auto' || ps.overflowX === 'scroll') { scrollable = true; break; }
      p = p.parentElement;
    }
    if (scrollable) continue;
    offenders.push(String(el.className || el.tagName).slice(0, 60));
  }
  const main = document.querySelector('.shell-content');
  return { overflowX: de.scrollWidth - de.clientWidth, offenders: offenders.slice(0, 6), mainText: main ? main.innerText.trim().length : 0 };
`;

const results = [];

await withPage(async (page) => {
  await page.setViewport(1440, 900);

  const check = async (name, action) => {
    page.resetIssues();
    try {
      if (action) await action();
      await sleep(700);
      const layout = await page.eval(OVERFLOW_PROBE);
      const issues = page.issues.filter((i) => i.level === 'error' || i.level === 'warning');
      results.push({ name, ...layout, issues });
      console.log(
        `${issues.length === 0 && layout.overflowX === 0 && layout.mainText > 50 ? 'PASS' : 'CHECK'}  ${name}  overflowX=${layout.overflowX} text=${layout.mainText} issues=${issues.length}`,
      );
      for (const issue of issues) console.log(`    [${issue.level}] ${issue.source}: ${issue.text.slice(0, 200)}`);
    } catch (error) {
      results.push({ name, error: error.message.split('\n')[0] });
      console.log(`FAIL  ${name}: ${error.message.split('\n')[0]}`);
    }
  };

  const clickSegmented = (label) => page.eval(`
    const button = [...document.querySelectorAll('[role="radio"], .segmented button, .segmented-option')]
      .find((el) => el.textContent.trim() === ${JSON.stringify(label)});
    if (!button) throw new Error('segmented option not found: ' + ${JSON.stringify(label)});
    button.click();
    return true;
  `);

  await page.goto(`${BASE_URL}/?route=okr`, { route: 'okr' });
  await check('OKR 卡片视图', null);
  await check('OKR 表格视图', () => clickSegmented('表格'));
  await check('OKR 对齐视图', () => clickSegmented('对齐'));
  await check('OKR 回到卡片 + 紧凑密度', async () => {
    await clickSegmented('卡片');
    await sleep(300);
    await clickSegmented('紧凑');
  });

  await page.goto(`${BASE_URL}/?route=gtd`, { route: 'gtd' });
  await check('GTD 流程台', null);
  await check('GTD 周回顾', () => clickSegmented('周回顾'));
  await check('GTD 回到流程台', () => clickSegmented('流程台'));

  await page.goto(`${BASE_URL}/?route=gantt`, { route: 'gantt' });
  await check('甘特检查器：选中任务', async () => {
    await page.eval(`const row=[...document.querySelectorAll('.gantt-tree-row.is-item')].find(el=>el.textContent.includes('视觉稿评审')); row.click(); return true;`);
  });
  await check('甘特缩放：日 / 月', async () => {
    await clickSegmented('日');
    await sleep(300);
    await clickSegmented('月');
  });

  await page.goto(`${BASE_URL}/?route=sop`, { route: 'sop' });
  await check('SOP 画布 + 检查器', null);
  await check('SOP 收起/展开右栏', async () => {
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='收起右栏'); b.click(); return true;`);
    await sleep(400);
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='展开右栏'); b.click(); return true;`);
  });
  await check('SOP 自动布局', async () => {
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='自动布局'); b.click(); return true;`);
  });
});

console.log('\n=== SECONDARY VIEW SUMMARY ===');
for (const entry of results) {
  console.log(`${entry.issues && entry.issues.length === 0 && !entry.error ? 'PASS' : 'CHECK'}  ${entry.name}`);
}
const bad = results.filter((entry) => entry.error || (entry.issues && entry.issues.length > 0) || entry.overflowX > 0);
console.log(`problems: ${bad.length}`);
if (bad.length) process.exitCode = 1;
