import { describe, expect, it } from 'vitest';
import { format } from 'date-fns';
import { createSeedWorkspace } from '../core/fixtures';
import type { Item, Report, Workspace } from '../core/model';
import { WORKSPACE_VERSION } from '../core/model';
import { scheduledItemsInRange } from '../core/selectors';
import { visibleItems } from '../modules/calendar/calendarLogic';
import { buildTodayFocus } from '../modules/dashboard/today';
import { routeCounts } from './navCounts';

const TODAY = '2026-03-10';

function makeItem(partial: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  const now = '2026-03-01T00:00:00.000Z';
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: now,
    updatedAt: now,
    completedAt: null,
    ...partial,
  };
}

function makeReport(id: string, status: Report['status']): Report {
  const now = '2026-03-01T00:00:00.000Z';
  return {
    id,
    kind: 'week',
    period: '2026-W10',
    title: id,
    author: '',
    status,
    templateId: 'weekly-external',
    sections: [],
    generatedAt: null,
    finalizedAt: null,
    createdAt: now,
    updatedAt: now,
  };
}

function workspace(items: Item[], extra: Partial<Workspace> = {}): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges: [],
    areas: [],
    runs: [],
    updatedAt: '2026-03-01T00:00:00.000Z',
    ...extra,
  };
}

function counts(ws: Workspace, okrPeriod = '2026-Q1') {
  return routeCounts(ws, { today: TODAY, okrPeriod });
}

describe('routeCounts — dashboard（与「今日聚焦」列表等长）', () => {
  it('超期与今天到期计入；done / dropped / 未来日期不计', () => {
    const ws = workspace([
      makeItem({ id: 'overdue', kind: 'action', title: '超期', gantt: { end: '2026-03-09', progress: 0 } }),
      makeItem({ id: 'today', kind: 'action', title: '今天', gantt: { end: TODAY, progress: 0 } }),
      makeItem({ id: 'overdue-done', kind: 'action', title: '超期但完成', status: 'done', gantt: { end: '2026-03-08', progress: 100 } }),
      makeItem({ id: 'today-dropped', kind: 'action', title: '今天但放弃', status: 'dropped', gantt: { end: TODAY, progress: 0 } }),
      makeItem({ id: 'future', kind: 'action', title: '明天', gantt: { end: '2026-03-11', progress: 0 } }),
    ]);
    expect(counts(ws).dashboard).toBe(2);
  });

  it('无截止日的下一步 action / project 计入（与页面「无日期」桶一致）', () => {
    const ws = workspace([
      makeItem({ id: 'today', kind: 'action', title: '今天', gantt: { end: TODAY, progress: 0 } }),
      makeItem({ id: 'undated-action', kind: 'action', title: '无日期行动' }),
      makeItem({ id: 'undated-project', kind: 'project', title: '无日期项目' }),
      makeItem({ id: 'undated-done', kind: 'action', title: '无日期已完成', status: 'done' }),
      makeItem({ id: 'undated-dropped', kind: 'action', title: '无日期已放弃', status: 'dropped' }),
      makeItem({ id: 'undated-inbox', kind: 'action', title: '收件箱里的', status: 'inbox' }),
      makeItem({ id: 'undated-note', kind: 'note', title: '笔记不算' }),
      makeItem({ id: 'undated-kr', kind: 'keyresult', title: 'KR 不算' }),
    ]);
    expect(counts(ws).dashboard).toBe(3);
  });

  it('与 buildTodayFocus（今日页数据源）在多种构造数据下等长', () => {
    const cases: Workspace[] = [
      workspace([]),
      workspace([
        makeItem({ id: 'a', kind: 'action', title: 'A', gantt: { start: '2026-03-01', end: TODAY, progress: 0 } }),
        makeItem({ id: 'b', kind: 'action', title: 'B', gantt: { end: '2026-02-01', progress: 0 } }),
      ]),
      workspace([
        makeItem({ id: 'o1', kind: 'action', title: '超期 1', gantt: { end: '2026-03-01', progress: 0 } }),
        makeItem({ id: 'o2', kind: 'project', title: '超期项目', gantt: { end: '2026-03-05', progress: 10 } }),
        makeItem({ id: 't1', kind: 'action', title: '今天', gantt: { end: TODAY, progress: 0 } }),
        makeItem({ id: 'u1', kind: 'action', title: '无日期 1' }),
        makeItem({ id: 'u2', kind: 'project', title: '无日期项目' }),
        makeItem({ id: 'f1', kind: 'action', title: '未来', gantt: { end: '2026-03-20', progress: 0 } }),
        makeItem({ id: 'd1', kind: 'action', title: '完成', status: 'done', gantt: { end: TODAY, progress: 100 } }),
        makeItem({ id: 'x1', kind: 'action', title: '放弃', status: 'dropped', gantt: { end: '2026-03-02', progress: 0 } }),
        makeItem({ id: 'i1', kind: 'action', title: '收件箱', status: 'inbox' }),
        makeItem({ id: 's1', kind: 'action', title: '将来', status: 'someday' }),
        makeItem({ id: 'w1', kind: 'action', title: '等待', status: 'waiting', gantt: { end: '2026-03-03', progress: 0 } }),
      ]),
      // 种子数据：today 用真实当天，验证两条实现路径在真实数据上一致。
      createSeedWorkspace(),
    ];
    const seedToday = format(new Date(), 'yyyy-MM-dd');
    for (const [index, ws] of cases.entries()) {
      const today = index === cases.length - 1 ? seedToday : TODAY;
      expect(
        routeCounts(ws, { today, okrPeriod: '2026-Q1' }).dashboard,
        `case ${index} 与 buildTodayFocus 不等长`,
      ).toBe(buildTodayFocus(ws, today).length);
    }
  });

  it('today 非法时与 buildTodayFocus 口径一致，calendar 归零且不抛错', () => {
    const ws = workspace([
      makeItem({ id: 'today', kind: 'action', title: '今天', gantt: { end: TODAY, progress: 0 } }),
      makeItem({ id: 'undated', kind: 'action', title: '无日期' }),
    ]);
    const result = routeCounts(ws, { today: '', okrPeriod: '2026-Q1' });
    expect(result.dashboard).toBe(buildTodayFocus(ws, '').length);
    expect(result.calendar).toBe(0);
  });
});

