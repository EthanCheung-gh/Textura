import { describe, expect, it } from 'vitest';
import type { Item, SopRunEntry, Workspace } from '../../core/model';
import { WORKSPACE_VERSION } from '../../core/model';
import {
  buildActivity,
  buildTodayFocus,
  completedThisWeek,
  countFocusBuckets,
  latestRun,
  summarizeToday,
} from './today';

const TODAY = '2026-01-05';

function makeItem(partial: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  const now = '2026-01-01T00:00:00.000Z';
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

function makeWorkspace(items: Item[], runs: SopRunEntry[] = []): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges: [],
    areas: [],
    runs,
    updatedAt: '2026-01-05T00:00:00.000Z',
  };
}

function focusWorkspace(): Workspace {
  return makeWorkspace([
    makeItem({ id: 'p', kind: 'project', title: '官网改版', status: 'active' }),
    makeItem({
      id: 'a',
      kind: 'action',
      title: '超期任务',
      parentId: 'p',
      order: 0,
      gantt: { start: '2025-12-30', end: '2026-01-02', progress: 20 },
    }),
    makeItem({
      id: 'b',
      kind: 'action',
      title: '今天到期',
      parentId: 'p',
      order: 0,
      gantt: { start: '2026-01-03', end: TODAY, progress: 40 },
    }),
    makeItem({
      id: 'c',
      kind: 'action',
      title: '无日期下一步',
      order: 3,
    }),
    makeItem({
      id: 'future',
      kind: 'action',
      title: '未来排期',
      order: 4,
      gantt: { start: '2026-01-08', end: '2026-01-10', progress: 0 },
    }),
    makeItem({
      id: 'd',
      kind: 'action',
      title: '已完成但逾期',
      order: 1,
      status: 'done',
      completedAt: '2026-01-04T00:00:00.000Z',
      gantt: { start: null, end: '2026-01-01', progress: 100 },
    }),
    makeItem({ id: 's', kind: 'sop', title: '新手引导 SOP', status: 'active' }),
    makeItem({
      id: 'st',
      kind: 'step',
      title: '发送欢迎邮件',
      parentId: 's',
      order: 1,
      gantt: { start: null, end: TODAY, progress: 0 },
    }),
    makeItem({ id: 'o', kind: 'objective', title: '提升激活', status: 'active' }),
    makeItem({ id: 'kr', kind: 'keyresult', title: 'NPS 提升', parentId: 'o' }),
    makeItem({
      id: 'ak',
      kind: 'action',
      title: '整理用户访谈',
      parentId: 'kr',
      order: 2,
      gantt: { start: null, end: TODAY, progress: 0 },
    }),
  ]);
}

describe('buildTodayFocus', () => {
  it('merges overdue, due-today and next actions without duplicates', () => {
    const entries = buildTodayFocus(focusWorkspace(), TODAY);
    expect(entries.map((entry) => entry.item.id)).toEqual(['a', 'b', 'st', 'ak', 'c']);
    expect(entries.map((entry) => entry.bucket)).toEqual([
      'overdue',
      'today',
      'today',
      'today',
      'undated',
    ]);
    expect(countFocusBuckets(entries)).toEqual({ overdue: 1, today: 3, undated: 1 });
  });

  it('keeps future-dated next actions out of the undated bucket', () => {
    const entries = buildTodayFocus(focusWorkspace(), TODAY);
    expect(entries.some((entry) => entry.item.id === 'future')).toBe(false);
    expect(entries.filter((entry) => entry.bucket === 'undated').map((entry) => entry.item.id)).toEqual([
      'c',
    ]);
    expect(entries.filter((entry) => entry.bucket === 'undated').every((entry) => entry.due === null)).toBe(
      true,
    );
  });

  it('keeps one row for an item that is both due today and a next action', () => {
    const entries = buildTodayFocus(focusWorkspace(), TODAY);
    expect(entries.filter((entry) => entry.item.id === 'b')).toHaveLength(1);
    expect(entries.find((entry) => entry.item.id === 'b')?.bucket).toBe('today');
  });

  it('excludes completed items and computes lateness', () => {
    const entries = buildTodayFocus(focusWorkspace(), TODAY);
    expect(entries.some((entry) => entry.item.id === 'd')).toBe(false);
    const overdue = entries.find((entry) => entry.item.id === 'a');
    expect(overdue?.daysLate).toBe(3);
    expect(overdue?.due).toBe('2026-01-02');
  });

  it('records breadcrumb paths and SOP/OKR sources', () => {
    const entries = buildTodayFocus(focusWorkspace(), TODAY);
    const byId = new Map(entries.map((entry) => [entry.item.id, entry]));
    expect(byId.get('a')?.pathTitles).toEqual(['官网改版', '超期任务']);
    expect(byId.get('st')?.source).toBe('sop');
    expect(byId.get('ak')?.source).toBe('okr');
    expect(byId.get('c')?.source).toBeNull();
  });

  it('returns an empty list for a workspace without open work', () => {
    const entries = buildTodayFocus(
      makeWorkspace([makeItem({ id: 'done', kind: 'action', title: '完成', status: 'done' })]),
      TODAY,
    );
    expect(entries).toEqual([]);
  });
});

