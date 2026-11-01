/**
 * 聚合层性能回归：10 000 条目工作区下生成报告草稿。
 *
 * 预算（与 Product 契约一致）：`buildReportSections` < 100ms、`collectFacts` < 50ms、
 * 周+月连算 < 200ms。构造方式沿用现有 perf 测试（sop/perf.test.ts、
 * gtd/gtdListPerf.test.ts）：直接造 `Item[]` 字面量、不走 store。
 *
 * ## 测量口径（`measureBest`）
 * 1. **预热 1 次**：把 `getWorkspaceIndex` 的 WeakMap 索引建起来、让 JIT 走完解释执行，
 *    等价页面层「同一份 workspace 连续重算多节 / 反复点重算」的真实调用形态。
 * 2. **连续采样 5 次，取最小值**再断言。
 *    预算衡量的是「这段纯计算自己花多少 CPU」，不是墙钟 SLA：`npm test` 默认并行跑
 *    34 个测试文件，邻居进程一起抢核时单次采样会被拉高 2~3 倍（页面层实测 loadavg≈6
 *    时 `collectFacts` 单次采样冲到 58.2 / 74.2ms，而单文件跑稳定在 24ms 以下）。
 *    最小值是受调度噪声污染最小的估计量；反过来，若代码真退化（例如日键换算退回
 *    `date-fns.parseISO`，10k 条目要转 3~4 万次，实测会劣化到 150ms 量级），
 *    5 次采样会**每一次**都超标，断言照样红——取最小值不会掩盖真实回归。
 * 3. 不靠放宽阈值掩盖问题：阈值仍是契约预算本身，没有改成几百毫秒。
 *
 * ## 机器基线（Linux / Node 24 / AMD Ryzen 7，`npm test` 默认并行 36 个文件，取最小值）
 * 连续 5 次 `npm test` 的实测分布：
 * - `collectFacts`（月报窗口）6.9 / 7.1 / 9.3 / 11.3 / 18.2ms → 预算 50ms 的 14%~36%
 * - `buildReportSections`（季报 7 节）14.4 / 6.6 / 7.2 / 7.5 / 3.7ms → 预算 100ms 的 4%~14%
 * - 周+月连算 8.2 / 19.5 / 17.7 / 17.8 / 14.4ms → 预算 200ms 的 4%~10%
 * 最坏观测值仍只用掉预算的 36%（≈2.7 倍余量），阈值没有放宽。
 */
import { format } from 'date-fns';
import { describe, expect, it } from 'vitest';
import type { Area, Item, SopRunEntry, Workspace } from '../../core/model';
import { buildReportSections } from './draft';
import { collectFacts } from './facts';

const BASE = '2026-01-01T00:00:00.000Z';
const NOW = new Date(2026, 11, 31, 9, 0, 0);

function dayKey(offset: number): string {
  return format(new Date(2026, 0, 1 + offset), 'yyyy-MM-dd');
}

function stamp(offset: number, hour = 10): string {
  return new Date(2026, 0, 1 + offset, hour).toISOString();
}

function item(seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: BASE,
    updatedAt: BASE,
    completedAt: null,
    ...seed,
  };
}

