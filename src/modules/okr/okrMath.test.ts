import { describe, expect, it } from 'vitest';
import type { Item, Workspace } from '../../core/model';
import { WORKSPACE_VERSION } from '../../core/model';
import {
  confidenceBucket,
  executionItemsOf,
  filterObjectives,
  hasMetricRange,
  isKrBehind,
  metricPercent,
  metricProgress,
  nextQuarter,
  quarterElapsedPercent,
  quarterLabel,
  shiftQuarter,
  summarize,
} from './okrMath';

const NOW = '2026-02-14T09:00:00.000Z';

function makeItem(partial: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: NOW,
    updatedAt: NOW,
    completedAt: null,
    ...partial,
  };
}

function makeWorkspace(items: Item[] = [], edges: Workspace['edges'] = [], areas: Workspace['areas'] = []): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges,
    areas,
    runs: [],
    updatedAt: NOW,
  };
}

describe('quarterElapsedPercent', () => {
  it('returns 0 on the first day of the quarter', () => {
    expect(quarterElapsedPercent('2026-Q1', new Date(2026, 0, 1))).toBe(0);
    expect(quarterElapsedPercent('2026-Q2', new Date(2026, 3, 1))).toBe(0);
  });

  it('returns 100 on the last day of the quarter', () => {
    expect(quarterElapsedPercent('2026-Q1', new Date(2026, 2, 31))).toBe(100);
    expect(quarterElapsedPercent('2026-Q4', new Date(2026, 11, 31))).toBe(100);
  });

  it('reports calendar progress inside the quarter', () => {
    // 2026-Q1: 89 天，2/14 已过 44 天 → 49.438% → 49.4
    expect(quarterElapsedPercent('2026-Q1', new Date(2026, 1, 14))).toBeCloseTo(49.4, 1);
    expect(quarterElapsedPercent('2026-Q3', new Date(2026, 7, 15))).toBeCloseTo(49.5, 1);
  });

  it('clamps before and after the quarter', () => {
    expect(quarterElapsedPercent('2025-Q1', new Date(2026, 1, 14))).toBe(100);
    expect(quarterElapsedPercent('2026-Q3', new Date(2026, 1, 14))).toBe(0);
    expect(quarterElapsedPercent('2027-Q4', new Date(2026, 1, 14))).toBe(0);
  });

  it('returns 0 for an unparseable period', () => {
    expect(quarterElapsedPercent('2026-Q9', new Date(2026, 1, 14))).toBe(0);
    expect(quarterElapsedPercent('', new Date(2026, 1, 14))).toBe(0);
  });
});

describe('isKrBehind', () => {
  it('flags when progress is at least 10 points behind time', () => {
    expect(isKrBehind(0, 10)).toBe(true);
    expect(isKrBehind(20, 49.4)).toBe(true);
    expect(isKrBehind(51, 61)).toBe(true);
  });

  it('does not flag inside the 10 point tolerance', () => {
    expect(isKrBehind(52, 61)).toBe(false);
    expect(isKrBehind(60, 60)).toBe(false);
    expect(isKrBehind(80, 40)).toBe(false);
    expect(isKrBehind(0, 0)).toBe(false);
  });

  it('returns false for non-finite inputs instead of throwing', () => {
    expect(isKrBehind(Number.NaN, 50)).toBe(false);
    expect(isKrBehind(10, Number.POSITIVE_INFINITY)).toBe(false);
  });
});

describe('confidenceBucket', () => {
  it('maps 1–3 low, 4–6 mid, 7–10 high', () => {
    expect([1, 2, 3].map(confidenceBucket)).toEqual(['low', 'low', 'low']);
    expect([4, 5, 6].map(confidenceBucket)).toEqual(['mid', 'mid', 'mid']);
    expect([7, 8, 9, 10].map(confidenceBucket)).toEqual(['high', 'high', 'high', 'high']);
  });

  it('clamps out-of-range values', () => {
    expect(confidenceBucket(0)).toBe('low');
    expect(confidenceBucket(-3)).toBe('low');
    expect(confidenceBucket(11)).toBe('high');
    expect(confidenceBucket(Number.NaN)).toBe('low');
  });
});

describe('metricPercent', () => {
  it('converts metric values linearly', () => {
    expect(metricPercent({ start: 42, target: 60, current: 47, unit: '分' })).toBe(28);
    expect(metricPercent({ start: 2.1, target: 3, current: 2.35, unit: '%' })).toBe(28);
    expect(metricPercent({ start: 0, target: 100, current: 50, unit: '%' })).toBe(50);
  });

  it('clamps overshoot and undershoot', () => {
    expect(metricPercent({ start: 42, target: 60, current: 70, unit: '分' })).toBe(100);
    expect(metricPercent({ start: 42, target: 60, current: 30, unit: '分' })).toBe(0);
  });

  it('returns null when there is no convertible range', () => {
    expect(metricPercent({ start: 5, target: 5, current: 5, unit: '' })).toBeNull();
    expect(metricPercent(undefined)).toBeNull();
    expect(metricPercent({ start: Number.NaN, target: 10, current: 5, unit: '' })).toBeNull();
  });

  it('supports negative metrics (target below start)', () => {
    expect(metricPercent({ start: 5, target: 2, current: 3.5, unit: '%' })).toBe(50);
    expect(metricPercent({ start: 5, target: 2, current: 10, unit: '%' })).toBe(0);
  });
});

