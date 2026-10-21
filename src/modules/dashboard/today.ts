/**
 * 「今日」聚合逻辑（纯函数，方便单测）。
 * 领域数据全部来自 core/selectors，这里只做展示层面的合并、去重与排序。
 */
import { differenceInCalendarDays, formatDistanceToNow, parseISO } from 'date-fns';
import { zhCN } from 'date-fns/locale';
import type { Item, SopRunEntry, Workspace } from '../../core/model';
import { KIND_LABELS } from '../../core/model';
import {
  ancestorsOf,
  dueTodayItems,
  itemById,
  nextActions,
  overdueItems,
} from '../../core/selectors';
import { dateKey } from '../../core/utils';

export type FocusBucket = 'overdue' | 'today' | 'undated';
export type FocusSource = 'sop' | 'okr' | null;

export interface FocusEntry {
  item: Item;
  bucket: FocusBucket;
  /** 截止日期 'YYYY-MM-DD' */
  due: string | null;
  /** 超期天数（仅 overdue 有值，至少 1） */
  daysLate: number;
  /** 根 → 自身 */
  pathTitles: string[];
  /** 来自 SOP / OKR 的条目标记 */
  source: FocusSource;
}

const BUCKET_WEIGHT: Record<FocusBucket, number> = { overdue: 0, today: 1, undated: 2 };

function sourceOf(item: Item, ancestors: Item[]): FocusSource {
  if (item.kind === 'sop' || item.kind === 'step') return 'sop';
  if (item.kind === 'objective' || item.kind === 'keyresult') return 'okr';
  if (ancestors.some((entry) => entry.kind === 'sop')) return 'sop';
  if (ancestors.some((entry) => entry.kind === 'objective' || entry.kind === 'keyresult')) {
    return 'okr';
  }
  return null;
}

function daysLateFor(todayKey: string, due: string | null): number {
  if (!due) return 1;
  const todayDate = parseISO(todayKey);
  const dueDate = parseISO(due);
  if (Number.isNaN(todayDate.getTime()) || Number.isNaN(dueDate.getTime())) return 1;
  return Math.max(1, differenceInCalendarDays(todayDate, dueDate));
}

/**
 * 今日聚焦：overdue + dueToday + 无 end 的 nextActions，按 id 去重（超期 > 今天 > 无日期），
 * 再按分组与组内规则排序。
 */
export function buildTodayFocus(ws: Workspace, today: string): FocusEntry[] {
  const todayKey = dateKey(today) ?? today;
  const entries: FocusEntry[] = [];
  const seen = new Set<string>();

  const push = (item: Item, bucket: FocusBucket) => {
    if (seen.has(item.id)) return;
    seen.add(item.id);
    const ancestors = [...ancestorsOf(ws, item.id)].reverse();
    const due = dateKey(item.gantt?.end);
    entries.push({
      item,
      bucket,
      due,
      daysLate: bucket === 'overdue' ? daysLateFor(todayKey, due) : 0,
      pathTitles: [...ancestors.map((entry) => entry.title), item.title],
      source: sourceOf(item, ancestors),
    });
  };

  for (const item of overdueItems(ws, todayKey)) push(item, 'overdue');
  for (const item of dueTodayItems(ws, todayKey)) push(item, 'today');
  for (const item of nextActions(ws)) {
    // 有截止日期的下一步已归入超期/今天，或属于未来排期，不进入「无日期」桶。
    if (dateKey(item.gantt?.end)) continue;
    push(item, 'undated');
  }

  entries.sort((a, b) => {
    const bucketDiff = BUCKET_WEIGHT[a.bucket] - BUCKET_WEIGHT[b.bucket];
    if (bucketDiff !== 0) return bucketDiff;
    if (a.bucket === 'overdue') {
      const dueDiff = (a.due ?? '').localeCompare(b.due ?? '');
      if (dueDiff !== 0) return dueDiff;
    }
    return a.item.order - b.item.order || a.item.createdAt.localeCompare(b.item.createdAt);
  });

  return entries;
}

export interface FocusCounts {
  overdue: number;
  today: number;
  undated: number;
}

/** 今日聚焦首屏最多渲染的条数。 */
export const FOCUS_PAGE_SIZE = 100;

export interface FocusPage {
  items: FocusEntry[];
  shown: number;
  total: number;
  remaining: number;
  hasMore: boolean;
}

