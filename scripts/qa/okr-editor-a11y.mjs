/**
 * 独立验收：OKR 编辑视图的可访问性 / 响应式 / 深色主题对比度。
 *
 * - role=region、aria-labelledby、保存状态 role=status
 * - 1024×720（列表 + 编辑视图 + 展开一条 KR 的编辑态）无横向溢出，并扫描越界元素
 * - 深色主题下 5 处正文对比度 ≥ 4.5:1（取实际 computed style + 有效背景合成）
 *
 * 注意：编辑视图默认零输入控件（渐进式单编辑态），`MetricEditor` 只在点开某条
 * KR 后才挂载 —— 依赖 `.okr-metric-*` 的选择器必须先点铅笔进入编辑态再采样。
 *
 * 用法：TEXTURA_BASE_URL=http://localhost:1438 node scripts/qa/okr-editor-a11y.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/okr-editor-acceptance';
const OBJ = 'obj_activation';

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  const payload = detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${payload}`);
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
  await sleep(500);
}

async function openEditor(page) {
  await page.click(`[data-edit-objective="${OBJ}"]`);
  await page.waitFor(`!!document.querySelector('.okr-editor')`, { label: 'editor visible' });
  await sleep(350);
}

/** 展开第一条 KR 的编辑态（渐进式编辑：输入控件只在该行挂载）。 */
async function openFirstKrEditor(page) {
  await page.click('[data-edit-target^="kr:"]');
  await page.waitFor(`document.querySelectorAll('.okr-kr--editing').length === 1`, {
    label: 'first KR editing',
  });
  await sleep(300);
}

function consoleErrors(page) {
  return page.issues.filter((issue) => issue.level === 'error');
}

/** 页内对比度探针：解析 computed color / 背景栈并合成。 */
const CONTRAST_PROBE = `
  const parseColor = (value) => {
    const match = value.match(/rgba?\\(([^)]+)\\)/);
    if (!match) return null;
    const parts = match[1].split(/[,\\/]/).map((part) => part.trim()).filter((part) => part !== '');
    const [r, g, b] = parts.slice(0, 3).map(Number);
    const a = parts.length > 3 ? Number(parts[3]) : 1;
    return { r, g, b, a: Number.isFinite(a) ? a : 1 };
  };
  const blend = (top, bottom) => ({
    r: top.r * top.a + bottom.r * (1 - top.a),
    g: top.g * top.a + bottom.g * (1 - top.a),
    b: top.b * top.a + bottom.b * (1 - top.a),
    a: 1,
  });
  const effectiveBackground = (el) => {
    const stack = [];
    for (let node = el; node instanceof Element; node = node.parentElement) {
      const color = parseColor(getComputedStyle(node).backgroundColor);
      if (color && color.a > 0) stack.push(color);
    }
    let base = { r: 255, g: 255, b: 255, a: 1 };
    for (const color of stack.reverse()) base = blend(color, base);
    return base;
  };
  const luminance = (color) => {
    const channel = (value) => {
      const c = value / 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
  };
  const contrast = (fg, bg) => {
    const [high, low] = [luminance(fg), luminance(bg)].sort((a, b) => b - a);
    return (high + 0.05) / (low + 0.05);
  };
  const sample = (label, selector) => {
    const el = document.querySelector(selector);
    if (!el) return { label, selector, missing: true };
    const style = getComputedStyle(el);
    const fgRaw = parseColor(style.color);
    const bg = effectiveBackground(el);
    const fg = fgRaw ? blend(fgRaw, bg) : null;
    const hex = (color) => '#' + [color.r, color.g, color.b]
      .map((value) => Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, '0')).join('');
    return {
      label,
      selector,
      text: (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 60),
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      color: style.color,
      bg: hex(bg),
      fgHex: fg ? hex(fg) : null,
      ratio: fg ? Number(contrast(fg, bg).toFixed(2)) : null,
    };
  };
  return { sample, effectiveBackground };
`;

async function scanOverflow(page, scope = '.shell-content') {
  return page.eval(`
    const root = document.documentElement;
    const viewportWidth = window.innerWidth;
    const offenders = [...document.querySelectorAll(${JSON.stringify(scope)} + ' *')]
      .filter((el) => {
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;
        return rect.right > viewportWidth + 1 || rect.left < -1;
      })
      .slice(0, 8)
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          cls: (el.className && el.className.baseVal === undefined ? el.className : '') || '',
          left: Math.round(rect.left),
          right: Math.round(rect.right),
          width: Math.round(rect.width),
        };
      });
    return {
      viewportWidth,
      scrollWidth: root.scrollWidth,
      clientWidth: root.clientWidth,
      bodyScrollWidth: document.body.scrollWidth,
      offenders,
    };
  `);
}

