/**
 * 中国农历 / 二十四节气引擎（纯函数、零依赖）。
 *
 * 数据与算法来源：
 * - 农历月序与大小月：1900–2100 经典 `lunarInfo` 表（每年一个 16 进制数，
 *   低 4 位为闰月月份，0x10000 位为闰月大小，0x8000..0x10 位为正月..腊月大小）。
 *   基准日 1900-01-31 = 农历 1900 年正月初一。该表与香港天文台/紫金山天文台公布的
 *   1900–2100 年农历月序一致，验收基准逐条断言见 lunar.test.ts。
 * - 节气：以太阳视黄经为目标（小寒 285°，每个节气 +15°）做牛顿迭代求解，
 *   太阳视黄经使用 Meeus《Astronomical Algorithms》第 25 章的低精度公式 + 长周期行星摄动项，
 *   并叠加 ΔT（Espenak–Meeus 多项式）把力学时换算为民用时；结果按北京时间（UTC+8）取日期。
 *
 * 所有日期运算使用 UTC 民用日（`Date.UTC` 或"日序号"整数），不依赖本地时区，
 * 因此在任意 `TZ` 下结果一致。
 */

export interface LunarDate {
  /** 农历年（以春节为界） */
  year: number;
  /** 农历月 1..12 */
  month: number;
  /** 农历日 1..30 */
  day: number;
  /** 是否闰月 */
  isLeap: boolean;
  /** 正月 / 二月 / … / 冬月 / 腊月（闰月带「闰」前缀） */
  monthName: string;
  /** 初一 … 初十 / 十一 … 十九 / 二十 / 廿一 … 廿九 / 三十 */
  dayName: string;
  /** 干支年，如「丙午」 */
  ganzhiYear: string;
  /** 生肖，如「马」 */
  zodiac: string;
  /** 农历节日（含除夕、清明），无则 null */
  festival: string | null;
  /** 当日节气名，无则 null */
  solarTerm: string | null;
}

export interface SolarTermInfo {
  name: string;
  /** 北京时间当天的 YYYY-MM-DD */
  dateKey: string;
}

/** 支持范围（含端点）：1900-01-31 ～ 2100-12-31 */
export const LUNAR_MIN_KEY = '1900-01-31';
export const LUNAR_MAX_KEY = '2100-12-31';

const DAY_MS = 86_400_000;
const BEIJING_OFFSET_MS = 8 * 3_600_000;

/** 1900–2100 每年的农历编码（经典 lunarInfo 表）。 */
const LUNAR_INFO: readonly number[] = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, // 2050-2059
  0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, // 2090-2099
  0x0d520, // 2100
];

const MONTH_NAMES = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const DIGITS = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
const STEMS = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const BRANCHES = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const ZODIACS = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];

export const SOLAR_TERM_NAMES = [
  '小寒', '大寒', '立春', '雨水', '惊蛰', '春分',
  '清明', '谷雨', '立夏', '小满', '芒种', '夏至',
  '小暑', '大暑', '立秋', '处暑', '白露', '秋分',
  '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
] as const;

/** 各节气对应的太阳视黄经（度）。 */
const SOLAR_TERM_LONGITUDES = [
  285, 300, 315, 330, 345, 0, 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210,
  225, 240, 255, 270,
];

/** 农历节日：非闰月的「月-日」→ 名称。 */
const LUNAR_FESTIVALS: Record<string, string> = {
  '1-1': '春节',
  '1-15': '元宵',
  '2-2': '龙抬头',
  '5-5': '端午',
  '7-7': '七夕',
  '7-15': '中元',
  '8-15': '中秋',
  '9-9': '重阳',
  '12-8': '腊八',
  '12-23': '小年',
};

export function isLeapMonth(year: number): number {
  if (year < 1900 || year > 2100) return 0;
  return LUNAR_INFO[year - 1900] & 0xf;
}

export function leapMonthDays(year: number): number {
  if (!isLeapMonth(year)) return 0;
  return LUNAR_INFO[year - 1900] & 0x10000 ? 30 : 29;
}

/** 农历某年某月（1..12，非闰月）的天数。 */
export function lunarMonthDays(year: number, month: number): number {
  if (year < 1900 || year > 2100 || month < 1 || month > 12) return 0;
  return LUNAR_INFO[year - 1900] & (0x10000 >> month) ? 30 : 29;
}

