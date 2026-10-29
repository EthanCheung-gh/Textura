/**
 * 独立验收：OKR 卡片编辑按钮 + 独立编辑视图（前端 / React 版）。
 *
 * 覆盖 2a–2e + 可访问性属性；全部通过 CDP 真实交互 + DOM / localStorage 断言。
 * 用法：TEXTURA_BASE_URL=http://localhost:1438 node scripts/qa/okr-editor-acceptance.mjs
 *
 * 编辑视图是**渐进式单编辑态**（`main@011c518` 起）：打开时全只读（0 个
 * input/select/textarea），每个字段一支铅笔（`[data-edit-target]`），任何时刻只有
 * 一个编辑目标（目标级字段互斥、同级 KR 互斥），Esc 两段语义（先收编辑、再返回列表）。
 * 2b 覆盖默认态与单编辑态，2c 覆盖逐字段持久化，2d 覆盖 Esc 两段语义与焦点归还。
 *
 * 2f（不存在的目标 id 空态）无法从 UI 触发，按验收说明跳过；单测
 * `src/modules/okr/okrEditor.test.ts` 已覆盖 resolveEditorObjective 的缺失 id。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { BASE_URL, sleep, withPage } from './lib.mjs';

const KEY = 'textura.workspace.v1';
const OUT = 'docs/screenshots/okr-editor-acceptance';
const ORIGIN = new URL(BASE_URL).origin;
const OBJ = 'obj_activation';
const OBJ_TITLE = '让新用户在第一周就爱上织理';
const KR_NPS = 'kr_nps';
const KR_WAU = 'kr_wau';
const KR_WAU_TITLE = '周活跃用户 1200 → 2000';
/** 默认展示态的铅笔入口：标题 / 领域 / 状态 / 信心 / 备注（`.okr-edit-pencil`）5 支 + 3 条 KR。 */
const DISPLAY_PENCILS = 8;
/** 铅笔 + 「新增关键结果」按钮（同为 `[data-edit-target]`）。 */
const DISPLAY_TARGETS = DISPLAY_PENCILS + 1;

const results = [];
let failures = 0;

