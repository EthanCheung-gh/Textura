import { describe, expect, it } from 'vitest';
import type { Item, ItemKind, ItemStatus } from '../../core/model';
import {
  bucketItemsByDay,
  buildMonthGrid,
  cellAriaLabel,
  fullDateLabel,
  itemSpan,
  lunarFullLabel,
  lunarLabel,
  lunarLabelInfo,
  monthLabel,
  relativeDayLabel,
  shiftMonth,
  shouldAutoOpenPanel,
  sortDayItems,
  spanDayIndex,
  visibleItems,
  weekDays,
  weekLabel,
  weekRange,
  weekdayLabel,
} from './calendarLogic';
import { solarToLunar } from './lunar';

function makeItem(
  partial: Partial<Item> & { id: string; title: string },
  kind: ItemKind = 'action',
  status: ItemStatus = 'next',
): Item {
  return {
    kind,
    notes: '',
    parentId: null,
    order: 0,
    status,
    tags: [],
    areaId: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    completedAt: null,
    ...partial,
  } as Item;
}

function ganttItem(id: string, title: string, start: string | null, end: string | null): Item {
  return makeItem({ id, title, gantt: { start, end, progress: 0 } });
}

describe('buildMonthGrid', () => {
  it('2026 年 10 月固定 42 格，首格 2026-09-28（周一），末格 2026-11-08', () => {
    const cells = buildMonthGrid(2026, 10);
    expect(cells).toHaveLength(42);
    expect(cells[0].key).toBe('2026-09-28');
    expect(cells[0].weekday).toBe(0); // 周一
    expect(cells[0].inMonth).toBe(false);
    expect(cells[41].key).toBe('2026-11-08');
    expect(cells.filter((cell) => cell.inMonth)).toHaveLength(31);
  });

  it('网格按周排列，周一为每行首日', () => {
    const cells = buildMonthGrid(2026, 10);
    for (let row = 0; row < 6; row += 1) {
      const week = cells.slice(row * 7, row * 7 + 7);
      expect(week.map((cell) => cell.weekday)).toEqual([0, 1, 2, 3, 4, 5, 6]);
    }
    expect(cells[3].key).toBe('2026-10-01');
    expect(cells[3].inMonth).toBe(true);
    expect(weekdayLabel(cells[3].key)).toBe('星期四');
  });

  it('周末列标记正确', () => {
    const cells = buildMonthGrid(2026, 10);
    expect(cells[5].weekend).toBe(true); // 周六
    expect(cells[6].weekend).toBe(true); // 周日
    expect(cells[4].weekend).toBe(false);
  });

  it('跨年：2027 年 1 月首格为 2026-12-28，12 月 → 次年 1 月', () => {
    const cells = buildMonthGrid(2027, 1);
    expect(cells[0].key).toBe('2026-12-28');
    expect(cells[41].key).toBe('2027-02-07');
    expect(shiftMonth(2026, 12, 1)).toEqual({ year: 2027, month: 1 });
    expect(shiftMonth(2026, 1, -1)).toEqual({ year: 2025, month: 12 });
    expect(shiftMonth(2026, 10, 3)).toEqual({ year: 2027, month: 1 });
  });

  it('闰年二月有 29 天', () => {
    expect(buildMonthGrid(2024, 2).filter((cell) => cell.inMonth)).toHaveLength(29);
    expect(buildMonthGrid(2026, 2).filter((cell) => cell.inMonth)).toHaveLength(28);
  });
});

describe('weekRange / weekDays', () => {
  it('2026-10-21 所在周为 10-19 ～ 10-25', () => {
    expect(weekRange('2026-10-21')).toMatchObject({ start: '2026-10-19', end: '2026-10-25' });
  });

  it('周日属于同一周', () => {
    expect(weekRange('2026-10-25')).toMatchObject({ start: '2026-10-19', end: '2026-10-25' });
  });

  it('跨年周', () => {
    expect(weekRange('2027-01-01')).toMatchObject({ start: '2026-12-28', end: '2027-01-03' });
  });

  it('weekDays 返回连续 7 天', () => {
    const days = weekDays('2026-10-21');
    expect(days.map((day) => day.key)).toEqual([
      '2026-10-19',
      '2026-10-20',
      '2026-10-21',
      '2026-10-22',
      '2026-10-23',
      '2026-10-24',
      '2026-10-25',
    ]);
    expect(days.map((day) => day.weekday)).toEqual([0, 1, 2, 3, 4, 5, 6]);
  });
});