/** 农历某年的总天数（含闰月）。 */
export function lunarYearDays(year: number): number {
  if (year < 1900 || year > 2100) return 0;
  const info = LUNAR_INFO[year - 1900];
  let days = 348; // 12 * 29
  for (let bit = 0x8000; bit > 0x8; bit >>= 1) {
    if (info & bit) days += 1;
  }
  return days + leapMonthDays(year);
}

/** 每个农历年正月初一相对 1900-01-31 的日序号（末尾多一项 = 2101 年起点）。 */
const YEAR_START_DAYS: readonly number[] = (() => {
  const starts: number[] = [];
  let acc = 0;
  for (let year = 1900; year <= 2100; year += 1) {
    starts.push(acc);
    acc += lunarYearDays(year);
  }
  starts.push(acc);
  return starts;
})();

/** YYYY-MM-DD → UTC 民用日序号（1970-01-01 为 0）；非法日期返回 null。 */
export function dayNumberFromKey(key: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const utc = Date.UTC(year, month - 1, day);
  const probe = new Date(utc);
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day) {
    return null;
  }
  return Math.round(utc / DAY_MS);
}

/** UTC 民用日序号 → YYYY-MM-DD。 */
export function keyFromDayNumber(dayNumber: number): string {
  return new Date(dayNumber * DAY_MS).toISOString().slice(0, 10);
}

/** 日期键加 n 天（跨月/跨年安全）。 */
export function addDaysToKey(key: string, days: number): string {
  const dayNumber = dayNumberFromKey(key);
  if (dayNumber === null) return key;
  return keyFromDayNumber(dayNumber + days);
}

/** 支持范围的 UTC 日序号（模块加载时计算一次，避免每次换算都解析两个日期串）。 */
const MIN_DAY_NUMBER = dayNumberFromKey(LUNAR_MIN_KEY) as number;
const MAX_DAY_NUMBER = dayNumberFromKey(LUNAR_MAX_KEY) as number;

function inSupportedRange(dayNumber: number): boolean {
  return dayNumber >= MIN_DAY_NUMBER && dayNumber <= MAX_DAY_NUMBER;
}

/** 农历月名：正月…腊月，闰月加「闰」。 */
export function lunarMonthName(month: number, isLeap = false): string {
  const base = MONTH_NAMES[Math.min(12, Math.max(1, month)) - 1];
  return `${isLeap ? '闰' : ''}${base}月`;
}

/** 农历日名：初一…初十、十一…十九、二十、廿一…廿九、三十。 */
export function lunarDayName(day: number): string {
  if (day < 1 || day > 30) return '';
  if (day === 10) return '初十';
  if (day === 20) return '二十';
  if (day === 30) return '三十';
  if (day < 10) return `初${DIGITS[day - 1]}`;
  if (day < 20) return `十${DIGITS[day - 11]}`;
  return `廿${DIGITS[day - 21]}`;
}

/** 干支与生肖（以农历年为准，春节切换）。 */
export function ganzhiOfYear(lunarYear: number): { ganzhi: string; zodiac: string } {
  const index = ((lunarYear - 1864) % 60 + 60) % 60;
  return {
    ganzhi: `${STEMS[index % 10]}${BRANCHES[index % 12]}`,
    zodiac: ZODIACS[index % 12],
  };
}

interface RawLunar {
  year: number;
  month: number;
  day: number;
  isLeap: boolean;
  monthDays: number;
}

/** 公历日序号 → 原始农历字段；超出 1900-01-31 ～ 2100-12-31 返回 null。 */
function rawLunarFromDayNumber(dayNumber: number): RawLunar | null {
  if (!inSupportedRange(dayNumber)) return null;
  let offset = dayNumber - MIN_DAY_NUMBER;

  // 二分查找农历年（YEAR_START_DAYS 单调递增）
  let low = 0;
  let high = 200; // 1900..2100
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (YEAR_START_DAYS[mid] <= offset) low = mid;
    else high = mid - 1;
  }
  const year = 1900 + low;
  offset -= YEAR_START_DAYS[low];

  const leap = isLeapMonth(year);
  for (let month = 1; month <= 12; month += 1) {
    const days = lunarMonthDays(year, month);
    if (offset < days) return { year, month, day: offset + 1, isLeap: false, monthDays: days };
    offset -= days;
    if (leap === month) {
      const leapDays = leapMonthDays(year);
      if (offset < leapDays) return { year, month, day: offset + 1, isLeap: true, monthDays: leapDays };
      offset -= leapDays;
    }
  }
  return null;
}

