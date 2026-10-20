/**
 * GTD 模块的纯函数层：分组、排序、停滞判定、等待天数、周回顾统计、
 * 以及澄清表单 → store patch 的映射。
 *
 * 这里不依赖 React，也不直接读写 store；组件与 gtdMutations 负责落库。
 */
import { format, parseISO } from 'date-fns';
import type {
  Area,
  Energy,
  Item,
  ItemKind,
  ItemPatch,
  ItemStatus,
  NewItemInput,
  Workspace,
} from '../../core/model';
import {
  childrenOf,
  descendantsOf,
  inboxItems,
  itemsOfKind,
  overdueItems,
  rollupProgress,
  waitingItems,
} from '../../core/selectors';
import {
  dateKey,
  dayOffset,
  daysBetween,
  formatDateKey,
  isOpen,
  nowIso,
} from '../../core/utils';

export const NO_CONTEXT = '无场景';
/** 筛选器里表示「无场景」的哨兵值，避免与用户自定义场景重名。 */
export const NO_CONTEXT_FILTER = '__none__';
export const PRESET_CONTEXTS = ['电脑', '电话', '外出', '会议', '深度工作'] as const;
export const WAITING_WARN_DAYS = 7;
export const ESTIMATE_OPTIONS = [2, 15, 30, 60, 120] as const;

export const ENERGY_LABELS: Record<Energy, string> = {
  low: '低',
  medium: '中',
  high: '高',
};

/** 当前本地日期键（YYYY-MM-DD）。 */
export function currentDateKey(date: Date = new Date()): string {
  return format(date, 'yyyy-MM-dd');
}

/**
 * 完整 ISO 时间戳 → 本地日历日（YYYY-MM-DD）。
 *
 * 不能用 `dateKey`：它只是截取 ISO 字符串前 10 位，对 `2026-10-14T17:01Z`
 * 会得到 UTC 的 10-14，而 Asia/Shanghai 本地是 10-15。这里先 parseISO，
 * 再按运行环境本地时区 format。无效输入返回 null。
 */
export function localDayKey(value: string | null | undefined): string | null {
  if (!value) return null;
  const date = parseISO(value);
  if (Number.isNaN(date.getTime())) return null;
  return format(date, 'yyyy-MM-dd');
}

export function contextOf(item: Item): string | null {
  const value = item.gtd?.context?.trim();
  return value ? value : null;
}

export function energyRank(item: Item): number {
  switch (item.gtd?.energy) {
    case 'high':
      return 3;
    case 'medium':
      return 2;
    case 'low':
      return 1;
    default:
      return 0;
  }
}

/** 收件箱：按 gtd.capturedAt 倒序（缺失时退回 createdAt）。 */
export function sortInboxItems(items: Item[]): Item[] {
  return [...items].sort((a, b) => {
    const aAt = a.gtd?.capturedAt ?? a.createdAt;
    const bAt = b.gtd?.capturedAt ?? b.createdAt;
    return bAt.localeCompare(aAt) || b.createdAt.localeCompare(a.createdAt) || a.order - b.order;
  });
}

export interface ContextGroup {
  context: string;
  items: Item[];
}

/**
 * 按 gtd.context 分组：null/空串归入「无场景」，空组不出现。
 * 组顺序固定：预设场景顺序 → 自定义场景按名称 → 无场景最后，
 * 因此同一批条目无论输入顺序如何，组顺序都稳定。
 */
export function groupByContext(items: Item[]): ContextGroup[] {
  const groups = new Map<string, Item[]>();
  for (const item of items) {
    const context = contextOf(item) ?? NO_CONTEXT;
    const bucket = groups.get(context);
    if (bucket) bucket.push(item);
    else groups.set(context, [item]);
  }
  return [...groups.entries()]
    .map(([context, groupItems]) => ({ context, items: groupItems }))
    .sort((a, b) => contextOrder(a.context) - contextOrder(b.context) || a.context.localeCompare(b.context));
}

function contextOrder(context: string): number {
  if (context === NO_CONTEXT) return 999;
  const index = (PRESET_CONTEXTS as readonly string[]).indexOf(context);
  return index >= 0 ? index : 100;
}