describe('月份 / 周标签', () => {
  it('monthLabel / weekLabel', () => {
    expect(monthLabel(2026, 10)).toBe('2026年10月');
    expect(weekLabel('2026-10-21')).toBe('10月19日 – 25日');
    expect(weekLabel('2026-10-01')).toBe('9月28日 – 10月4日');
    expect(weekLabel('2027-01-01')).toBe('2026年12月28日 – 1月3日');
  });
});

describe('bucketItemsByDay', () => {
  const spanning = ganttItem('a', '跨天任务', '2026-09-29', '2026-10-02');
  const dueOnly = ganttItem('b', '只有截止日', null, '2026-10-05');
  const lastDay = ganttItem('c', '月末单日', '2026-10-31', '2026-10-31');
  const crossesEnd = ganttItem('d', '跨到下月', '2026-10-30', '2026-11-02');
  const outside = ganttItem('e', '完全在区间外', '2026-11-10', '2026-11-12');
  const noDates = makeItem({ id: 'f', title: '没有日期' });
  const items = [spanning, dueOnly, lastDay, crossesEnd, outside, noDates];

  it('跨天条目落在每个覆盖日，超出区间部分被裁剪', () => {
    const buckets = bucketItemsByDay(items, '2026-10-01', '2026-10-31');
    expect(buckets.has('2026-09-29')).toBe(false);
    expect(buckets.get('2026-10-01')?.map((item) => item.id)).toEqual(['a']);
    expect(buckets.get('2026-10-02')?.map((item) => item.id)).toEqual(['a']);
    expect(buckets.has('2026-10-03')).toBe(false);
  });

  it('只有 end（GTD 截止日）的条目只出现在当天', () => {
    const buckets = bucketItemsByDay(items, '2026-10-01', '2026-10-31');
    expect(buckets.get('2026-10-05')?.map((item) => item.id)).toEqual(['b']);
    expect(buckets.get('2026-10-04')).toBeUndefined();
    expect(buckets.get('2026-10-06')).toBeUndefined();
  });

  it('边界日（区间首日 / 末日）包含在内', () => {
    const buckets = bucketItemsByDay(items, '2026-10-01', '2026-10-02');
    expect([...buckets.keys()].sort()).toEqual(['2026-10-01', '2026-10-02']);
  });

  it('跨月末的条目只分桶到区间内', () => {
    const buckets = bucketItemsByDay(items, '2026-10-01', '2026-10-31');
    expect(buckets.get('2026-10-30')?.map((item) => item.id)).toEqual(['d']);
    expect(buckets.get('2026-10-31')?.map((item) => item.id)).toEqual(['d', 'c']);
    expect(buckets.has('2026-11-01')).toBe(false);
  });

  it('没有日期的条目与区间外条目被忽略', () => {
    const buckets = bucketItemsByDay(items, '2026-10-01', '2026-10-31');
    const ids = new Set([...buckets.values()].flat().map((item) => item.id));
    expect(ids.has('e')).toBe(false);
    expect(ids.has('f')).toBe(false);
  });

  it('from > to 自动交换；非法输入返回空 Map', () => {
    const forward = bucketItemsByDay(items, '2026-10-01', '2026-10-02');
    const reversed = bucketItemsByDay(items, '2026-10-02', '2026-10-01');
    expect([...reversed.keys()].sort()).toEqual([...forward.keys()].sort());
    expect(bucketItemsByDay(items, '', '2026-10-02').size).toBe(0);
  });
});

describe('itemSpan / spanDayIndex / sortDayItems', () => {
  it('起止与天数', () => {
    expect(itemSpan(ganttItem('x', 'x', '2026-10-01', '2026-10-03'))).toEqual({
      start: '2026-10-01',
      end: '2026-10-03',
      days: 3,
    });
    expect(itemSpan(makeItem({ id: 'y', title: 'y' }))).toBeNull();
    // 反向区间被归一化
    expect(itemSpan(ganttItem('z', 'z', '2026-10-05', '2026-10-02'))?.start).toBe('2026-10-02');
  });

  it('跨天条目在每列标注第 n 天', () => {
    const item = ganttItem('x', 'x', '2026-10-01', '2026-10-03');
    expect(spanDayIndex(item, '2026-10-01')).toBe(1);
    expect(spanDayIndex(item, '2026-10-02')).toBe(2);
    expect(spanDayIndex(item, '2026-10-04')).toBe(0);
  });

  it('排序：跨天优先 → 开始日期 → 标题', () => {
    const single = ganttItem('s', 'B 单日', '2026-10-10', '2026-10-10');
    const sameDayA = ganttItem('sa', 'A 单日', '2026-10-10', '2026-10-10');
    const span = ganttItem('sp', '跨天', '2026-10-08', '2026-10-11');
    const sorted = sortDayItems([single, sameDayA, span]);
    expect(sorted.map((item) => item.title)).toEqual(['跨天', 'A 单日', 'B 单日']);
  });

  it('桌面隐藏 dropped，保留 done', () => {
    const done = makeItem({ id: 'd', title: '已完成' }, 'action', 'done');
    const dropped = makeItem({ id: 'x', title: '已放弃' }, 'action', 'dropped');
    expect(visibleItems([done, dropped]).map((item) => item.id)).toEqual(['d']);
  });
});

