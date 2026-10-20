import { describe, expect, it } from 'vitest';
import type { Edge, Item, ItemKind, ItemStatus, Workspace } from '../../core/model';
import { WORKSPACE_VERSION } from '../../core/model';
import {
  addDaysKey,
  barGeometry,
  buildHeader,
  buildRange,
  buildRows,
  dateToX,
  diffDays,
  displayProgress,
  formatRangeLabel,
  itemRange,
  moveBar,
  resizeBar,
  snapDate,
  toKey,
  UNGROUPED_ID,
  visibleRange,
  xToDate,
  ZOOM_CONFIG,
} from './scale';

function makeItem(partial: Partial<Item> & { id: string; title: string; kind: ItemKind }): Item {
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next' as ItemStatus,
    tags: [],
    areaId: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    completedAt: null,
    ...partial,
  };
}

function makeWorkspace(items: Item[], edges: Edge[] = []): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges,
    areas: [],
    runs: [],
    updatedAt: '2026-01-01T00:00:00.000Z',
  };
}

describe('buildRange', () => {
  it('无排期条目时给 today 前后留白默认区间', () => {
    const day = buildRange([], 'day', '2026-06-15');
    expect(day).toEqual({ start: '2026-06-08', end: '2026-06-29' });

    const week = buildRange([], 'week', '2026-06-15');
    // 2026-06-01 - 14d = 06-01，对齐周一；06-15 + 28d = 07-13，对齐周日。
    expect(week.start).toBe('2026-06-01');
    expect(week.end).toBe('2026-07-19');
    expect(diffDays(week.start, week.end)).toBeGreaterThan(30);

    const month = buildRange([], 'month', '2026-06-15');
    expect(month.start).toBe('2026-05-01');
    expect(month.end).toBe('2026-08-31');
  });

  it('有条目时覆盖最早 / 最晚并加缓冲', () => {
    const items = [
      makeItem({ id: 'a', title: 'A', kind: 'action', gantt: { start: '2026-06-10', end: '2026-06-12', progress: 0 } }),
      makeItem({ id: 'b', title: 'B', kind: 'action', gantt: { start: '2026-06-05', end: '2026-06-20', progress: 50 } }),
    ];
    const day = buildRange(items, 'day', '2026-06-15');
    expect(day.start < '2026-06-05').toBe(true);
    expect(day.end > '2026-06-20').toBe(true);
    expect(day.start <= '2026-06-15' && day.end >= '2026-06-15').toBe(true);

    const week = buildRange(items, 'week', '2026-06-15');
    expect(week.start <= '2026-06-05').toBe(true);
    expect(week.end >= '2026-06-20').toBe(true);

    const month = buildRange(items, 'month', '2026-06-15');
    expect(month.start).toBe('2026-05-01'); // 06-05 - 30d = 05-06 → 月初
    expect(month.end).toBe('2026-08-31');
  });

  it('跨月 / 跨年仍覆盖所有条目', () => {
    const items = [
      makeItem({ id: 'a', title: 'A', kind: 'action', gantt: { start: '2025-12-30', end: '2026-01-02', progress: 0 } }),
    ];
    const month = buildRange(items, 'month', '2026-01-01');
    expect(month.start <= '2025-12-30').toBe(true);
    expect(month.end >= '2026-01-02').toBe(true);
    expect(month.start).toBe('2025-11-01');
    expect(month.end).toBe('2026-03-31');

    const week = buildRange(items, 'week', '2026-01-01');
    expect(week.start <= '2025-12-30').toBe(true);
    expect(week.end >= '2026-01-02').toBe(true);
  });
});

