import { describe, expect, it } from 'vitest';
import type { Area, Item, SopRunEntry, Workspace } from '../../core/model';
import {
  AREA_SECTION_LIMIT,
  REPORT_TEMPLATES,
  SUPPORT_PLACEHOLDER,
  buildReportSections,
  rebuildSection,
  templateById,
  templateFor,
} from './draft';

const BASE = new Date(2025, 0, 1, 9, 0, 0).toISOString();
const NOW = new Date(2026, 10, 9, 9, 0, 0);
const WEEK = '2026-W45';

/** 本地时区构造 ISO 时间戳，避免测试依赖跑测机器的时区。 */
function localIso(year: number, month: number, date: number, hour = 12): string {
  return new Date(year, month - 1, date, hour).toISOString();
}

function makeItem(seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
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

const AREAS: Area[] = [
  { id: 'area_work', name: '工作', color: '#C0663A', order: 0 },
  { id: 'area_life', name: '生活', color: '#5B7C99', order: 1 },
];

function makeWorkspace(items: Item[], runs: SopRunEntry[] = [], areas: Area[] = []): Workspace {
  return { version: 1, items, edges: [], areas, runs, updatedAt: BASE };
}

function richWorkspace(): Workspace {
  return makeWorkspace(
    [
      makeItem({
        id: 'c1',
        kind: 'action',
        title: '完成项一',
        status: 'done',
        areaId: 'area_work',
        completedAt: localIso(2026, 11, 3, 10),
        order: 1,
      }),
      makeItem({
        id: 'c2',
        kind: 'action',
        title: '完成项二',
        status: 'done',
        areaId: 'area_work',
        completedAt: localIso(2026, 11, 4, 10),
        order: 2,
      }),
      makeItem({
        id: 'c3',
        kind: 'action',
        title: '完成项三',
        status: 'done',
        completedAt: localIso(2026, 11, 5, 10),
        order: 3,
      }),
      makeItem({
        id: 'o1',
        kind: 'action',
        title: '进行中的行动',
        status: 'active',
        updatedAt: localIso(2026, 11, 4, 10),
        gantt: { start: '2026-11-01', end: '2026-12-31', progress: 40 },
        order: 4,
      }),
      makeItem({
        id: 'r1',
        kind: 'action',
        title: '超期行动',
        gantt: { start: '2026-10-01', end: '2026-11-05', progress: 10 },
        order: 5,
      }),
      makeItem({
        id: 'p1',
        kind: 'project',
        title: '停滞项目',
        gantt: { start: '2026-10-01', end: '2026-12-31', progress: 10 },
        order: 6,
      }),
      makeItem({
        id: 'w1',
        kind: 'action',
        title: '等待反馈',
        status: 'waiting',
        gtd: { capturedAt: localIso(2026, 10, 30), clarified: true, waitingFor: '客户' },
        order: 7,
      }),
      makeItem({ id: 'u1', kind: 'action', title: '没排期的行动', order: 8 }),
      makeItem({
        id: 'i1',
        kind: 'note',
        title: '收集',
        status: 'inbox',
        gtd: { capturedAt: localIso(2026, 11, 3), clarified: false },
        order: 9,
      }),
      makeItem({
        id: 'n1',
        kind: 'action',
        title: '下周到期',
        gantt: { start: '2026-11-09', end: '2026-11-12', progress: 0 },
        order: 10,
      }),
      makeItem({ id: 'obj_1', kind: 'objective', title: '目标一', okr: { period: '2026-Q4', confidence: 7 }, order: 11 }),
      makeItem({
        id: 'kr_1',
        kind: 'keyresult',
        title: '关键结果一',
        parentId: 'obj_1',
        okr: { period: '2026-Q4', confidence: 7, metric: { start: 0, target: 20, current: 12, unit: '单' } },
        order: 12,
      }),
      makeItem({
        id: 'kr_2',
        kind: 'keyresult',
        title: '关键结果二',
        parentId: 'obj_1',
        okr: { period: '2026-Q4', confidence: 4 },
        order: 13,
      }),
      makeItem({ id: 'sop_1', kind: 'sop', title: '上线发布 SOP', order: 14 }),
      makeItem({ id: 'step_1', kind: 'step', title: '预检', parentId: 'sop_1', order: 15 }),
    ],
    [
      { id: 'run_1', sopId: 'sop_1', stepId: 'step_1', at: localIso(2026, 11, 3, 10), result: 'pass', note: '' },
      { id: 'run_2', sopId: 'sop_1', stepId: 'step_1', at: localIso(2026, 11, 4, 10), result: 'fail', note: '' },
    ],
    AREAS,
  );
}

function emptyWorkspace(): Workspace {
  return makeWorkspace([]);
}

function bodyOf(sections: { key: string; body: string }[], key: string): string {
  const section = sections.find((entry) => entry.key === key);
  expect(section).toBeDefined();
  return section!.body;
}

describe('模板', () => {
  it('三套模板的 id / 粒度 / 节数与 key 顺序', () => {
    expect(REPORT_TEMPLATES.map((template) => [template.id, template.kind, template.sections.length])).toEqual([
      ['weekly-external', 'week', 6],
      ['monthly-external', 'month', 6],
      ['quarterly-external', 'quarter', 7],
    ]);
    const keys = (id: string) => templateById(id).sections.map((section) => section.key);
    expect(keys('weekly-external')).toEqual(['overview', 'progress', 'metrics', 'risks', 'next', 'support']);
    expect(keys('monthly-external')).toEqual(['overview', 'progress', 'metrics', 'risks', 'next', 'support']);
    expect(keys('quarterly-external')).toEqual([
      'overview',
      'progress',
      'okr',
      'metrics',
      'risks',
      'next',
      'support',
    ]);
    // 节标题都非空且互不重复
    for (const template of REPORT_TEMPLATES) {
      const titles = template.sections.map((section) => section.title);
      expect(titles.every((title) => title.trim().length > 0)).toBe(true);
      expect(new Set(titles).size).toBe(titles.length);
    }
  });

  it('templateFor 按粒度映射，templateById 未知 id 回落周报', () => {
    expect(templateFor('week').id).toBe('weekly-external');
    expect(templateFor('month').id).toBe('monthly-external');
    expect(templateFor('quarter').id).toBe('quarterly-external');
    expect(templateById('monthly-external').id).toBe('monthly-external');
    expect(templateById('nope').id).toBe('weekly-external');
    expect(templateById('').id).toBe('weekly-external');
  });

  it('月报按「本月 / 下月」措辞', () => {
    const titles = templateFor('month').sections.map((section) => section.title);
    expect(titles[0]).toBe('本月概览');
    expect(titles[4]).toBe('下月计划');
  });
});

describe('buildReportSections', () => {
  it('6 节 / 7 节都由 buildReportSections 产出，正文非空且是 auto + 传入时间', () => {
    const ws = richWorkspace();
    const week = buildReportSections(ws, 'week', WEEK, NOW);
    const month = buildReportSections(ws, 'month', '2026-11', NOW);
    const quarter = buildReportSections(ws, 'quarter', '2026-Q4', NOW);

    expect(week.map((section) => section.key)).toEqual(templateFor('week').sections.map((s) => s.key));
    expect(month).toHaveLength(6);
    expect(quarter).toHaveLength(7);

    for (const sections of [week, month, quarter]) {
      for (const section of sections) {
        expect(section.body.trim().length).toBeGreaterThan(0);
        expect(section.body.startsWith(`### ${section.title}`)).toBe(true);
        expect(section.origin).toBe('auto');
        expect(section.updatedAt).toBe(NOW.toISOString());
        // 只由小标题与列表行组成
        for (const line of section.body.split('\n')) {
          expect(/^(#{3,4} |- )/.test(line)).toBe(true);
        }
      }
    }
  });

  it('overview 给出四条统计', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'overview');
    expect(body).toContain('- 完成：3 项');
    expect(body).toContain('- 进行中：1 项');
    expect(body).toContain('- 风险：4 项');
    expect(body).toContain('- 收件箱：剩余 1 项 · 清理进度 0%');
  });

  it('progress 按领域分组，未归属领域单列', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'progress');
    expect(body).toBe(
      [
        '### 本周进展',
        '#### 工作',
        '- 完成项二 · 完成于 11/04',
        '- 完成项一 · 完成于 11/03',
        '#### 未归属领域',
        '- 完成项三 · 完成于 11/05',
      ].join('\n'),
    );
  });

  it('progress 每领域最多 8 条，超出补「另有 N 条…」', () => {
    const items: Item[] = Array.from({ length: 12 }, (_, index) =>
      makeItem({
        id: `bulk_${index}`,
        kind: 'action',
        title: `批量完成 ${index}`,
        status: 'done',
        areaId: 'area_work',
        completedAt: localIso(2026, 11, 3, 8 + index),
        order: index,
      }),
    );
    const body = bodyOf(buildReportSections(makeWorkspace(items, [], AREAS), 'week', WEEK, NOW), 'progress');
    const groupLines = body.split('\n').filter((line) => line.startsWith('- 批量完成'));
    expect(groupLines).toHaveLength(AREA_SECTION_LIMIT);
    expect(body).toContain('- 另有 4 条…');
  });

  it('metrics 含 KR 与 SOP 运行两块', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'metrics');
    expect(body).toBe(
      [
        '### 量化指标',
        '#### 关键结果',
        '- 关键结果二 · 信心 4/10',
        '- 关键结果一 · 当前 12/20 单 · 60% · 信心 7/10',
        '#### SOP 运行',
        '- 运行 2 次：通过 1 / 失败 1 / 跳过 0',
        '- 预检 · 上线发布 SOP · 失败 · 11/04',
        '- 预检 · 上线发布 SOP · 通过 · 11/03',
      ].join('\n'),
    );
  });

  it('risks 四个小标题分组，无内容写「无」', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'risks');
    expect(body).toBe(
      [
        '### 风险与阻塞',
        '#### 超期',
        '- 超期行动 · 超期 3 天',
        '#### 停滞项目',
        '- 停滞项目 · 无下一步动作',
        '#### 等待超 7 天',
        '- 等待反馈 · 等待 9 天 · 客户',
        '#### 无日期关键任务',
        '- 没排期的行动 · 未排期',
      ].join('\n'),
    );
  });

  it('next 是下周期计划候选', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'next');
    expect(body).toBe(['### 下周计划', '- 下周到期 · 截止 11/12'].join('\n'));
  });

  it('support 是固定占位', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', WEEK, NOW), 'support');
    expect(body).toBe(['### 需要的支持', SUPPORT_PLACEHOLDER].join('\n'));
  });

  it('季报含 okr 节：目标数、完成度与前 3 个 KR 进度', () => {
    const ws = richWorkspace();
    // 追加第 4 个 KR，验证只展示前 3 个
    ws.items.push(
      makeItem({
        id: 'kr_3',
        kind: 'keyresult',
        title: '关键结果三',
        parentId: 'obj_1',
        okr: { period: '2026-Q4', confidence: 5, metric: { start: 0, target: 10, current: 5, unit: '件' } },
        order: 16,
      }),
      makeItem({
        id: 'kr_4',
        kind: 'keyresult',
        title: '关键结果四',
        parentId: 'obj_1',
        okr: { period: '2026-Q4', confidence: 5, metric: { start: 0, target: 10, current: 1, unit: '件' } },
        order: 17,
      }),
    );
    const body = bodyOf(buildReportSections(ws, 'quarter', '2026-Q4', NOW), 'okr');
    const lines = body.split('\n');
    expect(lines[0]).toBe('### 目标与关键结果');
    expect(lines).toHaveLength(2);
    expect(lines[1]).toContain('目标一：完成度');
    expect(lines[1]).toContain('关键结果一 60%');
    expect(lines[1]).toContain('关键结果二 0%');
    expect(lines[1]).toContain('关键结果三 50%');
    expect(lines[1]).toContain('另有 1 个 KR');
    expect(lines[1]).not.toContain('关键结果四');
  });

  it('季报之外的模板没有 okr 节', () => {
    expect(templateFor('week').sections.some((section) => section.key === 'okr')).toBe(false);
    expect(templateFor('month').sections.some((section) => section.key === 'okr')).toBe(false);
  });
});

