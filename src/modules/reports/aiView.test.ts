import { describe, expect, it } from 'vitest';
import { AiRequestError } from '../ai/client';
import type { AiErrorKind } from '../ai/client';
import { MAX_DIGEST_CHARS } from '../ai/prompts';
import {
  aiErrorText,
  buildAiContext,
  digestSizeText,
  filterSectionsByDisplay,
} from './aiView';
import { templateFor } from './draft';
import type { ReportFactsDetailed } from './facts';

function makeFacts(): ReportFactsDetailed {
  return {
    stats: { completed: 2, openInWindow: 1, risks: 0, runs: 0, inboxRemaining: 0, inboxProgress: 0 },
    facts: [],
    period: { kind: 'week', key: '2026-W44', start: '2026-10-26', end: '2026-11-01' },
    nextPeriod: { key: '2026-W45', start: '2026-11-02', end: '2026-11-08' },
    completedByArea: [],
    riskGroups: { overdue: [], stuck: [], waiting: [], undated: [] },
    runCounts: { total: 0, pass: 0, fail: 0, skip: 0 },
  };
}

function aiError(kind: AiErrorKind, message: string, detail?: string, status?: number) {
  return new AiRequestError(kind, message, { detail, status });
}

describe('aiErrorText', () => {
  it('auth：指向设置里的 API Key，不给重试', () => {
    const view = aiErrorText(aiError('auth', '鉴权失败（HTTP 401）', 'invalid token', 401));
    expect(view.title).toBe('密钥被拒绝，请到设置检查 API Key');
    expect(view.needsSettings).toBe(true);
    expect(view.canRetry).toBe(false);
    // hint 只带状态码与已脱敏的详情，方便用户自查网关
    expect(view.hint).toContain('HTTP 401');
    expect(view.hint).toContain('invalid token');
  });

  it('rate-limit：稍后重试，可以重发', () => {
    const view = aiErrorText(aiError('rate-limit', '请求被限流（HTTP 429）', undefined, 429));
    expect(view.title).toBe('请求过于频繁，稍后重试');
    expect(view.canRetry).toBe(true);
    expect(view.needsSettings).toBe(false);
  });

  it('timeout：提示可重试', () => {
    const view = aiErrorText(aiError('timeout', '请求超时（60 秒）'));
    expect(view.title).toBe('请求超时，可重试');
    expect(view.canRetry).toBe(true);
    expect(view.needsSettings).toBe(false);
  });

  it('network + detail 含「跨域」：按 CORS 处理，引导换网关', () => {
    const view = aiErrorText(
      aiError(
        'network',
        '网络请求失败，无法连接模型网关',
        '可能是跨域限制（CORS）或网关不可达；原始错误：TypeError: Failed to fetch',
      ),
    );
    expect(view.title).toBe('疑似跨域被拒（CORS）或网关不可达，请改用允许浏览器直连的网关');
    expect(view.needsSettings).toBe(true);
    expect(view.canRetry).toBe(false);
  });

  it('network 且没有跨域线索：按普通网络故障提示', () => {
    const view = aiErrorText(aiError('network', '网关返回异常状态（HTTP 302）', 'redirect'));
    expect(view.title).toBe('网络请求失败，请检查网络或网关地址');
    expect(view.canRetry).toBe(true);
    expect(view.needsSettings).toBe(false);
  });

  it('server：网关 5xx，可重试', () => {
    const view = aiErrorText(aiError('server', '模型服务异常（HTTP 502）', undefined, 502));
    expect(view.title).toBe('网关返回错误，稍后重试');
    expect(view.canRetry).toBe(true);
    expect(view.hint).toContain('HTTP 502');
  });

  it('response：模型输出格式异常，可重新生成', () => {
    const view = aiErrorText(aiError('response', '模型返回内容中找不到 JSON 数组', '这里是一段散文'));
    expect(view.title).toBe('模型输出格式异常，可重新生成');
    expect(view.canRetry).toBe(true);
    expect(view.needsSettings).toBe(false);
  });

  it('config：去设置补齐配置，不重试', () => {
    const view = aiErrorText(
      aiError('config', '大模型配置未通过校验', 'baseUrl：Base URL 需以 http:// 或 https:// 开头'),
    );
    expect(view.title).toBe('配置未就绪，请先到设置完成配置');
    expect(view.needsSettings).toBe(true);
    expect(view.canRetry).toBe(false);
  });

  it('unknown：直接展示原始 message', () => {
    const view = aiErrorText(aiError('unknown', '大模型请求失败', 'Error: boom'));
    expect(view.title).toBe('大模型请求失败');
    expect(view.canRetry).toBe(true);
    expect(view.needsSettings).toBe(false);
  });

  it('aborted 有分支且有文案（面板本身对取消静默忽略）', () => {
    expect(aiErrorText(aiError('aborted', '请求已取消')).title).toBe('已取消生成');
  });

  it('非 AiRequestError：回落到 Error.message，空值时给兜底文案', () => {
    expect(aiErrorText(new Error('boom')).title).toBe('boom');
    expect(aiErrorText(new Error('')).title).toBe('大模型请求失败');
    expect(aiErrorText(null).title).toBe('大模型请求失败');
    expect(aiErrorText('随便一个字符串').title).toBe('随便一个字符串');
  });

  it('过长的 detail 会被截断，不把整段网关回包塞进 280px 面板', () => {
    const view = aiErrorText(aiError('server', '模型服务异常', 'x'.repeat(500), 500));
    expect(view.hint.endsWith('…')).toBe(true);
    expect(view.hint.length).toBeLessThanOrEqual(180);
  });
});