describe('dateToX / xToDate', () => {
  it('跨月跨年往返一致', () => {
    const origin = '2025-12-20';
    const px = ZOOM_CONFIG.day.pxPerDay;
    let key = origin;
    for (let i = 0; i < 60; i += 1) {
      const x = dateToX(key, origin, px);
      expect(x).toBe(i * px);
      expect(xToDate(x, origin, px)).toBe(key);
      key = addDaysKey(key, 1);
    }
  });

  it('DST 无关：按日历天计算，而不是毫秒', () => {
    // 2026-03-08 是北美 DST 切换日；日历差必须是 2 天而不是 47/48 小时。
    const px = 10;
    expect(dateToX('2026-03-09', '2026-03-07', px)).toBe(2 * px);
    expect(dateToX('2026-03-10', '2026-03-07', px)).toBe(3 * px);
    expect(xToDate(2 * px, '2026-03-07', px)).toBe('2026-03-09');
    expect(xToDate(2 * px + 3, '2026-03-07', px)).toBe('2026-03-09');
    expect(xToDate(0, '2026-03-07', px)).toBe('2026-03-07');
  });

  it('支持 Date 与日期键混用，负坐标可回退', () => {
    expect(dateToX(new Date(2026, 0, 5), new Date(2026, 0, 1), 20)).toBe(80);
    expect(xToDate(-1, '2026-01-05', 20)).toBe('2026-01-04');
    expect(xToDate(-25, '2026-01-05', 20)).toBe('2026-01-03');
  });
});

describe('snapDate', () => {
  it('三种缩放都吸附到 1 天并清空时间', () => {
    const value = new Date(2026, 2, 8, 23, 45, 12);
    for (const zoom of ['day', 'week', 'month'] as const) {
      const snapped = snapDate(value, zoom);
      expect(toKey(snapped)).toBe('2026-03-08');
      expect(snapped.getHours()).toBe(0);
      expect(snapped.getMinutes()).toBe(0);
    }
  });

  it('接受日期键并保持幂等', () => {
    expect(toKey(snapDate('2026-10-20', 'week'))).toBe('2026-10-20');
    expect(toKey(snapDate(snapDate('2026-10-20', 'day'), 'month'))).toBe('2026-10-20');
  });
});

describe('resizeBar', () => {
  const bar = { start: '2026-06-10', end: '2026-06-14' };

  it('左边缘右移保持 start <= end，最小 1 天', () => {
    expect(resizeBar(bar, 'start', 2)).toEqual({ start: '2026-06-12', end: '2026-06-14' });
    expect(resizeBar(bar, 'start', 3)).toEqual({ start: '2026-06-13', end: '2026-06-14' });
    expect(resizeBar(bar, 'start', 10)).toEqual({ start: '2026-06-14', end: '2026-06-14' });
  });

  it('右边缘左移保持 start <= end', () => {
    expect(resizeBar(bar, 'end', -2)).toEqual({ start: '2026-06-10', end: '2026-06-12' });
    expect(resizeBar(bar, 'end', -10)).toEqual({ start: '2026-06-10', end: '2026-06-10' });
  });

  it('负增量与小数增量按天取整', () => {
    expect(resizeBar(bar, 'start', -2.4)).toEqual({ start: '2026-06-08', end: '2026-06-14' });
    expect(resizeBar(bar, 'end', 1.6)).toEqual({ start: '2026-06-10', end: '2026-06-16' });
  });

  it('跨月 / 跨年边界', () => {
    const crossing = { start: '2025-12-31', end: '2026-01-02' };
    expect(resizeBar(crossing, 'end', 1)).toEqual({ start: '2025-12-31', end: '2026-01-03' });
    expect(resizeBar(crossing, 'start', 2)).toEqual({ start: '2026-01-02', end: '2026-01-02' });
  });
});

