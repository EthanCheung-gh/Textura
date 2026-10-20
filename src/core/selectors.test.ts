import { describe, expect, it } from 'vitest';
import type { Item, Workspace } from './model';
import { WORKSPACE_VERSION } from './model';
import {
  nextActions,
  rollupProgress,
  scheduledItemsInRange,
  childrenOf,
  descendantsOf,
  findParentCycles,
} from './selectors';

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

function workspace(items: Item[]): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges: [],
    areas: [],
    runs: [],
    updatedAt: '2026-01-01T00:00:00.000Z',
  };
}

describe('rollupProgress', () => {
  it('averages KR metric progress for an objective', () => {
    const ws = workspace([
      makeItem({ id: 'obj', kind: 'objective', title: '目标' }),
      makeItem({
        id: 'kr1',
        kind: 'keyresult',
        title: 'KR1',
        parentId: 'obj',
        order: 0,
        okr: { period: '2026-Q1', confidence: 5, metric: { start: 0, target: 100, current: 50, unit: '%' } },
      }),
      makeItem({
        id: 'kr2',
        kind: 'keyresult',
        title: 'KR2',
        parentId: 'obj',
        order: 1,
        okr: { period: '2026-Q1', confidence: 5, metric: { start: 40, target: 60, current: 50, unit: '%' } },
      }),
    ]);
    expect(rollupProgress(ws, 'obj')).toBe(50);
    expect(rollupProgress(ws, 'kr1')).toBe(50);
    expect(rollupProgress(ws, 'kr2')).toBe(50);
  });

  it('falls back to child completion when a KR has no metric', () => {
    const ws = workspace([
      makeItem({ id: 'obj2', kind: 'objective', title: '目标二' }),
      makeItem({ id: 'kr3', kind: 'keyresult', title: 'KR3', parentId: 'obj2', okr: { period: '2026-Q1', confidence: 5 } }),
      makeItem({ id: 'child-a', kind: 'action', title: 'A', parentId: 'kr3', order: 0, status: 'done' }),
      makeItem({ id: 'child-b', kind: 'action', title: 'B', parentId: 'kr3', order: 1, status: 'next' }),
    ]);
    expect(rollupProgress(ws, 'kr3')).toBe(50);
    expect(rollupProgress(ws, 'obj2')).toBe(50);
  });

  it('uses child completion for projects and SOPs, done flag otherwise', () => {
    const ws = workspace([
      makeItem({ id: 'proj', kind: 'project', title: '项目' }),
      makeItem({ id: 'p1', kind: 'action', title: 'P1', parentId: 'proj', order: 0, status: 'done' }),
      makeItem({ id: 'p2', kind: 'action', title: 'P2', parentId: 'proj', order: 1, status: 'next' }),
      makeItem({ id: 'p3', kind: 'action', title: 'P3', parentId: 'proj', order: 2, status: 'next' }),
      makeItem({ id: 'sop', kind: 'sop', title: 'SOP' }),
      makeItem({ id: 's1', kind: 'step', title: 'S1', parentId: 'sop', status: 'done' }),
      makeItem({ id: 'done-action', kind: 'action', title: '完成', status: 'done' }),
      makeItem({ id: 'open-action', kind: 'action', title: '未完成', status: 'next' }),
    ]);
    expect(rollupProgress(ws, 'proj')).toBe(33);
    expect(rollupProgress(ws, 'sop')).toBe(100);
    expect(rollupProgress(ws, 'done-action')).toBe(100);
    expect(rollupProgress(ws, 'open-action')).toBe(0);
    expect(rollupProgress(ws, 'missing')).toBe(0);
  });

  it('clamps metric progress into 0..100', () => {
    const ws = workspace([
      makeItem({
        id: 'over',
        kind: 'keyresult',
        title: '超额',
        okr: { period: '2026-Q1', confidence: 5, metric: { start: 0, target: 10, current: 25, unit: '个' } },
      }),
      makeItem({
        id: 'under',
        kind: 'keyresult',
        title: '落后',
        okr: { period: '2026-Q1', confidence: 5, metric: { start: 10, target: 20, current: 2, unit: '个' } },
      }),
    ]);
    expect(rollupProgress(ws, 'over')).toBe(100);
    expect(rollupProgress(ws, 'under')).toBe(0);
  });
});