describe('filterSectionsByDisplay', () => {
  /** 展示清单（模板节 + 自建节），顺序即编辑器里的顺序。 */
  const orderedKeys = ['overview', 'custom-1', 'risks'];
  /** 只要模板口径时，把模板节的 key 序列当展示清单传进来（原 `filterSectionsByTemplate`）。 */
  const templateKeys = templateFor('week').sections.map((section) => section.key);

  it('自建节同样放行，输出顺序 = 展示顺序（与模型返回顺序无关）', () => {
    const result = filterSectionsByDisplay(
      [
        { key: 'risks', body: 'R' },
        { key: 'custom-1', body: 'C' },
        { key: 'overview', body: 'O' },
      ],
      orderedKeys,
    );
    expect(result.map((entry) => entry.key)).toEqual(['overview', 'custom-1', 'risks']);
  });

  it('清单外的 key（模型编出来的 / 旧模板遗留）丢掉', () => {
    const result = filterSectionsByDisplay(
      [
        { key: 'legacy-section', body: '旧模板的节' },
        { key: 'overview', body: 'O' },
      ],
      orderedKeys,
    );
    expect(result.map((entry) => entry.key)).toEqual(['overview']);
  });

  it('以模板 key 作展示清单：按模板顺序输出，自建节与遗留 key 一律丢掉', () => {
    const result = filterSectionsByDisplay(
      [
        { key: 'risks', body: 'R1' },
        { key: 'legacy-section', body: '旧模板的节' },
        { key: 'overview', body: 'O1' },
      ],
      templateKeys,
    );
    expect(result.map((entry) => entry.key)).toEqual(['overview', 'risks']);
    expect(result[1]?.body).toBe('R1');
    // 模板口径不会放行自建节：需要自建节时必须走展示清单。
    expect(filterSectionsByDisplay([{ key: 'custom-1', body: 'C' }], templateKeys)).toEqual([]);
  });

  it('同一 key 重复出现时只留第一条', () => {
    const result = filterSectionsByDisplay(
      [
        { key: 'custom-1', body: '第一份' },
        { key: 'custom-1', body: '第二份' },
      ],
      orderedKeys,
    );
    expect(result).toHaveLength(1);
    expect(result[0]?.body).toBe('第一份');
  });

  it('全被过滤 / 清单为空时返回空数组（由调用方报 response 错误）', () => {
    expect(filterSectionsByDisplay([{ key: 'nope', body: 'X' }], orderedKeys)).toEqual([]);
    expect(filterSectionsByDisplay([], orderedKeys)).toEqual([]);
    expect(filterSectionsByDisplay([{ key: 'overview', body: 'O' }], [])).toEqual([]);
  });

  it('引用相等：原样返回命中的对象，便于上层做 memo 比较', () => {
    const entry = { key: 'custom-1', body: 'C', extra: 1 };
    expect(filterSectionsByDisplay([entry], orderedKeys)[0]).toBe(entry);
  });
});

