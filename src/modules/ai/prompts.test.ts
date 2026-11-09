import { describe, expect, it } from 'vitest';
import { AiRequestError } from './client';
import {
  DIGEST_KIND_LIMITS,
  MAX_DIGEST_CHARS,
  MAX_HEADER_VALUE_CHARS,
  allowedSectionKeys,
  buildFactsDigest,
  parseReportSections,
  reportMessages,
  sectionMessages,
} from './prompts';
import type { ReportAiContext } from './prompts';
import { templateFor } from '../reports/draft';
import type { FactKind, ReportFact, ReportFactsDetailed } from '../reports/facts';

const EMOJI_PATTERN = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;

function makeFact(kind: FactKind, index: number, title?: string): ReportFact {
  const label = title ?? `事项${kind}${String(index).padStart(3, '0')}`;
  const meta = kind === 'completed' ? '完成于 11/02' : '当前 12/20 · 60%';
  return { id: `${kind}-${index}`, kind, title: label, meta, line: `- ${label} · ${meta}` };
}

function makeFacts(
  counts: Partial<Record<FactKind, number>>,
  titleLength = 0,
): ReportFactsDetailed {
  const kinds: FactKind[] = ['completed', 'risk', 'kr', 'run', 'nextUp'];
  const facts: ReportFact[] = [];
  for (const kind of kinds) {
    const count = counts[kind] ?? 0;
    for (let index = 0; index < count; index += 1) {
      // 需要压预算时用超长标题，验证按条截断而不是整份爆掉。
      const title =
        titleLength > 0
          ? `事项${kind}${String(index).padStart(3, '0')}${'长'.repeat(titleLength)}`
          : undefined;
      facts.push(makeFact(kind, index, title));
    }
  }
  const completed = facts.filter((fact) => fact.kind === 'completed');
  return {
    stats: {
      completed: counts.completed ?? 0,
      openInWindow: 3,
      risks: counts.risk ?? 0,
      runs: counts.run ?? 0,
      inboxRemaining: 2,
      inboxProgress: 50,
    },
    facts,
    period: { kind: 'week', key: '2026-W44', start: '2026-10-26', end: '2026-11-01' },
    nextPeriod: { key: '2026-W45', start: '2026-11-02', end: '2026-11-08' },
    completedByArea: [{ areaId: null, name: '未归属领域', facts: completed }],
    riskGroups: { overdue: [], stuck: [], waiting: [], undated: [] },
    runCounts: { total: counts.run ?? 0, pass: counts.run ?? 0, fail: 0, skip: 0 },
  };
}

function makeContext(overrides: Partial<ReportAiContext> = {}): ReportAiContext {
  const sections = templateFor('week').sections.map((section) => ({
    ...section,
    body: `### ${section.title}\n- 旧正文占位`,
  }));
  return {
    kind: 'week',
    periodLabel: '2026 年第 44 周',
    range: { start: '2026-10-26', end: '2026-11-01' },
    author: '张三',
    facts: makeFacts({ completed: 2, risk: 1 }),
    sections,
    ...overrides,
  };
}

/** 同 `makeContext`，但末尾多一节用户自建的 `custom-1`（章节清单里混入自建节）。 */
function makeContextWithCustom(): ReportAiContext {
  const base = makeContext();
  return {
    ...base,
    sections: [...base.sections, { key: 'custom-1', title: '复盘与改进', body: '' }],
  };
}

function onlyContent(messages: { content: string }[]): string {
  return messages.map((message) => message.content).join('\n');
}

/** 章节清单那一行（整份提示词里唯一列出 key（标题）的行）。 */
function listLineOf(content: string): string {
  return content.split('\n').find((line) => line.startsWith('章节清单：')) ?? '';
}

/** 在基础上下文末尾加一节标题可控的自建节，用来验证标题裁剪口径。 */
function withCustomTitle(title: string, key = 'custom-1'): ReportAiContext {
  const base = makeContext();
  return { ...base, sections: [...base.sections, { key, title, body: '' }] };
}