describe('scheduledItemsInRange', () => {
  const ws = workspace([
    makeItem({
      id: 'a',
      kind: 'action',
      title: 'A',
      gantt: { start: '2026-01-01', end: '2026-01-05', progress: 0 },
    }),
    makeItem({
      id: 'b',
      kind: 'action',
      title: 'B',
      gantt: { start: null, end: '2026-01-03', progress: 0 },
    }),
    makeItem({
      id: 'c',
      kind: 'action',
      title: 'C',
      gantt: { start: '2026-01-10', end: '2026-01-12', progress: 0 },
    }),
    makeItem({ id: 'unscheduled', kind: 'action', title: '无日期' }),
  ]);

  it('includes items overlapping the range, boundary inclusive', () => {
    expect(scheduledItemsInRange(ws, '2026-01-04', '2026-01-06').map((item) => item.id)).toEqual(['a']);
    expect(scheduledItemsInRange(ws, '2026-01-03', '2026-01-03').map((item) => item.id)).toEqual(['a', 'b']);
    expect(scheduledItemsInRange(ws, '2026-01-06', '2026-01-09')).toEqual([]);
  });

  it('accepts ISO timestamps and reversed ranges, and sorts by start', () => {
    expect(
      scheduledItemsInRange(ws, '2026-01-10T08:00:00.000Z', '2026-01-01T09:30:00.000Z').map(
        (item) => item.id,
      ),
    ).toEqual(['a', 'b', 'c']);
  });
});

describe('nextActions', () => {
  it('returns actionable next items sorted by order', () => {
    const ws = workspace([
      makeItem({ id: 'action', kind: 'action', title: '行动', status: 'next', order: 2 }),
      makeItem({ id: 'project', kind: 'project', title: '项目', status: 'next', order: 1 }),
      makeItem({ id: 'step', kind: 'step', title: '步骤', status: 'next', order: 0 }),
      makeItem({ id: 'note', kind: 'note', title: '笔记', status: 'next', order: 0 }),
      makeItem({ id: 'done', kind: 'action', title: '完成', status: 'done' }),
      makeItem({ id: 'inbox', kind: 'action', title: '收件箱', status: 'inbox' }),
    ]);
    // step 由 SOP 模块负责，不应进入 GTD 的下一步列表
    expect(nextActions(ws).map((item) => item.id)).toEqual(['project', 'action']);
  });
});

describe('childrenOf', () => {
  it('sorts siblings by order ascending', () => {
    const ws = workspace([
      makeItem({ id: 'parent', kind: 'project', title: '父' }),
      makeItem({ id: 'later', kind: 'action', title: '后', parentId: 'parent', order: 5 }),
      makeItem({ id: 'earlier', kind: 'action', title: '前', parentId: 'parent', order: 1 }),
    ]);
    expect(childrenOf(ws, 'parent').map((item) => item.id)).toEqual(['earlier', 'later']);
  });
});

describe('descendantsOf / findParentCycles', () => {
  it('does not recurse forever on a self-loop', () => {
    const ws = workspace([
      makeItem({ id: 'a', kind: 'action', title: 'A', parentId: 'a' }),
    ]);
    expect(() => descendantsOf(ws, 'a')).not.toThrow();
    expect(descendantsOf(ws, 'a')).toEqual([]);
    expect(findParentCycles(ws)).toEqual([['a', 'a']]);
  });

  it('handles a two-node cycle and still returns the reachable subtree', () => {
    const ws = workspace([
      makeItem({ id: 'a', kind: 'action', title: 'A', parentId: 'b', order: 0 }),
      makeItem({ id: 'b', kind: 'action', title: 'B', parentId: 'a', order: 1 }),
      makeItem({ id: 'c', kind: 'action', title: 'C', parentId: 'b', order: 2 }),
      makeItem({ id: 'd', kind: 'action', title: 'D', parentId: 'c', order: 3 }),
    ]);
    expect(descendantsOf(ws, 'a').map((item) => item.id)).toEqual(['b', 'c', 'd']);
    expect(findParentCycles(ws)).toEqual([['a', 'b', 'a']]);
  });

  it('reports disjoint cycles and returns [] for a healthy tree', () => {
    const twoCycles = workspace([
      makeItem({ id: 'a', kind: 'action', title: 'A', parentId: 'b', order: 0 }),
      makeItem({ id: 'b', kind: 'action', title: 'B', parentId: 'a', order: 1 }),
      makeItem({ id: 'x', kind: 'action', title: 'X', parentId: 'y', order: 2 }),
      makeItem({ id: 'y', kind: 'action', title: 'Y', parentId: 'x', order: 3 }),
    ]);
    expect(findParentCycles(twoCycles)).toEqual([
      ['a', 'b', 'a'],
      ['x', 'y', 'x'],
    ]);

    const healthy = workspace([
      makeItem({ id: 'root', kind: 'project', title: '根', order: 0 }),
      makeItem({ id: 'child', kind: 'action', title: '子', parentId: 'root', order: 0 }),
    ]);
    expect(findParentCycles(healthy)).toEqual([]);
  });
});