function buildLargeWorkspace(): Workspace {
  const areas: Area[] = Array.from({ length: 20 }, (_, index) => ({
    id: `area_${index}`,
    name: `领域 ${index}`,
    color: '#C0663A',
    order: index,
  }));

  const items: Item[] = [];
  let order = 0;
  const push = (seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>) => {
    items.push(item({ ...seed, order: order++ }));
  };

  // 100 个目标（季报 okr 节会读它们）
  for (let index = 0; index < 100; index += 1) {
    push({
      id: `obj_${index}`,
      kind: 'objective',
      title: `目标 ${index}`,
      areaId: `area_${index % 20}`,
      okr: { period: '2026-Q4', confidence: 7 },
    });
  }

  // 300 个 KR：一半带 metric，一半只靠完成状态
  for (let index = 0; index < 300; index += 1) {
    const hasMetric = index % 2 === 0;
    push({
      id: `kr_${index}`,
      kind: 'keyresult',
      title: `关键结果 ${index}`,
      parentId: `obj_${index % 100}`,
      areaId: `area_${index % 20}`,
      status: index % 7 === 0 ? 'done' : 'active',
      completedAt: index % 7 === 0 ? stamp(index % 365) : null,
      okr: {
        period: '2026-Q4',
        confidence: (index % 10) + 1,
        metric: hasMetric
          ? { start: 0, target: 100, current: index % 101, unit: '%' }
          : undefined,
      },
    });
  }

  // 3 000 条已完成 action，完成时间摊在全年
  for (let index = 0; index < 3000; index += 1) {
    push({
      id: `done_${index}`,
      kind: 'action',
      title: `已完成行动 ${index}`,
      status: 'done',
      areaId: `area_${index % 20}`,
      completedAt: stamp(index % 365),
      updatedAt: stamp(index % 365),
      gantt: { start: dayKey(index % 360), end: dayKey((index % 360) + 2), progress: 100 },
    });
  }

  // 2 000 条未完成 action，截止日摊在全年（一部分因此算超期）
  for (let index = 0; index < 2000; index += 1) {
    push({
      id: `open_${index}`,
      kind: 'action',
      title: `进行中行动 ${index}`,
      status: index % 2 === 0 ? 'next' : 'active',
      areaId: `area_${index % 20}`,
      updatedAt: stamp(index % 365),
      gantt: { start: dayKey(index % 350), end: dayKey((index % 350) + 3), progress: index % 100 },
    });
  }

  // 1 000 个停滞项目（无子动作、无日期）
  for (let index = 0; index < 1000; index += 1) {
    push({
      id: `stuck_${index}`,
      kind: 'project',
      title: `停滞项目 ${index}`,
      status: 'next',
      areaId: `area_${index % 20}`,
    });
  }

  // 1 000 条等待超 7 天
  for (let index = 0; index < 1000; index += 1) {
    push({
      id: `wait_${index}`,
      kind: 'action',
      title: `等待条目 ${index}`,
      status: 'waiting',
      gtd: { capturedAt: stamp(index % 60), clarified: true, waitingFor: '外部依赖' },
    });
  }

  // 2 000 条下周期到期（2027 年 1 月）
  for (let index = 0; index < 2000; index += 1) {
    push({
      id: `plan_${index}`,
      kind: 'action',
      title: `下月计划 ${index}`,
      status: 'next',
      gantt: { start: '2027-01-01', end: format(new Date(2027, 0, 1 + (index % 28)), 'yyyy-MM-dd'), progress: 0 },
    });
  }

  // 200 条收件箱 + 5 个 SOP / 步骤（run 的标题解析）
  for (let index = 0; index < 200; index += 1) {
    push({
      id: `inbox_${index}`,
      kind: 'note',
      title: `收集 ${index}`,
      status: 'inbox',
      gtd: { capturedAt: stamp(index % 365), clarified: index % 2 === 0 },
    });
  }
  for (let index = 0; index < 5; index += 1) {
    push({ id: `sop_${index}`, kind: 'sop', title: `SOP ${index}` });
    push({ id: `step_${index}`, kind: 'step', title: `步骤 ${index}`, parentId: `sop_${index}` });
  }

  // 390 条将来/想法类笔记（无风险、无完成），把总量凑到 10 000
  for (let index = 0; index < 390; index += 1) {
    push({
      id: `note_${index}`,
      kind: 'note',
      title: `笔记 ${index}`,
      status: 'someday',
      areaId: `area_${index % 20}`,
    });
  }

  const runs: SopRunEntry[] = Array.from({ length: 2000 }, (_, index) => ({
    id: `run_${index}`,
    sopId: `sop_${index % 5}`,
    stepId: `step_${index % 5}`,
    at: stamp(index % 365, 9),
    result: index % 3 === 0 ? ('fail' as const) : index % 5 === 0 ? ('skip' as const) : ('pass' as const),
    note: '',
  }));

  return { version: 1, items, edges: [], areas, runs, updatedAt: BASE };
}

const workspace = buildLargeWorkspace();
const WEEK = '2026-W02';
const MONTH = '2026-01';
const QUARTER = '2026-Q1';

/** 采样次数：5 次取最小值（口径见文件头注释）。 */
const PERF_SAMPLES = 5;

/**
 * 预热 1 次 + 连续采样 `samples` 次，返回**最小值**（毫秒）。
 * 取最小值是为了剔除并行测试邻居造成的调度噪声；真实回归会让每一次采样都超标。
 */
function measureBest(run: () => void, samples: number = PERF_SAMPLES): number {
  run(); // warm-up：建 WeakMap 索引 + JIT 预热
  let best = Number.POSITIVE_INFINITY;
  for (let index = 0; index < samples; index += 1) {
    const started = performance.now();
    run();
    const elapsed = performance.now() - started;
    if (elapsed < best) best = elapsed;
  }
  return best;
}

describe('10 000 条目工作区的报告聚合性能', () => {
  it('工作区规模符合预期', () => {
    expect(workspace.items).toHaveLength(10_000);
    expect(workspace.runs).toHaveLength(2000);
  });

  it('collectFacts < 50ms（预热 1 次 + 5 次采样取最小值）', () => {
    const best = measureBest(() => {
      const facts = collectFacts(workspace, 'month', MONTH, NOW);
      expect(facts.facts.length).toBeGreaterThan(0);
    });
    console.log(`[perf:reports] collectFacts(month) min=${best.toFixed(2)}ms 预算=50ms`);
    expect(best).toBeLessThan(50);
  });

  it('buildReportSections < 100ms（预热 1 次 + 5 次采样取最小值）', () => {
    const best = measureBest(() => {
      const sections = buildReportSections(workspace, 'quarter', QUARTER, NOW);
      expect(sections).toHaveLength(7);
      expect(sections.every((section) => section.body.length > 0)).toBe(true);
    });
    console.log(`[perf:reports] buildReportSections(quarter) min=${best.toFixed(2)}ms 预算=100ms`);
    expect(best).toBeLessThan(100);
  });

  it('周 + 月连算 < 200ms（预热 1 次 + 5 次采样取最小值）', () => {
    const best = measureBest(() => {
      buildReportSections(workspace, 'week', WEEK, NOW);
      buildReportSections(workspace, 'month', MONTH, NOW);
    });
    console.log(`[perf:reports] week+month min=${best.toFixed(2)}ms 预算=200ms`);
    expect(best).toBeLessThan(200);
  });

  it('同一 workspace 重复生成结果稳定（索引只建一次）', () => {
    const first = buildReportSections(workspace, 'week', WEEK, NOW);
    const second = buildReportSections(workspace, 'week', WEEK, NOW);
    expect(second.map((section) => section.body)).toEqual(first.map((section) => section.body));
  });
});
