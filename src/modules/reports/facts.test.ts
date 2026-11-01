import { describe, expect, it } from 'vitest';
import type { Area, Item, SopRunEntry, Workspace } from '../../core/model';
import { collectFacts, collectFactsDetailed, factLine } from './facts';

/** 周期：2026-W45 = 2026-11-02（周一）~ 2026-11-08（周日）；下个周期 2026-W46 = 11-09 ~ 11-15。 */
const PERIOD = '2026-W45';
const NOW = new Date(2026, 10, 9, 9, 0, 0);

const BASE_TIME = new Date(2025, 0, 1, 9, 0, 0).toISOString();

/** 本地时区构造 ISO 时间戳，避免测试依赖跑测机器的时区。 */
function localIso(year: number, month: number, date: number, hour = 12, minute = 0): string {
  return new Date(year, month - 1, date, hour, minute).toISOString();
}

function makeItem(seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: BASE_TIME,
    updatedAt: BASE_TIME,
    completedAt: null,
    ...seed,
  };
}

function makeWorkspace(items: Item[], runs: SopRunEntry[] = [], areas: Area[] = []): Workspace {
  return { version: 1, items, edges: [], areas, runs, updatedAt: BASE_TIME };
}

const AREAS: Area[] = [
  { id: 'area_work', name: '工作', color: '#C0663A', order: 0 },
  { id: 'area_life', name: '生活', color: '#5B7C99', order: 1 },
];

