import { describe, expect, it } from 'vitest';
import type { Item } from '../../core/model';
import { FOCUS_PAGE_SIZE, paginateFocus } from './today';
import type { FocusEntry } from './today';

function entry(index: number): FocusEntry {
  const item: Item = {
    id: `a${index}`,
    kind: 'action',
    title: `行动 ${index}`,
    notes: '',
    parentId: null,
    order: index,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    completedAt: null,
  };
  return {
    item,
    bucket: 'undated',
    due: null,
    daysLate: 0,
    pathTitles: [item.title],
    source: null,
  };
}

describe('paginateFocus', () => {
  it('0 条', () => {
    expect(paginateFocus([], FOCUS_PAGE_SIZE)).toMatchObject({
      shown: 0,
      total: 0,
      remaining: 0,
      hasMore: false,
    });
  });

  it('99 / 100 条不触发分页', () => {
    expect(paginateFocus(Array.from({ length: 99 }, (_, i) => entry(i)), FOCUS_PAGE_SIZE)).toMatchObject({
      shown: 99,
      remaining: 0,
      hasMore: false,
    });
    expect(paginateFocus(Array.from({ length: 100 }, (_, i) => entry(i)), FOCUS_PAGE_SIZE)).toMatchObject({
      shown: 100,
      remaining: 0,
      hasMore: false,
    });
  });

  it('101 条只渲染前 100 条', () => {
    const page = paginateFocus(Array.from({ length: 101 }, (_, i) => entry(i)), FOCUS_PAGE_SIZE);
    expect(page.items).toHaveLength(100);
    expect(page.items[99].item.id).toBe('a99');
    expect(page.remaining).toBe(1);
    expect(page.hasMore).toBe(true);
  });

  it('limit 非法时按 0 处理', () => {
    expect(paginateFocus([entry(0)], Number.NaN).items).toHaveLength(0);
    expect(paginateFocus([entry(0)], -5).items).toHaveLength(0);
  });
});
