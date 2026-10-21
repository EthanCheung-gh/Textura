import { describe, expect, it } from 'vitest';
import type { Edge, Item, Workspace } from '../../core/model';
import { nowIso } from '../../core/utils';
import {
  OKR_KR_PAGE_SIZE,
  buildParentPathText,
  executionItemsOf,
  nextOkrPage,
  paginateObjectiveKrs,
  resolveOkrPageLimit,
} from './okrMath';
import type { ObjectiveView } from './okrMath';

function makeItem(seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
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
    ...seed,
  };
}

function makeWorkspace(items: Item[], edges: Edge[] = []): Workspace {
  return { version: 1, items, edges, areas: [], runs: [], updatedAt: nowIso() };
}

function objectiveView(id: string, krCount: number): ObjectiveView {
  const objective = makeItem({ id, kind: 'objective', title: `目标 ${id}` });
  const keyResults = Array.from({ length: krCount }, (_, index) =>
    makeItem({
      id: `${id}_kr${index}`,
      kind: 'keyresult',
      title: `KR ${index}`,
      parentId: id,
      order: index,
    }),
  );
  return { objective, keyResults, objectiveMatched: true };
}

describe('paginateObjectiveKrs', () => {
  it('0 个目标 / 0 条 KR', () => {
    expect(paginateObjectiveKrs([], OKR_KR_PAGE_SIZE)).toMatchObject({
      entries: [],
      shownKeyResults: 0,
      totalKeyResults: 0,
      remaining: 0,
      hasMore: false,
    });
    const empty = paginateObjectiveKrs([objectiveView('o', 0)], OKR_KR_PAGE_SIZE);
    expect(empty.entries).toHaveLength(1);
    expect(empty.entries[0].keyResults).toHaveLength(0);
    expect(empty.hasMore).toBe(false);
  });

  it('199 条 KR 全部渲染', () => {
    const page = paginateObjectiveKrs([objectiveView('o', 199)], OKR_KR_PAGE_SIZE);
    expect(page.shownKeyResults).toBe(199);
    expect(page.entries[0].keyResults).toHaveLength(199);
    expect(page.hasMore).toBe(false);
  });

  it('200 条 KR 刚好占满一页', () => {
    const page = paginateObjectiveKrs([objectiveView('o', 200)], OKR_KR_PAGE_SIZE);
    expect(page.shownKeyResults).toBe(200);
    expect(page.remaining).toBe(0);
    expect(page.hasMore).toBe(false);
  });

  it('201 条 KR 只渲染前 200 条并保留 1 条', () => {
    const page = paginateObjectiveKrs([objectiveView('o', 201)], OKR_KR_PAGE_SIZE);
    expect(page.entries).toHaveLength(1);
    expect(page.entries[0].keyResults).toHaveLength(200);
    expect(page.entries[0].keyResults[199].id).toBe('o_kr199');
    expect(page.remaining).toBe(1);
    expect(page.hasMore).toBe(true);
  });

  it('跨目标顺序稳定：前一个目标占满预算后，下一个目标只显示剩余部分', () => {
    const page = paginateObjectiveKrs(
      [objectiveView('o1', 120), objectiveView('o2', 120)],
      OKR_KR_PAGE_SIZE,
    );
    expect(page.entries.map((entry) => entry.objective.id)).toEqual(['o1', 'o2']);
    expect(page.entries.map((entry) => entry.keyResults.length)).toEqual([120, 80]);
    expect(page.entries[1].keyResults[0].id).toBe('o2_kr0');
    expect(page.remaining).toBe(40);
  });

  it('没有 KR 的目标在预算内仍会显示（保留缺少 KR 提示）', () => {
    const page = paginateObjectiveKrs(
      [objectiveView('empty', 0), objectiveView('o', 201)],
      OKR_KR_PAGE_SIZE,
    );
    expect(page.entries.map((entry) => entry.objective.id)).toEqual(['empty', 'o']);
    expect(page.remaining).toBe(1);
  });

  it('不修改传入的 entries 与 keyResults', () => {
    const entry = objectiveView('o', 5);
    const original = [...entry.keyResults];
    paginateObjectiveKrs([entry], 2);
    expect(entry.keyResults).toEqual(original);
  });
});