function mainWorkspace(): Workspace {
  const items: Item[] = [
    // 完成：边界日 00:00 / 23:59 都算窗口内
    makeItem({
      id: 'c_in_start',
      kind: 'action',
      title: '完成项 窗口首日 00:00',
      status: 'done',
      areaId: 'area_work',
      completedAt: localIso(2026, 11, 2, 0, 0),
      order: 1,
    }),
    makeItem({
      id: 'c_in_end',
      kind: 'action',
      title: '完成项 窗口末日 23:59',
      status: 'done',
      completedAt: localIso(2026, 11, 8, 23, 59),
      order: 2,
    }),
    makeItem({
      id: 'c_out_before',
      kind: 'action',
      title: '完成项 窗口前一天',
      status: 'done',
      completedAt: localIso(2026, 11, 1, 23, 59),
      order: 3,
    }),
    makeItem({
      id: 'c_out_after',
      kind: 'action',
      title: '完成项 窗口后一天 00:00',
      status: 'done',
      completedAt: localIso(2026, 11, 9, 0, 0),
      order: 4,
    }),
    // 进行中：周期内更新过
    makeItem({
      id: 'o_active',
      kind: 'action',
      title: '进行中的行动',
      status: 'active',
      updatedAt: localIso(2026, 11, 4, 10),
      gantt: { start: '2026-11-01', end: '2026-12-31', progress: 40 },
      order: 5,
    }),
    // 风险 1：超期
    makeItem({
      id: 'r_overdue',
      kind: 'action',
      title: '超期的行动',
      gantt: { start: '2026-10-20', end: '2026-11-05', progress: 20 },
      order: 6,
    }),
    // 风险 2：停滞项目（无子动作）
    makeItem({
      id: 'p_stuck',
      kind: 'project',
      title: '停滞项目',
      gantt: { start: '2026-10-01', end: '2026-12-31', progress: 10 },
      order: 7,
    }),
    // 有 next 子动作 → 不算停滞
    makeItem({
      id: 'p_healthy',
      kind: 'project',
      title: '健康项目',
      gantt: { start: '2026-10-01', end: '2026-12-31', progress: 50 },
      order: 8,
    }),
    makeItem({
      id: 'p_healthy_child',
      kind: 'action',
      title: '健康项目的下一步',
      parentId: 'p_healthy',
      gantt: { start: '2026-12-01', end: '2026-12-20', progress: 0 },
      order: 9,
    }),
    // 风险 3：等待超 7 天（10-30 → 11-08 = 9 天）
    makeItem({
      id: 'w_waiting',
      kind: 'action',
      title: '等待反馈',
      status: 'waiting',
      gtd: { capturedAt: localIso(2026, 10, 30), clarified: true, waitingFor: '客户确认' },
      order: 10,
    }),
    // 风险 4：无日期关键任务
    makeItem({ id: 'u_undated', kind: 'action', title: '没排期的行动', order: 11 }),
    // 收件箱
    makeItem({
      id: 'i_inbox',
      kind: 'note',
      title: '待澄清的收集',
      status: 'inbox',
      gtd: { capturedAt: localIso(2026, 11, 3, 10), clarified: false },
      order: 12,
    }),
    makeItem({
      id: 'i_cleared',
      kind: 'action',
      title: '本周期已澄清的收集',
      gtd: { capturedAt: localIso(2026, 11, 4, 10), clarified: true },
      gantt: { start: '2026-11-20', end: '2026-12-15', progress: 0 },
      order: 13,
    }),
    // 下周期候选（2026-W46）
    makeItem({
      id: 'n_nextup',
      kind: 'action',
      title: '下周到期',
      gantt: { start: '2026-11-09', end: '2026-11-12', progress: 0 },
      order: 14,
    }),
    makeItem({
      id: 'n_out',
      kind: 'action',
      title: '再下周到期',
      gantt: { start: '2026-11-16', end: '2026-11-20', progress: 0 },
      order: 15,
    }),
    // 已完成但超期 → 不算风险
    makeItem({
      id: 'done_overdue',
      kind: 'action',
      title: '已完成但截止很早',
      status: 'done',
      completedAt: localIso(2025, 6, 1),
      gantt: { start: '2025-05-01', end: '2025-05-20', progress: 100 },
      order: 16,
    }),
    // KR
    makeItem({ id: 'obj_1', kind: 'objective', title: '目标一', okr: { period: '2026-Q4', confidence: 7 }, order: 17 }),
    makeItem({
      id: 'kr_1',
      kind: 'keyresult',
      title: '关键结果一',
      parentId: 'obj_1',
      okr: { period: '2026-Q4', confidence: 7, metric: { start: 0, target: 20, current: 12, unit: '单' } },
      order: 18,
    }),
    makeItem({
      id: 'kr_2',
      kind: 'keyresult',
      title: '关键结果二（无指标）',
      parentId: 'obj_1',
      okr: { period: '2026-Q4', confidence: 4 },
      order: 19,
    }),
    // 已完成的 KR 不算「未完成 KR」（完成时间故意放在窗口外，避免干扰完成类断言）
    makeItem({
      id: 'kr_done',
      kind: 'keyresult',
      title: '已完成 KR',
      parentId: 'obj_1',
      status: 'done',
      completedAt: localIso(2025, 3, 1),
      okr: { period: '2026-Q4', confidence: 9 },
      order: 20,
    }),
    // SOP 运行
    makeItem({ id: 'sop_1', kind: 'sop', title: '上线发布 SOP', order: 21 }),
    makeItem({ id: 'step_1', kind: 'step', title: '预检', parentId: 'sop_1', order: 22 }),
    makeItem({ id: 'step_2', kind: 'step', title: '回滚', parentId: 'sop_1', order: 23 }),
  ];

  const runs: SopRunEntry[] = [
    { id: 'run_in', sopId: 'sop_1', stepId: 'step_1', at: localIso(2026, 11, 3, 10), result: 'pass', note: '' },
    { id: 'run_out', sopId: 'sop_1', stepId: 'step_2', at: localIso(2026, 10, 20, 10), result: 'fail', note: '' },
  ];

  return makeWorkspace(items, runs, AREAS);
}

