/**
 * 甘特图纯函数层：日期 ↔ 像素、吸附、可视范围、表头列、任务条几何、分组行构建。
 *
 * 约定：
 * - 全部日期比较都走 'YYYY-MM-DD' 本地日期键（与 date-fns 的日历差），不碰毫秒，
 *   因此 DST / 时区切换不会导致列宽或拖拽偏移。
 * - 所有函数无副作用，便于 vitest 直接覆盖（`src/**\/*.test.ts`）。
 */
import {
  addDays,
  differenceInCalendarDays,
  endOfMonth,
  endOfQuarter,
  endOfWeek,
  format,
  parseISO,
  startOfMonth,
  startOfQuarter,
  startOfWeek,
} from 'date-fns';
import type { Item, ItemKind, Workspace } from '../../core/model';
import { ancestorsOf, descendantsOf, rollupProgress, treeDepth } from '../../core/selectors';
import { dateKey } from '../../core/utils';

export type GanttZoom = 'day' | 'week' | 'month';

export interface ZoomConfig {
  /** 每天像素宽度 */
  pxPerDay: number;
  /** 一个下层表头单元格覆盖的天数 */
  columnDays: number;
  /** 拖拽吸附粒度（天） */
  snapDays: number;
  /** 适配窗口时向前 / 向后留白的天数 */
  paddingBefore: number;
  paddingAfter: number;
}

export const ZOOM_CONFIG: Record<GanttZoom, ZoomConfig> = {
  day: { pxPerDay: 40, columnDays: 1, snapDays: 1, paddingBefore: 7, paddingAfter: 14 },
  week: { pxPerDay: 28, columnDays: 7, snapDays: 1, paddingBefore: 14, paddingAfter: 28 },
  month: { pxPerDay: 12, columnDays: 7, snapDays: 1, paddingBefore: 30, paddingAfter: 60 },
};

/** 行高固定 36px，左侧树与右侧条区共用。 */
export const ROW_HEIGHT = 36;
/** 两级表头总高度。 */
export const HEADER_HEIGHT = 52;
/** 无父级、且不属于任何 project/sop 分组的条目。 */
export const UNGROUPED_ID = '__ungrouped';

export interface DateRange {
  start: string;
  end: string;
}

export interface BarRange {
  start: string;
  end: string;
}

export interface BarGeometry extends BarRange {
  x: number;
  width: number;
  /** 含首尾的天数，最小 1 */
  days: number;
}

export interface TimelineColumn {
  key: string;
  start: string;
  end: string;
  x: number;
  width: number;
  label: string;
  sublabel?: string;
  weekend: boolean;
  past: boolean;
}

export interface HeaderGroup {
  key: string;
  label: string;
  x: number;
  width: number;
}

export interface TimelineHeader {
  groups: HeaderGroup[];
  columns: TimelineColumn[];
  width: number;
}

/* ------------------------------------------------------------------ *
 * 基础日期工具
 * ------------------------------------------------------------------ */

