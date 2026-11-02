import { describe, expect, it } from 'vitest';
import {
  currentPeriodKey,
  periodKey,
  periodKindOf,
  periodLabel,
  periodRange,
  shiftPeriod,
} from './period';

/** 本地时区构造日期，避免测试依赖跑测机器的时区。 */
function day(year: number, month: number, date: number): Date {
  return new Date(year, month - 1, date);
}

describe('periodKey', () => {
  it('周键按 ISO 8601（周一起始），不是「一年第几天 / 7」', () => {
    expect(periodKey('week', day(2026, 11, 2))).toBe('2026-W45');
    expect(periodKey('week', day(2026, 11, 8))).toBe('2026-W45');
    expect(periodKey('week', day(2026, 11, 9))).toBe('2026-W46');
    // 周号补零到两位
    expect(periodKey('week', day(2026, 1, 5))).toBe('2026-W02');
  });

  it('跨年周归属正确的 ISO 周年', () => {
    // 2026-01-01 是周四 → 属于 2026-W01；同一周的周一在 2025-12-29。
    expect(periodKey('week', day(2026, 1, 1))).toBe('2026-W01');
    expect(periodKey('week', day(2025, 12, 29))).toBe('2026-W01');
    // 2025-12-28 是周日 → 仍属 2025-W52（2025 只有 52 个 ISO 周）。
    expect(periodKey('week', day(2025, 12, 28))).toBe('2025-W52');
    // 2026 有 53 个 ISO 周：2026-12-28（周一）属 2026-W53，2027-01-01 也在这周里。
    expect(periodKey('week', day(2026, 12, 28))).toBe('2026-W53');
    expect(periodKey('week', day(2027, 1, 1))).toBe('2026-W53');
    expect(periodKey('week', day(2027, 1, 4))).toBe('2027-W01');
  });

  it('月 / 季键', () => {
    expect(periodKey('month', day(2026, 11, 2))).toBe('2026-11');
    expect(periodKey('month', day(2026, 1, 31))).toBe('2026-01');
    expect(periodKey('quarter', day(2026, 1, 1))).toBe('2026-Q1');
    expect(periodKey('quarter', day(2026, 11, 2))).toBe('2026-Q4');
    expect(periodKey('quarter', day(2026, 12, 31))).toBe('2026-Q4');
  });

  it('非法日期返回空串（与模型层归一化约定一致）', () => {
    expect(periodKey('week', new Date(Number.NaN))).toBe('');
  });

  it('currentPeriodKey 默认取当前时间', () => {
    expect(currentPeriodKey('week', day(2026, 11, 2))).toBe('2026-W45');
    expect(currentPeriodKey('month', day(2026, 11, 2))).toBe('2026-11');
    expect(currentPeriodKey('quarter', day(2026, 11, 2))).toBe('2026-Q4');
    expect(currentPeriodKey('week')).toMatch(/^\d{4}-W\d{2}$/);
  });
});

describe('periodRange', () => {
  it('周 = 周一 ~ 周日（含首尾）', () => {
    expect(periodRange('week', '2026-W45')).toEqual({ start: '2026-11-02', end: '2026-11-08' });
    // 跨年周：周一起于上一年 12 月
    expect(periodRange('week', '2026-W01')).toEqual({ start: '2025-12-29', end: '2026-01-04' });
    // 2026 的第 53 周跨到 2027 年
    expect(periodRange('week', '2026-W53')).toEqual({ start: '2026-12-28', end: '2027-01-03' });
  });

  it('月 = 自然月，闰年 2 月有 29 天', () => {
    expect(periodRange('month', '2026-11')).toEqual({ start: '2026-11-01', end: '2026-11-30' });
    expect(periodRange('month', '2026-02')).toEqual({ start: '2026-02-01', end: '2026-02-28' });
    expect(periodRange('month', '2028-02')).toEqual({ start: '2028-02-01', end: '2028-02-29' });
    expect(periodRange('month', '2026-12')).toEqual({ start: '2026-12-01', end: '2026-12-31' });
  });

  it('季 = 自然季度', () => {
    expect(periodRange('quarter', '2026-Q4')).toEqual({ start: '2026-10-01', end: '2026-12-31' });
    expect(periodRange('quarter', '2026-Q1')).toEqual({ start: '2026-01-01', end: '2026-03-31' });
  });

  it('非法 key 返回 null', () => {
    expect(periodRange('week', '2025-W53')).toBeNull(); // 2025 只有 52 个 ISO 周
    expect(periodRange('week', '2026-W00')).toBeNull();
    expect(periodRange('week', '2026-W54')).toBeNull();
    expect(periodRange('week', '2026-W5')).toBeNull();
    expect(periodRange('month', '2026-00')).toBeNull();
    expect(periodRange('month', '2026-13')).toBeNull();
    expect(periodRange('month', '2026-1')).toBeNull();
    expect(periodRange('quarter', '2026-Q0')).toBeNull();
    expect(periodRange('quarter', '2026-Q5')).toBeNull();
    expect(periodRange('week', '')).toBeNull();
    expect(periodRange('week', 'not-a-period')).toBeNull();
    // 粒度与 key 形态不一致也算非法
    expect(periodRange('week', '2026-11')).toBeNull();
    expect(periodRange('month', '2026-W45')).toBeNull();
    expect(periodRange('quarter', '2026-W45')).toBeNull();
  });
});