describe('collectFacts：契约面', () => {
  it('collectFacts 返回契约中的 stats + facts，与扩展结果一致', () => {
    const ws = mainWorkspace();
    const facts = collectFacts(ws, 'week', PERIOD, NOW);
    const detailed = collectFactsDetailed(ws, 'week', PERIOD, NOW);
    expect(facts.stats).toEqual(detailed.stats);
    expect(facts.facts).toEqual(detailed.facts);
    expect(Object.keys(facts).sort()).toEqual(['facts', 'stats']);
  });
});

describe('collectFacts：窗口过滤与统计', () => {
  const facts = collectFactsDetailed(mainWorkspace(), 'week', PERIOD, NOW);

  it('周期窗口是本地自然周期，边界日 00:00 / 23:59 都在窗口内', () => {
    expect(facts.period).toEqual({ kind: 'week', key: PERIOD, start: '2026-11-02', end: '2026-11-08' });
    const completedIds = facts.facts.filter((entry) => entry.kind === 'completed').map((entry) => entry.id);
    expect(completedIds).toEqual(['c_in_end', 'c_in_start']);
    expect(facts.stats.completed).toBe(2);
  });

  it('统计口径：进行中 / 运行 / 收件箱', () => {
    expect(facts.stats.openInWindow).toBe(1);
    expect(facts.stats.runs).toBe(1);
    expect(facts.stats.inboxRemaining).toBe(1);
    // 本周期收集 2 条，其中 1 条已澄清并离开收件箱 → 50%
    expect(facts.stats.inboxProgress).toBe(50);
  });

  it('完成项按领域分组，未归属领域排最后', () => {
    expect(facts.completedByArea.map((group) => [group.areaId, group.name, group.facts.length])).toEqual([
      ['area_work', '工作', 1],
      [null, '未归属领域', 1],
    ]);
  });
});

describe('collectFacts：四类风险各自命中', () => {
  const facts = collectFactsDetailed(mainWorkspace(), 'week', PERIOD, NOW);

  it('超期：end 早于周期末日且未完成', () => {
    expect(facts.riskGroups.overdue.map((entry) => entry.id)).toEqual(['r_overdue']);
    expect(facts.riskGroups.overdue[0].meta).toBe('超期 3 天');
  });

  it('停滞项目：没有任何 next/active 子动作', () => {
    expect(facts.riskGroups.stuck.map((entry) => entry.id)).toEqual(['p_stuck']);
  });

  it('等待超 7 天：带 waitingFor 且等待天数严格大于 7', () => {
    expect(facts.riskGroups.waiting.map((entry) => entry.id)).toEqual(['w_waiting']);
    expect(facts.riskGroups.waiting[0].meta).toBe('等待 9 天 · 客户确认');
  });

  it('无日期关键任务：next/active 的 action/project 且没有 gantt.end', () => {
    // p_stuck / p_healthy 有 end，u_undated 没有
    expect(facts.riskGroups.undated.map((entry) => entry.id)).toEqual(['u_undated']);
  });

  it('统计的 risks 与 facts 中 risk 条目一致', () => {
    expect(facts.stats.risks).toBe(4);
    expect(facts.facts.filter((entry) => entry.kind === 'risk')).toHaveLength(4);
  });
});