/**
 * 下一步排序：有截止日期优先（早→晚），无日期排后；
 * 同日期再按能量高→低；最后按创建时间（早→晚）。
 */
export function sortNextActions(items: Item[]): Item[] {
  return [...items].sort((a, b) => {
    const aEnd = dateKey(a.gantt?.end);
    const bEnd = dateKey(b.gantt?.end);
    if (aEnd && bEnd) {
      if (aEnd !== bEnd) return aEnd.localeCompare(bEnd);
    } else if (aEnd) {
      return -1;
    } else if (bEnd) {
      return 1;
    }
    const byEnergy = energyRank(b) - energyRank(a);
    if (byEnergy !== 0) return byEnergy;
    return a.createdAt.localeCompare(b.createdAt) || a.order - b.order;
  });
}

export interface NextFilter {
  /** null = 全部；NO_CONTEXT_FILTER = 无场景；其它为具体场景。 */
  context: string | null;
  dueSoonOnly: boolean;
  areaId: string | null;
  search: string;
  today: string;
}

export function matchesSearch(item: Item, search: string): boolean {
  const needle = search.trim().toLowerCase();
  if (!needle) return true;
  const haystack = [
    item.title,
    item.notes,
    item.gtd?.context ?? '',
    item.gtd?.waitingFor ?? '',
    ...item.tags,
  ]
    .join(' ')
    .toLowerCase();
  return haystack.includes(needle);
}

export function filterNextActions(items: Item[], filter: NextFilter): Item[] {
  const todayKey = localDayKey(filter.today) ?? filter.today;
  return items.filter((item) => {
    const context = contextOf(item);
    if (filter.context === NO_CONTEXT_FILTER) {
      if (context) return false;
    } else if (filter.context && context !== filter.context) {
      return false;
    }
    if (filter.dueSoonOnly) {
      const end = dateKey(item.gantt?.end);
      if (!end || end > todayKey) return false;
    }
    if (filter.areaId && item.areaId !== filter.areaId) return false;
    if (!matchesSearch(item, filter.search)) return false;
    return true;
  });
}

/**
 * 停滞项目：
 * - 无子动作 → true
 * - 有 status=next 的子动作 → false
 * - 所有子动作都完成/放弃 → false（已完成的项目不算停滞）
 * - 其余（有未完成但没有任何 next）→ true
 */
export function isStuckProject(ws: Workspace, projectId: string): boolean {
  const project = ws.items.find((item) => item.id === projectId);
  if (!project || project.kind !== 'project') return false;
  if (project.status === 'done' || project.status === 'dropped') return false;
  const related = descendantsOf(ws, projectId).filter(
    (child) => child.kind === 'action' || child.kind === 'project' || child.kind === 'milestone',
  );
  if (related.length === 0) return true;
  if (related.some((child) => child.status === 'next')) return false;
  if (related.every((child) => child.status === 'done' || child.status === 'dropped')) return false;
  return true;
}

export interface ProjectHealth {
  project: Item;
  total: number;
  done: number;
  open: number;
  next: number;
  progress: number;
  stuck: boolean;
}

/** 项目健康度：直接子动作的数量、完成比与停滞状态。 */
export function projectHealth(ws: Workspace): ProjectHealth[] {
  return itemsOfKind(ws, 'project').map((project) => {
    const children = childrenOf(ws, project.id).filter(
      (child) => child.kind === 'action' || child.kind === 'milestone' || child.kind === 'project',
    );
    const done = children.filter((child) => child.status === 'done' || child.status === 'dropped').length;
    const next = children.filter((child) => child.status === 'next').length;
    return {
      project,
      total: children.length,
      done,
      open: children.length - done,
      next,
      progress: rollupProgress(ws, project.id),
      stuck: isStuckProject(ws, project.id),
    };
  });
}

/** 等待基线：gtd.capturedAt 优先，其次 updatedAt，最后 createdAt。 */
export function waitingSince(item: Item): string {
  return item.gtd?.capturedAt ?? item.updatedAt ?? item.createdAt;
}