describe('routeCounts — calendar（未来 7 天，含今天）', () => {
  it('今天与第 7 天计入，第 8 天不计入', () => {
    const ws = workspace([
      makeItem({ id: 'today', kind: 'action', title: '今天', gantt: { start: TODAY, end: TODAY, progress: 0 } }),
      makeItem({ id: 'day7', kind: 'action', title: '第 7 天', gantt: { start: '2026-03-16', end: '2026-03-16', progress: 0 } }),
      makeItem({ id: 'day8', kind: 'action', title: '第 8 天', gantt: { start: '2026-03-17', end: '2026-03-17', progress: 0 } }),
      makeItem({ id: 'past', kind: 'action', title: '昨天结束', gantt: { start: '2026-03-08', end: '2026-03-09', progress: 0 } }),
    ]);
    expect(counts(ws).calendar).toBe(2);
  });

  it('含已完成、不含已放弃（与日历默认渲染的 visibleItems 一致）', () => {
    const ws = workspace([
      makeItem({ id: 'open', kind: 'action', title: '未完成', gantt: { start: TODAY, end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'done', kind: 'action', title: '已完成', status: 'done', gantt: { start: TODAY, end: '2026-03-12', progress: 100 } }),
      makeItem({ id: 'dropped', kind: 'action', title: '已放弃', status: 'dropped', gantt: { start: TODAY, end: '2026-03-12', progress: 0 } }),
    ]);
    // 原始 scheduledItemsInRange 会返回 3 条，徽标必须是 2（dropped 被过滤）。
    expect(scheduledItemsInRange(ws, TODAY, '2026-03-16')).toHaveLength(3);
    expect(counts(ws).calendar).toBe(2);
  });

  it('与「日历默认渲染集合」等长（visibleItems + scheduledItemsInRange，覆盖全部状态）', () => {
    const statuses: Item['status'][] = [
      'inbox',
      'next',
      'active',
      'waiting',
      'scheduled',
      'someday',
      'done',
      'dropped',
    ];
    const items = statuses.map((status) =>
      makeItem({
        id: `s-${status}`,
        kind: 'action',
        title: status,
        status,
        gantt: { start: TODAY, end: '2026-03-12', progress: 0 },
      }),
    );
    // 窗口内跨天的项目 + 窗口之后的条目 + 窗口之前的条目
    items.push(
      makeItem({ id: 'span', kind: 'project', title: '跨天', gantt: { start: '2026-03-05', end: '2026-03-20', progress: 30 } }),
      makeItem({ id: 'after', kind: 'action', title: '窗口之后', gantt: { start: '2026-03-17', end: '2026-03-17', progress: 0 } }),
      makeItem({ id: 'before', kind: 'action', title: '窗口之前', gantt: { start: '2026-03-01', end: '2026-03-02', progress: 0 } }),
    );
    const ws = workspace(items);
    const page = visibleItems(scheduledItemsInRange(ws, TODAY, '2026-03-16')).length;
    expect(counts(ws).calendar).toBe(page);
    // 8 种状态里只排除 dropped（7 条）+ 跨天项目 1 条。
    expect(page).toBe(statuses.length - 1 + 1);
  });

  it('跨过今天与窗口尾部的区间都算（按交集判定）', () => {
    const ws = workspace([
      makeItem({ id: 'span', kind: 'project', title: '本周横跨', gantt: { start: '2026-03-05', end: '2026-03-12', progress: 20 } }),
      makeItem({ id: 'touch-end', kind: 'action', title: '压到窗口末尾', gantt: { start: '2026-03-16', end: '2026-03-25', progress: 0 } }),
      makeItem({ id: 'after', kind: 'action', title: '窗口之后', gantt: { start: '2026-03-20', end: '2026-03-21', progress: 0 } }),
    ]);
    expect(counts(ws).calendar).toBe(2);
  });
});

describe('routeCounts — okr（当前周期目标）', () => {
  it('只计 ui.okrPeriod 对应的周期', () => {
    const ws = workspace([
      makeItem({ id: 'q1a', kind: 'objective', title: 'Q1 目标 A', okr: { period: '2026-Q1', confidence: 5 } }),
      makeItem({ id: 'q1b', kind: 'objective', title: 'Q1 目标 B', okr: { period: '2026-Q1', confidence: 4 } }),
      makeItem({ id: 'q2', kind: 'objective', title: 'Q2 目标', okr: { period: '2026-Q2', confidence: 5 } }),
      makeItem({ id: 'kr', kind: 'keyresult', title: 'Q1 KR', parentId: 'q1a', okr: { period: '2026-Q1', confidence: 5 } }),
    ]);
    expect(counts(ws, '2026-Q1').okr).toBe(2);
    expect(counts(ws, '2026-Q2').okr).toBe(1);
    expect(counts(ws, '2025-Q4').okr).toBe(0);
  });
});

describe('routeCounts — gtd（收件箱待澄清）', () => {
  it('等于 status=inbox 的条目数', () => {
    const ws = workspace([
      makeItem({ id: 'i1', kind: 'action', title: '收件箱 1', status: 'inbox' }),
      makeItem({ id: 'i2', kind: 'note', title: '收件箱 2', status: 'inbox' }),
      makeItem({ id: 'n1', kind: 'action', title: '下一步', status: 'next' }),
      makeItem({ id: 'd1', kind: 'action', title: '已完成', status: 'done' }),
    ]);
    expect(counts(ws).gtd).toBe(2);
  });
});

describe('routeCounts — gantt（时间轴未完成）', () => {
  it('排除无区间、已完成与不可甘特化的条目', () => {
    const ws = workspace([
      makeItem({ id: 'open', kind: 'action', title: '有区间未完成', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'one-end', kind: 'milestone', title: '只有 end', gantt: { end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'range-less', kind: 'action', title: '无区间', gantt: { progress: 0 } }),
      makeItem({ id: 'done', kind: 'action', title: '已完成', status: 'done', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 100 } }),
      makeItem({ id: 'dropped', kind: 'action', title: '已放弃', status: 'dropped', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'sop-with-range', kind: 'sop', title: 'SOP 不算', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'note-with-range', kind: 'note', title: '笔记不算', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 0 } }),
      makeItem({ id: 'inbox-with-range', kind: 'action', title: '收件箱不算', status: 'inbox', gantt: { start: '2026-03-10', end: '2026-03-12', progress: 0 } }),
    ]);
    expect(counts(ws).gantt).toBe(2);
  });
});

