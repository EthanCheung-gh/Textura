import { describe, expect, it } from 'vitest';
import type { Item, Workspace } from '../../core/model';
import { nowIso } from '../../core/utils';
import {
  LIST_PAGE_SIZE,
  buildPathTitleIndex,
  buildWaitingRows,
  groupByContext,
  nextPage,
  paginateItems,
  resolvePageLimit,
  sortNextActions,
} from './gtdLogic';

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

function makeWorkspace(items: Item[]): Workspace {
  return { version: 1, items, edges: [], areas: [], runs: [], updatedAt: nowIso() };
}

function actions(count: number, context = '电脑'): Item[] {
  return Array.from({ length: count }, (_, index) =>
    makeItem({
      id: `a${index}`,
      kind: 'action',
      title: `行动 ${index}`,
      order: index,
      gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true, context },
    }),
  );
}

describe('paginateItems', () => {
  it('0 条时没有可渲染条目', () => {
    const page = paginateItems([], LIST_PAGE_SIZE);
    expect(page).toMatchObject({ shown: 0, total: 0, remaining: 0, hasMore: false });
    expect(page.items).toEqual([]);
  });

  it('99 条全部渲染', () => {
    const items = actions(99);
    const page = paginateItems(items, LIST_PAGE_SIZE);
    expect(page.items).toHaveLength(99);
    expect(page.remaining).toBe(0);
    expect(page.hasMore).toBe(false);
  });

  it('100 条刚好占满一页', () => {
    const items = actions(100);
    const page = paginateItems(items, LIST_PAGE_SIZE);
    expect(page.items).toHaveLength(100);
    expect(page.remaining).toBe(0);
    expect(page.hasMore).toBe(false);
  });

  it('101 条只渲染 100 条并保留 1 条', () => {
    const items = actions(101);
    const page = paginateItems(items, LIST_PAGE_SIZE);
    expect(page.items).toHaveLength(100);
    expect(page.shown).toBe(100);
    expect(page.remaining).toBe(1);
    expect(page.hasMore).toBe(true);
  });

  it('limit 非法或小于 0 时按 0 处理', () => {
    const items = actions(3);
    expect(paginateItems(items, -1).items).toHaveLength(0);
    expect(paginateItems(items, Number.NaN).items).toHaveLength(0);
    expect(paginateItems(items, 2.9).items).toHaveLength(2);
  });

  it('不修改原数组', () => {
    const items = actions(5);
    paginateItems(items, 2);
    expect(items).toHaveLength(5);
  });
});

describe('分页状态（筛选后重置）', () => {
  it('key 变化时回到第一页，同 key 保留已显示的页数', () => {
    const first = resolvePageLimit({ key: 'k1', limit: 100 }, 'k1');
    expect(first).toBe(100);
    const advanced = nextPage({ key: 'k1', limit: 100 }, 'k1');
    expect(advanced).toEqual({ key: 'k1', limit: 200 });
    expect(resolvePageLimit(advanced, 'k1')).toBe(200);
    // 筛选 / 分组变化 → key 不同 → 重置
    expect(resolvePageLimit(advanced, 'k2')).toBe(100);
    expect(nextPage(advanced, 'k2')).toEqual({ key: 'k2', limit: 200 });
  });
});

describe('buildPathTitleIndex（面包屑映射）', () => {
  it('一次性给出路径与父级文本，行内可直接 O(1) 读取', () => {
    const workspace = makeWorkspace([
      makeItem({ id: 'o', kind: 'objective', title: '目标 O' }),
      makeItem({ id: 'p', kind: 'project', title: '项目 P', parentId: 'o' }),
      makeItem({ id: 'a', kind: 'action', title: '行动 A', parentId: 'p' }),
      makeItem({ id: 'root', kind: 'action', title: '根级行动' }),
    ]);
    const index = buildPathTitleIndex(workspace, workspace.items);
    expect(index.paths.get('a')).toEqual(['目标 O', '项目 P', '行动 A']);
    expect(index.parents.get('a')).toEqual(['目标 O', '项目 P']);
    expect(index.parentText.get('a')).toBe('目标 O / 项目 P');
    expect(index.parentText.get('o')).toBe('');
    expect(index.parentText.get('root')).toBe('');
  });

  it('同一 id 重复出现只计算一次，缺失条目返回空文本', () => {
    const workspace = makeWorkspace([makeItem({ id: 'p', kind: 'project', title: '项目' })]);
    const item = workspace.items[0];
    const index = buildPathTitleIndex(workspace, [item, item]);
    expect(index.parentText.size).toBe(1);
    expect(index.parentText.get('p')).toBe('');
  });
});

describe('分组 / 排序与分页组合', () => {
  it('跨组顺序稳定：组顺序按预设场景，组内保持排序结果', () => {
    const items = sortNextActions([
      makeItem({ id: 'pc0', kind: 'action', title: '电脑 0', order: 0, gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true, context: '电脑' } }),
      makeItem({ id: 'pc1', kind: 'action', title: '电脑 1', order: 1, gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true, context: '电脑' } }),
      makeItem({ id: 'phone0', kind: 'action', title: '电话 0', order: 2, gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true, context: '电话' } }),
      makeItem({ id: 'phone1', kind: 'action', title: '电话 1', order: 3, gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true, context: '电话' } }),
      makeItem({ id: 'none', kind: 'action', title: '无场景', order: 4, gtd: { capturedAt: '2026-01-01T00:00:00.000Z', clarified: true } }),
    ]);
    const page = paginateItems(items, 3);
    const groups = groupByContext(page.items);
    expect(groups.map((group) => group.context)).toEqual(['电脑', '电话']);
    expect(groups[0].items.map((item) => item.id)).toEqual(['pc0', 'pc1']);
    expect(groups[1].items.map((item) => item.id)).toEqual(['phone0']);
    expect(page.remaining).toBe(2);

    const rest = groupByContext(items.slice(page.shown));
    expect(rest.map((group) => group.context)).toEqual(['电话', '无场景']);
    expect(rest.map((group) => group.items.map((item) => item.id))).toEqual([
      ['phone1'],
      ['none'],
    ]);
  });

  it('101 条按分组渲染时首屏最多 100 行，剩余 1 条', () => {
    const items = sortNextActions(actions(101));
    const page = paginateItems(items, LIST_PAGE_SIZE);
    const groups = groupByContext(page.items);
    expect(groups.reduce((sum, group) => sum + group.items.length, 0)).toBe(100);
    expect(page.remaining).toBe(1);
  });
});

describe('buildWaitingRows', () => {
  it('等待天数只计算一次并按天数倒序，超 7 天标记正确', () => {
    const today = '2026-01-20';
    // 用本地时间构造时间戳，避免测试依赖跑测机器的时区。
    const localIso = (day: number) => new Date(2026, 0, day, 12).toISOString();
    const items = [
      makeItem({
        id: 'w1',
        kind: 'action',
        title: '等 2 天',
        status: 'waiting',
        gtd: { capturedAt: localIso(18), clarified: true },
      }),
      makeItem({
        id: 'w2',
        kind: 'action',
        title: '等 10 天',
        status: 'waiting',
        gtd: { capturedAt: localIso(10), clarified: true },
      }),
    ];
    const rows = buildWaitingRows(items, today);
    expect(rows.map((row) => row.item.id)).toEqual(['w2', 'w1']);
    expect(rows[0]).toMatchObject({ days: 10, overdue: true });
    expect(rows[1]).toMatchObject({ days: 2, overdue: false });
  });
});
