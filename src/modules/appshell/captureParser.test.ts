import { describe, expect, it } from 'vitest';
import { parseCapture, resolveDatePhrase } from './captureParser';

// 2026-01-05 是周一
const NOW = new Date(2026, 0, 5, 9, 30, 0);

describe('parseCapture', () => {
  it('parses tags, context, energy and date tokens', () => {
    const parsed = parseCapture('给财务回电确认发票抬头 #财务 @电话 !低能 /明天', NOW);
    expect(parsed.title).toBe('给财务回电确认发票抬头');
    expect(parsed.tags).toEqual(['财务']);
    expect(parsed.context).toBe('电话');
    expect(parsed.contexts).toEqual(['电话']);
    expect(parsed.energy).toBe('low');
    expect(parsed.datePhrase).toBe('/明天');
    expect(parsed.date).toBe('2026-01-06');
    expect(parsed.hasContent).toBe(true);
  });

  it('keeps multiple tags and mixed Chinese/English titles', () => {
    const parsed = parseCapture('整理 onboarding 复盘 #增长 #Q1复盘 #增长', NOW);
    expect(parsed.title).toBe('整理 onboarding 复盘');
    expect(parsed.tags).toEqual(['增长', 'Q1复盘']);
  });

  it('uses the first context when several are present', () => {
    const parsed = parseCapture('和设计师对齐 #设计 @电脑 @会议室', NOW);
    expect(parsed.context).toBe('电脑');
    expect(parsed.contexts).toEqual(['电脑', '会议室']);
  });

  it('returns an empty parse for blank input', () => {
    const parsed = parseCapture('   ', NOW);
    expect(parsed.title).toBe('');
    expect(parsed.tags).toEqual([]);
    expect(parsed.context).toBeNull();
    expect(parsed.energy).toBeNull();
    expect(parsed.date).toBeNull();
    expect(parsed.hasContent).toBe(false);
  });

  it('does not treat a tag-only capture as submittable', () => {
    const parsed = parseCapture('#只记录想法', NOW);
    expect(parsed.title).toBe('');
    expect(parsed.tags).toEqual(['只记录想法']);
    expect(parsed.hasContent).toBe(false);
  });

  it('supports high energy and English aliases', () => {
    expect(parseCapture('写方案 !高能', NOW).energy).toBe('high');
    expect(parseCapture('写方案 !high', NOW).energy).toBe('high');
    expect(parseCapture('写方案 !medium', NOW).energy).toBe('medium');
  });

  it('does not swallow email-like text as a context token', () => {
    const parsed = parseCapture('回复 linyi@example.com 的邮件', NOW);
    expect(parsed.title).toBe('回复 linyi@example.com 的邮件');
    expect(parsed.context).toBeNull();
  });
});

describe('resolveDatePhrase', () => {
  it('resolves relative and weekday phrases', () => {
    expect(resolveDatePhrase('今天', NOW)).toBe('2026-01-05');
    expect(resolveDatePhrase('明天', NOW)).toBe('2026-01-06');
    expect(resolveDatePhrase('后天', NOW)).toBe('2026-01-07');
    expect(resolveDatePhrase('周五', NOW)).toBe('2026-01-09');
    expect(resolveDatePhrase('周一', NOW)).toBe('2026-01-05');
    expect(resolveDatePhrase('周日', NOW)).toBe('2026-01-11');
  });

  it('resolves week phrases to the end of week', () => {
    expect(resolveDatePhrase('本周', NOW)).toBe('2026-01-11');
    expect(resolveDatePhrase('下周', NOW)).toBe('2026-01-18');
  });
});