describe('metricProgress / hasMetricRange', () => {
  it('marks target === start as flat with no percentage', () => {
    const info = metricProgress({ start: 5, target: 5, current: 5, unit: '' });
    expect(info).toEqual({ state: 'flat', percent: null, clamped: false });
    expect(hasMetricRange({ start: 5, target: 5, current: 5, unit: '' })).toBe(false);
  });

  it('treats ranges below the epsilon as flat', () => {
    expect(hasMetricRange({ start: 5, target: 5 + 5e-10, current: 5, unit: '' })).toBe(false);
    expect(hasMetricRange({ start: 5, target: 5 + 1e-6, current: 5, unit: '' })).toBe(true);
  });

  it('marks positive overshoot and undershoot without exceeding 0..100', () => {
    expect(metricProgress({ start: 42, target: 60, current: 70, unit: '分' })).toEqual({
      state: 'over',
      percent: 100,
      clamped: true,
    });
    expect(metricProgress({ start: 42, target: 60, current: 30, unit: '分' })).toEqual({
      state: 'under',
      percent: 0,
      clamped: true,
    });
    expect(metricProgress({ start: 42, target: 60, current: 60, unit: '分' })).toEqual({
      state: 'in-range',
      percent: 100,
      clamped: false,
    });
    expect(metricProgress({ start: 42, target: 60, current: 42, unit: '分' })).toEqual({
      state: 'in-range',
      percent: 0,
      clamped: false,
    });
  });

  it('is direction-aware for negative metrics (start > target)', () => {
    expect(metricProgress({ start: 5, target: 2, current: 3.5, unit: '%' })).toEqual({
      state: 'in-range',
      percent: 50,
      clamped: false,
    });
    // 负向指标：current 低于 target 才算越过目标
    expect(metricProgress({ start: 5, target: 2, current: 1, unit: '%' })).toEqual({
      state: 'over',
      percent: 100,
      clamped: true,
    });
    // 负向指标：current 高于 start 属于低于起点
    expect(metricProgress({ start: 5, target: 2, current: 10, unit: '%' })).toEqual({
      state: 'under',
      percent: 0,
      clamped: true,
    });
  });

  it('distinguishes unset and invalid metrics', () => {
    expect(metricProgress(undefined)).toEqual({ state: 'unset', percent: null, clamped: false });
    expect(metricProgress({ start: Number.NaN, target: 10, current: 5, unit: '' })).toEqual({
      state: 'invalid',
      percent: null,
      clamped: false,
    });
  });
});

describe('summarize', () => {
  const workspace = makeWorkspace([
    makeItem({
      id: 'obj_a',
      kind: 'objective',
      title: 'A',
      order: 0,
      okr: { period: '2026-Q1', confidence: 6 },
    }),
    makeItem({
      id: 'kr_1',
      kind: 'keyresult',
      title: 'KR 1',
      parentId: 'obj_a',
      order: 0,
      okr: {
        period: '2026-Q1',
        confidence: 5,
        metric: { start: 0, target: 100, current: 20, unit: '%' },
      },
    }),
    makeItem({
      id: 'kr_2',
      kind: 'keyresult',
      title: 'KR 2',
      parentId: 'obj_a',
      order: 1,
      okr: { period: '2026-Q1', confidence: 9 },
    }),
    makeItem({
      id: 'act_1',
      kind: 'action',
      title: '已完成行动',
      parentId: 'kr_2',
      order: 0,
      status: 'done',
    }),
    makeItem({
      id: 'obj_b',
      kind: 'objective',
      title: 'B',
      order: 1,
      okr: { period: '2026-Q1', confidence: 2 },
    }),
    makeItem({
      id: 'obj_c',
      kind: 'objective',
      title: '上一季度',
      order: 2,
      okr: { period: '2025-Q4', confidence: 8 },
    }),
    makeItem({
      id: 'kr_c',
      kind: 'keyresult',
      title: '不属于本季度',
      parentId: 'obj_c',
      okr: { period: '2025-Q4', confidence: 10 },
    }),
  ]);

  it('aggregates objectives, KRs, average progress, confidence and behind count', () => {
    const summary = summarize(workspace, '2026-Q1', new Date(2026, 1, 14));
    expect(summary.objectives).toBe(2);
    expect(summary.keyResults).toBe(2);
    // obj_a: (20 + 100) / 2 = 60；obj_b: 无 KR → 0；平均 (60 + 0) / 2 = 30
    expect(summary.averageProgress).toBe(30);
    expect(summary.behind).toBe(1);
    expect(summary.confidence).toEqual({ low: 0, mid: 1, high: 1 });
    expect(summary.elapsedPercent).toBeCloseTo(49.4, 1);
  });

  it('returns zeros for a quarter without objectives', () => {
    const summary = summarize(workspace, '2026-Q4', new Date(2026, 10, 1));
    expect(summary).toMatchObject({
      objectives: 0,
      keyResults: 0,
      averageProgress: 0,
      behind: 0,
      confidence: { low: 0, mid: 0, high: 0 },
    });
  });
});

