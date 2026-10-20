/**
 * Opens every overlay (capture, palette, shortcuts, clarify, link, dialogs)
 * and collects console errors/warnings per step.
 */
import { BASE_URL, sleep, withPage } from './lib.mjs';

const steps = [];

await withPage(async (page) => {
  const step = async (name, fn) => {
    page.resetIssues();
    try {
      await fn();
      await sleep(500);
    } catch (error) {
      steps.push({ name, ok: false, error: error.message.split('\n')[0], issues: page.issues });
      console.log(`FAIL ${name}: ${error.message.split('\n')[0]}`);
      return;
    }
    const issues = page.issues.filter((i) => i.level === 'error' || i.level === 'warning');
    steps.push({ name, ok: issues.length === 0, issues });
    console.log(`${issues.length === 0 ? 'PASS' : `WARN(${issues.length})`} ${name}`);
    for (const issue of issues) console.log(`    [${issue.level}] ${issue.source}: ${issue.text.slice(0, 240)}`);
  };

  await page.reset('dashboard');
  await page.setViewport(1440, 900);
  await sleep(600);

  await step('quick capture (typing + submit + undo)', async () => {
    await page.eval(`const b=[...document.querySelectorAll('.topbar button')].find(el=>el.textContent.trim()==='快速收集'); b.click(); return true;`);
    await sleep(350);
    await page.insertText('overlay 探针 #x @电话 !高能 /本周');
    await sleep(300);
    await page.pressKey('Enter', { code: 'Enter', vk: 13 });
    await sleep(400);
    await page.eval(`const b=[...document.querySelectorAll('[role="dialog"] button[aria-label="撤销最后一条收集"]')][0]; if(b) b.click(); return true;`);
    await sleep(300);
    await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  });

  await step('command palette (query + tabs + esc)', async () => {
    await page.shortcut('k');
    await sleep(350);
    await page.insertText('目标');
    await sleep(350);
    await page.pressKey('Tab', { code: 'Tab', vk: 9 });
    await sleep(200);
    await page.pressKey('ArrowDown', { code: 'ArrowDown', vk: 40 });
    await sleep(200);
    await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  });

  await step('shortcuts dialog (?)', async () => {
    await page.eval(`document.activeElement?.blur(); window.dispatchEvent(new KeyboardEvent('keydown', { key: '?', bubbles: true, cancelable: true })); return true;`);
    await sleep(400);
    const open = await page.eval(`return document.querySelectorAll('[role="dialog"]').length;`);
    if (!open) throw new Error('shortcuts dialog did not open');
    await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  });

  await step('gtd clarify dialog (open + type + cancel)', async () => {
    await page.eval(`const b=[...document.querySelectorAll('.sidebar-nav .sidebar-link')].find(el=>el.textContent.includes('GTD')); b.click(); return true;`);
    await page.waitFor(`!!document.querySelector('.gtd-inbox-row')`, { label: 'inbox rows' });
    await sleep(300);
    await page.eval(`document.querySelector('.gtd-inbox-row .gtd-row-title').click(); return true;`);
    await page.waitFor(`!!document.querySelector('#gtd-clarify-form')`, { label: 'clarify form' });
    await sleep(300);
    await page.typeInto('#gtd-clarify-title', '改过的标题');
    await sleep(200);
    await page.eval(`const b=[...document.querySelectorAll('[role="dialog"] button')].find(el=>el.textContent.trim()==='取消'); b.click(); return true;`);
  });

  await step('okr link dialog + quarter dialog', async () => {
    await page.eval(`const b=[...document.querySelectorAll('.sidebar-nav .sidebar-link')].find(el=>el.textContent.includes('OKR')); b.click(); return true;`);
    await page.waitFor(`document.documentElement.dataset.route === 'okr'`, { label: 'okr route' });
    await sleep(400);
    await page.eval(`const b=[...document.querySelectorAll('button[aria-label]')].find(el=>el.getAttribute('aria-label','').startsWith('关联「NPS')); b.click(); return true;`);
    await page.waitFor(`!!document.querySelector('.okr-link-list')`, { label: 'link list' });
    await sleep(300);
    await page.eval(`const b=[...document.querySelectorAll('[role="dialog"] button')].find(el=>el.textContent.trim()==='取消'); b.click(); return true;`);
    await sleep(300);
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='新建季度'); b.click(); return true;`);
    await sleep(400);
    await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  });

  await step('settings reset confirm + shortcuts', async () => {
    await page.eval(`const b=[...document.querySelectorAll('.sidebar-nav .sidebar-link')].find(el=>el.textContent.includes('设置')); b.click(); return true;`);
    await page.waitFor(`document.documentElement.dataset.route === 'settings'`, { label: 'settings route' });
    await sleep(400);
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='重置为演示数据'); b.scrollIntoView({block:'center'}); b.click(); return true;`);
    await sleep(400);
    await page.eval(`const b=[...document.querySelectorAll('[role="dialog"] button')].find(el=>el.textContent.trim()==='取消'); if(b) b.click(); return true;`);
  });

  await step('sop run bar + inspector selection', async () => {
    await page.eval(`const b=[...document.querySelectorAll('.sidebar-nav .sidebar-link')].find(el=>el.textContent.includes('SOP')); b.click(); return true;`);
    await page.waitFor(`document.documentElement.dataset.route === 'sop'`, { label: 'sop route' });
    await sleep(900);
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='运行'); b.click(); return true;`);
    await sleep(500);
    await page.eval(`const b=[...document.querySelectorAll('button')].find(el=>el.textContent.trim()==='退出运行'); b.click(); return true;`);
    await sleep(300);
    await page.eval(`const node=document.querySelector('.react-flow__node'); node.dispatchEvent(new MouseEvent('click',{bubbles:true})); return true;`);
  });

  await step('theme round-trip', async () => {
    await page.eval(`document.querySelector('button[aria-label="切换到深色主题"]').click(); return true;`);
    await sleep(300);
    await page.eval(`document.querySelector('button[aria-label="切换到浅色主题"]').click(); return true;`);
  });
});

const totalIssues = steps.reduce((sum, entry) => sum + (entry.issues?.length ?? 0), 0);
console.log('\n=== OVERLAY SUMMARY ===');
for (const entry of steps) console.log(`${entry.ok ? 'PASS' : 'ISSUES'}  ${entry.name}`);
console.log(`total console issues: ${totalIssues}`);
if (steps.some((entry) => !entry.ok)) process.exitCode = 1;