function check(flow, label, ok, detail) {
  results.push({ flow, label, ok, detail });
  if (!ok) failures += 1;
  const payload = detail === undefined ? '' : ` :: ${JSON.stringify(detail)}`;
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${flow}] ${label}${payload}`);
}

async function readWorkspace(page) {
  return page.eval(`
    const raw = localStorage.getItem(${JSON.stringify(KEY)});
    return raw ? JSON.parse(raw) : null;
  `);
}

async function waitSaved(page, timeout = 6000) {
  await page.waitFor(
    `[...document.querySelectorAll('.storage-status')].some((el) => el.textContent.includes('已保存'))`,
    { label: 'storage status 已保存', timeout },
  );
}

/**
 * 回到演示数据。
 *
 * 直接 clear + reload 有竞态：应用在 pagehide 时会把内存中的工作区写回
 * localStorage（MetricEditor 的 pagehide flush），覆盖掉刚清空的数据。
 * 因此先卸载到 about:blank，再在新文档「文档开始」阶段清空存储，让应用以
 * freshInstall 重新播种演示数据。
 */
async function clearAndReset(page, route) {
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
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'okr list cards' });
  await sleep(500);
}

async function openEditor(page, id = OBJ) {
  await page.click(`[data-edit-objective="${id}"]`);
  await page.waitFor(`!!document.querySelector('.okr-editor')`, { label: 'okr editor visible' });
  await sleep(350);
}

/** 点某个编辑目标的铅笔 / 触发按钮（`title` / `notes` / `kr:<id>` / `add-kr` …）。 */
async function clickEditTarget(page, target) {
  await page.click(`[data-edit-target="${target}"]`);
  await sleep(300);
}

/** 只读展示态探针：编辑视图里挂载了多少输入控件、多少支铅笔。 */
async function progressiveSnapshot(page) {
  return page.eval(`
    const editor = document.querySelector('.okr-editor');
    const count = (selector) => editor.querySelectorAll(selector).length;
    return {
      inputs: count('input'),
      selects: count('select'),
      textareas: count('textarea'),
      pencils: count('.okr-edit-pencil'),
      targets: [...editor.querySelectorAll('[data-edit-target]')].map((el) => el.getAttribute('data-edit-target')),
      displayRows: count('.okr-kr--display'),
      editingRows: count('.okr-kr--editing'),
      metricInputs: count('.okr-metric-input'),
    };
  `);
}

/** 当前编辑态探针：哪一行在编辑、输入控件落在哪里。 */
async function editingSnapshot(page) {
  return page.eval(`
    const editing = [...document.querySelectorAll('.okr-kr--editing')];
    const active = document.activeElement;
    const editingInput = active instanceof HTMLElement ? active.closest('.okr-kr--editing') : null;
    return {
      editingRows: editing.length,
      editingTitleInputs: document.querySelectorAll('.okr-kr--editing .okr-kr-title-input').length,
      editingTitles: editing.map((el) => el.querySelector('.okr-kr-title-input')?.value ?? null),
      metricInputs: document.querySelectorAll('.okr-metric-input').length,
      metricInputsInEditing: document.querySelectorAll('.okr-kr--editing .okr-metric-input').length,
      ownerInputsInEditing: document.querySelectorAll('.okr-kr--editing input[aria-label$="负责人"]').length,
      statusSelectsInEditing: document.querySelectorAll('.okr-kr--editing select').length,
      displayRows: document.querySelectorAll('.okr-kr--display').length,
      focusInEditing: Boolean(editingInput),
    };
  `);
}

async function backToList(page) {
  const clickedAt = await page.eval(`
    const button = [...document.querySelectorAll('.okr-editor-bar button')]
      .find((el) => el.textContent.trim() === '返回目标列表');
    if (!button) throw new Error('back button missing');
    button.click();
    return performance.now();
  `);
  await page.waitFor(`!document.querySelector('.okr-editor')`, { label: 'back to list' });
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'list cards restored' });
  await sleep(250);
  return clickedAt;
}

async function setSelect(page, ariaLabel, value) {
  await page.eval(`
    const el = document.querySelector('select[aria-label=' + JSON.stringify(${JSON.stringify(ariaLabel)}) + ']');
    if (!el) throw new Error('select not found: ' + ${JSON.stringify(ariaLabel)});
    const setter = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, 'value').set;
    setter.call(el, ${JSON.stringify(value)});
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  `);
  await sleep(250);
}

async function pressEnter(page) {
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyDown',
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
    text: '\r',
    unmodifiedText: '\r',
  });
  await page.cdp.send('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
  });
}

function consoleErrors(page) {
  return page.issues.filter((issue) => issue.level === 'error');
}

/* ================================================================ 2a ==== */
async function flowA(page) {
  const flow = '2a-card-edit-button';
  await clearAndReset(page, 'okr');

  const info = await page.eval(`
    const tools = document.querySelector('.okr-objective-tools');
    const buttons = [...tools.querySelectorAll('button')];
    const edit = tools.querySelector('[data-edit-objective]');
    const more = buttons.find((el) => (el.getAttribute('aria-label') || '').endsWith('更多操作'));
    const rect = (el) => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; };
    return {
      objectiveCards: document.querySelectorAll('.okr-objective').length,
      edit: edit
        ? {
            ariaLabel: edit.getAttribute('aria-label'),
            text: edit.textContent.replace(/\\s+/g, ' ').trim(),
            dataEditObjective: edit.getAttribute('data-edit-objective'),
            rect: rect(edit),
            svg: Boolean(edit.querySelector('svg')),
            index: buttons.indexOf(edit),
            visible: edit.offsetParent !== null,
          }
        : null,
      more: more
        ? {
            ariaLabel: more.getAttribute('aria-label'),
            rect: rect(more),
            index: buttons.indexOf(more),
            haspoup: more.getAttribute('aria-haspopup'),
          }
        : null,
      order: buttons.map((el) => el.getAttribute('aria-label')),
    };
  `);

  check(flow, '卡片存在编辑按钮（data-edit-objective 指向目标 id）', info.edit?.dataEditObjective === OBJ, info.edit);
  // 卡片按钮从「图标 + title 提示」改成「图标 + 可见文字」（`main@c80b107`），
  // 无障碍名称仍以 aria-label 为准，可见文字是「编辑」。
  check(
    flow,
    '编辑按钮 aria-label = 「编辑目标：…」且可见文字为「编辑」',
    info.edit?.ariaLabel === `编辑目标：${OBJ_TITLE}` && info.edit?.text === '编辑',
    { ariaLabel: info.edit?.ariaLabel, text: info.edit?.text },
  );
  check(
    flow,
    '编辑按钮在「更多操作」左侧（DOM 顺序 + 几何 x 坐标）',
    info.edit?.index === 0 && info.more?.index === 1 && info.edit.rect.x + info.edit.rect.w <= info.more.rect.x,
    { order: info.order, editX: info.edit?.rect.x, editRight: info.edit ? info.edit.rect.x + info.edit.rect.w : null, moreX: info.more?.rect.x },
  );
  check(flow, '编辑按钮可见、含图标、可访问名非空', info.edit?.visible === true && info.edit?.svg === true, { visible: info.edit?.visible });

  // 真实鼠标点击可进入编辑视图（2b 详细断言在 flowB）
  await page.screenshot(`${OUT}/2a-card-edit-button.png`);
  await openEditor(page);
  check(flow, '点击编辑按钮进入编辑视图（region 出现）', await page.exists('.okr-editor[role="region"]'));
  check(flow, '2a 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
}

/* ================================================================ 2b ==== */
async function flowB(page) {
  const flow = '2b-editor-view';

  // 先制造筛选提示，验证进入编辑视图后列表附属区域全部消失。
  await clearAndReset(page, 'okr');
  await page.typeInto('input[aria-label="搜索工作区"]', 'NPS');
  await page.waitFor(`!!document.querySelector('.okr-filter-note')`, { label: 'filter note' });
  await sleep(300);
  const listBefore = await page.eval(`
    return {
      periodbar: Boolean(document.querySelector('.okr-periodbar')),
      health: Boolean(document.querySelector('.okr-health')),
      filterNote: Boolean(document.querySelector('.okr-filter-note')),
      cards: document.querySelectorAll('.okr-objective').length,
    };
  `);
  check(
    flow,
    '列表态存在季度条 / 健康度 / 筛选提示 / 卡片',
    listBefore.periodbar && listBefore.health && listBefore.filterNote && listBefore.cards === 1,
    listBefore,
  );

  await openEditor(page);
  const editor = await page.eval(`
    const region = document.querySelector('.okr-editor');
    const save = document.querySelector('.okr-editor-save');
    return {
      h1: document.querySelector('h1')?.textContent ?? null,
      region: Boolean(region),
      periodbar: Boolean(document.querySelector('.okr-periodbar')),
      health: Boolean(document.querySelector('.okr-health')),
      filterNote: Boolean(document.querySelector('.okr-filter-note')),
      cards: document.querySelectorAll('.okr-objective').length,
      headerButtons: document.querySelectorAll('.okr-header-actions button').length,
      title: document.querySelector('.okr-editor-title')?.textContent?.trim() ?? null,
      krRows: document.querySelectorAll('.okr-kr').length,
      krTitles: [...document.querySelectorAll('.okr-kr-title')].map((el) => el.textContent.trim()),
      metricInputs: document.querySelectorAll('.okr-metric-input').length,
      exec: document.querySelector('.okr-editor-exec-line')?.textContent.replace(/\\s+/g, ' ').trim() ?? null,
      saveText: save?.textContent.trim() ?? null,
      saveRole: save?.getAttribute('role') ?? null,
      saveState: save?.getAttribute('data-state') ?? null,
      crumb: document.querySelector('.okr-editor-crumb')?.textContent.trim() ?? null,
      actions: [...document.querySelectorAll('.okr-editor-actions button')].map((b) => b.textContent.trim()),
      labelledby: region?.getAttribute('aria-labelledby') ?? null,
      headingId: document.querySelector('.okr-editor-heading')?.id ?? null,
    };
  `);

  check(flow, '页面 h1「OKR」保留', editor.h1 === 'OKR', { h1: editor.h1 });
  check(
    flow,
    '季度条 / 健康度 / 筛选提示 / 卡片列表全部消失',
    !editor.periodbar && !editor.health && !editor.filterNote && editor.cards === 0,
    { periodbar: editor.periodbar, health: editor.health, filterNote: editor.filterNote, cards: editor.cards },
  );
  check(flow, '编辑视图隐藏列表页头操作（密度/视图/新建目标）', editor.headerButtons === 0, { headerButtons: editor.headerButtons });
  check(flow, '显示目标标题', editor.title === OBJ_TITLE, { title: editor.title });
  check(
    flow,
    '显示 3 个 KR',
    editor.krRows === 3 && editor.krTitles.length === 3,
    { krRows: editor.krRows, krTitles: editor.krTitles },
  );
  check(flow, '默认展示态：指标输入 0 个（3 KR × 4 字段只在点铅笔后挂载）', editor.metricInputs === 0, {
    metricInputs: editor.metricInputs,
  });
  check(
    flow,
    '执行项概览文案「关联执行项 N · 已完成 M」',
    /^关联执行项 \d+ · 已完成 \d+$/.test(editor.exec ?? ''),
    { exec: editor.exec },
  );
  check(flow, '保存状态 role=status 且显示「已保存」', editor.saveRole === 'status' && editor.saveText === '已保存', {
    saveText: editor.saveText,
    saveRole: editor.saveRole,
    saveState: editor.saveState,
  });
  check(flow, '面包屑显示当前季度 · 目标编辑', editor.crumb === '2026 Q4 · 目标编辑', { crumb: editor.crumb });
  check(flow, '目标操作按钮（移动 / 复制 / 删除）', editor.actions.length === 3, { actions: editor.actions });
  check(
    flow,
    '编辑视图可访问性：role=region + aria-labelledby 指向标题',
    editor.labelledby === editor.headingId && Boolean(editor.headingId),
    { labelledby: editor.labelledby, headingId: editor.headingId },
  );

  /* ---------- 渐进式单编辑态：默认全只读，一次只展开一处 ---------- */
  const idle = await progressiveSnapshot(page);
  check(
    flow,
    '默认展示态：编辑视图内 input / select / textarea = 0',
    idle.inputs === 0 && idle.selects === 0 && idle.textareas === 0,
    idle,
  );
  check(
    flow,
    `默认展示态：${DISPLAY_PENCILS} 支铅笔 + 「新增关键结果」按钮（data-edit-target 共 ${DISPLAY_TARGETS} 个）`,
    idle.pencils === DISPLAY_PENCILS &&
      idle.targets.length === DISPLAY_TARGETS &&
      idle.targets.includes('add-kr') &&
      idle.targets.includes(`kr:${KR_NPS}`),
    { pencils: idle.pencils, targets: idle.targets },
  );
  check(
    flow,
    '默认展示态：3 条 KR 都是 display 态（无 .okr-kr--editing）',
    idle.displayRows === 3 && idle.editingRows === 0,
    { displayRows: idle.displayRows, editingRows: idle.editingRows },
  );

  // 点第 1 条 KR 的铅笔：只有该行挂载输入控件（标题 / 指标 ×4 / 负责人 / 状态）。
  await clickEditTarget(page, `kr:${KR_NPS}`);
  const firstEdit = await editingSnapshot(page);
  check(
    flow,
    '点 KR 铅笔：只该行进入编辑态，指标输入 4 个全在该行',
    firstEdit.editingRows === 1 &&
      firstEdit.metricInputs === 4 &&
      firstEdit.metricInputsInEditing === 4 &&
      firstEdit.displayRows === 2,
    firstEdit,
  );
  check(
    flow,
    '该行编辑态包含标题输入 / 负责人 / 状态 / 完成按钮',
    firstEdit.editingTitleInputs === 1 &&
      firstEdit.ownerInputsInEditing === 1 &&
      firstEdit.statusSelectsInEditing === 1 &&
      firstEdit.focusInEditing === true,
    firstEdit,
  );

  // 点第 2 条 KR 的铅笔：上一行自动结束（失焦提交），仍然只有 1 行编辑态。
  await clickEditTarget(page, `kr:${KR_WAU}`);
  const switched = await editingSnapshot(page);
  check(
    flow,
    '切到另一条 KR：同级 KR 互斥，仍然只有 1 个 .okr-kr--editing',
    switched.editingRows === 1 &&
      switched.editingTitles.length === 1 &&
      switched.editingTitles[0] === KR_WAU_TITLE &&
      switched.metricInputs === 4 &&
      switched.displayRows === 2,
    switched,
  );

  // 点标题铅笔：收起 KR 编辑态，只剩标题输入。
  await clickEditTarget(page, 'title');
  const titleOnly = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      titleInputs: editor.querySelectorAll('input.okr-editor-title').length,
      inputs: editor.querySelectorAll('input').length,
      selects: editor.querySelectorAll('select').length,
      textareas: editor.querySelectorAll('textarea').length,
      editingRows: editor.querySelectorAll('.okr-kr--editing').length,
      titlePencil: editor.querySelectorAll('[data-edit-target="title"]').length,
    };
  `);
  check(
    flow,
    '点标题铅笔：只出现标题输入，KR 编辑态与其余控件全部收起',
    titleOnly.titleInputs === 1 &&
      titleOnly.inputs === 1 &&
      titleOnly.selects === 0 &&
      titleOnly.textareas === 0 &&
      titleOnly.editingRows === 0 &&
      titleOnly.titlePencil === 0,
    titleOnly,
  );

  // 反过来再点 KR 铅笔：标题输入收起，仍然只有一处编辑目标（跨类型也互斥）。
  await clickEditTarget(page, `kr:${KR_WAU}`);
  const backToKr = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      titleInputs: editor.querySelectorAll('input.okr-editor-title').length,
      editingRows: editor.querySelectorAll('.okr-kr--editing').length,
      editingTitle: document.querySelector('.okr-kr--editing .okr-kr-title-input')?.value ?? null,
      metricInputs: editor.querySelectorAll('.okr-metric-input').length,
    };
  `);
  check(
    flow,
    '再点 KR 铅笔：标题输入收起，目标级字段与 KR 共用同一个编辑目标',
    backToKr.titleInputs === 0 &&
      backToKr.editingRows === 1 &&
      backToKr.editingTitle === KR_WAU_TITLE &&
      backToKr.metricInputs === 4,
    backToKr,
  );

  // 行内「完成」按钮收起编辑态，回到纯展示。
  await page.eval(`
    const row = document.querySelector('.okr-kr--editing');
    const button = [...row.querySelectorAll('button')].find((el) => el.textContent.trim() === '完成');
    if (!button) throw new Error('done button missing');
    button.click();
    return true;
  `);
  await sleep(300);
  const afterDone = await progressiveSnapshot(page);
  check(
    flow,
    '行内「完成」收起编辑态，回到 0 输入控件',
    afterDone.inputs === 0 &&
      afterDone.selects === 0 &&
      afterDone.textareas === 0 &&
      afterDone.editingRows === 0 &&
      afterDone.pencils === DISPLAY_PENCILS,
    afterDone,
  );

  // 「新增关键结果」是一个按钮点开输入，不是常驻输入框。
  await clickEditTarget(page, 'add-kr');
  const addKrOpen = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      addInput: editor.querySelectorAll('.okr-add-kr-input').length,
      inputs: editor.querySelectorAll('input').length,
      trigger: editor.querySelectorAll('[data-edit-target="add-kr"]').length,
      focused: document.activeElement?.classList.contains('okr-add-kr-input') ?? false,
    };
  `);
  check(
    flow,
    '「新增关键结果」按钮点开才出现输入框（触发器同时消失）',
    addKrOpen.addInput === 1 && addKrOpen.inputs === 1 && addKrOpen.trigger === 0 && addKrOpen.focused === true,
    addKrOpen,
  );
  await page.insertText('新增一条验收 KR');
  await pressEnter(page);
  await page.waitFor(
    `document.querySelectorAll('.okr-kr').length === 4 && !document.querySelector('.okr-add-kr-input')`,
    { label: 'new KR created' },
  );
  await sleep(300);
  await waitSaved(page);
  const addedKr = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const kr = ws.items.find((item) => item.kind === 'keyresult' && item.title === '新增一条验收 KR');
    const editor = document.querySelector('.okr-editor');
    return {
      stored: kr ? { parentId: kr.parentId, status: kr.status, confidence: kr.okr?.confidence ?? null } : null,
      krRows: editor.querySelectorAll('.okr-kr').length,
      inputs: editor.querySelectorAll('input').length,
      pencils: editor.querySelectorAll('.okr-edit-pencil').length,
      trigger: editor.querySelectorAll('[data-edit-target="add-kr"]').length,
    };
  `);
  check(
    flow,
    '回车创建 KR（挂在该目标下、默认信心 5）并回到展示态',
    addedKr.stored?.parentId === OBJ &&
      addedKr.stored?.status === 'active' &&
      addedKr.stored?.confidence === 5 &&
      addedKr.krRows === 4 &&
      addedKr.inputs === 0 &&
      addedKr.pencils === DISPLAY_PENCILS + 1 &&
      addedKr.trigger === 1,
    addedKr,
  );

  // 执行项 N>0：通过 KR 行「关联执行项」真实关联一条已完成行动。
  // 新行为下这条按钮只在 KR 编辑态里出现，所以先点开该行铅笔。
  await clickEditTarget(page, `kr:${KR_NPS}`);
  // 先把全局搜索清空：LinkItemsDialog 会用 ui.search 预填筛选词（此处为 NPS）。
  await page.click('input[aria-label="搜索工作区"]');
  await page.selectAll();
  await page.pressKey('Backspace', { code: 'Backspace', vk: 8 });
  await page.waitFor(
    `document.querySelector('input[aria-label="搜索工作区"]')?.value === ''`,
    { label: 'search cleared' },
  );
  await sleep(250);
  const linked = await page.eval(`
    const row = document.querySelector('.okr-kr--editing');
    const button = [...row.querySelectorAll('button')].find((el) => el.textContent.trim().startsWith('关联执行项'));
    if (!button) return false;
    button.click();
    return true;
  `);
  check(flow, '打开 KR「关联执行项」弹窗（编辑态内）', linked === true);
  await page.waitFor(`!!document.querySelector('[role="dialog"][aria-label="关联执行项"]')`, { label: 'link dialog' });
  await sleep(300);
  await page.click('input[aria-label="关联「需求梳理与竞品盘点」"]');
  await sleep(200);
  await page.eval(`
    const button = [...document.querySelectorAll('[role="dialog"] .modal-footer button')]
      .find((el) => el.textContent.trim() === '关联所选');
    if (!button) throw new Error('confirm link button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!document.querySelector('[role="dialog"][aria-label="关联执行项"]')`, { label: 'link dialog closed' });
  await sleep(500);
  const execAfter = await page.eval(`
    return {
      exec: document.querySelector('.okr-editor-exec-line')?.textContent.replace(/\\s+/g, ' ').trim() ?? null,
      executionRows: document.querySelectorAll('.okr-exec-list li').length,
    };
  `);
  check(
    flow,
    '关联 1 条已完成执行项后概览为「关联执行项 1 · 已完成 1」',
    execAfter.exec === '关联执行项 1 · 已完成 1',
    execAfter,
  );
  check(flow, '2b 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
  await page.screenshot(`${OUT}/2b-editor-view.png`);
}

/* ================================================================ 2c ==== */
async function flowC(page) {
  const flow = '2c-persistence';
  const NEW_TITLE = '让新用户在第一周就爱上织理（编辑验收）';
  const NEW_NOTES = '验收备注：这条 notes 在停止输入 600ms 内切回列表。';
  await clearAndReset(page, 'okr');
  await openEditor(page);

  // 1) 标题：点标题铅笔 → 输入 → Enter（失焦提交）
  await clickEditTarget(page, 'title');
  await page.waitFor(`!!document.querySelector('input.okr-editor-title')`, { label: 'title input' });
  await page.selectAll();
  await page.insertText(NEW_TITLE);
  await pressEnter(page);
  await page.waitFor(
    `document.querySelector('.okr-editor-title')?.textContent.trim() === ${JSON.stringify(NEW_TITLE)}`,
    { label: 'title committed' },
  );
  await waitSaved(page);
  const titleState = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return {
      title: ws.items.find((item) => item.id === ${JSON.stringify(OBJ)})?.title ?? null,
      inputs: document.querySelector('.okr-editor').querySelectorAll('input').length,
    };
  `);
  check(
    flow,
    '标题修改写入 localStorage，回车后收起标题输入',
    titleState.title === NEW_TITLE && titleState.inputs === 0,
    titleState,
  );

  // 2) KR 当前值：点 KR 铅笔 → 600ms 防抖提交
  await clickEditTarget(page, `kr:${KR_NPS}`);
  await page.waitFor(`!!document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')`, {
    label: 'metric input present',
  });
  await page.typeInto('input[aria-label="NPS 从 42 提升到 60 指标当前值"]', '55');
  await page.waitFor(
    `(() => { const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)})); return ws.items.find((i) => i.id === 'kr_nps')?.okr?.metric?.current === 55; })()`,
    { label: 'metric current committed', timeout: 6000 },
  );
  await waitSaved(page);
  const metricState = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const kr = ws.items.find((item) => item.id === 'kr_nps');
    return { current: kr?.okr?.metric?.current ?? null, start: kr?.okr?.metric?.start ?? null, target: kr?.okr?.metric?.target ?? null };
  `);
  check(flow, 'KR 当前值 47 → 55 写入 localStorage', metricState.current === 55 && metricState.start === 42 && metricState.target === 60, metricState);

  // 3) notes：点备注铅笔（自动结束上面的 KR 编辑态）→ 输入后 600ms 内立刻返回列表
  await clickEditTarget(page, 'notes');
  const notesMutual = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      textareas: editor.querySelectorAll('textarea').length,
      editingRows: editor.querySelectorAll('.okr-kr--editing').length,
      focused: document.activeElement?.classList.contains('okr-editor-notes') ?? false,
    };
  `);
  check(
    flow,
    '点备注铅笔：自动结束 KR 编辑态，只剩备注文本域',
    notesMutual.textareas === 1 && notesMutual.editingRows === 0 && notesMutual.focused === true,
    notesMutual,
  );
  await page.selectAll();
  const typedAt = Date.now();
  await page.insertText(NEW_NOTES);
  const backAt = await backToList(page);
  const switchMs = Date.now() - typedAt;
  check(flow, '在 600ms 内切回列表（实测切换耗时 < 600ms）', switchMs < 600, { switchMs, backAtFrame: backAt });
  await waitSaved(page);
  const notesState = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return ws.items.find((item) => item.id === ${JSON.stringify(OBJ)})?.notes ?? null;
  `);
  check(flow, 'notes 在 600ms 内切走仍写入 localStorage（未丢字）', notesState === NEW_NOTES, { notes: notesState });

  // 4) 重新进入编辑视图：默认仍然是零输入控件，逐字段点开才看到新值
  await openEditor(page);
  const reopenedIdle = await progressiveSnapshot(page);
  check(
    flow,
    '重新进入编辑视图：仍是零输入控件的展示态',
    reopenedIdle.inputs === 0 && reopenedIdle.selects === 0 && reopenedIdle.textareas === 0,
    reopenedIdle,
  );
  const reopenedTitle = await page.eval(`return document.querySelector('.okr-editor-title')?.textContent.trim() ?? null;`);
  await clickEditTarget(page, 'notes');
  const reopenedNotes = await page.eval(`
    return {
      value: document.querySelector('textarea.okr-editor-notes')?.value ?? null,
      display: document.querySelector('.okr-editor-notes-text')?.textContent.trim() ?? null,
    };
  `);
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(250);
  const notesAfterEscape = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    return {
      inEditor: Boolean(editor),
      textareas: editor ? editor.querySelectorAll('textarea').length : -1,
      display: document.querySelector('.okr-editor-notes-text')?.textContent.trim() ?? null,
    };
  `);
  await clickEditTarget(page, `kr:${KR_NPS}`);
  const reopenedMetric = await page.eval(`
    return document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')?.value ?? null;
  `);
  const reopenedExec = await page.eval(`
    return document.querySelector('.okr-editor-exec-line')?.textContent.replace(/\\s+/g, ' ').trim() ?? null;
  `);
  check(
    flow,
    '重新进入编辑视图：标题 / notes / KR 当前值都正确',
    reopenedTitle === NEW_TITLE && reopenedNotes.value === NEW_NOTES && reopenedMetric === '55',
    { reopenedTitle, reopenedNotes, reopenedMetric, reopenedExec },
  );
  check(
    flow,
    '备注 Esc 取消只收起编辑态（值已提交、仍留在编辑视图）',
    notesAfterEscape.inEditor === true &&
      notesAfterEscape.textareas === 0 &&
      notesAfterEscape.display === NEW_NOTES,
    notesAfterEscape,
  );

  // 5) 刷新后仍然保留
  await page.reload({ route: 'okr' });
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'list after reload' });
  await sleep(500);
  await openEditor(page);
  const afterReloadTitle = await page.eval(`return document.querySelector('.okr-editor-title')?.textContent.trim() ?? null;`);
  await clickEditTarget(page, 'notes');
  const afterReloadNotes = await page.eval(`return document.querySelector('textarea.okr-editor-notes')?.value ?? null;`);
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(250);
  await clickEditTarget(page, `kr:${KR_NPS}`);
  const afterReload = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const obj = ws.items.find((item) => item.id === ${JSON.stringify(OBJ)});
    const kr = ws.items.find((item) => item.id === 'kr_nps');
    return {
      metric: document.querySelector('input[aria-label="NPS 从 42 提升到 60 指标当前值"]')?.value ?? null,
      storedTitle: obj?.title ?? null,
      storedNotes: obj?.notes ?? null,
      storedCurrent: kr?.okr?.metric?.current ?? null,
    };
  `);
  check(
    flow,
    '刷新后标题 / notes / KR 当前值保留（DOM + 存储）',
    afterReloadTitle === NEW_TITLE &&
      afterReloadNotes === NEW_NOTES &&
      afterReload.metric === '55' &&
      afterReload.storedTitle === NEW_TITLE &&
      afterReload.storedNotes === NEW_NOTES &&
      afterReload.storedCurrent === 55,
    { afterReloadTitle, afterReloadNotes, ...afterReload },
  );
  check(flow, '2c 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
  await page.screenshot(`${OUT}/2c-persistence.png`);
}

/* ================================================================ 2d ==== */
async function flowD(page) {
  const flow = '2d-escape-focus-other';
  const SECOND_TITLE = '第二个目标：把激活率做成可复用的增长手册';
  await clearAndReset(page, 'okr');
  await openEditor(page);

  const focusInEditor = await page.eval(`
    return {
      active: document.activeElement?.textContent?.trim() ?? null,
      isBack: [...document.querySelectorAll('.okr-editor-bar button')].includes(document.activeElement),
    };
  `);
  check(flow, '进入编辑视图后焦点落在「返回目标列表」', focusInEditor.isBack === true, focusInEditor);

  /* ---------- Esc 两段语义：先收起编辑目标（并回退草稿），再返回列表 ---------- */
  await clickEditTarget(page, 'title');
  const titleBeforeEsc = await page.eval(`
    const input = document.querySelector('input.okr-editor-title');
    return { value: input?.value ?? null, focused: document.activeElement === input };
  `);
  await page.selectAll();
  await page.insertText('这段标题不应该被提交');
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await sleep(300);
  const firstEsc = await page.eval(`
    const editor = document.querySelector('.okr-editor');
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return {
      inEditor: Boolean(editor),
      inputs: editor ? editor.querySelectorAll('input').length : -1,
      title: document.querySelector('.okr-editor-title')?.textContent.trim() ?? null,
      storedTitle: ws.items.find((item) => item.id === ${JSON.stringify(OBJ)})?.title ?? null,
      focusTarget: document.activeElement?.getAttribute('data-edit-target') ?? null,
    };
  `);
  check(
    flow,
    '第一下 Esc：字段内取消（回退草稿）并收起编辑态，仍留在编辑视图',
    firstEsc.inEditor === true &&
      firstEsc.inputs === 0 &&
      firstEsc.title === OBJ_TITLE &&
      firstEsc.storedTitle === OBJ_TITLE,
    { titleBeforeEsc, ...firstEsc },
  );
  check(
    flow,
    '收起编辑态后焦点回到该字段的铅笔（data-edit-target=title）',
    firstEsc.focusTarget === 'title',
    { focusTarget: firstEsc.focusTarget },
  );

  // 第二下 Esc 才返回列表。
  await page.pressKey('Escape', { code: 'Escape', vk: 27 });
  await page.waitFor(`!document.querySelector('.okr-editor')`, { label: 'escape back to list' });
  await page.waitFor(`!!document.querySelector('.okr-objectives')`, { label: 'list restored' });
  await sleep(350);
  const focusBack = await page.eval(`
    const el = document.activeElement;
    return {
      isEditButton: el instanceof HTMLElement && el.hasAttribute('data-edit-objective'),
      id: el?.getAttribute('data-edit-objective') ?? null,
      ariaLabel: el?.getAttribute('aria-label') ?? null,
    };
  `);
  check(
    flow,
    'Esc 返回列表，焦点回到该卡片的编辑按钮',
    focusBack.isEditButton && focusBack.id === OBJ && focusBack.ariaLabel === `编辑目标：${OBJ_TITLE}`,
    focusBack,
  );

  // 通过「新建目标」再建一个目标，验证进入另一个目标内容正确。
  await page.eval(`
    const button = [...document.querySelectorAll('.okr-header-actions button')].find((el) => el.textContent.trim() === '新建目标');
    if (!button) throw new Error('new objective button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'new objective dialog' });
  await sleep(250);
  await page.typeInto('#okr-new-objective-title', SECOND_TITLE);
  await page.eval(`
    const button = [...document.querySelectorAll('[role="dialog"] .modal-footer button')].find((el) => el.textContent.trim() === '创建目标');
    if (!button) throw new Error('create objective button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!document.querySelector('[role="dialog"]')`, { label: 'dialog closed' });
  await page.waitFor(`document.querySelectorAll('.okr-objective').length === 2`, { label: 'two objective cards' });
  await sleep(400);
  const second = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const objective = ws.items.find((item) => item.kind === 'objective' && item.title === ${JSON.stringify(SECOND_TITLE)});
    return { id: objective?.id ?? null, title: objective?.title ?? null, period: objective?.okr?.period ?? null };
  `);
  check(flow, '新建第二个目标（同季度）', Boolean(second.id) && second.period === '2026-Q4', second);

  await openEditor(page, second.id);
  const other = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return {
      title: document.querySelector('.okr-editor-title')?.textContent.trim() ?? null,
      crumb: document.querySelector('.okr-editor-crumb')?.textContent.trim() ?? null,
      krRows: document.querySelectorAll('.okr-kr').length,
      krEmpty: document.querySelector('.okr-editor-kr-empty')?.textContent.trim() ?? null,
      exec: document.querySelector('.okr-editor-exec-line')?.textContent.replace(/\\s+/g, ' ').trim() ?? null,
      storedKrs: ws.items.filter((item) => item.kind === 'keyresult' && item.parentId === ${JSON.stringify(second.id)}).length,
    };
  `);
  check(
    flow,
    '进入另一个目标：标题 / 0 个 KR / 执行项 0 正确',
    other.title === SECOND_TITLE &&
      other.krRows === 0 &&
      other.storedKrs === 0 &&
      other.exec === '关联执行项 0 · 已完成 0' &&
      Boolean(other.krEmpty),
    other,
  );
  check(flow, '2d 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
  await page.screenshot(`${OUT}/2d-second-objective.png`);
}