describe('buildReportSections：空数据文案必须明确', () => {
  it('每节都有明确文案，不留空字符串', () => {
    const sections = buildReportSections(emptyWorkspace(), 'week', WEEK, NOW);
    const bodies = new Map(sections.map((section) => [section.key, section.body]));

    expect(bodies.get('overview')).toBe(
      [
        '### 本周概览',
        '- 完成：0 项',
        '- 进行中：0 项',
        '- 风险：0 项',
        '- 收件箱：剩余 0 项 · 清理进度 100%',
      ].join('\n'),
    );
    expect(bodies.get('progress')).toBe(['### 本周进展', '- 本周期无完成记录'].join('\n'));
    expect(bodies.get('metrics')).toBe(
      ['### 量化指标', '#### 关键结果', '- 本周期无关键结果数据', '#### SOP 运行', '- 本周期无 SOP 运行记录'].join(
        '\n',
      ),
    );
    expect(bodies.get('risks')).toBe(
      [
        '### 风险与阻塞',
        '#### 超期',
        '- 无',
        '#### 停滞项目',
        '- 无',
        '#### 等待超 7 天',
        '- 无',
        '#### 无日期关键任务',
        '- 无',
      ].join('\n'),
    );
    expect(bodies.get('next')).toBe(['### 下周计划', '- 下周期尚未排期'].join('\n'));
    expect(bodies.get('support')).toBe(['### 需要的支持', SUPPORT_PLACEHOLDER].join('\n'));
    for (const section of sections) expect(section.body.trim()).not.toBe('');
  });

  it('空工作区的季报 okr 节也给出明确文案', () => {
    const body = bodyOf(buildReportSections(emptyWorkspace(), 'quarter', '2026-Q4', NOW), 'okr');
    expect(body).toBe(['### 目标与关键结果', '- 本季度未设置目标'].join('\n'));
  });
});