/** 已等待天数：从等待基线到 today 的本地日历天数，负数归零。 */
export function waitingDays(item: Item, today: string = currentDateKey()): number {
  const todayKey = localDayKey(today) ?? currentDateKey();
  const sinceKey = localDayKey(waitingSince(item));
  if (!sinceKey) return 0;
  return Math.max(0, daysBetween(sinceKey, todayKey));
}

/** 超过 7 天（严格大于）视为需要催办。 */
export function isWaitingOverdue(
  item: Item,
  today: string = currentDateKey(),
  threshold: number = WAITING_WARN_DAYS,
): boolean {
  return waitingDays(item, today) > threshold;
}

export interface StaleArea {
  area: Area;
  openCount: number;
  lastTouched: string | null;
}

export interface WeeklyReviewStats {
  today: string;
  windowStart: string;
  inbox: Item[];
  inboxCount: number;
  inboxCleared: Item[];
  inboxClearedCount: number;
  inboxProgress: number;
  completedThisWeek: Item[];
  completedCount: number;
  overdue: Item[];
  overdueCount: number;
  stuckProjects: Item[];
  stuckProjectCount: number;
  waitingOverdue: Item[];
  waitingOverdueCount: number;
  undatedTasks: Item[];
  undatedCount: number;
  staleAreas: StaleArea[];
}

/**
 * 周回顾统计（最近 7 天，含今天）：
 * - 本周完成：completedAt 落在窗口内
 * - 超期：gantt.end < today 且未完成/未放弃
 * - 无日期任务：status 为 next/active 的 action/project 且没有 start/end
 * - 等待超 7 天、停滞项目、收件箱清零进度
 */
export function weeklyReview(ws: Workspace, today: string = currentDateKey()): WeeklyReviewStats {
  const todayKey = localDayKey(today) ?? currentDateKey();
  const startDate = parseISO(todayKey);
  const windowStart = dayOffset(-6, startDate);
  const staleBefore = dayOffset(-14, startDate);

  const inbox = inboxItems(ws);

  const completedThisWeek = ws.items
    .filter((item) => {
      if (!item.completedAt) return false;
      const key = localDayKey(item.completedAt);
      if (!key) return false;
      // 与 dashboard/today.ts 的 completedThisWeek 完全一致：
      // differenceInCalendarDays(now, completed) ∈ [0, 7)。
      const diff = daysBetween(key, todayKey);
      return diff >= 0 && diff < 7;
    })
    .sort((a, b) => (b.completedAt ?? '').localeCompare(a.completedAt ?? ''));

  const inboxCleared = ws.items.filter((item) => {
    if (!item.gtd?.clarified || item.status === 'inbox') return false;
    const key = localDayKey(item.gtd.capturedAt);
    if (!key) return false;
    const diff = daysBetween(key, todayKey);
    return diff >= 0 && diff < 7;
  });

  const inboxProgress =
    inbox.length + inboxCleared.length === 0
      ? 100
      : Math.round((inboxCleared.length / (inbox.length + inboxCleared.length)) * 100);

  const overdue = overdueItems(ws, todayKey);

  const stuckProjects = projectHealth(ws)
    .filter((entry) => entry.stuck)
    .map((entry) => entry.project);

  const waitingOverdue = waitingItems(ws).filter((item) => isWaitingOverdue(item, todayKey));

  const undatedTasks = ws.items.filter((item) => {
    if (item.kind !== 'action' && item.kind !== 'project') return false;
    if (!isOpen(item)) return false;
    if (item.status !== 'next' && item.status !== 'active') return false;
    return !dateKey(item.gantt?.start) && !dateKey(item.gantt?.end);
  });

  const staleAreas = ws.areas.flatMap((area): StaleArea[] => {
    const areaItems = ws.items.filter(
      (item) =>
        item.areaId === area.id &&
        isOpen(item) &&
        (item.kind === 'action' || item.kind === 'project'),
    );
    if (areaItems.length === 0) return [];
    const lastTouched = areaItems
      .map((item) => item.updatedAt)
      .sort((a, b) => b.localeCompare(a))[0] ?? null;
    const lastKey = localDayKey(lastTouched);
    if (lastKey && lastKey >= staleBefore) return [];
    return [{ area, openCount: areaItems.length, lastTouched }];
  });

  return {
    today: todayKey,
    windowStart,
    inbox,
    inboxCount: inbox.length,
    inboxCleared,
    inboxClearedCount: inboxCleared.length,
    inboxProgress,
    completedThisWeek,
    completedCount: completedThisWeek.length,
    overdue,
    overdueCount: overdue.length,
    stuckProjects,
    stuckProjectCount: stuckProjects.length,
    waitingOverdue,
    waitingOverdueCount: waitingOverdue.length,
    undatedTasks,
    undatedCount: undatedTasks.length,
    staleAreas,
  };
}