/** 把 Date / 'YYYY-MM-DD' / ISO 串统一为本地午夜 Date；非法时返回 Invalid Date。 */
export function toDate(value: Date | string): Date {
  if (value instanceof Date) return value;
  const key = dateKey(value);
  if (key) {
    const parsed = parseISO(key);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return new Date(NaN);
}

export function toKey(value: Date | string): string {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  return format(toDate(value), 'yyyy-MM-dd');
}

/** b - a，按日历天（与时区 / DST 无关）。 */
export function diffDays(a: Date | string, b: Date | string): number {
  return differenceInCalendarDays(toDate(b), toDate(a));
}

export function addDaysKey(key: string, days: number): string {
  return format(addDays(toDate(key), days), 'yyyy-MM-dd');
}

/** 本地日期 → 相对 origin 左边界的像素坐标。 */
export function dateToX(date: Date | string, origin: Date | string, pxPerDay: number): number {
  return diffDays(origin, date) * pxPerDay;
}

/** 像素坐标 → 该位置所在日期的键（左闭右开映射到所在天）。 */
export function xToDate(x: number, origin: Date | string, pxPerDay: number): string {
  const originKey = toKey(origin);
  if (!Number.isFinite(x)) return originKey;
  return addDaysKey(originKey, Math.floor(x / pxPerDay));
}

/**
 * 吸附到日历天。三种缩放的吸附粒度都是 1 天（契约要求），
 * 返回本地午夜 Date，便于直接转日期键。
 */
export function snapDate(value: Date | string, zoom: GanttZoom): Date {
  const step = Math.max(1, ZOOM_CONFIG[zoom].snapDays);
  const snapped = toDate(toKey(value));
  if (step === 1) {
    return new Date(snapped.getFullYear(), snapped.getMonth(), snapped.getDate());
  }
  const offset = snapped.getDate() % step;
  return addDays(snapped, -offset);
}

export function normalizeBar(start: string, end: string): BarRange {
  return start <= end ? { start, end } : { start: end, end: start };
}

/* ------------------------------------------------------------------ *
 * 任务条几何 / 拖拽
 * ------------------------------------------------------------------ */

/** 条目有效的起止（缺失一端时按 1 天处理）；两端都没有返回 null。 */
export function itemRange(item: Item): BarRange | null {
  const start = dateKey(item.gantt?.start);
  const end = dateKey(item.gantt?.end);
  if (!start && !end) return null;
  return normalizeBar(start ?? end!, end ?? start!);
}

/**
 * 甘特视图统一的进度展示口径：
 * - `status === 'done'` 一律视为 100（toggleDone 不会回写 gantt.progress）；
 * - 其余取 `gantt.progress`，缺失 / 非数按 0，并夹到 0..100 的整数。
 * 只用于展示，不写回 store。
 */
export function displayProgress(item: Item): number {
  if (item.status === 'done') return 100;
  const raw = item.gantt?.progress;
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return 0;
  return Math.min(100, Math.max(0, Math.round(raw)));
}

/** 把像素位置 + 缩放换算成绝对几何。 */
export function barGeometry(range: BarRange, origin: string, pxPerDay: number): BarGeometry {
  const normalized = normalizeBar(range.start, range.end);
  const days = diffDays(normalized.start, normalized.end) + 1;
  return {
    ...normalized,
    x: diffDays(origin, normalized.start) * pxPerDay,
    width: Math.max(pxPerDay, days * pxPerDay),
    days: Math.max(1, days),
  };
}

/** 整体平移（deltaDays 允许为负，调用方负责吸附）。 */
export function moveBar(bar: BarRange, deltaDays: number): BarRange {
  const delta = Math.round(deltaDays);
  return { start: addDaysKey(bar.start, delta), end: addDaysKey(bar.end, delta) };
}

/**
 * 拖左右边缘：保持 start <= end，最小 1 天。
 * 左边缘向右越过 end 时夹到 end；右边缘向左越过 start 时夹到 start。
 */
export function resizeBar(bar: BarRange, edge: 'start' | 'end', deltaDays: number): BarRange {
  const delta = Math.round(deltaDays);
  const normalized = normalizeBar(bar.start, bar.end);
  if (edge === 'start') {
    const candidate = addDaysKey(normalized.start, delta);
    return { start: candidate > normalized.end ? normalized.end : candidate, end: normalized.end };
  }
  const candidate = addDaysKey(normalized.end, delta);
  return { start: normalized.start, end: candidate < normalized.start ? normalized.start : candidate };
}

/* ------------------------------------------------------------------ *
 * 可视范围 / 适配窗口
 * ------------------------------------------------------------------ */

/**
 * 时间轴总范围：
 * - 无排期条目：以 today 为中心按缩放留白；
 * - 有条目：覆盖最早开始 → 最晚结束，并加缓冲；today 始终在范围内。
 * 周模式对齐到周一，月模式对齐到月初 / 月末，保证表头从边界开始。
 */
export function buildRange(
  items: Item[],
  zoom: GanttZoom,
  today: Date | string = new Date(),
): DateRange {
  const config = ZOOM_CONFIG[zoom];
  const todayKey = toKey(snapDate(today, zoom));
  let min = todayKey;
  let max = todayKey;
  for (const item of items) {
    const range = itemRange(item);
    if (!range) continue;
    if (range.start < min) min = range.start;
    if (range.end > max) max = range.end;
  }

  let start = addDaysKey(min, -config.paddingBefore);
  let end = addDaysKey(max, config.paddingAfter);

  if (zoom === 'week') {
    start = format(startOfWeek(toDate(start), { weekStartsOn: 1 }), 'yyyy-MM-dd');
    end = format(endOfWeek(toDate(end), { weekStartsOn: 1 }), 'yyyy-MM-dd');
  } else if (zoom === 'month') {
    start = format(startOfMonth(toDate(start)), 'yyyy-MM-dd');
    end = format(endOfMonth(toDate(end)), 'yyyy-MM-dd');
  }

  return { start, end };
}

/** 当前滚动窗口对应的日期范围（用于周末底色 / 区间标签）。 */
export function visibleRange(
  range: DateRange,
  scrollLeft: number,
  width: number,
  pxPerDay: number,
): DateRange {
  const start = xToDate(Math.max(0, scrollLeft), range.start, pxPerDay);
  const end = xToDate(Math.max(0, scrollLeft + Math.max(1, width) - 1), range.start, pxPerDay);
  const clamp = (key: string): string => (key < range.start ? range.start : key > range.end ? range.end : key);
  return { start: clamp(start), end: clamp(end) };
}

export function totalWidth(range: DateRange, pxPerDay: number): number {
  return Math.max(pxPerDay, (diffDays(range.start, range.end) + 1) * pxPerDay);
}

/** 「10月 20 – 11月 16」；跨年时补年份。 */
export function formatRangeLabel(start: string, end: string): string {
  const sameYear = toDate(start).getFullYear() === toDate(end).getFullYear();
  const pattern = sameYear ? 'M月 d' : 'yyyy年M月 d';
  return `${format(toDate(start), pattern)} – ${format(toDate(end), pattern)}`;
}

/* ------------------------------------------------------------------ *
 * 表头
 * ------------------------------------------------------------------ */

const WEEKDAY_LABELS = ['日', '一', '二', '三', '四', '五', '六'];

function clipRect(range: DateRange, start: string, end: string, pxPerDay: number): { x: number; width: number } {
  const from = start < range.start ? range.start : start;
  const to = end > range.end ? range.end : end;
  if (from > to) return { x: 0, width: 0 };
  return {
    x: diffDays(range.start, from) * pxPerDay,
    width: (diffDays(from, to) + 1) * pxPerDay,
  };
}

function monthGroups(range: DateRange, pxPerDay: number): HeaderGroup[] {
  const groups: HeaderGroup[] = [];
  let cursor = startOfMonth(toDate(range.start));
  const last = endOfMonth(toDate(range.end));
  while (cursor <= last) {
    const monthStart = format(cursor, 'yyyy-MM-dd');
    const monthEnd = format(endOfMonth(cursor), 'yyyy-MM-dd');
    const rect = clipRect(range, monthStart, monthEnd, pxPerDay);
    const isFirst = groups.length === 0;
    groups.push({
      key: format(cursor, 'yyyy-MM'),
      label: cursor.getMonth() === 0 || isFirst ? format(cursor, 'yyyy年M月') : format(cursor, 'M月'),
      ...rect,
    });
    cursor = startOfMonth(addDays(endOfMonth(cursor), 1));
  }
  return groups;
}

function quarterGroups(range: DateRange, pxPerDay: number): HeaderGroup[] {
  const groups: HeaderGroup[] = [];
  let cursor = startOfQuarter(toDate(range.start));
  const last = endOfQuarter(toDate(range.end));
  while (cursor <= last) {
    const quarterStart = format(cursor, 'yyyy-MM-dd');
    const quarterEnd = format(endOfQuarter(cursor), 'yyyy-MM-dd');
    const rect = clipRect(range, quarterStart, quarterEnd, pxPerDay);
    const quarter = Math.floor(cursor.getMonth() / 3) + 1;
    groups.push({
      key: `${cursor.getFullYear()}-Q${quarter}`,
      label: `${format(cursor, 'yyyy')} Q${quarter}`,
      ...rect,
    });
    cursor = addDays(endOfQuarter(cursor), 1);
  }
  return groups;
}

function dayColumns(range: DateRange, pxPerDay: number, todayKey: string): TimelineColumn[] {
  const columns: TimelineColumn[] = [];
  let cursor = range.start;
  while (cursor <= range.end) {
    const date = toDate(cursor);
    const weekday = date.getDay();
    columns.push({
      key: cursor,
      start: cursor,
      end: cursor,
      x: diffDays(range.start, cursor) * pxPerDay,
      width: pxPerDay,
      label: format(date, 'd'),
      sublabel: WEEKDAY_LABELS[weekday],
      weekend: weekday === 0 || weekday === 6,
      past: cursor < todayKey,
    });
    cursor = addDaysKey(cursor, 1);
  }
  return columns;
}

function weekColumns(range: DateRange, pxPerDay: number, todayKey: string): TimelineColumn[] {
  const columns: TimelineColumn[] = [];
  let cursor = range.start;
  while (cursor <= range.end) {
    const rawEnd = addDaysKey(cursor, 6);
    const end = rawEnd > range.end ? range.end : rawEnd;
    columns.push({
      key: `w-${cursor}`,
      start: cursor,
      end,
      x: diffDays(range.start, cursor) * pxPerDay,
      width: (diffDays(cursor, end) + 1) * pxPerDay,
      label: format(toDate(cursor), 'M/d'),
      past: end < todayKey,
      weekend: false,
    });
    cursor = addDaysKey(cursor, 7);
  }
  return columns;
}

/** 月模式：每月按 1 / 8 / 15 / 22 / 29 切段，与月末对齐。 */
function monthColumns(range: DateRange, pxPerDay: number, todayKey: string): TimelineColumn[] {
  const columns: TimelineColumn[] = [];
  let monthStart = startOfMonth(toDate(range.start));
  const lastMonth = startOfMonth(toDate(range.end));
  while (monthStart <= lastMonth) {
    const year = monthStart.getFullYear();
    const month = monthStart.getMonth();
    const daysInMonth = Number(format(endOfMonth(monthStart), 'd'));
    for (let day = 1; day <= daysInMonth; day += 7) {
      const rawStart = format(new Date(year, month, day), 'yyyy-MM-dd');
      const rawEnd = format(new Date(year, month, Math.min(day + 6, daysInMonth)), 'yyyy-MM-dd');
      if (rawEnd < range.start || rawStart > range.end) continue;
      const start = rawStart < range.start ? range.start : rawStart;
      const end = rawEnd > range.end ? range.end : rawEnd;
      columns.push({
        key: `m-${year}-${month + 1}-${day}`,
        start,
        end,
        x: diffDays(range.start, start) * pxPerDay,
        width: (diffDays(start, end) + 1) * pxPerDay,
        label: String(day),
        past: end < todayKey,
        weekend: false,
      });
    }
    monthStart = startOfMonth(addDays(endOfMonth(monthStart), 1));
  }
  return columns;
}

/** 两级表头：日/周 → 月 + 日/周；月 → 季度 + 1/8/15/22。 */
export function buildHeader(
  range: DateRange,
  zoom: GanttZoom,
  today: Date | string = new Date(),
): TimelineHeader {
  const pxPerDay = ZOOM_CONFIG[zoom].pxPerDay;
  const todayKey = toKey(snapDate(today, zoom));
  const groups = zoom === 'month' ? quarterGroups(range, pxPerDay) : monthGroups(range, pxPerDay);
  const columns =
    zoom === 'day'
      ? dayColumns(range, pxPerDay, todayKey)
      : zoom === 'week'
        ? weekColumns(range, pxPerDay, todayKey)
        : monthColumns(range, pxPerDay, todayKey);
  return { groups, columns, width: totalWidth(range, pxPerDay) };
}

/* ------------------------------------------------------------------ *
 * 左侧树 / 分组
 * ------------------------------------------------------------------ */

export interface GanttGroupRow {
  type: 'group';
  /** project / sop 条目 id，或 UNGROUPED_ID */
  id: string;
  title: string;
  /** 组内可显示条目数（不含组本身） */
  count: number;
  start: string | null;
  end: string | null;
  progress: number;
  collapsed: boolean;
  /** 未分组的合成组没有对应条目 */
  item: Item | null;
}

export interface GanttItemRow {
  type: 'item';
  id: string;
  item: Item;
  /** 相对分组的层级（组内直接子项为 1） */
  depth: number;
  groupId: string;
}

export type GanttRow = GanttGroupRow | GanttItemRow;

export const GANTTABLE_KINDS: ItemKind[] = ['project', 'action', 'milestone'];

const HIDDEN_STATUSES = new Set(['inbox', 'someday', 'dropped']);

/** 甘特视图里可出现的条目：项目 / 行动 / 里程碑，且不在收件箱、将来、已放弃。 */
export function isGanttableItem(item: Item): boolean {
  return GANTTABLE_KINDS.includes(item.kind) && !HIDDEN_STATUSES.has(item.status);
}

function isGroupRoot(item: Item): boolean {
  return item.parentId === null && (item.kind === 'project' || item.kind === 'sop') && !HIDDEN_STATUSES.has(item.status);
}

/** 组内排序：有 start 的在前并按升序；无日期在后；再按 order / createdAt。 */
function compareItems(a: Item, b: Item): number {
  const aStart = itemRange(a)?.start ?? null;
  const bStart = itemRange(b)?.start ?? null;
  if (aStart && bStart && aStart !== bStart) return aStart < bStart ? -1 : 1;
  if (aStart && !bStart) return -1;
  if (!aStart && bStart) return 1;
  return a.order - b.order || a.createdAt.localeCompare(b.createdAt);
}

function summarize(items: Item[]): { start: string | null; end: string | null } {
  let start: string | null = null;
  let end: string | null = null;
  for (const item of items) {
    const range = itemRange(item);
    if (!range) continue;
    if (!start || range.start < start) start = range.start;
    if (!end || range.end > end) end = range.end;
  }
  return { start, end };
}

/**
 * 构建左侧行模型：
 * - 顶层 project / sop 成为可折叠分组；
 * - 组内条目按 start 升序、无日期在后；
 * - 根级无分组归属的条目进「未分组」（始终排最后）；
 * - `collapsed` 中的分组只输出组头行（`collapsed: true`）。
 */
export function buildRows(ws: Workspace, collapsed: ReadonlySet<string> = new Set()): GanttRow[] {
  const groups = ws.items
    .filter(isGroupRoot)
    .map((root) => {
      const members = descendantsOf(ws, root.id).filter(isGanttableItem);
      const withDates = [root, ...members].filter((item) => itemRange(item) !== null);
      return { root, members, hasDates: withDates.length > 0 };
    })
    .filter((group) => group.members.length > 0 || itemRange(group.root) !== null)
    .sort(
      (a, b) =>
        Number(b.hasDates) - Number(a.hasDates) ||
        a.root.order - b.root.order ||
        a.root.createdAt.localeCompare(b.root.createdAt),
    );

  const rows: GanttRow[] = [];
  const covered = new Set<string>();

  for (const group of groups) {
    covered.add(group.root.id);
    for (const member of group.members) covered.add(member.id);

    const isCollapsed = collapsed.has(group.root.id);
    const summary = summarize([group.root, ...group.members]);
    rows.push({
      type: 'group',
      id: group.root.id,
      title: group.root.title,
      count: group.members.length,
      start: summary.start,
      end: summary.end,
      progress: rollupProgress(ws, group.root.id),
      collapsed: isCollapsed,
      item: group.root,
    });

    if (isCollapsed) continue;
    const rootDepth = treeDepth(ws, group.root.id);
    for (const member of [...group.members].sort(compareItems)) {
      rows.push({
        type: 'item',
        id: member.id,
        item: member,
        depth: Math.max(1, treeDepth(ws, member.id) - rootDepth),
        groupId: group.root.id,
      });
    }
  }

  // 未分组：不属于任何已展示分组的可排期条目（例如直接挂在 OKR 下的行动）。
  const groupIds = new Set(groups.map((group) => group.root.id));
  const ungrouped = ws.items
    .filter(isGanttableItem)
    .filter((item) => !covered.has(item.id))
    .filter((item) => !ancestorsOf(ws, item.id).some((ancestor) => groupIds.has(ancestor.id)))
    .sort(compareItems);

  if (ungrouped.length > 0) {
    const summary = summarize(ungrouped);
    const progress = Math.round(
      ungrouped.reduce((sum, item) => sum + displayProgress(item), 0) / ungrouped.length,
    );
    rows.push({
      type: 'group',
      id: UNGROUPED_ID,
      title: '未分组',
      count: ungrouped.length,
      start: summary.start,
      end: summary.end,
      progress,
      collapsed: collapsed.has(UNGROUPED_ID),
      item: null,
    });
    if (!collapsed.has(UNGROUPED_ID)) {
      for (const item of ungrouped) {
        rows.push({
          type: 'item',
          id: item.id,
          item,
          depth: Math.max(1, treeDepth(ws, item.id)),
          groupId: UNGROUPED_ID,
        });
      }
    }
  }

  return rows;
}
