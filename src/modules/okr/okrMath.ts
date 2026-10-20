/**
 * OKR 视图的纯函数：时间进度、落后判定、信心分档、健康度汇总、执行项合并。
 * 领域计算一律复用 core/selectors，这里只做「视图层派生」。
 */
import { differenceInCalendarDays, parseISO } from 'date-fns';
import type { Item, OkrData, Workspace } from '../../core/model';
import {
  areaById,
  childrenOf,
  edgeTargetsOf,
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
 */
export function executionItemsOf(workspace: Workspace, krId: string): ExecutionItemRef[] {
  const result: ExecutionItemRef[] = [];
  const seen = new Set<string>();

  for (const item of edgeTargetsOf(workspace, krId, 'okr')) {
    if (!isExecutionItem(item) || seen.has(item.id)) continue;
    seen.add(item.id);
    const edgeId =
      workspace.edges.find(
        (edge) => edge.from === krId && edge.to === item.id && edge.type === 'okr',
      )?.id ?? null;
    result.push({ item, via: 'edge', edgeId });
  }

  for (const item of childrenOf(workspace, krId)) {
    if (!isExecutionItem(item) || seen.has(item.id)) continue;
    seen.add(item.id);
    result.push({ item, via: 'child', edgeId: null });
  }

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