describe('collectFacts：kr / run / nextUp', () => {
  const facts = collectFactsDetailed(mainWorkspace(), 'week', PERIOD, NOW);

  it('未完成 KR 用 metricPercent 算进度，无 metric 只报信心', () => {
    const kr = facts.facts.filter((entry) => entry.kind === 'kr');
    expect(kr.map((entry) => entry.id)).toEqual(['kr_2', 'kr_1']);
    expect(kr[0].meta).toBe('信心 4/10');
    expect(kr[1].meta).toBe('当前 12/20 单 · 60% · 信心 7/10');
  });

  it('SOP 运行附 SOP / 步骤标题', () => {
    const run = facts.facts.filter((entry) => entry.kind === 'run');
    expect(run).toHaveLength(1);
    expect(run[0].id).toBe('run_in');
    expect(run[0].title).toBe('预检');
    expect(run[0].meta).toBe('上线发布 SOP · 通过 · 11/03');
  });

  it('下周期候选只取下一个自然周期内到期的条目', () => {
    const nextUp = facts.facts.filter((entry) => entry.kind === 'nextUp');
    expect(nextUp.map((entry) => entry.id)).toEqual(['n_nextup']);
    expect(nextUp[0].meta).toBe('截止 11/12');
    expect(facts.nextPeriod).toEqual({ key: '2026-W46', start: '2026-11-09', end: '2026-11-15' });
  });

  it('facts 顺序：completed → risk → kr → run → nextUp', () => {
    const order = ['completed', 'risk', 'kr', 'run', 'nextUp'];
    const kinds = facts.facts.map((entry) => order.indexOf(entry.kind));
    expect(kinds).toEqual([...kinds].sort((a, b) => a - b));
    expect(facts.facts[0].kind).toBe('completed');
    expect(facts.facts[facts.facts.length - 1].kind).toBe('nextUp');
  });

  it('每条 line 都是可直接插入正文的 Markdown 单行', () => {
    for (const entry of facts.facts) {
      expect(entry.line.startsWith('- ')).toBe(true);
      expect(entry.line).not.toContain('\n');
      expect(entry.line).toBe(factLine(entry));
      expect(entry.line).toContain(entry.title);
      expect(entry.line).toContain(entry.meta);
      // 行格式是 `- <标题> · <meta>`：分隔符固定，不额外包一层括号
      expect(entry.line).toBe(`- ${entry.title} · ${entry.meta}`);
    }
  });
});

describe('collectFacts：行格式不产生嵌套括号（回归）', () => {
  /** 括号最大嵌套深度：`（` +1、`）` -1，取过程最大值。 */
  function maxParenDepth(text: string): number {
    let depth = 0;
    let max = 0;
    for (const char of text) {
      if (char === '（') {
        depth += 1;
        max = Math.max(max, depth);
      } else if (char === '）') {
        depth -= 1;
      }
    }
    return max;
  }

  /** 标题 / SOP 标题 / 等待对象 / 单位全都自带括号。 */
  function bracketRichWorkspace(): Workspace {
    return makeWorkspace(
      [
        makeItem({
          id: 'c_paren',
          kind: 'action',
          title: '周会（周报）',
          status: 'done',
          areaId: 'area_work',
          completedAt: localIso(2026, 11, 3, 10),
          order: 1,
        }),
        makeItem({
          id: 'r_paren',
          kind: 'action',
          title: '超期项（临时）',
          gantt: { start: '2026-10-20', end: '2026-11-05', progress: 10 },
          order: 2,
        }),
        makeItem({
          id: 'p_paren',
          kind: 'project',
          title: '停滞项目（暂停）',
          gantt: { start: '2026-10-01', end: '2026-12-31', progress: 0 },
          order: 3,
        }),
        makeItem({
          id: 'w_paren',
          kind: 'action',
          title: '日报汇总（手动）',
          status: 'waiting',
          gtd: { capturedAt: localIso(2026, 10, 29), clarified: true, waitingFor: '张三（外部）' },
          order: 4,
        }),
        makeItem({ id: 'u_paren', kind: 'action', title: '无日期项（待定）', order: 5 }),
        makeItem({
          id: 'n_paren',
          kind: 'action',
          title: '下周项（暂定）',
          gantt: { start: '2026-11-09', end: '2026-11-12', progress: 0 },
          order: 6,
        }),
        makeItem({
          id: 'kr_paren',
          kind: 'keyresult',
          title: '注册转化（周）',
          okr: { period: '2026-Q4', confidence: 5, metric: { start: 0, target: 100, current: 10, unit: '次（估）' } },
          order: 7,
        }),
        makeItem({ id: 'sop_paren', kind: 'sop', title: '上线发布 SOP（旧）', order: 8 }),
        makeItem({
          id: 'step_paren',
          kind: 'step',
          title: '预检（灰度）',
          parentId: 'sop_paren',
          order: 9,
        }),
      ],
      [
        {
          id: 'run_paren',
          sopId: 'sop_paren',
          stepId: 'step_paren',
          at: localIso(2026, 11, 4, 10),
          result: 'fail',
          note: '',
        },
      ],
      AREAS,
    );
  }

  it('标题与 meta 都含括号时，line 里没有 （（ / ）） 也没有三层以上嵌套', () => {
    const facts = collectFactsDetailed(bracketRichWorkspace(), 'week', PERIOD, NOW);
    // 五类事实都要命中，否则这个回归用例形同虚设
    expect(new Set(facts.facts.map((entry) => entry.kind))).toEqual(
      new Set(['completed', 'risk', 'kr', 'run', 'nextUp']),
    );

    for (const entry of facts.facts) {
      expect(entry.line).not.toContain('（（');
      expect(entry.line).not.toContain('））');
      expect(maxParenDepth(entry.line)).toBeLessThanOrEqual(1);
      // meta 自身不写括号（外部文本里的括号除外）
      expect(entry.meta).not.toContain('（（');
      expect(entry.meta).not.toContain('））');
    }

    // 具体样例：外部括号原样保留，但不再被外层括号包住
    const byId = new Map(facts.facts.map((entry) => [entry.id, entry.line]));
    expect(byId.get('w_paren')).toBe('- 日报汇总（手动） · 等待 10 天 · 张三（外部）');
    expect(byId.get('kr_paren')).toBe('- 注册转化（周） · 当前 10/100 次（估） · 10% · 信心 5/10');
    expect(byId.get('run_paren')).toBe('- 预检（灰度） · 上线发布 SOP（旧） · 失败 · 11/04');
    expect(byId.get('c_paren')).toBe('- 周会（周报） · 完成于 11/03');
  });
});

