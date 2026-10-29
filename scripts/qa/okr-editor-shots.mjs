/**
 * 独立验收截图：okr-editor.png（1440×900 浅色）、okr-editor-dark.png（深色），
 * 以及 1024×720 有代表性布局差异时的 okr-editor-1024.png。
 *
 * 截图前统一「清 localStorage + 刷新」回到演示数据；每张截图前断言 console error = 0。
 *
 * 用法：TEXTURA_BASE_URL=http://localhost:1434 node scripts/qa/okr-editor-shots.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const SHOTS = 'docs/screenshots';
const OBJ = 'obj_activation';
const OBJ_TITLE = '让新用户在第一周就爱上织理';
const DEMO_NOTES = '本季度聚焦激活与留存，所有 KR 以周为单位复盘。';

const results = [];
let failures = 0;

function check(label, ok, detail) {
  results.push({ label, ok, detail });
  if (!ok) failures += 1;
  const payload = detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${payload}`);
}

async function hardReset(page, route = 'okr') {
  await page.cdp.send('Page.navigate', { url: 'about:blank' });
  await page.waitFor(`document.readyState === 'complete'`, { label: 'about:blank ready' });
  await sleep(250);
  const { identifier } = await page.cdp.send('Page.addScriptToEvaluateOnNewDocument', {
    source: 'try { localStorage.clear(); } catch (error) {}',
  });
  try {
    await page.goto(`${BASE_URL}/?route=${route}`, { route });
  } finally {
    await page.cdp.send('Page.removeScriptToEvaluateOnNewDocument', { identifier }).catch(() => {});
  }
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'okr list' });
  await sleep(600);
}

async function openEditor(page) {
  await page.click(`[data-edit-objective="${OBJ}"]`);
  await page.waitFor(`!!document.querySelector('.okr-editor')`, { label: 'editor' });
  await sleep(450);
}

function errors(page) {
  return page.issues.filter((issue) => issue.level === 'error').map((issue) => issue.text.slice(0, 200));
}

async function demoState(page) {
  return page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const objectives = ws.items.filter((item) => item.kind === 'objective');
    const obj = ws.items.find((item) => item.id === ${JSON.stringify(OBJ)});
    const kr = ws.items.find((item) => item.id === 'kr_nps');
    return {
      objectives: objectives.map((item) => ({ id: item.id, title: item.title, period: item.okr?.period ?? null })),
      notes: obj?.notes ?? null,
      metricCurrent: kr?.okr?.metric?.current ?? null,
      search: document.querySelector('input[aria-label="搜索工作区"]')?.value ?? null,
      theme: document.documentElement.dataset.theme ?? null,
      storedTheme: localStorage.getItem('textura.theme'),
    };
  `);
}

async function layoutSignature(page) {
  return page.eval(`
    const rowsOf = (selector) => {
      const tops = [...document.querySelectorAll(selector)].map((el) => Math.round(el.getBoundingClientRect().top));
      return [...new Set(tops)].sort((a, b) => a - b).length;
    };
    const hero = document.querySelector('.okr-editor-hero');
    const fields = document.querySelector('.okr-editor-fields');
    const notes = document.querySelector('.okr-editor-notes');
    return {
      viewport: { w: window.innerWidth, h: window.innerHeight },
      editorWidth: Math.round(document.querySelector('.okr-editor').getBoundingClientRect().width),
      fieldRows: rowsOf('.okr-editor-field'),
      fieldGroupHeight: Math.round(fields.getBoundingClientRect().height),
      heroHeight: Math.round(hero.getBoundingClientRect().height),
      notesWidth: Math.round(notes.getBoundingClientRect().width),
      krMetaRows: rowsOf('.okr-kr-meta'),
      firstKrHeight: Math.round(document.querySelector('.okr-kr').getBoundingClientRect().height),
      overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  `);
}

async function main() {
  mkdirSync(SHOTS, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);

    /* ---------------- 1440×900 浅色 ---------------- */
    await hardReset(page);
    const demoLight = await demoState(page);
    check('截图前工作区为演示数据（清 localStorage 后重新播种）', demoLight.objectives.length === 1 &&
      demoLight.objectives[0].id === OBJ &&
      demoLight.objectives[0].title === OBJ_TITLE &&
      demoLight.notes === DEMO_NOTES &&
      demoLight.metricCurrent === 47, demoLight);
    await openEditor(page);
    const beforeLight = errors(page);
    check('浅色编辑视图 console error = 0', beforeLight.length === 0, { errors: beforeLight });
    const lightSig = await layoutSignature(page);
    await page.eval(`document.querySelector('.okr-page')?.scrollIntoView({ block: 'start' }); window.scrollTo(0, 0); return true;`);
    await sleep(250);
    await page.screenshot(`${SHOTS}/okr-editor.png`);
    check('已生成 docs/screenshots/okr-editor.png（1440×900）', true, lightSig);

    /* ---------------- 1024×720（浅色，布局差异判定） ---------------- */
    await page.setViewport(1024, 720);
    await sleep(600);
    const narrowSig = await layoutSignature(page);
    const representative =
      narrowSig.fieldRows !== lightSig.fieldRows ||
      Math.abs(narrowSig.heroHeight - lightSig.heroHeight) > 24 ||
      narrowSig.krMetaRows !== lightSig.krMetaRows ||
      Math.abs(narrowSig.firstKrHeight - lightSig.firstKrHeight) > 20;
    check('1024×720 布局与 1440 对比（判断是否有代表性差异）', true, {
      representative,
      wide: lightSig,
      narrow: narrowSig,
    });
    if (representative) {
      const narrowErrors = errors(page);
      check('1024 编辑视图 console error = 0（截图前）', narrowErrors.length === 0, { errors: narrowErrors });
      await page.eval(`window.scrollTo(0, 0); return true;`);
      await sleep(250);
      await page.screenshot(`${SHOTS}/okr-editor-1024.png`);
      check('已生成 docs/screenshots/okr-editor-1024.png（1024×720）', true);
    } else {
      check('1024 无代表性差异，跳过 okr-editor-1024.png', true, { wide: lightSig, narrow: narrowSig });
    }
    await page.setViewport(1440, 900);
    await sleep(500);

    /* ---------------- 深色 ---------------- */
    await page.eval(`localStorage.setItem('textura.theme', 'dark'); return true;`);
    await page.reload({ route: 'okr' });
    await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'list after dark reload' });
    await sleep(500);
    check('深色主题重载后工作区仍是演示数据', (await demoState(page)).objectives.length === 1);
    await openEditor(page);
    const darkState = await demoState(page);
    check('深色主题生效', darkState.theme === 'dark' && darkState.storedTheme === 'dark', {
      theme: darkState.theme,
      storedTheme: darkState.storedTheme,
    });
    const darkErrors = errors(page);
    check('深色编辑视图 console error = 0', darkErrors.length === 0, { errors: darkErrors });
    await page.eval(`window.scrollTo(0, 0); return true;`);
    await sleep(250);
    await page.screenshot(`${SHOTS}/okr-editor-dark.png`);
    check('已生成 docs/screenshots/okr-editor-dark.png', true);
  });

  writeFileSync(`${SHOTS}/okr-editor-shots-report.json`, JSON.stringify({ baseUrl: BASE_URL, results }, null, 2));
  console.log(`\n断言失败总数：${failures}`);
  if (failures) process.exitCode = 1;
}

main().catch((error) => {
  console.error('OKR EDITOR SHOTS FAILED:', error);
  process.exit(1);
});