describe('bar geometry / moveBar', () => {
  it('缺失一端时按 1 天宽度', () => {
    const onlyStart = makeItem({ id: 'a', title: 'A', kind: 'action', gantt: { start: '2026-06-10', end: null, progress: 0 } });
    expect(itemRange(onlyStart)).toEqual({ start: '2026-06-10', end: '2026-06-10' });
    const onlyEnd = makeItem({ id: 'b', title: 'B', kind: 'action', gantt: { start: null, end: '2026-06-12', progress: 0 } });
    expect(itemRange(onlyEnd)).toEqual({ start: '2026-06-12', end: '2026-06-12' });
    const geometry = barGeometry(itemRange(onlyStart)!, '2026-06-01', 40);
    expect(geometry.x).toBe(9 * 40);
    expect(geometry.width).toBe(40);
    expect(geometry.days).toBe(1);
  });

  it('两端都没有时返回 null；反向区间自动纠正', () => {
    const empty = makeItem({ id: 'a', title: 'A', kind: 'action', gantt: { start: null, end: null, progress: 0 } });
    expect(itemRange(empty)).toBeNull();
    const reversed = makeItem({ id: 'b', title: 'B', kind: 'action', gantt: { start: '2026-06-14', end: '2026-06-10', progress: 0 } });
    expect(itemRange(reversed)).toEqual({ start: '2026-06-10', end: '2026-06-14' });
  });

  it('整体平移保持跨度', () => {
    expect(moveBar({ start: '2026-06-10', end: '2026-06-14' }, 3)).toEqual({
      start: '2026-06-13',
      end: '2026-06-17',
    });
    expect(moveBar({ start: '2026-01-01', end: '2026-01-01' }, -1)).toEqual({
      start: '2025-12-31',
      end: '2025-12-31',
    });
  });
});

describe('displayProgress', () => {
  it('已完成条目一律展示 100%，即使 gantt.progress 为 0 或缺失', () => {
    const doneWithZero = makeItem({
      id: 'done',
      title: '已完成',
      kind: 'action',
      status: 'done',
      gantt: { start: '2026-06-01', end: '2026-06-02', progress: 0 },
    });
    expect(displayProgress(doneWithZero)).toBe(100);

    const doneWithoutGantt = makeItem({ id: 'done-2', title: '已完成但未排期', kind: 'action', status: 'done' });
    expect(displayProgress(doneWithoutGantt)).toBe(100);

    const doneWithPartial = makeItem({
      id: 'done-3',
      title: '完成前进度 37',
      kind: 'action',
      status: 'done',
      gantt: { start: null, end: null, progress: 37 },
    });
    expect(displayProgress(doneWithPartial)).toBe(100);
  });

  it('未完成条目读取 gantt.progress 并四舍五入', () => {
    const item = makeItem({
      id: 'a',
      title: '进行中',
      kind: 'action',
      status: 'active',
      gantt: { start: '2026-06-01', end: '2026-06-02', progress: 42.6 },
    });
    expect(displayProgress(item)).toBe(43);

    const low = makeItem({
      id: 'b',
      title: '低进度',
      kind: 'action',
      status: 'next',
      gantt: { start: null, end: null, progress: 42.4 },
    });
    expect(displayProgress(low)).toBe(42);
  });

  it('缺 gantt 块或进度非法时按 0', () => {
    expect(displayProgress(makeItem({ id: 'no-gantt', title: '无排期', kind: 'action' }))).toBe(0);
    const missing = makeItem({
      id: 'missing',
      title: '缺进度',
      kind: 'action',
      gantt: { start: '2026-06-01', end: '2026-06-02', progress: 0 },
    });
    expect(displayProgress(missing)).toBe(0);

    const notANumber = makeItem({
      id: 'nan',
      title: 'NaN',
      kind: 'action',
      gantt: { start: null, end: null, progress: Number.NaN },
    });
    expect(displayProgress(notANumber)).toBe(0);
  });

  it('进度夹在 0..100，且不修改条目', () => {
    const over = makeItem({
      id: 'over',
      title: '超范围',
      kind: 'action',
      status: 'active',
      gantt: { start: '2026-06-01', end: '2026-06-02', progress: 150 },
    });
    expect(displayProgress(over)).toBe(100);

    const under = makeItem({
      id: 'under',
      title: '负进度',
      kind: 'action',
      status: 'active',
      gantt: { start: '2026-06-01', end: '2026-06-02', progress: -20 },
    });
    expect(displayProgress(under)).toBe(0);
    expect(under.gantt?.progress).toBe(-20);
  });
});

