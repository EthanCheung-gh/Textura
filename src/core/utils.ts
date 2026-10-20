import { format, parseISO, startOfQuarter, endOfQuarter, addDays, differenceInCalendarDays } from 'date-fns';
import type { Item, Workspace } from './model';

/** 生成短 id：prefix_随机串。 */
export function uid(prefix = 'i'): string {
  const rand =
    typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID().replace(/-/g, '').slice(0, 10)
      : Math.random().toString(36).slice(2, 12);
  return `${prefix}_${rand}`;
}

export function nowIso(): string {
  return new Date().toISOString();
}

/** 深拷贝工作区（只含 JSON 数据，structuredClone 足够）。 */
export function cloneWorkspace(ws: Workspace): Workspace {
  if (typeof structuredClone === 'function') return structuredClone(ws);
  return JSON.parse(JSON.stringify(ws)) as Workspace;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** 把 ISO 时间或日期串统一成 'YYYY-MM-DD'。 */
export function dateKey(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (trimmed.length >= 10) return trimmed.slice(0, 10);
  return null;
}

export function parseDateKey(value: string | null | undefined): Date | null {
  const key = dateKey(value);
  if (!key) return null;
  const parsed = parseISO(key);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function formatDateKey(value: string | null | undefined, pattern = 'MM/dd'): string {
  const date = parseDateKey(value);
  return date ? format(date, pattern) : '—';
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  return format(date, 'yyyy-MM-dd HH:mm');
}

/** 当前季度，例如 '2026-Q1'。 */
export function currentQuarter(date: Date = new Date()): string {
  return format(date, 'yyyy') + '-Q' + (Math.floor(date.getMonth() / 3) + 1);
}

/** 某季度对应的 [start, end] 日期键。无法解析时返回 null。 */
export function quarterRange(period: string): { start: string; end: string } | null {
  const match = /^(\d{4})-Q([1-4])$/.exec(period);
  if (!match) return null;
  const year = Number(match[1]);
  const quarter = Number(match[2]);
  const start = startOfQuarter(new Date(year, (quarter - 1) * 3, 1));
  return { start: format(start, 'yyyy-MM-dd'), end: format(endOfQuarter(start), 'yyyy-MM-dd') };
}

/** 相对今天偏移 n 天，返回 'YYYY-MM-DD'。 */
export function dayOffset(days: number, from: Date = new Date()): string {
  return format(addDays(from, days), 'yyyy-MM-dd');
}

/** 相对今天偏移 n 天，返回 ISO 时间。 */
export function isoOffset(days: number, from: Date = new Date()): string {
  return addDays(from, days).toISOString();
}

export function daysBetween(fromISO: string, toISO: string): number {
  const from = parseDateKey(fromISO);
  const to = parseDateKey(toISO);
  if (!from || !to) return 0;
  return differenceInCalendarDays(to, from);
}

/** 判断 item 是否处于 done/dropped 之外的完成态。 */
export function isOpen(item: Item): boolean {
  return item.status !== 'done' && item.status !== 'dropped';
}

export function isDone(item: Item): boolean {
  return item.status === 'done';
}

/** 子项完成比（done / 总数），0..100 的整数；无子项返回 0。 */
export function childCompletion(children: Item[]): number {
  if (children.length === 0) return 0;
  const done = children.filter(isDone).length;
  return Math.round((done / children.length) * 100);
}

/** 生成一个可取消的防抖器（store 自动保存使用）。 */
export function createDebouncer(fn: () => void, wait = 400): { schedule: () => void; cancel: () => void } {
  let timer: ReturnType<typeof setTimeout> | null = null;
  return {
    schedule() {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        fn();
      }, wait);
    },
    cancel() {
      if (timer) clearTimeout(timer);
      timer = null;
    },
  };
}

export function areaPalette(index: number): string {
  const palette = ['#C0663A', '#5B7C99', '#7C8A5D', '#9B6A8F', '#B08A3E', '#5E8A82', '#8A6B52', '#6C6FA0'];
  return palette[index % palette.length];
}

export function percent(value: number): string {
  return `${Math.round(value)}%`;
}