describe('buildFactsDigest', () => {
  it('包含周期、作者与统计口径', () => {
    const digest = buildFactsDigest(makeContext());
    expect(digest).toContain('2026 年第 44 周');
    expect(digest).toContain('2026-10-26 至 2026-11-01');
    expect(digest).toContain('作者：张三');
    expect(digest).toContain('完成 2 项');
    expect(digest).toContain('风险 1 项');
  });

  it('按 kind 上限裁剪条目，超出写「另有 N 条略」', () => {
    const digest = buildFactsDigest(makeContext({ facts: makeFacts({ completed: 45 }) }));
    const itemLines = digest.split('\n').filter((line) => line.startsWith('- '));
    expect(itemLines).toHaveLength(DIGEST_KIND_LIMITS.completed);
    expect(digest).toContain(`另有 ${45 - DIGEST_KIND_LIMITS.completed} 条略`);
    expect(digest).toContain('【完成事项】共 45 条');
  });

  it('超量输入按条截断，总长不超过 MAX_DIGEST_CHARS', () => {
    const heavy = makeContext({
      facts: makeFacts({ completed: 40, risk: 25, kr: 12, run: 12, nextUp: 12 }, 120),
    });
    const digest = buildFactsDigest(heavy);
    expect(digest.length).toBeLessThanOrEqual(MAX_DIGEST_CHARS);
    expect(digest).toContain('另有');
    expect(digest).toContain('条略');
    // 头部一定保留，预算耗尽只丢条目。
    expect(digest).toContain('2026 年第 44 周');
  });

  it('摘要与提示词都不含 emoji', () => {
    const ctx = makeContext();
    expect(EMOJI_PATTERN.test(buildFactsDigest(ctx))).toBe(false);
    expect(EMOJI_PATTERN.test(onlyContent(sectionMessages(ctx, 'progress')))).toBe(false);
    expect(EMOJI_PATTERN.test(onlyContent(reportMessages(ctx)))).toBe(false);
  });

  it('预算按 UTF-16 长度计：emoji 密集输入仍不超过 MAX_DIGEST_CHARS', () => {
    const base = makeFacts({ completed: 30 });
    const emojiFacts: ReportFact[] = Array.from({ length: 30 }, (_, index) =>
      makeFact('completed', index, `事项${index}${'😀'.repeat(100)}`),
    );
    const digest = buildFactsDigest(makeContext({ facts: { ...base, facts: emojiFacts } }));

    // 唯一真源：String.length（UTF-16 长度），也是 UI 的显示口径。
    expect(digest.length).toBeLessThanOrEqual(MAX_DIGEST_CHARS);
    expect(digest).toContain('另有');
    // 码点口径明显更小：若按码点数判预算，会误以为还有余量。
    expect([...digest].length).toBeLessThan(digest.length);
  });

  it('裁剪长行时不留下孤立代理（emoji 不被从中间切断）', () => {
    const base = makeFacts({ completed: 1 });
    const fact = makeFact('completed', 0, `${'😀'.repeat(120)}`);
    const digest = buildFactsDigest(
      makeContext({ facts: { ...base, facts: [{ ...fact, line: `- ${'😀'.repeat(120)}` }] } }),
    );
    // 孤立代理：0xD800–0xDFFF 且必须成对出现，这里用 encodeURIComponent 会抛 URIError。
    expect(() => encodeURIComponent(digest)).not.toThrow();
    expect(digest).toContain('…');
  });

  it('无事实时只输出头部，不出现空的条目段', () => {
    const digest = buildFactsDigest(makeContext({ facts: makeFacts({}) }));
    expect(digest).not.toContain('另有');
    expect(digest.split('\n').some((line) => line.startsWith('- '))).toBe(false);
  });
});