describe('农历标签优先级', () => {
  it('传统节日优先于节气与农历日', () => {
    expect(lunarLabel('2026-09-25')).toBe('中秋');
    expect(lunarLabelInfo('2026-09-25')).toEqual({ kind: 'festival', text: '中秋' });
  });

  it('清明按节气定日，显示为节日', () => {
    expect(lunarLabel('2026-04-05')).toBe('清明');
    expect(lunarLabelInfo('2026-04-05').kind).toBe('festival');
  });

  it('节气优先于农历日', () => {
    expect(lunarLabel('2026-09-23')).toBe('秋分');
    expect(lunarLabelInfo('2026-09-23')).toEqual({ kind: 'term', text: '秋分' });
  });

  it('初一显示月名，其余显示日名', () => {
    expect(lunarLabel('2026-10-10')).toBe('九月');
    expect(lunarLabel('2026-10-21')).toBe('十二');
    const leap = solarToLunar('2025-07-25');
    expect(lunarLabel('2025-07-25')).toBe(leap?.monthName);
    expect(lunarLabel('2025-07-25')).toBe('闰六月');
  });

  it('超出支持范围返回空标签', () => {
    expect(lunarLabel('1900-01-01')).toBe('');
    expect(lunarLabelInfo('2101-05-01')).toEqual({ kind: 'none', text: '' });
  });

  it('农历全称', () => {
    const lunar = solarToLunar('2026-10-21');
    expect(lunar).not.toBeNull();
    expect(lunarFullLabel(lunar!)).toBe('丙午年 九月十二');
  });
});

describe('无障碍与相对日期文案', () => {
  it('fullDateLabel', () => {
    expect(fullDateLabel('2026-10-21')).toBe('2026年10月21日 星期三');
  });

  it('cellAriaLabel 形如「2026年10月21日，星期三，农历九月十二，今天」', () => {
    expect(cellAriaLabel('2026-10-21', '2026-10-21')).toBe(
      '2026年10月21日，星期三，农历九月十二，今天',
    );
    expect(cellAriaLabel('2026-10-21', '2026-10-22')).toBe(
      '2026年10月21日，星期三，农历九月十二',
    );
  });

  it('节日与节气写入 aria-label', () => {
    expect(cellAriaLabel('2026-09-25', '2026-10-21')).toBe(
      '2026年9月25日，星期五，农历八月十五，中秋',
    );
    expect(cellAriaLabel('2026-09-23', '2026-10-21')).toBe(
      '2026年9月23日，星期三，农历八月十三，秋分节气',
    );
  });

  it('relativeDayLabel', () => {
    expect(relativeDayLabel('2026-10-21', '2026-10-21')).toBe('今天');
    expect(relativeDayLabel('2026-10-22', '2026-10-21')).toBe('明天');
    expect(relativeDayLabel('2026-10-20', '2026-10-21')).toBe('昨天');
    expect(relativeDayLabel('2026-10-31', '2026-10-21')).toBe('10 天后');
    expect(relativeDayLabel('2026-10-11', '2026-10-21')).toBe('10 天前');
  });
});

describe('shouldAutoOpenPanel（窄屏选中日期是否自动展开）', () => {
  const NARROW = 1024;
  const WIDE = 1440;

  it('折叠 + 窄视口 + 未手动收起 → 自动展开', () => {
    expect(shouldAutoOpenPanel(false, NARROW, false)).toBe(true);
  });

  it('折叠 + 宽视口 → 不自动展开（宽屏面板常驻）', () => {
    expect(shouldAutoOpenPanel(false, WIDE, false)).toBe(false);
  });

  it('面板已展开 → 不重复展开', () => {
    expect(shouldAutoOpenPanel(true, NARROW, false)).toBe(false);
  });

  it('用户手动收起过 → 尊重意图，选中日期不自动展开', () => {
    expect(shouldAutoOpenPanel(false, NARROW, true)).toBe(false);
  });

  it('1180 为断点边界（含），1181 不触发', () => {
    expect(shouldAutoOpenPanel(false, 1180, false)).toBe(true);
    expect(shouldAutoOpenPanel(false, 1181, false)).toBe(false);
  });
});
