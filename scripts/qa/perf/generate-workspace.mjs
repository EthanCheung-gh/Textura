/**
 * 生成 10,000 条目的性能基准工作区（写入 /tmp，不落项目目录）。
 *
 * 分布（合计 10,000）：
 *   1   objective + 300 KR
 *   1   SOP + 300 step（链式 flow 边）
 *   1   project + 2,000 带日期 action（甘特 2,000 行）
 *   1,500 next action（GTD 下一步）
 *   1,000 inbox / 500 waiting / 300 someday
 *   其余 note(dropped) 补齐
 */
import { mkdirSync, writeFileSync } from 'node:fs';

const now = new Date().toISOString();
const iso = (daysAgo) => new Date(Date.now() - daysAgo * 86400000).toISOString();
const dayKey = (offset) => {
  const d = new Date(Date.UTC(2026, 0, 1));
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};

const items = [];
const edges = [];
const areas = [
  { id: 'area_perf_product', name: '产品', color: '#C0663A', order: 0 },
  { id: 'area_perf_ops', name: '运营', color: '#4F7A52', order: 1 },
  { id: 'area_perf_personal', name: '个人', color: '#4A6F8F', order: 2 },
];
const areaIds = areas.map((area) => area.id);

let order = 0;
const push = (item) => {
  items.push({
    notes: '',
    parentId: null,
    order: order++,
    tags: [],
    areaId: areaIds[items.length % 3],
    createdAt: now,
    updatedAt: now,
    completedAt: null,
    ...item,
  });
};

// 1 + 300 OKR
push({ id: 'perf_obj', kind: 'objective', title: '性能基准目标', status: 'active', okr: { period: '2026-Q4', confidence: 5 } });
for (let index = 0; index < 300; index += 1) {
  push({
    id: `perf_kr_${index}`,
    kind: 'keyresult',
    title: `性能 KR ${index + 1}`,
    parentId: 'perf_obj',
    status: 'active',
    okr: {
      period: '2026-Q4',
      confidence: 5,
      metric: { start: 0, target: 100, current: index % 100, unit: '%' },
      krOwner: '性能组',
    },
  });
  edges.push({ id: `perf_edge_okr_${index}`, from: 'perf_obj', to: `perf_kr_${index}`, type: 'okr', label: '' });
}

// 1 SOP + 300 steps（链式）
push({ id: 'perf_sop', kind: 'sop', title: '性能基准流程', status: 'active', sop: { nodeType: 'action', canvas: { x: 0, y: 0 }, checklist: [] } });
for (let index = 0; index < 300; index += 1) {
  push({
    id: `perf_step_${index}`,
    kind: 'step',
    title: `流程步骤 ${index + 1}`,
    parentId: 'perf_sop',
    status: 'next',
    sop: {
      nodeType: index === 0 ? 'start' : index === 299 ? 'end' : 'action',
      canvas: { x: 40 + (index % 12) * 240, y: 80 + Math.floor(index / 12) * 150 },
      checklist: [
        { id: `perf_step_${index}_c1`, text: '检查项 A', done: index % 2 === 0 },
        { id: `perf_step_${index}_c2`, text: '检查项 B', done: false },
      ],
      owner: '性能组',
      durationMin: 5 + (index % 30),
    },
  });
  if (index > 0) {
    edges.push({ id: `perf_flow_${index}`, from: `perf_step_${index - 1}`, to: `perf_step_${index}`, type: 'flow', label: '' });
  }
}

// 1 project + 2,000 带日期 action（甘特）
push({ id: 'perf_project', kind: 'project', title: '性能基准项目', status: 'active', gantt: { start: dayKey(0), end: dayKey(760), progress: 30 } });
for (let index = 0; index < 2000; index += 1) {
  const start = dayKey(index % 760);
  const end = dayKey(Math.min(760, (index % 760) + 1 + (index % 7)));
  push({
    id: `perf_gantt_${index}`,
    kind: 'action',
    title: `甘特任务 ${index + 1}`,
    parentId: 'perf_project',
    status: index % 11 === 0 ? 'done' : index % 3 === 0 ? 'active' : 'scheduled',
    completedAt: index % 11 === 0 ? iso(1 + (index % 30)) : null,
    gantt: { start, end, progress: index % 11 === 0 ? 100 : index % 101 },
  });
  if (index > 0 && index % 250 === 0) {
    edges.push({ id: `perf_dep_${index}`, from: `perf_gantt_${index}`, to: `perf_gantt_${index - 1}`, type: 'depends', label: '依赖' });
  }
}

// 1,500 next action（GTD 下一步，无日期）
for (let index = 0; index < 1500; index += 1) {
  push({
    id: `perf_next_${index}`,
    kind: 'action',
    title: `下一步行动 ${index + 1}`,
    status: 'next',
    gtd: { capturedAt: iso(index % 20), clarified: true, context: ['电脑', '电话', '会议', '外出'][index % 4], energy: ['low', 'medium', 'high'][index % 3] },
  });
}

// 1,000 inbox / 500 waiting / 300 someday
for (let index = 0; index < 1000; index += 1) {
  push({
    id: `perf_inbox_${index}`,
    kind: 'action',
    title: `收件箱条目 ${index + 1}`,
    status: 'inbox',
    gtd: { capturedAt: iso(index % 30), clarified: false, context: index % 2 ? '电脑' : undefined, twoMinuteCandidate: index % 9 === 0 },
  });
}
for (let index = 0; index < 500; index += 1) {
  push({
    id: `perf_wait_${index}`,
    kind: 'action',
    title: `等待事项 ${index + 1}`,
    status: 'waiting',
    gtd: { capturedAt: iso(index % 30), clarified: true, waitingFor: `同事 ${index % 12}` },
  });
}
for (let index = 0; index < 300; index += 1) {
  push({
    id: `perf_someday_${index}`,
    kind: 'action',
    title: `将来事项 ${index + 1}`,
    status: 'someday',
    gtd: { capturedAt: iso(index % 60), clarified: true },
  });
}

// 补齐到 10,000：dropped note（不进入任何 GTD 列表）
const TARGET = 10000;
let filler = 0;
while (items.length < TARGET) {
  push({ id: `perf_note_${filler}`, kind: 'note', title: `归档笔记 ${filler + 1}`, status: 'dropped' });
  filler += 1;
}

const workspace = { version: 1, items, edges, areas, runs: [], updatedAt: now };
if (items.length !== TARGET) throw new Error(`条目数 ${items.length} != ${TARGET}`);

const dir = '/tmp/textura-perf';
mkdirSync(dir, { recursive: true });
const path = `${dir}/workspace-10k.json`;
const json = JSON.stringify(workspace);
writeFileSync(path, json);

const counts = items.reduce((acc, item) => {
  acc.kind[item.kind] = (acc.kind[item.kind] ?? 0) + 1;
  acc.status[item.status] = (acc.status[item.status] ?? 0) + 1;
  return acc;
}, { kind: {}, status: {} });

console.log(
  JSON.stringify(
    {
      path,
      bytes: Buffer.byteLength(json),
      items: items.length,
      edges: edges.length,
      areas: areas.length,
      kinds: counts.kind,
      statuses: counts.status,
      ganttDated: items.filter((item) => item.gantt?.start || item.gantt?.end).length,
      nextActions: items.filter((item) => item.status === 'next' && (item.kind === 'action' || item.kind === 'project')).length,
      sopSteps: items.filter((item) => item.kind === 'step').length,
    },
    null,
    2,
  ),
);
