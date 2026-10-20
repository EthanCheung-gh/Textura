/** OKR 视图共用的展示映射（只做格式化，不含业务判定）。 */
import type { Item, ItemStatus } from '../../core/model';
import type { BadgeTone } from '../../ui/Badge';
import type { ProgressTone } from '../../ui/Progress';
import type { OkrMetric } from './okrMath';
import { formatDateKey } from '../../core/utils';

export const STATUS_TONE: Record<ItemStatus, BadgeTone> = {
  inbox: 'neutral',
  next: 'info',
  active: 'accent',
  waiting: 'warn',
  scheduled: 'info',
  someday: 'neutral',
  done: 'ok',
  dropped: 'neutral',
};

export function statusTone(status: ItemStatus): BadgeTone {
  return STATUS_TONE[status] ?? 'neutral';
}

export function progressTone(progress: number, behind: boolean): ProgressTone {
  if (behind) return 'danger';
  if (progress >= 100) return 'ok';
  if (progress <= 0) return 'info';
  return 'accent';
}

export function formatNumber(value: number): string {
  if (!Number.isFinite(value)) return '—';
  return Number.isInteger(value) ? String(value) : String(Number(value.toFixed(2)));
}

/** 百分号紧跟数字，其他单位用空格分隔。 */
export function unitSuffix(unit: string): string {
  if (!unit) return '';
  return unit === '%' ? '%' : ` ${unit}`;
}

/** 指标摘要：`2.1 → 3%`。 */
export function formatMetric(metric: OkrMetric | undefined): string {
  if (!metric) return '未设指标';
  return `${formatNumber(metric.start)} → ${formatNumber(metric.target)}${unitSuffix(metric.unit)}`;
}

export function formatSchedule(item: Item): string {
  if (!item.gantt || (!item.gantt.start && !item.gantt.end)) return '未排期';
  const start = formatDateKey(item.gantt.start, 'MM/dd');
  const end = formatDateKey(item.gantt.end, 'MM/dd');
  return `${start} – ${end}`;
}