describe('sectionMessages', () => {
  it('含目标节标题与事实摘要，且不含其它节正文', () => {
    const ctx = makeContext();
    const messages = sectionMessages(ctx, 'progress');
    const content = onlyContent(messages);

    expect(messages).toHaveLength(1);
    expect(messages[0]?.role).toBe('user');
    expect(content).toContain('「本周进展」');
    expect(content).toContain('- 事项completed000');
    expect(content).toContain('2026 年第 44 周');
    // 只给单节，不能夹带其它节的既有正文。
    expect(content).not.toContain('旧正文占位');
    expect(content).not.toContain('### 本周概览');
  });

  it('带上单节输出约束：只输出正文、不编造、无数据显式说明', () => {
    const content = onlyContent(sectionMessages(makeContext(), 'risks'));
    expect(content).toContain('只输出该节正文');
    expect(content).toContain('不要重复节标题');
    expect(content).toContain('不要编造');
    expect(content).toContain('本周期无相关记录');
    expect(content).toContain('Markdown 列表');
  });

  it('未知节 key 抛 config 错误（不静默返回空提示词）', () => {
    let error: AiRequestError | null = null;
    try {
      sectionMessages(makeContext(), 'nope');
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('config');
    expect(error?.detail).toContain('overview');
  });

  it('模板节沿用固定的写作提示（口径不变）', () => {
    const content = onlyContent(sectionMessages(makeContext(), 'overview'));
    expect(content).toContain('本节范围：用三到五条概述本周期整体产出与节奏');
    expect(content).not.toContain('不在模板的固定章节里');
  });

  it('自建节：标题进句子，并用兜底写作提示说明它不是模板章节', () => {
    const content = onlyContent(sectionMessages(makeContextWithCustom(), 'custom-1'));

    expect(content).toContain('「复盘与改进」一节');
    // 兜底提示要点名「不在模板的固定章节里」，避免模型去找一个并不存在的模板节。
    expect(content).toContain('本节范围：「复盘与改进」不在模板的固定章节里');
    expect(content).toContain('「- 」列表格式');
    expect(content).toContain('不编造数据');
    // 不串用模板节的写作提示。
    expect(content).not.toContain('用三到五条概述本周期整体产出与节奏');
  });

  it('自建节标题被清空时退回 key，仍能给出可读的范围说明', () => {
    const base = makeContext();
    const ctx: ReportAiContext = {
      ...base,
      sections: [...base.sections, { key: 'custom-2', title: '   ', body: '' }],
    };
    const content = onlyContent(sectionMessages(ctx, 'custom-2'));
    expect(content).toContain('本节范围：「custom-2」不在模板的固定章节里');
    // 句子里的标题同样退回 key，不留一对空括号。
    expect(content).toContain('请撰写这份周报的「custom-2」一节。');
  });

  it('超长自建节标题按 MAX_HEADER_VALUE_CHARS 裁剪（不把整段粘贴文本塞进提示词）', () => {
    const clipped = `${'长'.repeat(MAX_HEADER_VALUE_CHARS - 1)}…`;
    const content = onlyContent(sectionMessages(withCustomTitle('长'.repeat(300)), 'custom-1'));

    expect(content).toContain(`请撰写这份周报的「${clipped}」一节。`);
    expect(content).toContain(`本节范围：「${clipped}」不在模板的固定章节里`);
    // 未裁剪的原文不应出现在提示词的任何位置。
    expect(content).not.toContain('长'.repeat(MAX_HEADER_VALUE_CHARS + 1));
  });

  it('标题里的换行 / 连续空白压成单个空格：句子与范围说明都保持单行', () => {
    const content = onlyContent(
      sectionMessages(withCustomTitle('复盘与改进\n第二行\t附录'), 'custom-1'),
    );

    expect(content).toContain('请撰写这份周报的「复盘与改进 第二行 附录」一节。');
    expect(content).toContain('本节范围：「复盘与改进 第二行 附录」不在模板的固定章节里');
  });

  it('正常标题逐字进入句子（裁剪不改变正常标题的字节）', () => {
    const content = onlyContent(sectionMessages(makeContextWithCustom(), 'custom-1'));

    expect(content).toContain('请撰写这份周报的「复盘与改进」一节。');
    expect(content).toContain('本节范围：「复盘与改进」不在模板的固定章节里');
    expect(content).not.toContain('…');
  });
});

describe('reportMessages', () => {
  it('明确列出模板节 key 与 JSON 数组格式', () => {
    const content = onlyContent(reportMessages(makeContext()));
    for (const section of templateFor('week').sections) {
      expect(content).toContain(section.key);
      expect(content).toContain(section.title);
    }
    expect(content).toContain('只允许这些取值');
    expect(content).toContain('JSON 数组');
    expect(content).toContain('{"key":"overview","body":"..."}');
    // 季报独有的 okr 不应出现在周报的 key 约定里。
    expect(content).not.toContain('okr（目标与关键结果）');
  });

  it('调用方未给 sections 时回落到模板 key', () => {
    const content = onlyContent(reportMessages(makeContext({ sections: [] })));
    expect(content).toContain('overview');
    expect(content).toContain('support');
  });

  it('自建节进入 key 白名单与章节清单，并说明它是用户自建章节', () => {
    const content = onlyContent(reportMessages(makeContextWithCustom()));
    expect(content).toContain('custom-1（复盘与改进）');
    expect(content).toContain('只允许这些取值');
    expect(content).toContain('章节清单：');
    expect(content).toContain('用户自建章节');
  });

  it('纯模板场景的提示词不带自建节痕迹（行为与以前一致）', () => {
    const content = onlyContent(reportMessages(makeContext()));
    expect(content).not.toContain('用户自建章节');
    expect(content).not.toContain('custom-');
  });

  it('提示词不夹带人格设定（systemPrompt 由调用方注入）', () => {
    const content = onlyContent(reportMessages(makeContext()));
    expect(content).not.toContain('你是 Textura');
    expect(content).not.toContain('执行助理');
  });

  it('正常标题逐字进入章节清单（与裁剪前的拼装完全一致）', () => {
    const ctx = makeContextWithCustom();
    const listLine = listLineOf(onlyContent(reportMessages(ctx)));

    // 逐字比对：等于「直接拿原始标题拼」的结果，说明裁剪对正常标题零影响。
    expect(listLine).toBe(
      `章节清单：${ctx.sections.map((entry) => `${entry.key}（${entry.title}）`).join('、')}`,
    );
    expect(listLine).not.toContain('…');
  });

  it('超长自建节标题在章节清单里被裁剪到 MAX_HEADER_VALUE_CHARS', () => {
    const clipped = `${'长'.repeat(MAX_HEADER_VALUE_CHARS - 1)}…`;
    const listLine = listLineOf(onlyContent(reportMessages(withCustomTitle('长'.repeat(300)))));

    expect(listLine).toContain(`custom-1（${clipped}）`);
    // 清单仍是「一行」：长度只随章节数与上限增长，不会被用户的粘贴文本撑爆。
    expect(listLine.length).toBeLessThan(MAX_HEADER_VALUE_CHARS + 200);
  });

  it('标题里的换行 / 全角右括号：清单保持单行，且不牵连相邻章节', () => {
    const clean = onlyContent(reportMessages(makeContextWithCustom()));
    const messy = onlyContent(reportMessages(withCustomTitle('复盘与改进\n第二行）附录')));
    const listLine = listLineOf(messy);

    // 换行被压平：整份提示词的行数不因标题而增加（摘要与标题无关，行数应完全一致）。
    expect(messy.split('\n')).toHaveLength(clean.split('\n').length);
    // 相邻章节仍在同一行里、按「、」分隔，没有被标题里的括号拆出去。
    expect(listLine.startsWith('章节清单：overview（本周概览）、progress（本周进展）')).toBe(true);
    expect(listLine.endsWith('custom-1（复盘与改进 第二行）附录）')).toBe(true);
  });
});

describe('allowedSectionKeys', () => {
  it('与提示词清单同源：含自建节，且保持章节顺序', () => {
    expect(allowedSectionKeys(makeContextWithCustom())).toEqual([
      ...templateFor('week').sections.map((section) => section.key),
      'custom-1',
    ]);
  });

  it('ctx.sections 为空时回落模板 key（解析白名单不会变成空集）', () => {
    expect(allowedSectionKeys(makeContext({ sections: [] }))).toEqual(
      templateFor('week').sections.map((section) => section.key),
    );
  });
});

describe('parseReportSections', () => {
  it('解析纯 JSON 数组并 trim body', () => {
    const sections = parseReportSections(
      '[{"key":"overview","body":"  - 完成 3 项  "},{"key":"risks","body":"- 无风险"}]',
    );
    expect(sections).toEqual([
      { key: 'overview', body: '- 完成 3 项' },
      { key: 'risks', body: '- 无风险' },
    ]);
  });

  it('容忍 ```json 围栏', () => {
    const text = ['```json', '[{"key":"progress","body":"- 推进 A"}]', '```'].join('\n');
    expect(parseReportSections(text)).toEqual([{ key: 'progress', body: '- 推进 A' }]);
  });

  it('容忍前后说明文字', () => {
    const text = [
      '好的，以下是报告内容：',
      '[{"key":"next","body":"- 下周完成 B"}]',
      '以上为全部章节，如需调整请告诉我。',
    ].join('\n');
    expect(parseReportSections(text)).toEqual([{ key: 'next', body: '- 下周完成 B' }]);
  });

  it('容忍尾随逗号，且不破坏字符串里的逗号', () => {
    const text = '[{"key":"metrics","body":"- 见 1, 2 两项",},{"key":"overview","body":"- 概览",},]';
    expect(parseReportSections(text)).toEqual([
      { key: 'metrics', body: '- 见 1, 2 两项' },
      { key: 'overview', body: '- 概览' },
    ]);
  });

  it('过滤未知 key、空 body、非字符串 body 与重复 key', () => {
    const text = JSON.stringify([
      { key: 'overview', body: '- 有效概览' },
      { key: 'unknown-key', body: '- 未知章节' },
      { key: 'risks', body: '   ' },
      { key: 'metrics', body: 42 },
      { key: 'overview', body: '- 重复概览' },
      'not-an-object',
    ]);
    expect(parseReportSections(text)).toEqual([{ key: 'overview', body: '- 有效概览' }]);
  });

  it('非法 JSON 抛 AiRequestError(response)', () => {
    let error: AiRequestError | null = null;
    try {
      parseReportSections('[{key: overview, body: 没有引号}]');
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('response');
  });

  it('找不到数组时抛 AiRequestError(response)', () => {
    let error: AiRequestError | null = null;
    try {
      parseReportSections('抱歉，我无法完成这个请求。');
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('response');
  });

  it('全部章节被过滤后抛 AiRequestError(response)', () => {
    let error: AiRequestError | null = null;
    try {
      parseReportSections('[{"key":"nope","body":"- x"},{"key":"overview","body":""}]');
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('response');
    expect(error?.message).toContain('全部无效');
  });

  it('JSON 是对象而不是数组时抛 AiRequestError(response)', () => {
    let error: AiRequestError | null = null;
    try {
      parseReportSections('{"sections":[{"key":"overview","body":"- x"}]}');
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('response');
  });

  it('自建节 key 只有传了章节清单才放行，没传时按模板并集兜底', () => {
    const text = '[{"key":"overview","body":"- 概览"},{"key":"custom-1","body":"- 复盘"}]';

    expect(parseReportSections(text, ['overview', 'custom-1'])).toEqual([
      { key: 'overview', body: '- 概览' },
      { key: 'custom-1', body: '- 复盘' },
    ]);
    // 不传清单：回落模板并集，自建节被丢弃（老调用方的行为不变）。
    expect(parseReportSections(text)).toEqual([{ key: 'overview', body: '- 概览' }]);
    // 空清单同样回落模板并集，而不是「什么都不允许」。
    expect(parseReportSections(text, [])).toEqual([{ key: 'overview', body: '- 概览' }]);
  });

  it('白名单以传入的章节清单为准：清单外的模板 key 也会被丢掉', () => {
    const text = '[{"key":"overview","body":"- 概览"},{"key":"risks","body":"- 风险"}]';
    expect(parseReportSections(text, ['overview', 'custom-1'])).toEqual([
      { key: 'overview', body: '- 概览' },
    ]);
  });
});