/* ============================================================ a11y ===== */
async function flowA11y(page) {
  const flow = '4-a11y-semantics';
  await hardReset(page);
  await openEditor(page);

  const semantics = await page.eval(`
    const region = document.querySelector('.okr-editor');
    const labelledby = region?.getAttribute('aria-labelledby') ?? null;
    const heading = labelledby ? document.getElementById(labelledby) : null;
    const save = document.querySelector('.okr-editor-save');
    const back = [...document.querySelectorAll('.okr-editor-bar button')].find((el) => el.textContent.trim() === '返回目标列表');
    const active = document.activeElement;
    return {
      role: region?.getAttribute('role') ?? null,
      ariaLabel: region?.getAttribute('aria-label') ?? null,
      labelledby,
      headingTag: heading?.tagName ?? null,
      headingId: heading?.id ?? null,
      headingText: (heading?.textContent || '').replace(/\\s+/g, ' ').trim() ?? null,
      saveRole: save?.getAttribute('role') ?? null,
      saveText: save?.textContent.trim() ?? null,
      saveLive: save?.getAttribute('aria-live') ?? null,
      backFocused: active === back,
      backText: back?.textContent.trim() ?? null,
    };
  `);

  check(flow, '编辑视图 role="region"', semantics.role === 'region', { role: semantics.role, ariaLabel: semantics.ariaLabel });
  check(
    flow,
    'aria-labelledby 指向存在的标题节点（h2）',
    semantics.labelledby === semantics.headingId && semantics.headingTag === 'H2' && semantics.headingId.startsWith('okr-editor-heading-'),
    { labelledby: semantics.labelledby, headingTag: semantics.headingTag, headingText: semantics.headingText },
  );
  check(flow, '保存状态 role="status"', semantics.saveRole === 'status', { saveRole: semantics.saveRole, saveText: semantics.saveText });
  check(flow, '进入编辑视图后焦点交给「返回目标列表」', semantics.backFocused === true, { active: semantics.backText });

  // 渐进式编辑的键盘入口：默认零输入控件，每支铅笔都有无障碍名称。
  const pencils = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    const nodes = [...editor.querySelectorAll('[data-edit-target]')];
    return {
      inputs: editor.querySelectorAll('input').length,
      selects: editor.querySelectorAll('select').length,
      textareas: editor.querySelectorAll('textarea').length,
      targets: nodes.map((el) => el.getAttribute('data-edit-target')),
      // 铅笔用 aria-label，唯一带可见文字的是「新增关键结果」按钮。
      unnamed: nodes
        .filter((el) => !(el.getAttribute('aria-label') || '').trim() && !(el.textContent || '').trim())
        .map((el) => el.outerHTML.slice(0, 120)),
      labelled: nodes.filter((el) => (el.getAttribute('aria-label') || '').trim()).length,
      buttons: nodes.filter((el) => el.tagName === 'BUTTON').length,
    };
  `);
  check(
    flow,
    '默认展示态零输入控件，每个编辑入口都是 button 且有可访问名（aria-label 或可见文字）',
    pencils.inputs === 0 &&
      pencils.selects === 0 &&
      pencils.textareas === 0 &&
      pencils.targets.length === 9 &&
      pencils.buttons === 9 &&
      pencils.labelled === 8 &&
      pencils.unnamed.length === 0,
    pencils,
  );
  check(flow, '语义检查期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
}

/* ========================================================== 1024x720 === */
async function flowResponsive(page) {
  const flow = '4-1024x720';
  await page.setViewport(1024, 720);
  await hardReset(page);

  const listOverflow = await scanOverflow(page);
  check(
    flow,
    '1024 列表态无横向溢出',
    listOverflow.scrollWidth <= listOverflow.clientWidth + 1 && listOverflow.offenders.length === 0,
    listOverflow,
  );

  await openEditor(page);
  const editorOverflow = await scanOverflow(page);
  const editorBox = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    const sections = [...document.querySelectorAll('.okr-editor-hero, .okr-editor-section, .okr-editor-exec-summary')];
    return {
      editorWidth: Math.round(editor.getBoundingClientRect().width),
      viewport: window.innerWidth,
      scrollWidth: editor.scrollWidth,
      clientWidth: editor.clientWidth,
      sections: sections.map((el) => ({
        cls: el.className,
        width: Math.round(el.getBoundingClientRect().width),
        scrollWidth: el.scrollWidth,
        clientWidth: el.clientWidth,
      })),
    };
  `);
  check(
    flow,
    '1024 编辑视图无横向溢出',
    editorOverflow.scrollWidth <= editorOverflow.clientWidth + 1 && editorOverflow.offenders.length === 0,
    editorOverflow,
  );
  check(
    flow,
    '编辑视图容器与各分区宽度不超过可视区',
    editorBox.sections.every((section) => section.width <= editorBox.viewport && section.scrollWidth <= section.clientWidth + 1),
    editorBox,
  );
  check(flow, '1024 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
  await page.screenshot(`${OUT}/4-1024x720-editor.png`);

  // 展开一条 KR（指标 / 负责人 / 状态 / 执行项都挂上）后仍然不溢出。
  await openFirstKrEditor(page);
  const expandedOverflow = await scanOverflow(page);
  const expandedBox = await page.eval(`
    const row = document.querySelector('.okr-kr--editing');
    return {
      editingRows: document.querySelectorAll('.okr-kr--editing').length,
      metricInputs: document.querySelectorAll('.okr-metric-input').length,
      metricInputsInRow: row ? row.querySelectorAll('.okr-metric-input').length : -1,
      rowWidth: row ? Math.round(row.getBoundingClientRect().width) : null,
      rowScrollWidth: row?.scrollWidth ?? null,
      viewport: window.innerWidth,
    };
  `);
  check(
    flow,
    '1024 展开一条 KR 的编辑态：4 个指标输入且无横向溢出',
    expandedBox.editingRows === 1 &&
      expandedBox.metricInputs === 4 &&
      expandedBox.metricInputsInRow === 4 &&
      expandedBox.rowScrollWidth <= expandedBox.rowWidth + 1 &&
      expandedOverflow.scrollWidth <= expandedOverflow.clientWidth + 1 &&
      expandedOverflow.offenders.length === 0,
    { expandedBox, offenders: expandedOverflow.offenders, scrollWidth: expandedOverflow.scrollWidth },
  );
  check(
    flow,
    '1024 展开态 console error = 0',
    consoleErrors(page).length === 0,
    { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) },
  );
  await page.screenshot(`${OUT}/4-1024x720-editor-expanded.png`);

  // 恢复 1440，避免影响后续
  await page.setViewport(1440, 900);
}