describe('buildRows', () => {
  const ws = makeWorkspace([
    makeItem({ id: 'p1', title: '官网改版', kind: 'project', order: 1, status: 'active', gantt: { start: '2026-01-05', end: '2026-01-10', progress: 30 } }),
    makeItem({ id: 'a2', title: '较早任务', kind: 'action', parentId: 'p1', order: 1, gantt: { start: '2026-01-05', end: '2026-01-06', progress: 0 } }),
    makeItem({ id: 'a1', title: '较晚任务', kind: 'action', parentId: 'p1', order: 0, gantt: { start: '2026-01-07', end: '2026-01-09', progress: 100 }, status: 'done' }),
    makeItem({ id: 'a3', title: '未排期任务', kind: 'action', parentId: 'p1', order: 2 }),
    makeItem({ id: 'a4', title: '最早任务', kind: 'action', parentId: 'p1', order: 3, gantt: { start: '2026-01-03', end: '2026-01-04', progress: 0 } }),
    makeItem({ id: 'a2b', title: '嵌套子任务', kind: 'action', parentId: 'a2', order: 0, gantt: { start: '2026-01-06', end: '2026-01-06', progress: 0 } }),
    makeItem({ id: 's1', title: '新用户 onboarding SOP', kind: 'sop', order: 0, status: 'active' }),
    makeItem({ id: 'step1', title: '注册', kind: 'step', parentId: 's1', order: 0 }),
    makeItem({ id: 'a5', title: '欢迎邮件初稿', kind: 'action', parentId: 's1', order: 1 }),
    makeItem({ id: 'r1', title: '整理本周复盘', kind: 'action', order: 4 }),
    makeItem({ id: 'i1', title: '收件箱任务', kind: 'action', order: 0, status: 'inbox' }),
    makeItem({ id: 'm1', title: '发布里程碑', kind: 'milestone', order: 5, gantt: { start: '2026-01-12', end: '2026-01-12', progress: 0 } }),
  ]);

  it('分组、组内排序、深度与汇总区间', () => {
    const rows = buildRows(ws);
    const groupIds = rows.filter((row) => row.type === 'group').map((row) => row.id);
    // 有日期的分组优先；SOP 只有未排期子项；未分组始终最后。
    expect(groupIds).toEqual(['p1', 's1', UNGROUPED_ID]);

    const p1 = rows[0];
    expect(p1.type).toBe('group');
    if (p1.type !== 'group') throw new Error('expected group');
    expect(p1.count).toBe(5);
    expect(p1.start).toBe('2026-01-03');
    expect(p1.end).toBe('2026-01-10');
    expect(p1.collapsed).toBe(false);

    const p1Items = rows.filter((row) => row.type === 'item' && row.groupId === 'p1');
    expect(p1Items.map((row) => row.id)).toEqual(['a4', 'a2', 'a2b', 'a1', 'a3']);
    const a2b = p1Items.find((row) => row.id === 'a2b');
    expect(a2b?.type === 'item' ? a2b.depth : 0).toBe(2);
    const a4 = p1Items.find((row) => row.id === 'a4');
    expect(a4?.type === 'item' ? a4.depth : 0).toBe(1);

    // 收件箱条目被排除，step 不进入甘特。
    expect(rows.some((row) => row.type === 'item' && row.id === 'i1')).toBe(false);
    expect(rows.some((row) => row.type === 'item' && row.id === 'step1')).toBe(false);

    const ungrouped = rows.find((row) => row.type === 'group' && row.id === UNGROUPED_ID);
    expect(ungrouped?.type === 'group' ? ungrouped.count : 0).toBe(2);
    const ungroupedIds = rows.filter((row) => row.type === 'item' && row.groupId === UNGROUPED_ID).map((row) => row.id);
    expect(ungroupedIds).toEqual(['m1', 'r1']);
  });

  it('折叠标记生效且组头保留统计', () => {
    const rows = buildRows(ws, new Set(['p1']));
    const p1 = rows[0];
    expect(p1.type).toBe('group');
    if (p1.type !== 'group') throw new Error('expected group');
    expect(p1.collapsed).toBe(true);
    expect(p1.count).toBe(5);
    expect(rows.some((row) => row.type === 'item' && row.groupId === 'p1')).toBe(false);

    const collapsedUngrouped = buildRows(ws, new Set([UNGROUPED_ID]));
    expect(collapsedUngrouped.some((row) => row.type === 'item' && row.groupId === UNGROUPED_ID)).toBe(false);
    expect(collapsedUngrouped.at(-1)?.id).toBe(UNGROUPED_ID);
  });
});

