/**
 * 日历视图的纯计算逻辑：月网格、周区间、按日分桶、标签与无障碍文案。
 * 全部函数只依赖 core 类型与 utils + lunar 引擎，方便单测。
 */
import type { Item } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { dateKey } from '../../core/utils';
import type { LunarDate } from './lunar';
import { addDaysToKey, dayNumberFromKey, keyFromDayNumber, solarToLunar } from './lunar';

export type CalendarView = 'month' | 'week';

/** 窄视口断点：≤1180px 时日程面板折叠为底部抽屉。 */
export const PANEL_BREAKPOINT = 1180;

/**
 * 选中日期时是否应自动展开日程面板。
 *
 * 规则：面板当前收起、视口处于窄屏（≤ breakpoint）、且本次会话中用户没有手动收起过。
 * 用户手动收起后保持收起意图，直到再次点击「展开日程」。
 */
export function shouldAutoOpenPanel(
  panelOpen: boolean,
  viewportWidth: number,
  userCollapsed: boolean,
  breakpoint: number = PANEL_BREAKPOINT,
): boolean {
  if (panelOpen) return false;
  if (userCollapsed) return false;
  return viewportWidth <= breakpoint;
}

export interface MonthCell {
  /** YYYY-MM-DD */
  key: string;
  year: number;
  month: number;
  day: number;
  /** 0 = 周一 … 6 = 周日 */
  weekday: number;
  /** 是否属于当前展示月 */
  inMonth: boolean;
  /** 是否周末（周六/周日） */
  weekend: boolean;
}

export interface WeekInfo {
  /** YYYY-MM-DD */
  start: string;
  /** YYYY-MM-DD */
  end: string;
  year: number;
  month: number;
  /** 1..12 */
  monthEnd: number;
}

const WEEKDAY_CN = ['一', '二', '三', '四', '五', '六', '日'];
const WEEKDAY_FULL_CN = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const MONTH_NAMES_CN = [
  '一月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '十一月', '十二月',
];

export function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