/* ------------------------------------------------------------------ */
/* 展示辅助                                                            */
/* ------------------------------------------------------------------ */

/** 收集时间：今天 / 昨天 / n 天前，超过两周用 MM/dd。 */
export function relativeTimeLabel(iso: string | null | undefined, now: Date = new Date()): string {
  const key = localDayKey(iso);
  if (!key) return '—';
  const todayKey = currentDateKey(now);
  const diff = daysBetween(key, todayKey);
  if (diff <= 0) return '今天';
  if (diff === 1) return '昨天';
  if (diff < 14) return `${diff} 天前`;
  return formatDateKey(key, 'MM/dd');
}

export type DeadlineTone = 'danger' | 'accent' | 'muted';

export interface DeadlineInfo {
  label: string;
  tone: DeadlineTone;
  date: string | null;
}

/** 截止日期展示：超期标 danger，今天标 accent，其余 MM/dd。 */
export function deadlineInfo(item: Item, today: string = currentDateKey()): DeadlineInfo {
  const end = dateKey(item.gantt?.end);
  if (!end) return { label: '未设截止', tone: 'muted', date: null };
  const todayKey = localDayKey(today) ?? currentDateKey();
  const diff = daysBetween(end, todayKey);
  if (diff > 0) return { label: `逾期 ${diff} 天`, tone: 'danger', date: end };
  if (diff === 0) return { label: '今天到期', tone: 'accent', date: end };
  return { label: formatDateKey(end, 'MM/dd'), tone: 'muted', date: end };
}

/** 在 notes 末尾追加一条带时间戳的记录。 */
export function appendTimestampedNote(notes: string, message: string, at: Date = new Date()): string {
  const line = `[${format(at, 'yyyy-MM-dd HH:mm')}] ${message}`;
  const base = notes.trimEnd();
  return base ? `${base}\n${line}` : line;
}

/* ------------------------------------------------------------------ */
/* 澄清表单                                                            */
/* ------------------------------------------------------------------ */

export type ClarifyType = 'next' | 'project' | 'reference' | 'note';

export interface ClarifyFormState {
  type: ClarifyType;
  title: string;
  notes: string;
  /** 逗号/空格分隔，允许带 # 前缀。 */
  tags: string;
  /** '' 表示无领域。 */
  areaId: string;
  /** 预设场景、''（未设置）或 '__custom__'。 */
  context: string;
  customContext: string;
  energy: Energy;
  /** UI 辅助：仅用于 2 分钟规则提示，模型没有时长字段。 */
  estimateMin: number | null;
  /** YYYY-MM-DD；'' 表示清空截止日期。 */
  dueDate: string;
  delegated: boolean;
  waitingFor: string;
  someday: boolean;
  twoMinuteCandidate: boolean;
}

export interface ClarifyErrors {
  title?: string;
  waitingFor?: string;
  status?: string;
}