/** 取前 limit 条；limit 非法或小于 0 时按 0 处理。 */
export function paginateFocus(entries: readonly FocusEntry[], limit: number): FocusPage {
  const total = entries.length;
  const safeLimit = Number.isFinite(limit) ? Math.max(0, Math.floor(limit)) : 0;
  const shown = Math.min(safeLimit, total);
  return {
    items: shown === total ? [...entries] : entries.slice(0, shown),
    shown,
    total,
    remaining: total - shown,
    hasMore: shown < total,
  };
}

export function countFocusBuckets(entries: FocusEntry[]): FocusCounts {
  const counts: FocusCounts = { overdue: 0, today: 0, undated: 0 };
  for (const entry of entries) counts[entry.bucket] += 1;
  return counts;
}

export interface TodaySummaryInput {
  overdue: number;
  today: number;
  inbox: number;
  next: number;
}

/** 一句话状态摘要。 */
export function summarizeToday(input: TodaySummaryInput): string {
  const parts: string[] = [];
  if (input.overdue > 0) parts.push(`${input.overdue} 项已超期`);
  if (input.today > 0) parts.push(`${input.today} 项今日到期`);
  if (input.inbox > 0) parts.push(`收件箱 ${input.inbox} 条待澄清`);
  if (parts.length > 0) return `${parts.join('，')}。`;
  if (input.next > 0) return `今天没有硬性截止，${input.next} 项下一步可以先推进。`;
  return '今天没有待办，先收集一点想法，或者去定一个目标。';
}

/** 最近 7 天完成的条目（按完成时间倒序）。 */
export function completedThisWeek(ws: Workspace, now: Date = new Date(), days = 7): Item[] {
  return ws.items
    .filter((item) => {
      if (!item.completedAt) return false;
      const completed = parseISO(item.completedAt);
      if (Number.isNaN(completed.getTime())) return false;
      const diff = differenceInCalendarDays(now, completed);
      return diff >= 0 && diff < days;
    })
    .sort((a, b) => (b.completedAt ?? '').localeCompare(a.completedAt ?? ''));
}

/** 最近完成的条目（不限时间窗口），按完成时间倒序。 */
export function recentlyCompleted(ws: Workspace, limit = 5): Item[] {
  return ws.items
    .filter((item) => Boolean(item.completedAt))
    .sort((a, b) => (b.completedAt ?? '').localeCompare(a.completedAt ?? ''))
    .slice(0, limit);
}

/** 全部 SOP 运行记录，按时间倒序。 */
export function sortedRuns(ws: Workspace): SopRunEntry[] {
  return [...ws.runs].sort((a, b) => b.at.localeCompare(a.at) || a.id.localeCompare(b.id));
}

export function latestRun(ws: Workspace): SopRunEntry | null {
  return sortedRuns(ws)[0] ?? null;
}

export function latestRunFor(ws: Workspace, sopId: string): SopRunEntry | null {
  return sortedRuns(ws).find((run) => run.sopId === sopId) ?? null;
}

export const RUN_RESULT_LABELS: Record<SopRunEntry['result'], string> = {
  pass: '通过',
  fail: '失败',
  skip: '跳过',
};

export interface ActivityEntry {
  id: string;
  kind: 'run' | 'completed';
  at: string;
  title: string;
  detail: string;
  result: SopRunEntry['result'] | null;
}

/**
 * 最近活动：runs（最近 5 条）+ completedAt（最近 5 条），时间倒序。
 */
export function buildActivity(ws: Workspace, limitPerSource = 5): ActivityEntry[] {
  const runs = sortedRuns(ws)
    .slice(0, limitPerSource)
    .map<ActivityEntry>((run) => {
      const sop = itemById(ws, run.sopId);
      const step = itemById(ws, run.stepId);
      const resultLabel = RUN_RESULT_LABELS[run.result];
      return {
        id: `run:${run.id}`,
        kind: 'run',
        at: run.at,
        title: sop ? sop.title : '未知 SOP',
        detail: step ? `${step.title} · ${resultLabel}` : resultLabel,
        result: run.result,
      };
    });

  const completed = recentlyCompleted(ws, limitPerSource)
    .map<ActivityEntry>((item) => ({
      id: `completed:${item.id}`,
      kind: 'completed',
      at: item.completedAt ?? item.updatedAt,
      title: item.title,
      detail: `${KIND_LABELS[item.kind]} · 已完成`,
      result: null,
    }));

  return [...runs, ...completed].sort((a, b) => b.at.localeCompare(a.at));
}

/** 相对时间（中文）。 */
export function relativeTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  return formatDistanceToNow(date, { addSuffix: true, locale: zhCN });
}
