import { describe, expect, it } from 'vitest';
import {
  LUNAR_MAX_KEY,
  LUNAR_MIN_KEY,
  festivalOf,
  lunarDayName,
  lunarMonthName,
  lunarToSolar,
  solarTermFestivalOf,
  solarTermOf,
  solarTermsOfYear,
  solarToLunar,
} from './lunar';

/** 逐条断言的验收基准（北京时间公历日期）。 */
const SPRING_FESTIVALS = [
  '1900-01-31',
  '2020-01-25',
  '2021-02-12',
  '2022-02-01',
  '2023-01-22',
  '2024-02-10',
  '2025-01-29',
  '2026-02-17',
  '2027-02-06',
  '2028-01-26',
  '2029-02-13',
  '2030-02-03',
];

const MID_AUTUMNS = ['2024-09-17', '2025-10-06', '2026-09-25', '2027-09-15', '2028-10-03'];
const DUANWUS = ['2024-06-10', '2025-05-31', '2026-06-19', '2027-06-09'];

const TERMS_2026: Array<[string, string]> = [
  ['2026-02-04', '立春'],
  ['2026-03-20', '春分'],
  ['2026-04-05', '清明'],
  ['2026-06-21', '夏至'],
  ['2026-09-23', '秋分'],
  ['2026-12-22', '冬至'],
];

describe('春节（正月初一）', () => {
  for (const key of SPRING_FESTIVALS) {
    it(`${key} 是正月初一`, () => {
      const lunar = solarToLunar(key);
      expect(lunar).not.toBeNull();
      expect(lunar?.month).toBe(1);
      expect(lunar?.day).toBe(1);
      expect(lunar?.isLeap).toBe(false);
      expect(lunar?.monthName).toBe('正月');
      expect(lunar?.dayName).toBe('初一');
      expect(lunar?.festival).toBe('春节');
      // 反向：该年正月初一回推为同一天
      expect(lunarToSolar(lunar!.year, 1, 1)).toBe(key);
    });
  }
});

describe('中秋（八月十五）', () => {
  for (const key of MID_AUTUMNS) {
    it(`${key} 是八月十五`, () => {
      const lunar = solarToLunar(key);
      expect(lunar?.month).toBe(8);
      expect(lunar?.day).toBe(15);
      expect(lunar?.isLeap).toBe(false);
      expect(lunar?.monthName).toBe('八月');
      expect(lunar?.dayName).toBe('十五');
      expect(lunar?.festival).toBe('中秋');
      expect(lunarToSolar(lunar!.year, 8, 15)).toBe(key);
    });
  }
});

describe('端午（五月初五）', () => {
  for (const key of DUANWUS) {
    it(`${key} 是五月初五`, () => {
      const lunar = solarToLunar(key);
      expect(lunar?.month).toBe(5);
      expect(lunar?.day).toBe(5);
      expect(lunar?.isLeap).toBe(false);
      expect(lunar?.festival).toBe('端午');
      expect(lunarToSolar(lunar!.year, 5, 5)).toBe(key);
    });
  }
});

describe('闰月', () => {
  it('2023 闰二月初一 = 2023-03-22', () => {
    const lunar = solarToLunar('2023-03-22');
    expect(lunar?.month).toBe(2);
    expect(lunar?.day).toBe(1);
    expect(lunar?.isLeap).toBe(true);
    expect(lunar?.monthName).toBe('闰二月');
    expect(lunarToSolar(2023, 2, 1, true)).toBe('2023-03-22');
  });

  it('2023 闰二月前一天仍属二月（非闰）', () => {
    const lunar = solarToLunar('2023-03-21');
    expect(lunar?.month).toBe(2);
    expect(lunar?.isLeap).toBe(false);
    expect(lunar?.day).toBe(30);
  });

  it('2025 闰六月初一 = 2025-07-25', () => {
    const lunar = solarToLunar('2025-07-25');
    expect(lunar?.month).toBe(6);
    expect(lunar?.day).toBe(1);
    expect(lunar?.isLeap).toBe(true);
    expect(lunar?.monthName).toBe('闰六月');
    expect(lunarToSolar(2025, 6, 1, true)).toBe('2025-07-25');
  });

  it('不存在的闰月返回 null', () => {
    expect(lunarToSolar(2023, 3, 1, true)).toBeNull();
    expect(lunarToSolar(2026, 2, 1, true)).toBeNull();
  });
});