describe('shiftPeriod', () => {
  it('周：±1 往返、跨年、负 delta', () => {
    expect(shiftPeriod('week', '2026-W45', 1)).toBe('2026-W46');
    expect(shiftPeriod('week', '2026-W45', -1)).toBe('2026-W44');
    expect(shiftPeriod('week', '2026-W45', 0)).toBe('2026-W45');
    expect(shiftPeriod('week', '2026-W45', -5)).toBe('2026-W40');
    // 2026 有 53 周：W53 + 1 → 次年 W01
    expect(shiftPeriod('week', '2026-W53', 1)).toBe('2027-W01');
    // 2026-W01 的周一在 2025-12-29 → 减一周落到 2025-W52（2025 的最后一周）
    expect(shiftPeriod('week', '2026-W01', -1)).toBe('2025-W52');
    expect(shiftPeriod('week', '2025-W52', 1)).toBe('2026-W01');
  });

  it('周：往返一致（随机抽样 20 个连续周）', () => {
    let key: string | null = '2025-W40';
    const seen: string[] = [];
    for (let index = 0; index < 20; index += 1) {
      key = shiftPeriod('week', key as string, 1);
      expect(key).not.toBeNull();
      seen.push(key as string);
    }
    for (let index = seen.length - 1; index >= 0; index -= 1) {
      key = shiftPeriod('week', key as string, -1);
      if (index === 0) expect(key).toBe('2025-W40');
      else expect(key).toBe(seen[index - 1]);
    }
  });

  it('月：12 月 +1 跨年，1 月 -1 回上年', () => {
    expect(shiftPeriod('month', '2026-11', 1)).toBe('2026-12');
    expect(shiftPeriod('month', '2026-12', 1)).toBe('2027-01');
    expect(shiftPeriod('month', '2026-01', -1)).toBe('2025-12');
    expect(shiftPeriod('month', '2026-11', -12)).toBe('2025-11');
    expect(shiftPeriod('month', '2026-03', -1)).toBe('2026-02');
    expect(shiftPeriod('month', '2026-12', 13)).toBe('2028-01');
  });

  it('季：Q4 +1 → 次年 Q1，Q1 -1 → 上年 Q4', () => {
    expect(shiftPeriod('quarter', '2026-Q4', 1)).toBe('2027-Q1');
    expect(shiftPeriod('quarter', '2026-Q1', -1)).toBe('2025-Q4');
    expect(shiftPeriod('quarter', '2026-Q4', -4)).toBe('2025-Q4');
    expect(shiftPeriod('quarter', '2026-Q2', 3)).toBe('2027-Q1');
  });

  it('非法输入返回 null', () => {
    expect(shiftPeriod('week', '2025-W53', 1)).toBeNull();
    expect(shiftPeriod('month', '2026-13', 1)).toBeNull();
    expect(shiftPeriod('week', '2026-W45', 1.5)).toBeNull();
    expect(shiftPeriod('week', '2026-W45', Number.NaN)).toBeNull();
  });
});

describe('periodLabel', () => {
  it('三种中文格式', () => {
    expect(periodLabel('week', '2026-W44')).toBe('2026 年第 44 周');
    expect(periodLabel('week', '2026-W04')).toBe('2026 年第 4 周');
    expect(periodLabel('month', '2026-11')).toBe('2026 年 11 月');
    expect(periodLabel('month', '2026-01')).toBe('2026 年 1 月');
    expect(periodLabel('quarter', '2026-Q4')).toBe('2026 年第四季度');
    expect(periodLabel('quarter', '2026-Q1')).toBe('2026 年第一季度');
  });

  it('非法 key 返回空串', () => {
    expect(periodLabel('week', '2025-W53')).toBe('');
    expect(periodLabel('month', '')).toBe('');
  });
});

describe('periodKindOf', () => {
  it('按形态反推', () => {
    expect(periodKindOf('2026-W44')).toBe('week');
    expect(periodKindOf('2026-11')).toBe('month');
    expect(periodKindOf('2026-Q4')).toBe('quarter');
  });

  it('无法识别返回 null（只判形态不判范围）', () => {
    expect(periodKindOf('')).toBeNull();
    expect(periodKindOf('2026-W4')).toBeNull();
    expect(periodKindOf('2026-1')).toBeNull();
    expect(periodKindOf('2026-Q')).toBeNull();
    expect(periodKindOf('2026')).toBeNull();
    expect(periodKindOf('weekly')).toBeNull();
    // 形态合法但范围非法：交给 periodRange 判
    expect(periodKindOf('2026-13')).toBe('month');
    expect(periodRange('month', '2026-13')).toBeNull();
  });
});