describe('collectFacts：上限', () => {
  function crowdedWorkspace(): Workspace {
    const items: Item[] = [];
    for (let index = 0; index < 7; index += 1) {
      items.push(
        makeItem({
          id: `over_${index}`,
          kind: 'action',
          title: `超期 ${index}`,
          order: index,
          gantt: { start: '2026-10-01', end: '2026-11-06', progress: 0 },
        }),
      );
      items.push(
        makeItem({
          id: `stuck_${index}`,
          kind: 'project',
          title: `停滞项目 ${index}`,
          order: 100 + index,
          gantt: { start: '2026-10-01', end: '2026-12-31', progress: 0 },
        }),
      );
      items.push(
        makeItem({
          id: `wait_${index}`,
          kind: 'action',
          title: `等待 ${index}`,
          status: 'waiting',
          order: 200 + index,
          gtd: { capturedAt: localIso(2026, 10, 1), clarified: true, waitingFor: '供应商' },
        }),
      );
      items.push(makeItem({ id: `undated_${index}`, kind: 'action', title: `未排期 ${index}`, order: 300 + index }));
      items.push(
        makeItem({
          id: `nextup_${index}`,
          kind: 'action',
          title: `下周到期 ${index}`,
          order: 400 + index,
          gantt: { start: '2026-11-09', end: '2026-11-12', progress: 0 },
        }),
      );
    }
    for (let index = 0; index < 12; index += 1) {
      items.push(
        makeItem({
          id: `kr_${index}`,
          kind: 'keyresult',
          title: `KR ${index}`,
          order: 500 + index,
          okr: { period: '2026-Q4', confidence: 5, metric: { start: 0, target: 100, current: index, unit: '%' } },
        }),
      );
      items.push(
        makeItem({
          id: `extra_nextup_${index}`,
          kind: 'action',
          title: `下周到期 额外 ${index}`,
          order: 600 + index,
          gantt: { start: '2026-11-09', end: '2026-11-13', progress: 0 },
        }),
      );
    }
    const runs: SopRunEntry[] = Array.from({ length: 12 }, (_, index) => ({
      id: `run_${index}`,
      sopId: 'sop_1',
      stepId: 'step_1',
      at: localIso(2026, 11, 3, 8, index),
      result: index % 3 === 0 ? ('fail' as const) : ('pass' as const),
      note: '',
    }));
    const extra: Item[] = [
      makeItem({ id: 'sop_1', kind: 'sop', title: 'SOP', order: 900 }),
      makeItem({ id: 'step_1', kind: 'step', title: '步骤一', parentId: 'sop_1', order: 901 }),
    ];
    return makeWorkspace([...items, ...extra], runs, AREAS);
  }

  const facts = collectFactsDetailed(crowdedWorkspace(), 'week', PERIOD, NOW);

  it('每类风险最多 5 条，合计最多 20 条', () => {
    expect(facts.riskGroups.overdue).toHaveLength(5);
    expect(facts.riskGroups.stuck).toHaveLength(5);
    expect(facts.riskGroups.waiting).toHaveLength(5);
    expect(facts.riskGroups.undated).toHaveLength(5);
    expect(facts.stats.risks).toBe(20);
    expect(facts.facts.filter((entry) => entry.kind === 'risk')).toHaveLength(20);
  });

  it('kr / run / nextUp 各最多 10 条，但 stats 报全量计数', () => {
    expect(facts.facts.filter((entry) => entry.kind === 'kr')).toHaveLength(10);
    expect(facts.facts.filter((entry) => entry.kind === 'run')).toHaveLength(10);
    expect(facts.facts.filter((entry) => entry.kind === 'nextUp')).toHaveLength(10);
    expect(facts.stats.runs).toBe(12);
    expect(facts.runCounts).toEqual({ total: 12, pass: 8, fail: 4, skip: 0 });
  });

  it('KR 按进度升序（最落后的先出现）', () => {
    const kr = facts.facts.filter((entry) => entry.kind === 'kr');
    expect(kr[0].id).toBe('kr_0');
    expect(kr[0].meta).toBe('当前 0/100 % · 0% · 信心 5/10');
  });
});