describe('routeCounts — sop（SOP 数量）', () => {
  it('只计 kind=sop，且不按状态过滤', () => {
    const ws = workspace([
      makeItem({ id: 'sop1', kind: 'sop', title: '流程 1' }),
      makeItem({ id: 'sop2', kind: 'sop', title: '流程 2', status: 'done' }),
      makeItem({ id: 'step', kind: 'step', title: '步骤', parentId: 'sop1' }),
      makeItem({ id: 'proj', kind: 'project', title: '项目' }),
    ]);
    expect(counts(ws).sop).toBe(2);
  });
});

describe('routeCounts — reports（草稿）', () => {
  it('只计 status=draft', () => {
    const ws = workspace([], {
      reports: [makeReport('r1', 'draft'), makeReport('r2', 'final'), makeReport('r3', 'draft')],
    });
    expect(counts(ws).reports).toBe(2);
  });

  it('reports 为 undefined 时返回 0 而不抛错', () => {
    const ws = workspace([makeItem({ id: 'a', kind: 'action', title: 'A' })]);
    expect(ws.reports).toBeUndefined();
    expect(() => counts(ws)).not.toThrow();
    expect(counts(ws).reports).toBe(0);
  });
});

describe('routeCounts — 返回结构', () => {
  it('空工作区返回全 0，且不含 settings 键', () => {
    const result = counts(workspace([]));
    expect(result).toEqual({ dashboard: 0, calendar: 0, okr: 0, gtd: 0, gantt: 0, sop: 0, reports: 0 });
    expect('settings' in result).toBe(false);
  });
});