/* ================================================================ 2e ==== */
async function flowE(page) {
  const flow = '2e-delete-move';

  // ---- 删除目标 ----
  await clearAndReset(page, 'okr');
  await openEditor(page);
  await page.eval(`
    const button = [...document.querySelectorAll('.okr-editor-actions button')].find((el) => el.textContent.trim() === '删除目标');
    if (!button) throw new Error('delete button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'delete confirm dialog' });
  await sleep(250);
  const confirmText = await page.eval(`
    const dialog = document.querySelector('[role="dialog"]');
    return {
      title: dialog?.querySelector('.modal-title')?.textContent.trim() ?? null,
      description: dialog?.querySelector('.okr-dialog-text')?.textContent.trim() ?? null,
      confirm: [...dialog.querySelectorAll('.modal-footer button')].map((el) => el.textContent.trim()),
    };
  `);
  check(flow, '删除前出现确认弹窗（含目标名与 KR 数）', /删除目标/.test(confirmText.title ?? '') && /3 个关键结果/.test(confirmText.description ?? ''), confirmText);
  await page.eval(`
    const button = [...document.querySelectorAll('[role="dialog"] .modal-footer button')].find((el) => el.textContent.trim() === '删除目标');
    if (!button) throw new Error('confirm delete button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!document.querySelector('.okr-editor')`, { label: 'editor closed after delete' });
  await page.waitFor(`!document.querySelector('[role="dialog"]')`, { label: 'dialog closed after delete' });
  await sleep(600);
  const afterDelete = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    return {
      cards: document.querySelectorAll('.okr-objective').length,
      emptyTitle: document.querySelector('.okr-empty .empty-state-title')?.textContent.trim() ?? null,
      emptyText: (document.querySelector('.okr-empty')?.innerText || '').trim().slice(0, 120),
      storedObjective: ws.items.some((item) => item.id === ${JSON.stringify(OBJ)}),
      storedKrs: ws.items.filter((item) => item.parentId === ${JSON.stringify(OBJ)}).length,
      periodbar: Boolean(document.querySelector('.okr-periodbar')),
    };
  `);
  check(
    flow,
    '删除目标 → 回到列表且目标与 KR 消失',
    afterDelete.cards === 0 && afterDelete.storedObjective === false && afterDelete.storedKrs === 0 && afterDelete.periodbar === true,
    afterDelete,
  );
  check(flow, '删除后列表展示空态', afterDelete.emptyText.includes('本季度还没有目标'), { emptyText: afterDelete.emptyText });

  // ---- 移动到其他季度 ----
  await clearAndReset(page, 'okr');
  await openEditor(page);
  await page.eval(`
    const button = [...document.querySelectorAll('.okr-editor-actions button')].find((el) => el.textContent.trim() === '移动到其他季度');
    if (!button) throw new Error('move button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!!document.querySelector('[role="dialog"]')`, { label: 'quarter dialog' });
  await sleep(300);
  await setSelect(page, '选择年份', '2026');
  await page.eval(`
    const dialog = document.querySelector('[role="dialog"]');
    const button = [...dialog.querySelectorAll('.segmented-item')].find((el) => el.textContent.trim() === 'Q1');
    if (!button) throw new Error('Q1 option missing');
    button.click();
    return true;
  `);
  await sleep(200);
  const dialogHint = await page.text('[role="dialog"] .okr-dialog-hint');
  await page.eval(`
    const button = [...document.querySelectorAll('[role="dialog"] .modal-footer button')].find((el) => el.textContent.trim() === '移动');
    if (!button) throw new Error('confirm move button missing');
    button.click();
    return true;
  `);
  await page.waitFor(`!document.querySelector('[role="dialog"]')`, { label: 'quarter dialog closed' });
  await sleep(700);
  const afterMove = await page.eval(`
    const ws = JSON.parse(localStorage.getItem(${JSON.stringify(KEY)}));
    const obj = ws.items.find((item) => item.id === ${JSON.stringify(OBJ)});
    const krs = ws.items.filter((item) => item.kind === 'keyresult' && item.parentId === ${JSON.stringify(OBJ)});
    return {
      editorStillOpen: Boolean(document.querySelector('.okr-editor')),
      h1: document.querySelector('h1')?.textContent ?? null,
      crumb: document.querySelector('.okr-editor-crumb')?.textContent.trim() ?? null,
      storedPeriod: obj?.okr?.period ?? null,
      krPeriods: [...new Set(krs.map((kr) => kr.okr?.period))],
      objectiveCards: document.querySelectorAll('.okr-objective').length,
    };
  `);
  check(flow, '移动后仍留在编辑视图', afterMove.editorStillOpen === true && afterMove.h1 === 'OKR', afterMove);
  check(flow, '移动后面包屑季度更新为 2026 Q1', afterMove.crumb === '2026 Q1 · 目标编辑', { crumb: afterMove.crumb, hint: dialogHint });
  check(
    flow,
    '目标与全部 KR 的季度一起改为 2026-Q1（存储）',
    afterMove.storedPeriod === '2026-Q1' && afterMove.krPeriods.length === 1 && afterMove.krPeriods[0] === '2026-Q1',
    { storedPeriod: afterMove.storedPeriod, krPeriods: afterMove.krPeriods },
  );

  await backToList(page);
  const listAfterMove = await page.eval(`
    const chip = document.querySelector('.okr-period-chip.is-active');
    return {
      activePeriod: chip?.querySelector('span')?.textContent.trim() ?? null,
      pressed: chip?.getAttribute('aria-pressed') ?? null,
      cards: [...document.querySelectorAll('.okr-objective')].map((el) => el.getAttribute('aria-label')),
    };
  `);
  check(
    flow,
    '返回列表后停在新季度且能看到该目标',
    listAfterMove.activePeriod === '2026 Q1' &&
      listAfterMove.pressed === 'true' &&
      listAfterMove.cards.includes(`目标：${OBJ_TITLE}`),
    listAfterMove,
  );
  check(flow, '2e 期间 console error = 0', consoleErrors(page).length === 0, { errors: consoleErrors(page).map((e) => e.text.slice(0, 160)) });
  await page.screenshot(`${OUT}/2e-after-move.png`);

  // 2f：无法从 UI 构造不存在 id，按验收说明跳过（单测覆盖）。
  check(flow, '2f 空态：跳过（无法从 UI 触发；okrEditor.test.ts 已覆盖缺失 id）', true, {
    skipped: true,
    reason: 'editingId 只能由卡片按钮写入真实目标 id；不存在 id 的空态由 resolveEditorObjective 单测覆盖',
  });
}

/* ================================================================ run ==== */
async function main() {
  mkdirSync(OUT, { recursive: true });
  await withPage(async (page) => {
    await page.setViewport(1440, 900);
    for (const flow of [flowA, flowB, flowC, flowD, flowE]) {
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

  writeFileSync(`${OUT}/report.json`, JSON.stringify({ baseUrl: BASE_URL, results }, null, 2));
  const flows = [...new Set(results.map((entry) => entry.flow))];
  console.log('\n=== OKR EDITOR ACCEPTANCE SUMMARY ===');
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
  console.error('OKR EDITOR ACCEPTANCE FAILED:', error);
  process.exit(1);
});