describe('summarizeToday', () => {
  it('summarizes overdue, due today and inbox counts', () => {
    expect(summarizeToday({ overdue: 2, today: 1, inbox: 6, next: 0 })).toBe(
      '2 项已超期，1 项今日到期，收件箱 6 条待澄清。',
    );
  });

  it('falls back to next actions or an empty message', () => {
    expect(summarizeToday({ overdue: 0, today: 0, inbox: 0, next: 3 })).toBe(
      '今天没有硬性截止，3 项下一步可以先推进。',
    );
    expect(summarizeToday({ overdue: 0, today: 0, inbox: 0, next: 0 })).toContain('今天没有待办');
  });
});

describe('completedThisWeek', () => {
  it('keeps completions from the last seven days, newest first', () => {
    const now = new Date(2026, 0, 5, 12, 0, 0);
    const ws = makeWorkspace([
      makeItem({ id: 'recent', kind: 'action', title: '最近完成', status: 'done', completedAt: '2026-01-03T10:00:00' }),
      makeItem({ id: 'older', kind: 'action', title: '早些完成', status: 'done', completedAt: '2026-01-01T10:00:00' }),
      makeItem({ id: 'stale', kind: 'action', title: '很久以前', status: 'done', completedAt: '2025-12-01T10:00:00' }),
      makeItem({ id: 'open', kind: 'action', title: '未完成' }),
    ]);
    expect(completedThisWeek(ws, now).map((item) => item.id)).toEqual(['recent', 'older']);
  });
});

describe('buildActivity / latestRun', () => {
  const ws = makeWorkspace(
    [
      makeItem({ id: 's', kind: 'sop', title: '新手引导 SOP', status: 'active' }),
      makeItem({ id: 'st', kind: 'step', title: '发送欢迎邮件', parentId: 's' }),
      makeItem({
        id: 'done',
        kind: 'action',
        title: '需求梳理',
        status: 'done',
        completedAt: '2026-01-04T08:00:00',
      }),
      makeItem({ id: 's2', kind: 'sop', title: '周复盘 SOP', status: 'active' }),
      makeItem({
        id: 'old-done',
        kind: 'note',
        title: '很久以前完成',
        status: 'done',
        completedAt: '2025-12-01T08:00:00',
      }),
    ],
    [
      { id: 'r1', sopId: 's', stepId: 'st', at: '2026-01-05T09:00:00', result: 'pass', note: '' },
      { id: 'r2', sopId: 's2', stepId: 'missing', at: '2026-01-03T09:00:00', result: 'fail', note: '' },
    ],
  );

  it('merges runs and completions in reverse chronological order', () => {
    const activity = buildActivity(ws, 5);
    expect(activity.map((entry) => entry.id)).toEqual([
      'run:r1',
      'completed:done',
      'run:r2',
      'completed:old-done',
    ]);
    expect(activity[0].title).toBe('新手引导 SOP');
    expect(activity[0].detail).toBe('发送欢迎邮件 · 通过');
    expect(activity[1].detail).toBe('行动 · 已完成');
    expect(activity[2].detail).toBe('失败');
    // 活动时间线不受「近 7 天完成」的窗口限制
    expect(activity[3].title).toBe('很久以前完成');
  });

  it('returns the newest run', () => {
    expect(latestRun(ws)?.id).toBe('r1');
    expect(latestRun(makeWorkspace([]))).toBeNull();
  });
});