describe('OKR 表格分页状态（筛选后重置）', () => {
  it('季度 / 搜索变化时回到第一页', () => {
    expect(resolveOkrPageLimit({ key: '2026-Q1|', limit: 200 }, '2026-Q1|')).toBe(200);
    const advanced = nextOkrPage({ key: '2026-Q1|', limit: 200 }, '2026-Q1|');
    expect(advanced).toEqual({ key: '2026-Q1|', limit: 400 });
    expect(resolveOkrPageLimit(advanced, '2026-Q1|nps')).toBe(200);
    expect(resolveOkrPageLimit(advanced, '2026-Q1|')).toBe(400);
  });
});

describe('buildParentPathText', () => {
  it('为执行项一次构建父级路径文本', () => {
    const workspace = makeWorkspace([
      makeItem({ id: 'o', kind: 'objective', title: '目标 O' }),
      makeItem({ id: 'p', kind: 'project', title: '项目 P', parentId: 'o' }),
      makeItem({ id: 'a', kind: 'action', title: '行动 A', parentId: 'p' }),
    ]);
    const map = buildParentPathText(workspace, workspace.items);
    expect(map.get('a')).toBe('目标 O / 项目 P');
    expect(map.get('p')).toBe('目标 O');
    expect(map.get('o')).toBe('');
  });

  it('重复条目只计算一次', () => {
    const workspace = makeWorkspace([makeItem({ id: 'a', kind: 'action', title: '行动' })]);
    const map = buildParentPathText(workspace, [workspace.items[0], workspace.items[0]]);
    expect(map.size).toBe(1);
  });
});

describe('executionItemsOf', () => {
  const kr = makeItem({ id: 'kr', kind: 'keyresult', title: 'KR' });
  const edgeItem = makeItem({ id: 'edge_action', kind: 'action', title: '边关联行动' });
  const childItem = makeItem({
    id: 'child_action',
    kind: 'action',
    title: '子项行动',
    parentId: 'kr',
  });
  const other = makeItem({ id: 'other', kind: 'action', title: '无关行动' });
  const edges: Edge[] = [
    { id: 'e1', from: 'kr', to: 'edge_action', type: 'okr', label: '' },
    { id: 'e2', from: 'kr', to: 'other', type: 'related', label: '' },
  ];

  it('合并 okr 边与子项，忽略非 okr 边与重复项', () => {
    const workspace = makeWorkspace([kr, edgeItem, childItem, other], edges);
    const items = executionItemsOf(workspace, 'kr');
    expect(items.map((entry) => [entry.item.id, entry.via, entry.edgeId])).toEqual([
      ['edge_action', 'edge', 'e1'],
      ['child_action', 'child', null],
    ]);
  });

  it('内容不变时返回同一数组引用（行组件可被 memo 跳过）', () => {
    const workspace = makeWorkspace([kr, edgeItem, childItem, other], edges);
    const first = executionItemsOf(workspace, 'kr');
    const second = executionItemsOf(workspace, 'kr');
    expect(second).toBe(first);

    // 无关条目变化（新的 workspace 对象）不影响本 KR 的执行项引用
    const unrelated = makeItem({
      id: 'other',
      kind: 'action',
      title: '无关行动',
      updatedAt: '2026-02-02T00:00:00.000Z',
    });
    const nextWorkspace = makeWorkspace([kr, edgeItem, childItem, unrelated], edges);
    expect(executionItemsOf(nextWorkspace, 'kr')).toBe(first);
  });

  it('执行项内容变化后返回新数组', () => {
    const workspace = makeWorkspace([kr, edgeItem, childItem, other], edges);
    const first = executionItemsOf(workspace, 'kr');
    const renamed = {
      ...edgeItem,
      title: '边关联行动（新）',
      updatedAt: '2026-02-03T00:00:00.000Z',
    };
    const nextWorkspace = makeWorkspace([kr, renamed, childItem, other], edges);
    const second = executionItemsOf(nextWorkspace, 'kr');
    expect(second).not.toBe(first);
    expect(second[0].item.title).toBe('边关联行动（新）');
  });
});