export function parseTags(input: string): string[] {
  const seen = new Set<string>();
  for (const raw of input.split(/[,，\s]+/)) {
    const tag = raw.replace(/^#+/, '').trim();
    if (tag) seen.add(tag);
  }
  return [...seen];
}

export function resolveFormContext(form: ClarifyFormState): string {
  const raw = form.context === '__custom__' ? form.customContext : form.context;
  return raw.trim();
}

export function desiredKind(type: ClarifyType): ItemKind {
  switch (type) {
    case 'project':
      return 'project';
    case 'reference':
      return 'reference';
    case 'note':
      return 'note';
    case 'next':
    default:
      return 'action';
  }
}

export function isArchiveType(type: ClarifyType): boolean {
  return type === 'reference' || type === 'note';
}

/** 目标状态：归档类 → done；委派 → waiting；someday → someday；其余 → next。 */
export function clarifyTargetStatus(form: ClarifyFormState): ItemStatus {
  if (isArchiveType(form.type)) return 'done';
  if (form.delegated) return 'waiting';
  if (form.someday) return 'someday';
  return 'next';
}

export function validateClarifyForm(form: ClarifyFormState): ClarifyErrors {
  const errors: ClarifyErrors = {};
  if (!form.title.trim()) errors.title = '标题不能为空';
  const actsOnStatus = !isArchiveType(form.type);
  if (form.delegated && actsOnStatus && !form.waitingFor.trim()) {
    errors.waitingFor = '委派给他人时必须填写等待对象';
  }
  if (form.delegated && form.someday && actsOnStatus) {
    errors.status = '「委派等待」与「某天/搁置」只能选一个';
  }
  return errors;
}

/** 澄清表单 → updateItem patch（status 由 clarifyTargetStatus + setStatus 落库）。 */
export interface ClarifyPatch extends ItemPatch {
  title: string;
  notes: string;
  tags: string[];
  areaId: string | null;
  gantt: { end: string | null };
  gtd: {
    clarified: true;
    context: string;
    energy: Energy;
    waitingFor: string;
    twoMinuteCandidate: boolean;
  };
}

export function buildClarifyPatch(form: ClarifyFormState): ClarifyPatch {
  const context = resolveFormContext(form);
  return {
    title: form.title.trim(),
    notes: form.notes,
    tags: parseTags(form.tags),
    areaId: form.areaId || null,
    gantt: { end: form.dueDate || null },
    gtd: {
      clarified: true,
      context,
      energy: form.energy,
      waitingFor: form.delegated ? form.waitingFor.trim() : '',
      twoMinuteCandidate: form.twoMinuteCandidate || form.estimateMin === 2,
    },
  };
}

/** 需要「新建条目 + 归档原条目」时使用的 createItem 输入。 */
export function buildClarifyNewItem(
  form: ClarifyFormState,
  source: Item,
  status: ItemStatus = clarifyTargetStatus(form),
): NewItemInput {
  const patch = buildClarifyPatch(form);
  return {
    kind: desiredKind(form.type),
    title: patch.title,
    notes: patch.notes,
    tags: patch.tags,
    areaId: patch.areaId,
    status,
    gtd: {
      capturedAt: source.gtd?.capturedAt ?? nowIso(),
      clarified: true,
      context: patch.gtd.context,
      energy: patch.gtd.energy,
      waitingFor: patch.gtd.waitingFor,
      twoMinuteCandidate: patch.gtd.twoMinuteCandidate,
    },
    gantt: {
      start: source.gantt?.start ?? null,
      end: patch.gantt.end,
    },
  };
}

/** 从现有条目初始化表单。 */
export function createClarifyForm(item: Item): ClarifyFormState {
  const rawContext = item.gtd?.context?.trim() ?? '';
  const isPreset = (PRESET_CONTEXTS as readonly string[]).includes(rawContext);
  const type: ClarifyType =
    item.kind === 'project'
      ? 'project'
      : item.kind === 'reference'
        ? 'reference'
        : item.kind === 'note'
          ? 'note'
          : 'next';
  const twoMinuteCandidate = Boolean(item.gtd?.twoMinuteCandidate);
  return {
    type,
    title: item.title,
    notes: item.notes,
    tags: item.tags.join(' '),
    areaId: item.areaId ?? '',
    context: rawContext ? (isPreset ? rawContext : '__custom__') : '',
    customContext: rawContext && !isPreset ? rawContext : '',
    energy: item.gtd?.energy ?? 'medium',
    estimateMin: twoMinuteCandidate ? 2 : null,
    dueDate: dateKey(item.gantt?.end) ?? '',
    delegated: item.status === 'waiting',
    waitingFor: item.gtd?.waitingFor ?? '',
    someday: item.status === 'someday',
    twoMinuteCandidate,
  };
}