describe('正文不产生嵌套括号（回归）', () => {
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

  /** 所有外部文本（条目 / 目标 / KR / SOP / 步骤标题、等待对象、指标单位）都带括号。 */
  function bracketRichWorkspace(): Workspace {
    return makeWorkspace(
      [
        makeItem({
          id: 'c1',
          kind: 'action',
          title: '周会（周报）',
          status: 'done',
          areaId: 'area_work',
          completedAt: localIso(2026, 11, 3, 10),
          order: 1,
        }),
        makeItem({
          id: 'r1',
          kind: 'action',
          title: '超期项（临时）',
          gantt: { start: '2026-10-20', end: '2026-11-05', progress: 10 },
          order: 2,
        }),
        makeItem({
          id: 'p1',
          kind: 'project',
          title: '停滞项目（暂停）',
          gantt: { start: '2026-10-01', end: '2026-12-31', progress: 0 },
          order: 3,
        }),
        makeItem({
          id: 'w1',
          kind: 'action',
          title: '日报汇总（手动）',
          status: 'waiting',
          gtd: { capturedAt: localIso(2026, 10, 29), clarified: true, waitingFor: '张三（外部）' },
          order: 4,
        }),
        makeItem({ id: 'u1', kind: 'action', title: '无日期项（待定）', order: 5 }),
        makeItem({
          id: 'n1',
          kind: 'action',
          title: '下周项（暂定）',
          gantt: { start: '2026-11-09', end: '2026-11-12', progress: 0 },
          order: 6,
        }),
        makeItem({
          id: 'obj_1',
          kind: 'objective',
          title: '目标一（季度）',
          okr: { period: '2026-Q4', confidence: 7 },
          order: 7,
        }),
        makeItem({
          id: 'kr_1',
          kind: 'keyresult',
          title: '注册转化（周）',
          parentId: 'obj_1',
          okr: { period: '2026-Q4', confidence: 5, metric: { start: 0, target: 100, current: 10, unit: '次（估）' } },
          order: 8,
        }),
        makeItem({ id: 'sop_1', kind: 'sop', title: '上线发布 SOP（旧）', order: 9 }),
        makeItem({ id: 'step_1', kind: 'step', title: '预检（灰度）', parentId: 'sop_1', order: 10 }),
      ],
      [
        {
          id: 'run_1',
          sopId: 'sop_1',
          stepId: 'step_1',
          at: localIso(2026, 11, 4, 10),
          result: 'fail',
          note: '',
        },
      ],
      AREAS,
    );
  }

  it('三套模板的所有节都没有 （（ / ）） 与三层以上嵌套', () => {
    const ws = bracketRichWorkspace();
    const all = [
      ...buildReportSections(ws, 'week', WEEK, NOW),
      ...buildReportSections(ws, 'month', '2026-11', NOW),
      ...buildReportSections(ws, 'quarter', '2026-Q4', NOW),
      ...buildReportSections(emptyWorkspace(), 'week', WEEK, NOW),
      ...buildReportSections(emptyWorkspace(), 'quarter', '2026-Q4', NOW),
    ];

    expect(all.length).toBe(6 + 6 + 7 + 6 + 7);
    for (const section of all) {
      expect(section.body).not.toContain('（（');
      expect(section.body).not.toContain('））');
      for (const line of section.body.split('\n')) {
        // support 的固定占位是唯一允许的单层括号，且深度也只能是 1
        expect(maxParenDepth(line)).toBeLessThanOrEqual(1);
      }
    }
  });

  it('季报 okr 行不再把 KR 进度包进括号', () => {
    const body = bodyOf(buildReportSections(bracketRichWorkspace(), 'quarter', '2026-Q4', NOW), 'okr');
    expect(body).toBe(
      ['### 目标与关键结果', '- 目标一（季度）：完成度 10% · 注册转化（周） 10%'].join('\n'),
    );
  });
});