export function makeKey(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** 周一为 0 的星期序号。1970-01-01（日序号 0）是星期四。 */
export function weekdayIndexMonday(dayNumber: number): number {
  return ((dayNumber + 3) % 7 + 7) % 7;
}

export function weekdayOfKey(key: string): number {
  const dayNumber = dayNumberFromKey(key);
  return dayNumber === null ? 0 : weekdayIndexMonday(dayNumber);
}

/** 周一为每周首日 */
export const WEEKDAY_LABELS = WEEKDAY_CN;

export function weekdayLabel(key: string): string {
  return WEEKDAY_FULL_CN[weekdayOfKey(key)];
}

/** 月份标题：2026年10月 */
export function monthLabel(year: number, month: number): string {
  return `${year}年${month}月`;
}

/** 年月偏移（月份 1..12） */
export function shiftMonth(year: number, month: number, delta: number): { year: number; month: number } {
  const zeroBased = year * 12 + (month - 1) + delta;
  return { year: Math.floor(zeroBased / 12), month: (zeroBased % 12) + 1 };
}

/** 固定 6×7 = 42 格的月网格，周一为首列，含上下月补位。 */
export function buildMonthGrid(year: number, month: number): MonthCell[] {
  const first = dayNumberFromKey(makeKey(year, month, 1));
  if (first === null) return [];
  const start = first - weekdayIndexMonday(first);
  const cells: MonthCell[] = [];
  for (let index = 0; index < 42; index += 1) {
    const dayNumber = start + index;
    const key = keyFromDayNumber(dayNumber);
    const cellYear = Number(key.slice(0, 4));
    const cellMonth = Number(key.slice(5, 7));
    const cellDay = Number(key.slice(8, 10));
    const weekday = index % 7;
    cells.push({
      key,
      year: cellYear,
      month: cellMonth,
      day: cellDay,
      weekday,
      inMonth: cellYear === year && cellMonth === month,
      weekend: weekday >= 5,
    });
  }
  return cells;
}

/** 所在周的周一～周日 */
export function weekRange(key: string): WeekInfo {
  const dayNumber = dayNumberFromKey(key);
  if (dayNumber === null) return { start: key, end: key, year: 0, month: 0, monthEnd: 0 };
  const start = dayNumber - weekdayIndexMonday(dayNumber);
  const startKey = keyFromDayNumber(start);
  const endKey = keyFromDayNumber(start + 6);
  return {
    start: startKey,
    end: endKey,
    year: Number(startKey.slice(0, 4)),
    month: Number(startKey.slice(5, 7)),
    monthEnd: Number(endKey.slice(5, 7)),
  };
}

/** 周视图 7 天 */
export function weekDays(key: string): MonthCell[] {
  const range = weekRange(key);
  return Array.from({ length: 7 }, (_, index) => {
    const dayKey = addDaysToKey(range.start, index);
    const weekday = index;
    return {
      key: dayKey,
      year: Number(dayKey.slice(0, 4)),
      month: Number(dayKey.slice(5, 7)),
      day: Number(dayKey.slice(8, 10)),
      weekday,
      inMonth: true,
      weekend: weekday >= 5,
    };
  });
}

/** 周区间标题：10月19日 – 10月25日（跨年时带上年份） */
export function weekLabel(key: string): string {
  const range = weekRange(key);
  const startMonth = Number(range.start.slice(5, 7));
  const startDay = Number(range.start.slice(8, 10));
  const endMonth = Number(range.end.slice(5, 7));
  const endDay = Number(range.end.slice(8, 10));
  const prefix = range.year === Number(range.end.slice(0, 4)) ? '' : `${range.year}年`;
  if (startMonth === endMonth) {
    return `${prefix}${startMonth}月${startDay}日 – ${endDay}日`;
  }
  return `${prefix}${startMonth}月${startDay}日 – ${endMonth}月${endDay}日`;
}

export function lunarOf(key: string): LunarDate | null {
  return solarToLunar(key);
}

export interface LabelTone {
  kind: 'festival' | 'term' | 'lunar' | 'none';
  text: string;
}

/**
 * 农历标签优先级：传统节日 > 节气 > 农历日（初一显示月名）。
 * 超出农历支持范围时返回 none（只显示公历）。
 */
export function lunarLabelOf(lunar: LunarDate | null): LabelTone {
  if (!lunar) return { kind: 'none', text: '' };
  if (lunar.festival) return { kind: 'festival', text: lunar.festival };
  if (lunar.solarTerm) return { kind: 'term', text: lunar.solarTerm };
  if (lunar.day === 1) return { kind: 'lunar', text: lunar.monthName };
  return { kind: 'lunar', text: lunar.dayName };
}

/** 农历标签（内部只换算一次农历）。 */
export function lunarLabelInfo(key: string): LabelTone {
  return lunarLabelOf(lunarOf(key));
}

export function lunarLabel(key: string): string {
  return lunarLabelInfo(key).text;
}

export interface DayItemSpan {
  start: string;
  end: string;
  /** 覆盖天数（含首尾） */
  days: number;
}

/** 条目占用的日期区间；只有 end（GTD 截止日）时收敛为单日。 */
export function itemSpan(item: Item): DayItemSpan | null {
  const start = dateKey(item.gantt?.start) ?? dateKey(item.gantt?.end);
  const end = dateKey(item.gantt?.end) ?? dateKey(item.gantt?.start);
  if (!start || !end) return null;
  const startNumber = dayNumberFromKey(start);
  const endNumber = dayNumberFromKey(end);
  if (startNumber === null || endNumber === null) return null;
  if (endNumber < startNumber) return { start: end, end: start, days: startNumber - endNumber + 1 };
  return { start, end, days: endNumber - startNumber + 1 };
}

/** 第 n 天（1 起）；不在区间内返回 0。 */
export function spanDayIndex(item: Item, key: string): number {
  const span = itemSpan(item);
  if (!span) return 0;
  const start = dayNumberFromKey(span.start);
  const current = dayNumberFromKey(key);
  if (start === null || current === null) return 0;
  const index = current - start + 1;
  return index >= 1 && index <= span.days ? index : 0;
}

/**
 * 按日分桶：跨天条目落在每个覆盖日，仅 end 的条目落在当天，边界日包含。
 * 超出 [from, to] 的部分被裁剪；`from > to` 自动交换。
 */
export function bucketItemsByDay(items: Item[], from: string, to: string): Map<string, Item[]> {
  let startKey = dateKey(from);
  let endKey = dateKey(to);
  const buckets = new Map<string, Item[]>();
  if (!startKey || !endKey) return buckets;
  if (startKey > endKey) [startKey, endKey] = [endKey, startKey];

  for (const item of items) {
    const span = itemSpan(item);
    if (!span) continue;
    const visibleStart = span.start < startKey ? startKey : span.start;
    const visibleEnd = span.end > endKey ? endKey : span.end;
    const startNumber = dayNumberFromKey(visibleStart);
    const endNumber = dayNumberFromKey(visibleEnd);
    if (startNumber === null || endNumber === null || endNumber < startNumber) continue;
    for (let dayNumber = startNumber; dayNumber <= endNumber; dayNumber += 1) {
      const key = keyFromDayNumber(dayNumber);
      const list = buckets.get(key);
      if (list) list.push(item);
      else buckets.set(key, [item]);
    }
  }

  for (const [key, list] of buckets) buckets.set(key, sortDayItems(list));
  return buckets;
}

/**
 * 当日条目排序：全天/跨天优先 → 开始日期 → 标题。
 * 同一天内单日条目按标题排序（模型没有时刻字段）。
 */
export function sortDayItems(items: Item[]): Item[] {
  return [...items].sort((a, b) => {
    const spanA = itemSpan(a);
    const spanB = itemSpan(b);
    const rankA = spanA && spanA.days > 1 ? 0 : 1;
    const rankB = spanB && spanB.days > 1 ? 0 : 1;
    if (rankA !== rankB) return rankA - rankB;
    const startA = spanA?.start ?? '';
    const startB = spanB?.start ?? '';
    if (startA !== startB) return startA.localeCompare(startB);
    return a.title.localeCompare(b.title, 'zh-Hans-CN');
  });
}

/** 过滤已放弃条目（done 保留）。 */
export function visibleItems(items: Item[]): Item[] {
  return items.filter((item) => item.status !== 'dropped');
}

export function isDoneItem(item: Item): boolean {
  return item.status === 'done';
}

export function statusLabel(item: Item): string {
  return STATUS_LABELS[item.status];
}

/** 相对今天的文案：今天 / 明天 / 昨天 / n 天后 / n 天前。 */
export function relativeDayLabel(key: string, today: string): string {
  const target = dayNumberFromKey(key);
  const base = dayNumberFromKey(today);
  if (target === null || base === null) return '';
  const diff = target - base;
  if (diff === 0) return '今天';
  if (diff === 1) return '明天';
  if (diff === -1) return '昨天';
  return diff > 0 ? `${diff} 天后` : `${-diff} 天前`;
}

/** 农历全称：丙午年 九月初一 */
export function lunarFullLabel(lunar: LunarDate): string {
  return `${lunar.ganzhiYear}年 ${lunar.monthName}${lunar.dayName}`;
}

/** 2026年10月21日 星期三 */
export function fullDateLabel(key: string): string {
  const year = Number(key.slice(0, 4));
  const month = Number(key.slice(5, 7));
  const day = Number(key.slice(8, 10));
  return `${year}年${month}月${day}日 ${weekdayLabel(key)}`;
}

/** 网格单元格的无障碍名称：2026年10月21日，星期三，农历九月初一，今天 */
export function cellAriaLabelOf(key: string, lunar: LunarDate | null, today?: string): string {
  const year = Number(key.slice(0, 4));
  const month = Number(key.slice(5, 7));
  const day = Number(key.slice(8, 10));
  const parts = [`${year}年${month}月${day}日`, weekdayLabel(key)];
  if (lunar) {
    parts.push(`农历${lunar.monthName}${lunar.dayName}`);
    if (lunar.festival && lunar.festival !== lunar.solarTerm) parts.push(lunar.festival);
    else if (lunar.solarTerm) parts.push(`${lunar.solarTerm}节气`);
  }
  if (today && key === today) parts.push('今天');
  return parts.join('，');
}

/** 便捷版本：内部换算一次农历。 */
export function cellAriaLabel(key: string, today?: string): string {
  return cellAriaLabelOf(key, lunarOf(key), today);
}

/** 月份选择器选项 1..12 */
export function monthOptions(): Array<{ value: string; label: string }> {
  return MONTH_NAMES_CN.map((label, index) => ({ value: String(index + 1), label }));
}

/** 年份选择器选项 1900..2100 */
export function yearOptions(): Array<{ value: string; label: string }> {
  return Array.from({ length: 2100 - 1900 + 1 }, (_, index) => {
    const year = 1900 + index;
    return { value: String(year), label: `${year}年` };
  });
}
