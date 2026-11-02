/**
 * 周报 / 月报 / 季报的周期计算（纯函数）。
 *
 * 契约：
 * - 周期键形态固定为 `2026-W44` | `2026-11` | `2026-Q4`；
 * - 周一律按 ISO 8601（周一起始，与 gantt/scale.ts 的 `weekStartsOn: 1` 一致），
 *   绝不用「一年第几天 / 7」的近似算法，跨年周必须归属正确的 ISO 周年；
 * - 所有范围都是本地时区的自然周期，`start`/`end` 均为含首尾的 `YYYY-MM-DD` 日键；
 * - 任何无法解析的输入都返回 `null`，调用方负责拒绝（聚合层据此抛「非法周期」）。
 *
 * 季度数学全部复用 `okr/okrMath` 与 `core/utils.quarterRange`，这里不重复实现。
 */
import { addDays, addMonths, addWeeks, format, getISOWeek, getISOWeekYear, getISOWeeksInYear, parseISO, startOfISOWeek } from 'date-fns';
import type { ReportPeriodKind } from '../../core/model';
import { quarterRange } from '../../core/utils';
import { shiftQuarter } from '../okr/okrMath';

export interface PeriodRange {
  /** 周期第一天（含），本地时区 `YYYY-MM-DD`。 */
  start: string;
  /** 周期最后一天（含），本地时区 `YYYY-MM-DD`。 */
  end: string;
}

const WEEK_KEY_PATTERN = /^(\d{4})-W(\d{2})$/;
const MONTH_KEY_PATTERN = /^(\d{4})-(\d{2})$/;
const QUARTER_KEY_PATTERN = /^(\d{4})-Q([1-4])$/;

const QUARTER_CN = ['一', '二', '三', '四'] as const;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

/** 日期 → ISO 周键（周年取 ISO week-numbering year，不是自然年）。 */
function weekKeyOf(date: Date): string {
  return `${getISOWeekYear(date)}-W${pad2(getISOWeek(date))}`;
}

/** ISO 周的周一：该 ISO 年第 1 周恒包含 1 月 4 日。 */
function isoWeekOneMonday(year: number): Date {
  return startOfISOWeek(new Date(year, 0, 4));
}

/**
 * 周期键。非法 `kind` 或非法日期回退为空串（与模型层归一化约定一致），
 * 调用方用 `periodRange` 判定有效性。
 */
export function periodKey(kind: ReportPeriodKind, date: Date): string {
  if (Number.isNaN(date.getTime())) return '';
  switch (kind) {
    case 'week':
      return weekKeyOf(date);
    case 'month':
      return format(date, 'yyyy-MM');
    case 'quarter': {
      const quarter = Math.floor(date.getMonth() / 3) + 1;
      return `${format(date, 'yyyy')}-Q${quarter}`;
    }
    default:
      return '';
  }
}

export function currentPeriodKey(kind: ReportPeriodKind, now: Date = new Date()): string {
  return periodKey(kind, now);
}

/** 周期键 → [start, end]（含首尾，本地日键）。非法 key 返回 null。 */
export function periodRange(kind: ReportPeriodKind, key: string): PeriodRange | null {
  if (typeof key !== 'string' || key.length === 0) return null;

  switch (kind) {
    case 'week': {
      const match = WEEK_KEY_PATTERN.exec(key);
      if (!match) return null;
      const year = Number(match[1]);
      const week = Number(match[2]);
      const weekOne = isoWeekOneMonday(year);
      if (week < 1 || week > getISOWeeksInYear(weekOne)) return null;
      const monday = addWeeks(weekOne, week - 1);
      // 回读校验：跨年周必须落在同一个 ISO 周年内，否则视为非法键。
      if (getISOWeekYear(monday) !== year || getISOWeek(monday) !== week) return null;
      return { start: format(monday, 'yyyy-MM-dd'), end: format(addDays(monday, 6), 'yyyy-MM-dd') };
    }
    case 'month': {
      const match = MONTH_KEY_PATTERN.exec(key);
      if (!match) return null;
      const year = Number(match[1]);
      const month = Number(match[2]);
      if (month < 1 || month > 12) return null;
      const start = new Date(year, month - 1, 1);
      // 下个月 1 号再退 1 天 = 本月最后一天，避免手写月份天数表。
      const end = new Date(year, month, 1);
      end.setDate(end.getDate() - 1);
      return { start: format(start, 'yyyy-MM-dd'), end: format(end, 'yyyy-MM-dd') };
    }
    case 'quarter': {
      if (!QUARTER_KEY_PATTERN.test(key)) return null;
      return quarterRange(key);
    }
    default:
      return null;
  }
}

/**
 * 周期偏移。跨年、负数、周跨年（本周是当年最后一周 / 第一周）都由日期运算自然处理：
 * 周 = 周一 ± 7×delta 后回读 ISO 周键，因此 `2026-W53`（若存在）+1 → 次年 `W01`，
 * 不存在的周号（如 `2025-W53`）直接判非法返回 null。
 */
export function shiftPeriod(kind: ReportPeriodKind, key: string, delta: number): string | null {
  if (!Number.isFinite(delta) || !Number.isInteger(delta)) return null;
  const range = periodRange(kind, key);
  if (!range) return null;
  const start = parseISO(range.start);
  if (Number.isNaN(start.getTime())) return null;

  switch (kind) {
    case 'week':
      return weekKeyOf(addWeeks(start, delta));
    case 'month':
      return format(addMonths(start, delta), 'yyyy-MM');
    case 'quarter':
      return shiftQuarter(key, delta);
    default:
      return null;
  }
}

/** 中文周期标题：`2026 年第 44 周` / `2026 年 11 月` / `2026 年第四季度`。 */
export function periodLabel(kind: ReportPeriodKind, key: string): string {
  const range = periodRange(kind, key);
  if (!range) return '';
  switch (kind) {
    case 'week': {
      const year = Number(key.slice(0, 4));
      const week = Number(key.slice(6));
      return `${year} 年第 ${week} 周`;
    }
    case 'month': {
      const year = Number(key.slice(0, 4));
      const month = Number(key.slice(5));
      return `${year} 年 ${month} 月`;
    }
    case 'quarter': {
      const year = Number(key.slice(0, 4));
      const quarter = Number(key.slice(6));
      return `${year} 年第${QUARTER_CN[quarter - 1]}季度`;
    }
    default:
      return '';
  }
}

/**
 * 按形态反推粒度（深链 / 跨模块校验用）。
 * 只判形态不判范围：`2026-13` 形态上是月键，是否合法交给 `periodRange`。
 */
export function periodKindOf(key: string): ReportPeriodKind | null {
  if (typeof key !== 'string') return null;
  if (WEEK_KEY_PATTERN.test(key)) return 'week';
  if (MONTH_KEY_PATTERN.test(key)) return 'month';
  if (QUARTER_KEY_PATTERN.test(key)) return 'quarter';
  return null;
}