describe('executionItemsOf', () => {
  const workspace = makeWorkspace(
    [
      makeItem({ id: 'kr', kind: 'keyresult', title: 'KR', okr: { period: '2026-Q1', confidence: 5 } }),
      makeItem({ id: 'act_edge', kind: 'action', title: '边关联行动', parentId: 'kr', order: 0 }),
      makeItem({ id: 'act_child', kind: 'action', title: '子项行动', parentId: 'kr', order: 1 }),
      makeItem({ id: 'proj_edge', kind: 'project', title: '边关联项目', order: 0 }),
      makeItem({ id: 'note_edge', kind: 'note', title: '笔记', order: 0 }),
    ],
    [
      { id: 'e1', from: 'kr', to: 'act_edge', type: 'okr', label: '' },
      { id: 'e2', from: 'kr', to: 'proj_edge', type: 'okr', label: '' },
      { id: 'e3', from: 'kr', to: 'note_edge', type: 'okr', label: '' },
      { id: 'e4', from: 'kr', to: 'proj_edge', type: 'related', label: '' },
    ],
  );

  it('merges okr edges and parentId children, deduplicating by item id', () => {
    const items = executionItemsOf(workspace, 'kr');
    expect(items).toHaveLength(3);
    expect(items.map((entry) => entry.item.id)).toEqual(['act_edge', 'proj_edge', 'act_child']);
    expect(items[0]).toMatchObject({ via: 'edge', edgeId: 'e1' });
    expect(items[1]).toMatchObject({ via: 'edge', edgeId: 'e2' });
    expect(items[2]).toMatchObject({ via: 'child', edgeId: null });
  });
});

describe('filterObjectives', () => {
  const workspace = makeWorkspace(
    [
      makeItem({
        id: 'obj',
        kind: 'objective',
        title: '让新用户爱上织理',
        tags: ['增长'],
        areaId: 'area_product',
        okr: { period: '2026-Q1', confidence: 6 },
      }),
      makeItem({
        id: 'kr_nps',
        kind: 'keyresult',
        title: 'NPS 从 42 提升到 60',
        parentId: 'obj',
        order: 0,
        okr: { period: '2026-Q1', confidence: 4, krOwner: '林一' },
      }),
      makeItem({
        id: 'kr_wau',
        kind: 'keyresult',
        title: '周活跃用户 1200 → 2000',
        parentId: 'obj',
        order: 1,
        okr: { period: '2026-Q1', confidence: 6, krOwner: '周然' },
      }),
    ],
    [],
    [{ id: 'area_product', name: '产品', color: '#C0663A', order: 0 }],
  );

  it('returns every objective and KR for an empty query', () => {
    const result = filterObjectives(workspace, '2026-Q1', '');
    expect(result).toHaveLength(1);
    expect(result[0].keyResults).toHaveLength(2);
    expect(result[0].objectiveMatched).toBe(true);
  });

  it('keeps only matching KRs when the objective does not match', () => {
    const result = filterObjectives(workspace, '2026-Q1', 'nps');
    expect(result).toHaveLength(1);
    expect(result[0].objectiveMatched).toBe(false);
    expect(result[0].keyResults.map((kr) => kr.id)).toEqual(['kr_nps']);
  });

  it('matches objective title, tag, area and KR owner case-insensitively', () => {
    expect(filterObjectives(workspace, '2026-Q1', '织理')[0].keyResults).toHaveLength(2);
    expect(filterObjectives(workspace, '2026-Q1', '增长')[0].keyResults).toHaveLength(2);
    expect(filterObjectives(workspace, '2026-Q1', '产品')[0].objectiveMatched).toBe(true);
    const byOwner = filterObjectives(workspace, '2026-Q1', '周然');
    expect(byOwner[0].keyResults.map((kr) => kr.id)).toEqual(['kr_wau']);
  });

  it('returns nothing when no objective or KR matches', () => {
    expect(filterObjectives(workspace, '2026-Q1', '不存在')).toEqual([]);
    expect(filterObjectives(workspace, '2026-Q2', '')).toEqual([]);
  });
});

describe('quarter helpers', () => {
  it('shifts across year boundaries', () => {
    expect(nextQuarter('2026-Q4')).toBe('2027-Q1');
    expect(nextQuarter('2026-Q1')).toBe('2026-Q2');
    expect(shiftQuarter('2026-Q1', -1)).toBe('2025-Q4');
    expect(shiftQuarter('2026-Q3', -5)).toBe('2025-Q2');
  });

  it('formats labels and tolerates invalid input', () => {
    expect(quarterLabel('2026-Q4')).toBe('2026 Q4');
    expect(quarterLabel('自定义')).toBe('自定义');
    expect(nextQuarter('自定义')).toBe('自定义');
  });
});