/* ======================================================= dark contrast == */
async function flowDarkContrast(page) {
  const flow = '4-dark-contrast';
  await hardReset(page);
  await page.eval(`localStorage.setItem('textura.theme', 'dark'); return true;`);
  await page.reload({ route: 'okr' });
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'list after dark reload' });
  await sleep(500);
  await openEditor(page);

  const theme = await page.eval(`
    return {
      dataTheme: document.documentElement.dataset.theme ?? null,
      bodyBg: getComputedStyle(document.body).backgroundColor,
      bodyColor: getComputedStyle(document.body).color,
    };
  `);
  check(flow, '深色主题已生效（html[data-theme=dark]）', theme.dataTheme === 'dark', theme);

  // 指标字段标签只在该行编辑态里存在：先点开第一条 KR 再采样对比度。
  await openFirstKrEditor(page);
  const samples = await page.eval(`
    const probe = (() => { ${CONTRAST_PROBE} })();
    return [
      probe.sample('编辑视图目标标题', '.okr-editor-title'),
      probe.sample('KR 标题', '.okr-kr-title'),
      probe.sample('指标字段标签（11px muted）', '.okr-editor-section .okr-metric-label'),
      probe.sample('执行项概览提示（11.5px muted）', '.okr-editor-hint'),
      probe.sample('面包屑（12px muted）', '.okr-editor-crumb'),
    ];
  `);

  for (const row of samples) {
    check(
      flow,
      `深色主题对比度 ≥ 4.5:1 · ${row.label}`,
      typeof row.ratio === 'number' && row.ratio >= 4.5,
      row,
    );
  }
  check(flow, '深色主题检查期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });

  // 收起编辑态再截图：证据图对应默认展示态。
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);
  const darkCollapsed = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      inEditor: Boolean(editor),
      editingRows: editor ? editor.querySelectorAll('.okr-kr--editing').length : -1,
      inputs: editor ? editor.querySelectorAll('input').length : -1,
    };
  `);
  check(
    flow,
    '深色下 Esc 收起 KR 编辑态（仍留在编辑视图、零输入控件）',
    darkCollapsed.inEditor === true && darkCollapsed.editingRows === 0 && darkCollapsed.inputs === 0,
    darkCollapsed,
  );
  await page.screenshot(`${OUT}/4-dark-editor.png`);
  writeFileSync(`${OUT}/contrast-samples.json`, JSON.stringify(samples, null, 2));
}

async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    for (const flow of [flowA11y, flowResponsive, flowDarkContrast]) {
      try {
        await flow(page);
      } catch (error) {
        check(flow.name, `流程异常：${error.message.split('\n')[0]}`, false, {
          error: error.message.split('\n').slice(0, 3).join(' | '),
        });
        await page.screenshot(`${OUT}/${flow.name}-failed.png`).catch(() => {});
      }
    }
  });

  writeFileSync(`${OUT}/a11y-report.json`, JSON.stringify({ baseUrl: BASE_URL, results }, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== OKR EDITOR A11Y SUMMARY ===');
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
  console.error('OKR EDITOR A11Y FAILED:', error);
  process.exit(1);
});