function lunarFestival(raw: RawLunar): string | null {
  if (!raw.isLeap) {
    const named = LUNAR_FESTIVALS[`${raw.month}-${raw.day}`];
    if (named) return named;
    // 除夕：农历腊月的最后一天（可能是廿九，也可能是三十）
    if (raw.month === 12 && raw.day === raw.monthDays) return '除夕';
  }
  return null;
}

// ---------------------------------------------------------------------------
// 二十四节气（太阳视黄经 + ΔT）
// ---------------------------------------------------------------------------

const RAD = Math.PI / 180;
const termCache = new Map<number, Map<string, SolarTermInfo>>();

function normalizeDegrees(value: number): number {
  return ((value % 360) + 360) % 360;
}

/** ΔT = TT - UT（秒），Espenak–Meeus 多项式，覆盖 1900–2100。 */
function deltaTSeconds(year: number): number {
  if (year < 1920) {
    const t = year - 1900;
    return -2.79 + 1.494119 * t - 0.0598939 * t ** 2 + 0.0061966 * t ** 3 - 0.000197 * t ** 4;
  }
  if (year < 1941) {
    const t = year - 1920;
    return 21.2 + 0.84493 * t - 0.0761 * t ** 2 + 0.0020936 * t ** 3;
  }
  if (year < 1961) {
    const t = year - 1950;
    return 29.07 + 0.407 * t - t ** 2 / 233 + t ** 3 / 2547;
  }
  if (year < 1986) {
    const t = year - 1975;
    return 45.45 + 1.067 * t - t ** 2 / 260 - t ** 3 / 718;
  }
  if (year < 2005) {
    const t = year - 2000;
    return (
      63.86 +
      0.3345 * t -
      0.060374 * t ** 2 +
      0.0017275 * t ** 3 +
      0.000651814 * t ** 4 +
      0.00002373599 * t ** 5
    );
  }
  if (year < 2050) {
    const t = year - 2000;
    return 62.92 + 0.32217 * t + 0.005589 * t ** 2;
  }
  return -20 + 32 * ((year - 1820) / 100) ** 2 - 0.5628 * (2150 - year);
}

/** 太阳视黄经（度），入参为力学时儒略日（JDE）。 */
function sunApparentLongitude(jde: number): number {
  const t = (jde - 2451545.0) / 36525;
  const meanLongitude = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
  const meanAnomaly = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * RAD;
  const equationOfCenter =
    (1.914602 - 0.004817 * t - 0.000014 * t * t) * Math.sin(meanAnomaly) +
    (0.019993 - 0.000101 * t) * Math.sin(2 * meanAnomaly) +
    0.000289 * Math.sin(3 * meanAnomaly);
  const omega = (125.04 - 1934.136 * t) * RAD;
  let lambda = meanLongitude + equationOfCenter - 0.00569 - 0.00478 * Math.sin(omega);

  // 行星长周期摄动（Meeus 第 25 章）
  const a = (153.23 + 22518.7541 * t) * RAD;
  const b = (216.57 + 45037.5082 * t) * RAD;
  const c = (312.69 + 32964.3577 * t) * RAD;
  const d = (350.74 + 445267.1142 * t - 0.00144 * t * t) * RAD;
  const e = (231.19 + 20.2 * t) * RAD;
  lambda +=
    0.00134 * Math.cos(a) +
    0.00154 * Math.cos(b) +
    0.002 * Math.cos(c) +
    0.00179 * Math.sin(d) +
    0.00178 * Math.sin(e);
  return normalizeDegrees(lambda);
}

const J2000_UNIX_EPOCH = Date.UTC(2000, 0, 1, 12, 0, 0); // 2000-01-01T12:00Z = JD 2451545.0

function julianDayFromUnixMs(ms: number): number {
  return (ms - J2000_UNIX_EPOCH) / DAY_MS + 2451545.0;
}