describe('buildAiContext', () => {
  it('节清单取展示顺序，模板缺节保留空正文', () => {
    const template = templateFor('week');
    const ctx = buildAiContext({
      kind: 'week',
      period: '2026-W44',
      range: { start: '2026-10-26', end: '2026-11-01' },
      author: '张三',
      sections: [{ key: 'overview', body: '本周概览正文' }],
      facts: makeFacts(),
    });

    expect(ctx.sections.map((section) => section.key)).toEqual(
      template.sections.map((section) => section.key),
    );
    expect(ctx.sections.map((section) => section.title)).toEqual(
      template.sections.map((section) => section.title),
    );
    expect(ctx.sections[0]?.body).toBe('本周概览正文');
    // 模板里有、报告里没有的节：保留成空正文，而不是从数组里删掉
    expect(ctx.sections.slice(1).every((section) => section.body === '')).toBe(true);
  });

  it('自建节与历史遗留 key 照样进入上下文，留在原槽位、用报告自存的标题', () => {
    const ctx = buildAiContext({
      kind: 'week',
      period: '2026-W44',
      range: null,
      author: '',
      sections: [
        { key: 'risks', title: '风险与阻塞', body: '风险正文' },
        { key: 'custom-1', title: '复盘与改进', body: '- 复盘' },
        // 旧报告里残留的旧模板标题：模板节一律以模板标题为准，见下一条断言。
        { key: 'overview', title: '旧的概览标题', body: '概览正文' },
      ],
      facts: makeFacts(),
    });

    // 顺序 = displaySections 的顺序：补齐的模板缺节夹在前后模板节之间，自建节留在原槽位。
    expect(ctx.sections.map((section) => section.key)).toEqual([
      'progress',
      'metrics',
      'risks',
      'next',
      'support',
      'custom-1',
      'overview',
    ]);
    const byKey = new Map(ctx.sections.map((section) => [section.key, section]));
    expect(byKey.get('custom-1')).toEqual({
      key: 'custom-1',
      title: '复盘与改进',
      body: '- 复盘',
    });
    expect(byKey.get('risks')?.body).toBe('风险正文');
    // 模板节标题是口径来源：报告里存的旧标题不漂进提示词。
    expect(byKey.get('overview')?.title).toBe('本周概览');
  });

  it('报告没有任何正文时，整份模板节都在，且都是空正文', () => {
    const template = templateFor('week');
    const ctx = buildAiContext({
      kind: 'week',
      period: '2026-W44',
      range: null,
      author: '',
      sections: [],
      facts: makeFacts(),
    });
    expect(ctx.sections).toEqual(
      template.sections.map((section) => ({ key: section.key, title: section.title, body: '' })),
    );
  });

  it('头部字段：期次文案由期次键反推，作者与范围原样带出', () => {
    const ctx = buildAiContext({
      kind: 'week',
      period: '2026-W44',
      range: { start: '2026-10-26', end: '2026-11-01' },
      author: '  张三  ',
      sections: [],
      facts: makeFacts(),
    });
    expect(ctx.periodLabel).toBe('2026 年第 44 周');
    expect(ctx.author).toBe('  张三  ');
    expect(ctx.range).toEqual({ start: '2026-10-26', end: '2026-11-01' });
    expect(ctx.kind).toBe('week');
  });

  it('期次非法时回退到期次键，范围可为空', () => {
    const ctx = buildAiContext({
      kind: 'week',
      period: '不是期次键',
      range: null,
      author: '',
      sections: [],
      facts: makeFacts(),
    });
    expect(ctx.periodLabel).toBe('不是期次键');
    expect(ctx.range).toBeNull();
  });

  it('同一 key 出现多次时取第一处；可注入报告自带模板', () => {
    const ctx = buildAiContext({
      kind: 'week',
      period: '2026-W44',
      range: null,
      author: '',
      sections: [
        { key: 'overview', body: '第一处' },
        { key: 'overview', body: '第二处' },
      ],
      facts: makeFacts(),
      template: { id: 'custom', kind: 'week', sections: [{ key: 'overview', title: '概览' }] },
    });
    expect(ctx.sections).toEqual([{ key: 'overview', title: '概览', body: '第一处' }]);
  });
});

describe('digestSizeText', () => {
  it('空摘要计 0', () => {
    expect(digestSizeText('')).toBe('本次摘要 0 字符');
  });

  it('与 prompts.ts 同口径：按 UTF-16 长度计数（emoji 算 2）', () => {
    expect(digestSizeText('abc')).toBe('本次摘要 3 字符');
    expect(digestSizeText('😀中')).toBe('本次摘要 3 字符');
  });

  it('emoji 摘要：显示值与 text.length 一致，不按码点缩水', () => {
    const digest = '😀 完成 3 项'.repeat(2);
    // 码点口径会数出更小的值，这里必须与预算口径（String.length）一致。
    expect(digest.length).toBeGreaterThan([...digest].length);
    expect(digestSizeText(digest)).toBe(`本次摘要 ${digest.length} 字符`);
  });

  it('emoji 摘要到上限时同样给出截断提示', () => {
    const digest = '😀'.repeat(MAX_DIGEST_CHARS / 2);
    expect(digest.length).toBe(MAX_DIGEST_CHARS);
    expect(digestSizeText(digest)).toBe(
      `本次摘要 ${MAX_DIGEST_CHARS} 字符（已到上限，部分条目未计入）`,
    );
  });

  it('未到上限时不加提示', () => {
    expect(digestSizeText('x'.repeat(MAX_DIGEST_CHARS - 1))).toBe(
      `本次摘要 ${MAX_DIGEST_CHARS - 1} 字符`,
    );
  });

  it('到达上限时提示已截断', () => {
    expect(digestSizeText('x'.repeat(MAX_DIGEST_CHARS))).toBe(
      `本次摘要 ${MAX_DIGEST_CHARS} 字符（已到上限，部分条目未计入）`,
    );
  });
});