describe('rebuildSection', () => {
  it('重算单节等于整体生成时的同一节', () => {
    const ws = richWorkspace();
    const all = buildReportSections(ws, 'week', WEEK, NOW);
    for (const section of all) {
      expect(rebuildSection(ws, 'week', WEEK, section.key, NOW)).toBe(section.body);
    }
    const quarter = buildReportSections(ws, 'quarter', '2026-Q4', NOW);
    const okr = quarter.find((section) => section.key === 'okr');
    expect(rebuildSection(ws, 'quarter', '2026-Q4', 'okr', NOW)).toBe(okr?.body);
  });

  it('未知 sectionKey 返回 null（不抛错）', () => {
    const ws = richWorkspace();
    expect(rebuildSection(ws, 'week', WEEK, 'okr', NOW)).toBeNull();
    expect(rebuildSection(ws, 'week', WEEK, 'nope', NOW)).toBeNull();
    expect(rebuildSection(ws, 'week', WEEK, '', NOW)).toBeNull();
  });

  it('非法 period 抛错', () => {
    const ws = richWorkspace();
    expect(() => buildReportSections(ws, 'week', '', NOW)).toThrow('非法周期：');
    expect(() => buildReportSections(ws, 'week', '2026-11', NOW)).toThrow('非法周期：2026-11');
    expect(() => buildReportSections(ws, 'month', '2026-13', NOW)).toThrow('非法周期：2026-13');
    expect(() => rebuildSection(ws, 'quarter', '2026-Q5', 'okr', NOW)).toThrow('非法周期：2026-Q5');
  });

  it('未知模板 id 与非法 period 的优先级：周期优先抛错', () => {
    const ws = richWorkspace();
    expect(() => rebuildSection(ws, 'week', 'bad', 'nope', NOW)).toThrow('非法周期：bad');
  });
});