describe('二十四节气（2026）', () => {
  for (const [key, name] of TERMS_2026) {
    it(`${key} 是${name}`, () => {
      expect(solarTermOf(key)).toBe(name);
    });
  }

  it('2026 年共 24 个节气日，名称不重复且按时间升序', () => {
    const terms = solarTermsOfYear(2026);
    expect(terms).toHaveLength(24);
    expect(new Set(terms.map((term) => term.name)).size).toBe(24);
    expect(new Set(terms.map((term) => term.dateKey)).size).toBe(24);
    expect(terms.map((term) => term.dateKey)).toEqual([
      ...terms.map((term) => term.dateKey),
    ].sort());
    // 每个节气日都能被 solarTermOf 识别
    for (const term of terms) expect(solarTermOf(term.dateKey)).toBe(term.name);
  });

  it('节气名称集合完整', () => {
    expect(solarTermsOfYear(2026).map((term) => term.name)).toEqual([
      '小寒', '大寒', '立春', '雨水', '惊蛰', '春分',
      '清明', '谷雨', '立夏', '小满', '芒种', '夏至',
      '小暑', '大暑', '立秋', '处暑', '白露', '秋分',
      '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
    ]);
  });

  it('清明既是以节气定日的节日，也是当日节气', () => {
    expect(solarTermFestivalOf('2026-04-05')).toBe('清明');
    expect(solarTermOf('2026-04-05')).toBe('清明');
    expect(festivalOf('2026-04-05')).toBe('清明');
    expect(solarTermFestivalOf('2026-04-06')).toBeNull();
  });

  it('非节气日返回 null', () => {
    expect(solarTermOf('2026-04-06')).toBeNull();
    expect(solarTermOf('2026-10-21')).toBeNull();
  });

  it('1900 / 1950 / 2000 / 2050 / 2100 也是 24 个升序且不重复的节气日', () => {
    for (const year of [1900, 1950, 2000, 2050, 2100]) {
      const terms = solarTermsOfYear(year);
      const days = terms.map((term) => term.dateKey);
      expect(terms).toHaveLength(24);
      expect(new Set(days).size).toBe(24);
      expect(days).toEqual([...days].sort());
      expect(days.every((day) => day.startsWith(String(year)))).toBe(true);
      // 1900-01-31 之前不在农历支持范围内（小寒 / 大寒 在此前），按约定返回 null
      for (const term of terms) {
        expect(solarTermOf(term.dateKey)).toBe(term.dateKey >= LUNAR_MIN_KEY ? term.name : null);
      }
    }
  });
});

describe('除夕', () => {
  it('2026 年除夕是 2026-02-16（腊月廿九，该年无三十）', () => {
    const lunar = solarToLunar('2026-02-16');
    expect(lunar?.year).toBe(2025);
    expect(lunar?.month).toBe(12);
    expect(lunar?.day).toBe(29);
    expect(lunar?.monthName).toBe('腊月');
    expect(lunar?.dayName).toBe('廿九');
    expect(lunar?.festival).toBe('除夕');
    expect(lunar?.solarTerm).toBeNull();
  });

  it('春节当天不是除夕', () => {
    expect(solarToLunar('2026-02-17')?.festival).toBe('春节');
  });
});

describe('干支与生肖（春节切换）', () => {
  it('2026-02-17 起为丙午 · 马', () => {
    const lunar = solarToLunar('2026-02-17');
    expect(lunar?.year).toBe(2026);
    expect(lunar?.ganzhiYear).toBe('丙午');
    expect(lunar?.zodiac).toBe('马');
  });

  it('2026-02-16 仍属乙巳 · 蛇', () => {
    const lunar = solarToLunar('2026-02-16');
    expect(lunar?.year).toBe(2025);
    expect(lunar?.ganzhiYear).toBe('乙巳');
    expect(lunar?.zodiac).toBe('蛇');
  });

  it('1900 年正月初一为庚子 · 鼠', () => {
    const lunar = solarToLunar('1900-01-31');
    expect(lunar?.ganzhiYear).toBe('庚子');
    expect(lunar?.zodiac).toBe('鼠');
  });
});

