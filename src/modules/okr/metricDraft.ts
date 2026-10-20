/**
 * 指标草稿与提交决策的纯逻辑。
 *
 * 组件负责 timer / focus / ref；本模块只回答「当前草稿里哪些字段需要提交，
 * 合并后的 metric 是什么」。这样卸载 flush 可以脱离 React 状态单独测试。
 */
import type { OkrMetric } from './okrMath';

export type MetricField = 'start' | 'current' | 'target' | 'unit';
export type MetricDraft = Record<MetricField, string>;

export const METRIC_FIELDS: MetricField[] = ['start', 'current', 'target', 'unit'];
export const METRIC_NUMBER_FIELDS = ['start', 'current', 'target'] as const;

export const EMPTY_METRIC: OkrMetric = { start: 0, target: 100, current: 0, unit: '' };

export function metricToText(value: number): string {
  return Number.isFinite(value) ? String(value) : '';
}

export function metricFieldText(metric: OkrMetric, field: MetricField): string {
  return field === 'unit' ? metric.unit : metricToText(metric[field]);
}

export function metricToDraft(metric: OkrMetric): MetricDraft {
  return {
    start: metricToText(metric.start),
    current: metricToText(metric.current),
    target: metricToText(metric.target),
    unit: metric.unit,
  };
}

export function parseMetricNumber(raw: string): number | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

export interface MetricFlushDecision {
  metric: OkrMetric;
  /** 实际需要写入的字段。 */
  fields: MetricField[];
  /** 规范化后的完整草稿（"60.0" → "60"，单位会 trim）。 */
  normalized: MetricDraft;
}

/**
 * 计算待提交 patch。
 * - 数值字段为空/非法：跳过（保留 store 里的旧值）；
 * - draft 已与 lastCommitted 或 store 当前值相同：跳过（避免重复历史）；
 * - 单位是文本字段，允许清空，提交时 trim；
 * - 多字段同时待提交时合并成一个 metric，供一次 updateItem 使用。
 */
export function pendingMetricPatch(
  latest: OkrMetric | undefined,
  draft: MetricDraft,
  lastCommitted: MetricDraft,
): MetricFlushDecision | null {
  const base = latest ?? EMPTY_METRIC;
  const metric: OkrMetric = { ...base };
  const normalized = metricToDraft(base);
  const fields: MetricField[] = [];

  for (const field of METRIC_FIELDS) {
    const raw = draft[field] ?? '';

    if (field === 'unit') {
      const unit = raw.trim();
      if (unit === lastCommitted.unit || unit === base.unit) continue;
      metric.unit = unit;
      normalized.unit = unit;
      fields.push(field);
      continue;
    }

    const parsed = parseMetricNumber(raw);
    if (parsed === null) continue;
    const text = metricToText(parsed);
    if (text === lastCommitted[field] || text === metricToText(base[field])) continue;
    metric[field] = parsed;
    normalized[field] = text;
    fields.push(field);
  }

  if (fields.length === 0) return null;
  return { metric, fields, normalized };
}

/**
 * 卸载 / 失焦兜底：把当前草稿里所有待提交字段合并成一次 update。
 * 返回 decision 以便调用方（组件）同步 lastCommitted；没有待提交字段时返回 null。
 */
export function flushMetricDrafts(
  latest: OkrMetric | undefined,
  draft: MetricDraft,
  lastCommitted: MetricDraft,
  update: (metric: OkrMetric) => void,
): MetricFlushDecision | null {
  const decision = pendingMetricPatch(latest, draft, lastCommitted);
  if (!decision) return null;
  update(decision.metric);
  return decision;
}
