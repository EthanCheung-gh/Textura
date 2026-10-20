/**
 * 快速收集语法解析（纯函数，无 React / 无 store 依赖）。
 *
 * 支持：
 *   #标签        可多个，支持中英文、数字、下划线与短横线
 *   @场景        可多个，第一个作为 gtd.context
 *   !高能/!低能   能量标记（也接受 !high / !low / !中能 / !medium）
 *   /今天 /明天 /后天 /本周 /下周 /周一…/周日   日期短语（写入 gantt.end）
 *
 * 语法 token 从标题中剥离；剩下的是标题。只有标签、没有标题时 hasContent 为 false。
 */
import { addDays, endOfWeek, format } from 'date-fns';
import type { Energy } from '../../core/model';

export interface ParsedCapture {
  /** 原始输入 */
  raw: string;
  /** 去除语法 token 后的标题 */
  title: string;
  /** 去重后的标签（不含 #） */
  tags: string[];
  /** 全部 @场景（不含 @） */
  contexts: string[];
  /** 第一个 @场景 */
  context: string | null;
  /** 能量标记 */
  energy: Energy | null;
  /** 命中的日期短语（含 /），例如 '/明天' */
  datePhrase: string | null;
  /** 解析出的截止日期 'YYYY-MM-DD' */
  date: string | null;
  /** 是否有可提交的标题 */
  hasContent: boolean;
}

const WEEKDAY_INDEX: Record<string, number> = {
  一: 1,
  二: 2,
  三: 3,
  四: 4,
  五: 5,
  六: 6,
  日: 0,
  天: 0,
};

function tagPattern(): RegExp {
  // 前置边界（行首或空白）避免把 email / URL 片段误判成标签。
  return /(^|\s)#([\p{L}\p{N}_-]+)/gu;
}

function contextPattern(): RegExp {
  return /(^|\s)@([\p{L}\p{N}_-]+)/gu;
}

function energyPattern(): RegExp {
  return /!(高能|低能|中能|high|low|medium)/giu;
}

function datePattern(): RegExp {
  return /\/(今天|明天|后天|本周|下周|周[一二三四五六日天])/gu;
}

function collect(input: string, pattern: RegExp, group: number): string[] {
  const values: string[] = [];
  for (const match of input.matchAll(pattern)) {
    const value = match[group];
    if (value) values.push(value);
  }
  return values;
}

function normalizeEnergy(token: string): Energy {
  switch (token.toLowerCase()) {
    case '高能':
    case 'high':
      return 'high';
    case '低能':
    case 'low':
      return 'low';
    default:
      return 'medium';
  }
}

/** 把日期短语换算成具体日期（本地时区，'YYYY-MM-DD'）。 */
export function resolveDatePhrase(phrase: string, now: Date = new Date()): string {
  let target: Date;
  switch (phrase) {
    case '今天':
      target = now;
      break;
    case '明天':
      target = addDays(now, 1);
      break;
    case '后天':
      target = addDays(now, 2);
      break;
    case '本周':
      target = endOfWeek(now, { weekStartsOn: 1 });
      break;
    case '下周':
      target = addDays(endOfWeek(now, { weekStartsOn: 1 }), 7);
      break;
    default: {
      const weekday = WEEKDAY_INDEX[phrase.slice(1)];
      const diff = weekday === undefined ? 0 : (weekday - now.getDay() + 7) % 7;
      target = addDays(now, diff);
    }
  }
  return format(target, 'yyyy-MM-dd');
}

export function parseCapture(input: string, now: Date = new Date()): ParsedCapture {
  const raw = input ?? '';
  const tags = [...new Set(collect(raw, tagPattern(), 2))];
  const contexts = [...new Set(collect(raw, contextPattern(), 2))];
  const energyToken = collect(raw, energyPattern(), 1)[0] ?? null;
  const datePhrase = collect(raw, datePattern(), 1)[0] ?? null;

  const title = raw
    .replace(tagPattern(), '$1')
    .replace(contextPattern(), '$1')
    .replace(energyPattern(), ' ')
    .replace(datePattern(), ' ')
    .replace(/\s+/g, ' ')
    .trim();

  return {
    raw,
    title,
    tags,
    contexts,
    context: contexts[0] ?? null,
    energy: energyToken ? normalizeEnergy(energyToken) : null,
    datePhrase: datePhrase ? `/${datePhrase}` : null,
    date: datePhrase ? resolveDatePhrase(datePhrase, now) : null,
    hasContent: title.length > 0,
  };
}