/** 某年第 index 个节气（0=小寒）的北京时间毫秒时间戳。 */
function solarTermTimeMs(year: number, index: number): number {
  const target = SOLAR_TERM_LONGITUDES[index];
  // 初值：1 月 5 日前后，每个节气间隔约 15.2184 天
  let ms = Date.UTC(year, 0, 1) + (index * 15.2184 + 4.5) * DAY_MS;
  for (let iteration = 0; iteration < 30; iteration += 1) {
    const jde = julianDayFromUnixMs(ms) + deltaTSeconds(year) / 86400;
    let diff = normalizeDegrees(sunApparentLongitude(jde) - target);
    if (diff > 180) diff -= 360;
    if (Math.abs(diff) < 1e-8) break;
    ms -= (diff / 0.98564736) * DAY_MS;
  }
  return ms;
}

/** 某年 24 节气的北京时间日期（按小寒→冬至排列）。 */
export function solarTermsOfYear(year: number): SolarTermInfo[] {
  if (year < 1900 || year > 2100) return [];
  const cached = termCache.get(year);
  if (cached) return [...cached.values()];
  const map = new Map<string, SolarTermInfo>();
  const terms: SolarTermInfo[] = SOLAR_TERM_NAMES.map((name, index) => {
    const dateKey = new Date(solarTermTimeMs(year, index) + BEIJING_OFFSET_MS).toISOString().slice(0, 10);
    return { name, dateKey };
  });
  for (const term of terms) map.set(term.dateKey, term);
  termCache.set(year, map);
  return terms;
}

function termMapOfYear(year: number): Map<string, SolarTermInfo> {
  if (!termCache.has(year)) solarTermsOfYear(year);
  return termCache.get(year) ?? new Map<string, SolarTermInfo>();
}

/** 当日节气名（北京时间日期）；不是节气日或超出 1900–2100 返回 null。 */
export function solarTermOf(dateKey: string): string | null {
  const dayNumber = dayNumberFromKey(dateKey);
  if (dayNumber === null || !inSupportedRange(dayNumber)) return null;
  const year = Number(dateKey.slice(0, 4));
  return termMapOfYear(year).get(dateKey)?.name ?? null;
}

/** 当天是否某个「以节气定日」的节日（目前仅清明），是则返回节名。 */
export function solarTermFestivalOf(dateKey: string): string | null {
  return solarTermOf(dateKey) === '清明' ? '清明' : null;
}

// ---------------------------------------------------------------------------
// 对外 API
// ---------------------------------------------------------------------------

/** 公历 YYYY-MM-DD → 农历；超出 1900-01-31 ～ 2100-12-31 返回 null。 */
export function solarToLunar(dateKey: string): LunarDate | null {
  const dayNumber = dayNumberFromKey(dateKey);
  if (dayNumber === null) return null;
  const raw = rawLunarFromDayNumber(dayNumber);
  if (!raw) return null;
  const { ganzhi, zodiac } = ganzhiOfYear(raw.year);
  const term = solarTermOf(dateKey);
  const festival = lunarFestival(raw) ?? (term === '清明' ? '清明' : null);
  return {
    year: raw.year,
    month: raw.month,
    day: raw.day,
    isLeap: raw.isLeap,
    monthName: lunarMonthName(raw.month, raw.isLeap),
    dayName: lunarDayName(raw.day),
    ganzhiYear: ganzhi,
    zodiac,
    festival,
    solarTerm: term,
  };
}

/** 农历 → 公历 YYYY-MM-DD；非法/超出范围返回 null。 */
export function lunarToSolar(year: number, month: number, day: number, isLeap = false): string | null {
  if (year < 1900 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  const leap = isLeapMonth(year);
  if (isLeap && leap !== month) return null;
  if (day < 1) return null;

  let offset = YEAR_START_DAYS[year - 1900];
  for (let m = 1; m < month; m += 1) {
    offset += lunarMonthDays(year, m);
    if (leap === m) offset += leapMonthDays(year);
  }
  if (isLeap) offset += lunarMonthDays(year, month);
  const duration = isLeap ? leapMonthDays(year) : lunarMonthDays(year, month);
  if (day > duration) return null;
  offset += day - 1;

  const dayNumber = MIN_DAY_NUMBER + offset;
  if (!inSupportedRange(dayNumber)) return null;
  return keyFromDayNumber(dayNumber);
}

/** 农历节日（含除夕、清明）；无则 null。超出范围返回 null。 */
export function festivalOf(dateKey: string): string | null {
  return solarToLunar(dateKey)?.festival ?? null;
}