/* ------------------------------------------------------------------ */
/* PER-05 回归：未来期次的指标与风险不列当前数据                        */
/* ------------------------------------------------------------------ */

describe('buildReportSections：未来期次不列当前数据（PER-05 回归）', () => {
  /** 2027-01-04 起的一周，晚于 NOW（2026-11-09）。 */
  const FUTURE_WEEK = '2027-W01';

  it('风险节改成「本周期尚未开始」，不再罗列四类「无」', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', FUTURE_WEEK, NOW), 'risks');
    expect(body).toBe(['### 风险与阻塞', '- 本周期尚未开始，暂无风险数据'].join('\n'));
    expect(body).not.toContain('#### 超期');
  });

  it('量化指标的 KR 段说「本周期无关键结果数据」，SOP 段沿用现有文案', () => {
    const body = bodyOf(buildReportSections(richWorkspace(), 'week', FUTURE_WEEK, NOW), 'metrics');
    expect(body).toContain('#### 关键结果\n- 本周期无关键结果数据');
    expect(body).toContain('#### SOP 运行\n- 本周期无 SOP 运行记录');
  });

  it('当季报告仍列当季 KR 与当季风险（防止过度过滤）', () => {
    const sections = buildReportSections(richWorkspace(), 'week', WEEK, NOW);
    const metrics = bodyOf(sections, 'metrics');
    expect(metrics).toContain('关键结果一');
    expect(metrics).toContain('关键结果二');
    expect(metrics).not.toContain('本周期无关键结果数据');

    const risks = bodyOf(sections, 'risks');
    expect(risks).toContain('#### 超期\n- 超期行动');
    expect(risks).not.toContain('本周期尚未开始');
  });

  it('未来期次的重算单节与整体生成给出同一份文案', () => {
    const ws = richWorkspace();
    expect(rebuildSection(ws, 'week', FUTURE_WEEK, 'risks', NOW)).toBe(
      ['### 风险与阻塞', '- 本周期尚未开始，暂无风险数据'].join('\n'),
    );
  });

  /** 目标与 KR 都排在 2027-Q1（未来季），且当季已经有进度，用来验证「不拿现在当结论」。 */
  function futureOkrWorkspace(): Workspace {
    return makeWorkspace([
      makeItem({
        id: 'obj_2027',
        kind: 'objective',
        title: '2027 目标',
        okr: { period: '2027-Q1', confidence: 7 },
        order: 1,
      }),
      makeItem({
        id: 'kr_2027_a',
        kind: 'keyresult',
        title: '2027 KR A',
        parentId: 'obj_2027',
        status: 'active',
        okr: { period: '2027-Q1', confidence: 7, metric: { start: 0, target: 100, current: 45, unit: '%' } },
        order: 2,
      }),
      makeItem({
        id: 'kr_2027_b',
        kind: 'keyresult',
        title: '2027 KR B',
        parentId: 'obj_2027',
        status: 'done',
        completedAt: localIso(2026, 11, 3, 10),
        okr: { period: '2027-Q1', confidence: 8 },
        order: 3,
      }),
    ]);
  }

  it('未来周 / 月 / 季的概览风险行是「本周期尚未开始」，不写「风险：0 项」', () => {
    const ws = futureOkrWorkspace();
    for (const [kind, period] of [
      ['week', FUTURE_WEEK],
      ['month', '2027-01'],
      ['quarter', '2027-Q1'],
    ] as const) {
      const overview = bodyOf(buildReportSections(ws, kind, period, NOW), 'overview');
      expect(overview).toContain('- 风险：本周期尚未开始');
      expect(overview).not.toContain('- 风险：0 项');
      // 概览里唯一的百分比是收件箱清理进度，完成度一个都不该出现
      expect(overview).not.toContain('完成度');
    }
  });

  it('未来季报的 okr 节只列目标与「尚未开始」，不输出完成度百分比', () => {
    const okr = bodyOf(buildReportSections(futureOkrWorkspace(), 'quarter', '2027-Q1', NOW), 'okr');
    expect(okr).toBe(['### 目标与关键结果', '- 2027 目标：本季度尚未开始'].join('\n'));
    // 当前 rollupProgress（45%）是「此刻」的进度，不能当成未来季度的结论
    expect(okr).not.toContain('%');
    expect(okr).not.toContain('完成度');
  });
});