describe('buildHeader', () => {
  it('日模式每天一列，周末标记正确', () => {
    const header = buildHeader({ start: '2026-06-01', end: '2026-06-30' }, 'day', '2026-06-15');
    expect(header.columns).toHaveLength(30);
    expect(header.columns[0]).toMatchObject({ start: '2026-06-01', x: 0, width: 40, label: '1' });
    // 2026-06-06 / 07 是周六 / 周日
    expect(header.columns[5].weekend).toBe(true);
    expect(header.columns[6].weekend).toBe(true);
    expect(header.columns[7].weekend).toBe(false);
    expect(header.columns[13].past).toBe(true); // 06-14
    expect(header.columns[14].past).toBe(false); // 06-15
    expect(header.groups).toHaveLength(1);
    expect(header.groups[0].label).toContain('2026年6月');
    expect(header.width).toBe(30 * 40);
  });

  it('周模式按周一成列，宽度 7 天', () => {
    const header = buildHeader({ start: '2026-06-01', end: '2026-06-28' }, 'week', '2026-06-15');
    expect(header.columns).toHaveLength(4);
    expect(header.columns[0]).toMatchObject({ start: '2026-06-01', end: '2026-06-07', width: 196, label: '6/1' });
    expect(header.columns[1].label).toBe('6/8');
  });

  it('月模式按 1 / 8 / 15 / 22 / 29 切段', () => {
    const header = buildHeader({ start: '2026-06-01', end: '2026-07-31' }, 'month', '2026-06-15');
    const june = header.columns.filter((column) => column.start.startsWith('2026-06'));
    expect(june.map((column) => column.label)).toEqual(['1', '8', '15', '22', '29']);
    expect(june[0].width).toBe(7 * 12);
    expect(june[4].width).toBe(2 * 12); // 06-29 / 30
    expect(header.groups.map((group) => group.label)).toEqual(['2026 Q2', '2026 Q3']);
  });
});

describe('visibleRange / formatRangeLabel', () => {
  it('计算滚动窗口并夹在总范围内', () => {
    const range = { start: '2026-06-01', end: '2026-06-30' };
    expect(visibleRange(range, 0, 400, 40)).toEqual({ start: '2026-06-01', end: '2026-06-10' });
    expect(visibleRange(range, -100, 200, 40)).toEqual({ start: '2026-06-01', end: '2026-06-03' });
    expect(visibleRange(range, 1200, 400, 40)).toEqual({ start: '2026-06-30', end: '2026-06-30' });
  });

  it('区间标签跨月 / 跨年可读', () => {
    expect(formatRangeLabel('2026-10-20', '2026-11-16')).toBe('10月 20 – 11月 16');
    expect(formatRangeLabel('2025-12-29', '2026-01-11')).toBe('2025年12月 29 – 2026年1月 11');
  });
});