describe('农历名与日名', () => {
  it('月名：正月…冬月、腊月', () => {
    expect(Array.from({ length: 12 }, (_, index) => lunarMonthName(index + 1))).toEqual([
      '正月', '二月', '三月', '四月', '五月', '六月',
      '七月', '八月', '九月', '十月', '冬月', '腊月',
    ]);
    expect(lunarMonthName(6, true)).toBe('闰六月');
  });

  it('日名：初一到三十', () => {
    expect(Array.from({ length: 30 }, (_, index) => lunarDayName(index + 1))).toEqual([
      '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
      '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
      '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
    ]);
  });

  it('大小月与闰月天数一致（2023 闰二月 29 天）', () => {
    const firstLeapDay = lunarToSolar(2023, 2, 1, true);
    const lastLeapDay = lunarToSolar(2023, 2, 29, true);
    expect(firstLeapDay).toBe('2023-03-22');
    expect(lastLeapDay).toBe('2023-04-19');
    expect(lunarToSolar(2023, 2, 30, true)).toBeNull();
  });
});

describe('往返一致性', () => {
  it('2000-01-01 ～ 2050-12-31 每一天 solarToLunar → lunarToSolar 还原', () => {
    const start = Date.UTC(2000, 0, 1);
    const end = Date.UTC(2050, 11, 31);
    let checked = 0;
    const failures: string[] = [];
    for (let time = start; time <= end; time += 86_400_000) {
      const key = new Date(time).toISOString().slice(0, 10);
      const lunar = solarToLunar(key);
      if (!lunar) {
        failures.push(`${key}: null`);
        continue;
      }
      const back = lunarToSolar(lunar.year, lunar.month, lunar.day, lunar.isLeap);
      if (back !== key) failures.push(`${key} → ${back}`);
      checked += 1;
    }
    expect(checked).toBe(18_628); // 2000-01-01 … 2050-12-31
    expect(failures.slice(0, 5)).toEqual([]);
  });

  it('边界与范围外', () => {
    expect(solarToLunar(LUNAR_MIN_KEY)?.month).toBe(1);
    expect(solarToLunar('1900-01-30')).toBeNull();
    expect(solarToLunar('2099-12-31')).not.toBeNull();
    expect(solarToLunar(LUNAR_MAX_KEY)?.month).toBe(12);
    expect(solarToLunar('2101-01-01')).toBeNull();
    expect(solarToLunar('not-a-date')).toBeNull();
    expect(lunarToSolar(1899, 12, 1)).toBeNull();
    expect(lunarToSolar(2101, 1, 1)).toBeNull();
    expect(lunarToSolar(2026, 13, 1)).toBeNull();
    expect(lunarToSolar(2026, 1, 31)).toBeNull();
    expect(lunarToSolar(2100, 12, 1)).toBe('2100-12-31');
    expect(lunarToSolar(2100, 12, 2)).toBeNull();
    expect(festivalOf('2101-01-01')).toBeNull();
    expect(festivalOf('1900-01-30')).toBeNull();
  });

  it('1900-01-31 与 2099-12-31 可反过来还原', () => {
    for (const key of ['1900-01-31', '2099-12-31', '2100-12-31']) {
      const lunar = solarToLunar(key);
      expect(lunar).not.toBeNull();
      expect(lunarToSolar(lunar!.year, lunar!.month, lunar!.day, lunar!.isLeap)).toBe(key);
    }
  });
});

describe('性能', () => {
  it('42 个格子 + 12 个月的农历换算在 1ms 级完成', () => {
    // 预热节气缓存后测量；阈值放宽到 40ms，仍能拦住"每年线性扫描"的实现。
    solarToLunar('2026-10-01');
    const started = performance.now();
    for (let round = 0; round < 20; round += 1) {
      for (let day = 1; day <= 42; day += 1) {
        solarToLunar(`2026-${String((round % 12) + 1).padStart(2, '0')}-${String(((day - 1) % 28) + 1).padStart(2, '0')}`);
      }
    }
    const elapsed = performance.now() - started;
    expect(elapsed).toBeLessThan(40);
  });
});
