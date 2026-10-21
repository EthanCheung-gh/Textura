/**
 * OKR 视图的纯函数：时间进度、落后判定、信心分档、健康度汇总、执行项合并。
 * 领域计算一律复用 core/selectors，这里只做「视图层派生」。
 */
import { differenceInCalendarDays, parseISO } from 'date-fns';
import type { Item, OkrData, Workspace } from '../../core/model';
import {
  areaById,
  childrenOf,
  getWorkspaceIndex,
  itemPathTitles,
  objectivesOfPeriod,
  rollupProgress,
} from '../../core/selectors';
import { quarterRange } from '../../core/utils';

/** 低于时间进度 10 个点（含）即视为落后。 */
export const BEHIND_MARGIN_POINTS = 10;

export type OkrMetric = NonNullable<OkrData['metric']>;

export type ConfidenceBucket = 'low' | 'mid' | 'high';

export type OkrDensity = 'compact' | 'detailed';

export type OkrView = 'cards' | 'table' | 'alignment';

export function roundTo(value: number, digits = 0): number {
  if (!Number.isFinite(value)) return 0;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/**
 * 季度已过百分比：季度第一天为 0，最后一天为 100，区间外夹紧到 0/100。
 * 无法解析的周期返回 0，避免 UI 崩溃。
 */
export function quarterElapsedPercent(period: string, today: Date = new Date()): number {
  const range = quarterRange(period);
  if (!range) return 0;
  const start = parseISO(range.start);
  const end = parseISO(range.end);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return 0;
  const totalDays = differenceInCalendarDays(end, start);
  const elapsedDays = differenceInCalendarDays(today, start);
  if (totalDays <= 0) return elapsedDays >= 0 ? 100 : 0;
  return roundTo(Math.min(100, Math.max(0, (elapsedDays / totalDays) * 100)), 1);
}

/** 进度落后时间进度达到阈值（10 个点）。 */
export function isKrBehind(progress: number, elapsedPercent: number): boolean {
  if (!Number.isFinite(progress) || !Number.isFinite(elapsedPercent)) return false;
  return elapsedPercent - progress >= BEHIND_MARGIN_POINTS;
}

/** 信心指数分档：1–3 低、4–6 中、7–10 高。 */
export function confidenceBucket(confidence: number): ConfidenceBucket {
  const value = Number.isFinite(confidence) ? Math.min(10, Math.max(1, confidence)) : 1;
  if (value <= 3) return 'low';
  if (value <= 6) return 'mid';
  return 'high';
}

/**
 * metric 进度换算与提示状态。
 *
 * 核心 `rollupProgress` 对 target === start 的 KR 会回退到完成状态/子项完成比，
 * 因此模块内必须单独识别「无法换算」的情况，不能显示一个凭空的 100%。
 */
export const METRIC_RANGE_EPSILON = 1e-9;

export type MetricProgressState = 'unset' | 'invalid' | 'flat' | 'under' | 'in-range' | 'over';

export interface MetricProgressInfo {
  state: MetricProgressState;
  /** 仅在存在可换算区间时给出，夹紧在 0..100；unset/flat/invalid 为 null。 */
  percent: number | null;
  /** 是否因超出区间而被夹紧（under / over）。 */
  clamped: boolean;
}

/** 起点与目标之间是否存在可换算区间（容忍 1e-9 以内的浮点噪声）。 */
export function hasMetricRange(metric: OkrMetric | undefined): boolean {
  if (!metric) return false;
  const { start, target } = metric;
  return (
    Number.isFinite(start) &&
    Number.isFinite(target) &&
    Math.abs(target - start) >= METRIC_RANGE_EPSILON
  );
}

/**
 * 指标换算状态（方向感知）：
 * - flat：|target - start| < 1e-9，无法换算，percent 为 null；
 * - under：current 未达到起点（正向低于 start / 负向高于 start），夹紧到 0；
 * - over：current 已越过目标（正向高于 target / 负向低于 target），夹紧到 100；
 * - in-range：包含 current === start 与 current === target，不视为超额/低于起点。
 */
export function metricProgress(metric: OkrMetric | undefined): MetricProgressInfo {
  if (!metric) return { state: 'unset', percent: null, clamped: false };
  const { start, target, current } = metric;
  if (![start, target, current].every((value) => Number.isFinite(value))) {
    return { state: 'invalid', percent: null, clamped: false };
  }
  if (!hasMetricRange(metric)) return { state: 'flat', percent: null, clamped: false };

  const ratio = (current - start) / (target - start);
  if (ratio < 0) return { state: 'under', percent: 0, clamped: true };
  if (ratio > 1) return { state: 'over', percent: 100, clamped: true };
  return { state: 'in-range', percent: roundTo(ratio * 100, 0), clamped: false };
}

/**
 * 纯换算值（0..100），没有可换算区间时返回 null。
 * UI 应优先使用 metricProgress() 以拿到 flat / over / under 提示。
 */
export function metricPercent(metric: OkrMetric | undefined): number | null {
  return metricProgress(metric).percent;
}

export interface OkrSummary {
  objectives: number;
  keyResults: number;
  averageProgress: number;
  behind: number;
  elapsedPercent: number;
  confidence: Record<ConfidenceBucket, number>;
}

/** 季度健康度：目标/KR 数、目标平均进度、信心分布、落后 KR 数。 */
export function summarize(
  workspace: Workspace,
  period: string,
  today: Date = new Date(),
): OkrSummary {
  const objectives = objectivesOfPeriod(workspace, period);
  const elapsedPercent = quarterElapsedPercent(period, today);
  const confidence: Record<ConfidenceBucket, number> = { low: 0, mid: 0, high: 0 };
  let keyResults = 0;
  let behind = 0;
  let progressSum = 0;

  for (const objective of objectives) {
    progressSum += rollupProgress(workspace, objective.id);
    const krs = childrenOf(workspace, objective.id).filter((item) => item.kind === 'keyresult');
    for (const kr of krs) {
      keyResults += 1;
      confidence[confidenceBucket(kr.okr?.confidence ?? 5)] += 1;
      if (isKrBehind(rollupProgress(workspace, kr.id), elapsedPercent)) behind += 1;
    }
  }

  return {
    objectives: objectives.length,
    keyResults,
    averageProgress: objectives.length > 0 ? Math.round(progressSum / objectives.length) : 0,
    behind,
    elapsedPercent,
    confidence,
  };
}

export interface ExecutionItemRef {
  item: Item;
  /** edge：通过 `okr` 边关联；child：通过 parentId 挂在 KR 下。 */
  via: 'edge' | 'child';
  edgeId: string | null;
}

function isExecutionItem(item: Item): boolean {
  return item.kind === 'project' || item.kind === 'action';
}

/**
 * 一条 KR 的全部执行项。两条路径都要展示：
 * 1) `okr` 边（from = KR, to = 执行项）
 * 2) parentId 直接挂在 KR 下的 project/action
 * 同一执行项同时命中两条路径时以 edge 为准（可解除关联）。
 *
 * 通过 `edgesFrom` 索引取边（不再对每条执行项扫描整个 edges 数组），
 * 并用内容签名缓存结果数组：内容没变时返回同一引用，行组件可以 memo 跳过。
 */
interface ExecutionCacheEntry {
  signature: string;
  items: ExecutionItemRef[];
}

const executionCache = new Map<string, ExecutionCacheEntry>();

/**
 * Item 引用身份：store 的不可变更新保证未修改条目引用不变，
 * 因此可以用引用身份做缓存签名（比 updatedAt 更可靠：导入 / 外部替换也能识别）。
 */
const itemIdentity = new WeakMap<Item, number>();
let nextItemIdentity = 1;

function identityOf(item: Item): number {
  const cached = itemIdentity.get(item);
  if (cached !== undefined) return cached;
  const identity = nextItemIdentity;
  nextItemIdentity += 1;
  itemIdentity.set(item, identity);
  return identity;
}

export function executionItemsOf(workspace: Workspace, krId: string): ExecutionItemRef[] {
  const index = getWorkspaceIndex(workspace);
  const result: ExecutionItemRef[] = [];
  const seen = new Set<string>();

  for (const edge of index.edgesFrom.get(krId) ?? []) {
    if (edge.type !== 'okr' || seen.has(edge.to)) continue;
    const target = index.byId.get(edge.to);
    if (!target || !isExecutionItem(target)) continue;
    seen.add(target.id);
    result.push({ item: target, via: 'edge', edgeId: edge.id });
  }

  for (const child of index.children.get(krId) ?? []) {
    if (seen.has(child.id) || !isExecutionItem(child)) continue;
    seen.add(child.id);
    result.push({ item: child, via: 'child', edgeId: null });
  }

  const signature = result
    .map((entry) => `${identityOf(entry.item)}:${entry.via}:${entry.edgeId ?? ''}`)
    .join('|');
  const cached = executionCache.get(krId);
  if (cached && cached.signature === signature) return cached.items;
  executionCache.set(krId, { signature, items: result });
  return result;
}

export interface ObjectiveView {
  objective: Item;
  /** 经过搜索过滤后的 KR。 */
  keyResults: Item[];
  /** 目标本身命中搜索时为 true；仅 KR 命中时为 false。 */
  objectiveMatched: boolean;
}

function searchableText(workspace: Workspace, item: Item): string {
  const area = item.areaId ? (areaById(workspace, item.areaId)?.name ?? '') : '';
  return [
    item.title,
    item.notes,
    area,
    item.okr?.krOwner ?? '',
    ...item.tags,
  ]
    .join(' ')
    .toLowerCase();
}

export function matchesQuery(workspace: Workspace, item: Item, query: string): boolean {
  const needle = query.trim().toLowerCase();
  if (!needle) return true;
  return searchableText(workspace, item).includes(needle);
}

/** 目标 + 过滤后的 KR；目标命中时保留全部 KR，仅 KR 命中时只保留命中的 KR。 */
export function filterObjectives(
  workspace: Workspace,
  period: string,
  query: string,
): ObjectiveView[] {
  const needle = query.trim().toLowerCase();
  const result: ObjectiveView[] = [];

  for (const objective of objectivesOfPeriod(workspace, period)) {
    const keyResults = childrenOf(workspace, objective.id).filter(
      (item) => item.kind === 'keyresult',
    );
    if (!needle) {
      result.push({ objective, keyResults, objectiveMatched: true });
      continue;
    }
    if (matchesQuery(workspace, objective, needle)) {
      result.push({ objective, keyResults, objectiveMatched: true });
      continue;
    }
    const matched = keyResults.filter((kr) => matchesQuery(workspace, kr, needle));
    if (matched.length > 0) {
      result.push({ objective, keyResults: matched, objectiveMatched: false });
    }
  }

  return result;
}

/* ------------------------------------------------------------------ */
/* 表格长列表分页                                                       */
/* ------------------------------------------------------------------ */

/** 表格一次渲染的 KR 行数上限。 */
export const OKR_KR_PAGE_SIZE = 200;

export interface ObjectiveTablePage {
  /** 本页要渲染的目标；每个目标的 keyResults 已切到本页范围内。 */
  entries: ObjectiveView[];
  shownKeyResults: number;
  totalKeyResults: number;
  remaining: number;
  hasMore: boolean;
}

/**
 * 按 KR 行数分页（不是按目标数）：跨目标顺序保持不变，
 * 一个目标只有在前面的 KR 进入本页时才出现，避免空目标块。
 * 没有 KR 的目标在还有预算时照常显示（保留「缺少 KR」提示）。
 */
export function paginateObjectiveKrs(
  entries: readonly ObjectiveView[],
  limit: number,
): ObjectiveTablePage {
  const totalKeyResults = entries.reduce((sum, entry) => sum + entry.keyResults.length, 0);
  const safeLimit = Number.isFinite(limit) ? Math.max(0, Math.floor(limit)) : 0;
  let budget = safeLimit;
  let shownKeyResults = 0;
  const page: ObjectiveView[] = [];

  for (const entry of entries) {
    if (budget <= 0) break;
    if (entry.keyResults.length === 0) {
      page.push({ ...entry, keyResults: [] });
      continue;
    }
    const visible = entry.keyResults.slice(0, budget);
    budget -= visible.length;
    shownKeyResults += visible.length;
    page.push({ ...entry, keyResults: visible });
  }

  return {
    entries: page,
    shownKeyResults,
    totalKeyResults,
    remaining: totalKeyResults - shownKeyResults,
    hasMore: shownKeyResults < totalKeyResults,
  };
}

export interface OkrPaginationState {
  key: string;
  limit: number;
}

/** 分页 key（季度 + 搜索词）变化时自动回到第一页。 */
export function resolveOkrPageLimit(
  state: OkrPaginationState,
  key: string,
  pageSize: number = OKR_KR_PAGE_SIZE,
): number {
  if (state.key !== key) return pageSize;
  return Math.max(pageSize, state.limit);
}

export function nextOkrPage(
  state: OkrPaginationState,
  key: string,
  pageSize: number = OKR_KR_PAGE_SIZE,
): OkrPaginationState {
  return { key, limit: resolveOkrPageLimit(state, key, pageSize) + pageSize };
}

/* ------------------------------------------------------------------ */
/* 执行项路径索引（列表级一次构建，行内 O(1)）                          */
/* ------------------------------------------------------------------ */

/**
 * 为一批执行项构建「根 → 父级」的路径文本。
 * 行内只做 Map.get，不再逐条调用 itemPathTitles。
 */
export function buildParentPathText(
  workspace: Workspace,
  items: readonly Item[],
): Map<string, string> {
  const map = new Map<string, string>();
  for (const item of items) {
    if (map.has(item.id)) continue;
    const titles = itemPathTitles(workspace, item.id);
    map.set(item.id, titles.slice(0, -1).join(' / '));
  }
  return map;
}

/** 季度偏移，例如 2026-Q4 + 1 → 2027-Q1。 */
export function shiftQuarter(period: string, delta: number): string {
  const match = /^(\d{4})-Q([1-4])$/.exec(period);
  if (!match) return period;
  const index = Number(match[1]) * 4 + (Number(match[2]) - 1) + delta;
  const year = Math.floor(index / 4);
  const quarter = ((index % 4) + 4) % 4 + 1;
  return `${year}-Q${quarter}`;
}

export function nextQuarter(period: string): string {
  return shiftQuarter(period, 1);
}

/** '2026-Q4' → '2026 Q4'；无法解析时原样返回。 */
export function quarterLabel(period: string): string {
  const match = /^(\d{4})-Q([1-4])$/.exec(period);
  return match ? `${match[1]} Q${match[2]}` : period;
}