describe('collectFacts：月报 / 季报窗口', () => {
  const ws = mainWorkspace();

  it('月报窗口覆盖整月，周报里在窗口外的完成项也能命中', () => {
    const monthly = collectFactsDetailed(ws, 'month', '2026-11', NOW);
    expect(monthly.period).toEqual({ kind: 'month', key: '2026-11', start: '2026-11-01', end: '2026-11-30' });
    // 11-01 23:59、11-09 00:00 都进入 11 月窗口
    expect(monthly.stats.completed).toBe(4);
    expect(monthly.nextPeriod).toEqual({ key: '2026-12', start: '2026-12-01', end: '2026-12-31' });
  });

  it('季报窗口与 nextPeriod 跨年', () => {
    const quarterly = collectFactsDetailed(ws, 'quarter', '2026-Q4', NOW);
    expect(quarterly.period.start).toBe('2026-10-01');
    expect(quarterly.period.end).toBe('2026-12-31');
    expect(quarterly.nextPeriod).toEqual({ key: '2027-Q1', start: '2027-01-01', end: '2027-03-31' });
  });

  it('非法周期直接抛错，不产出归属不明的报告', () => {
    expect(() => collectFactsDetailed(ws, 'week', '')).toThrow('非法周期：');
    expect(() => collectFactsDetailed(ws, 'week', '2026-11')).toThrow('非法周期：2026-11');
    expect(() => collectFactsDetailed(ws, 'month', '2026-W45')).toThrow('非法周期：2026-W45');
  });
});

describe('collectFacts：空工作区', () => {
  it('全零统计且没有任何事实', () => {
    const facts = collectFactsDetailed(makeWorkspace([]), 'week', PERIOD, NOW);
    expect(facts.stats).toEqual({
      completed: 0,
      openInWindow: 0,
      risks: 0,
      runs: 0,
      inboxRemaining: 0,
      inboxProgress: 100,
    });
    expect(facts.facts).toEqual([]);
    expect(facts.completedByArea).toEqual([]);
  });
});
