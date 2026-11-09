/**
 * `markdown.ts` 的表驱动单测。
 *
 * 测试环境是 node（无 DOM），所以全部断言都打在**解析结果**上，不碰渲染：
 * 渲染层 `MarkdownView.tsx` 只做结构 → 元素映射，逻辑风险都在这里。
 *
 * 用例覆盖三类风险：
 * 1. 方言边界（哪些语法认、哪些必须原样显示）；
 * 2. 安全性（协议白名单、HTML 不成为结构）；
 * 3. 健壮性（CRLF、空正文、500 行、重复调用、非字符串输入）。
 */
import { describe, expect, it } from 'vitest';
import { isSafeLinkUrl, parseInline, parseMarkdown } from './markdown';
import type { MarkdownBlock } from './markdown';

const text = (value: string) => ({ type: 'text' as const, text: value });
const strong = (value: string) => ({ type: 'strong' as const, text: value });
const code = (value: string) => ({ type: 'code' as const, text: value });
const link = (label: string, url: string) => ({ type: 'link' as const, label, url });

/** 一节典型的自动汇总正文：导出用的就是这个形态，预览必须能整段吃下。 */
const TYPICAL_SECTION = [
  '### 本周完成',
  '- 完成 **3** 项里程碑，详见 `v0.2` 发布记录',
  '- 与 [周报说明](https://example.com/doc) 对齐口径',
  '',
  '#### 风险',
  '接口联调依赖第三方，下周才能确认。',
  '已准备降级方案。',
].join('\n');

describe('parseMarkdown：端到端', () => {
  it('典型的自动汇总正文解析为 标题 / 列表 / 标题 / 段落', () => {
    expect(parseMarkdown(TYPICAL_SECTION)).toEqual([
      { type: 'heading', level: 3, spans: [text('本周完成')] },
      {
        type: 'list',
        items: [
          {
            spans: [
              text('完成 '),
              strong('3'),
              text(' 项里程碑，详见 '),
              code('v0.2'),
              text(' 发布记录'),
            ],
          },
          {
            spans: [text('与 '), link('周报说明', 'https://example.com/doc'), text(' 对齐口径')],
          },
        ],
      },
      { type: 'heading', level: 4, spans: [text('风险')] },
      {
        type: 'paragraph',
        spans: [text('接口联调依赖第三方，下周才能确认。\n已准备降级方案。')],
      },
    ]);
  });
});

describe('parseMarkdown：标题', () => {
  const HEADING_CASES: [string, 3 | 4, string][] = [
    ['### 本周概览', 3, '本周概览'],
    ['#### 下周计划', 4, '下周计划'],
    ['### 尾部空格保留 ', 3, '尾部空格保留 '],
  ];

  it.each(HEADING_CASES)('「%s」解析为 %i 级标题', (line, level, body) => {
    expect(parseMarkdown(line)).toEqual([{ type: 'heading', level, spans: [text(body)] }]);
  });

  it('「### 」只有前缀没有标题文字时仍是标题，spans 为空（不产生空 text span）', () => {
    expect(parseMarkdown('### ')).toEqual([{ type: 'heading', level: 3, spans: [] }]);
  });

  // 只认 `### ` / `#### `：其它级数、以及「# 号后没有空格」都必须原样显示，不能当成标题。
  const LITERAL_HEADING_LINES = [
    '# 一级标题',
    '## 二级标题',
    '##### 五级标题',
    '###### 六级标题',
    '###没有空格',
    '####没有空格',
    '###',
    '####',
  ];

  it.each(LITERAL_HEADING_LINES)('「%s」不算标题，按段落文字保留', (line) => {
    expect(parseMarkdown(line)).toEqual([{ type: 'paragraph', spans: [text(line)] }]);
  });

  it('标题内部仍支持行内标记', () => {
    expect(parseMarkdown('### 本周 **重点**')).toEqual([
      { type: 'heading', level: 3, spans: [text('本周 '), strong('重点')] },
    ]);
  });
});

describe('parseMarkdown：列表', () => {
  it('单个列表项成一个列表块', () => {
    expect(parseMarkdown('- 完成：3 项')).toEqual([
      { type: 'list', items: [{ spans: [text('完成：3 项')] }] },
    ]);
  });

  it('连续的 - 行合成一个列表块，而不是每行一个', () => {
    const blocks = parseMarkdown('- 甲\n- 乙\n- 丙');
    expect(blocks).toHaveLength(1);
    const block = blocks[0];
    expect(block.type).toBe('list');
    if (block.type !== 'list') throw new Error('应为列表块');
    expect(block.items.map((item) => item.spans)).toEqual([
      [text('甲')],
      [text('乙')],
      [text('丙')],
    ]);
    // 任务列表不在本批方言内：`checked` 字段从不写入。
    expect(block.items.some((item) => 'checked' in item)).toBe(false);
  });

  it('列表后紧跟非列表行时另起段落', () => {
    expect(parseMarkdown('- 甲\n- 乙\n补充说明')).toEqual([
      { type: 'list', items: [{ spans: [text('甲')] }, { spans: [text('乙')] }] },
      { type: 'paragraph', spans: [text('补充说明')] },
    ]);
  });

  it('列表项内部支持行内标记', () => {
    expect(parseMarkdown('- 完成 `v0.2` 发布')).toEqual([
      { type: 'list', items: [{ spans: [text('完成 '), code('v0.2'), text(' 发布')] }] },
    ]);
  });

  it('「-」后没有空格时不是列表项', () => {
    expect(parseMarkdown('-不是列表\n-')).toEqual([
      { type: 'paragraph', spans: [text('-不是列表\n-')] },
    ]);
  });
});

describe('parseMarkdown：段落与空行', () => {
  it('空行分隔两个段落', () => {
    expect(parseMarkdown('第一段\n\n第二段')).toEqual([
      { type: 'paragraph', spans: [text('第一段')] },
      { type: 'paragraph', spans: [text('第二段')] },
    ]);
  });

  it('连续非空行合成一个段落，行内换行原样保留', () => {
    const blocks = parseMarkdown('第一行\n第二行\n第三行');
    expect(blocks).toHaveLength(1);
    expect(blocks[0]).toEqual({ type: 'paragraph', spans: [text('第一行\n第二行\n第三行')] });
  });

  it('首尾空行忽略，连续空行不产生空块', () => {
    expect(parseMarkdown('\n\n### 标题\n\n\n- 甲\n\n')).toEqual([
      { type: 'heading', level: 3, spans: [text('标题')] },
      { type: 'list', items: [{ spans: [text('甲')] }] },
    ]);
  });

  it('空正文与纯空白正文都返回空数组', () => {
    expect(parseMarkdown('')).toEqual([]);
    expect(parseMarkdown('   \n\n \t \n')).toEqual([]);
  });
});

describe('parseMarkdown：换行归一化', () => {
  it('CRLF 按行切分，正文里不残留 \\r', () => {
    expect(parseMarkdown('### 标题\r\n- 甲\r\n- 乙\r\n\r\n正文')).toEqual([
      { type: 'heading', level: 3, spans: [text('标题')] },
      { type: 'list', items: [{ spans: [text('甲')] }, { spans: [text('乙')] }] },
      { type: 'paragraph', spans: [text('正文')] },
    ]);
  });

  it('孤立的 \\r 也当换行', () => {
    expect(parseMarkdown('甲\r乙')).toEqual([{ type: 'paragraph', spans: [text('甲\n乙')] }]);
  });
});

describe('parseInline：粗体与行内代码', () => {
  it('单个粗体 / 单个代码各成一个 span', () => {
    expect(parseInline('**粗**')).toEqual([strong('粗')]);
    expect(parseInline('`码`')).toEqual([code('码')]);
  });

  it('混排时文本与标记按出现顺序排列', () => {
    expect(parseInline('前 **粗** 中 `码` 后')).toEqual([
      text('前 '),
      strong('粗'),
      text(' 中 '),
      code('码'),
      text(' 后'),
    ]);
  });

  it('粗体内部不递归解析：嵌套标记按字面显示（方言不做嵌套）', () => {
    expect(parseInline('**a `b` c**')).toEqual([strong('a `b` c')]);
  });
});

describe('parseInline：不成立的标记按字面保留', () => {
  const LITERAL_MARKUP = [
    '**未闭合',
    '`未闭合',
    '[文字](https://example.com',
    '[](https://example.com)',
    '[文字]()',
    '****',
    '``',
    '*斜体*',
    '只有前 ** 没有后',
  ];

  it.each(LITERAL_MARKUP)('「%s」整串退化为字面文本', (input) => {
    expect(parseInline(input)).toEqual([text(input)]);
  });
});

describe('parseInline：链接白名单', () => {
  it('https 链接切成 link span，前后文本保留', () => {
    expect(parseInline('见 [周报说明](https://example.com/a?b=1) 一节')).toEqual([
      text('见 '),
      link('周报说明', 'https://example.com/a?b=1'),
      text(' 一节'),
    ]);
  });

  it('mailto 链接同样放行', () => {
    expect(parseInline('[写信](mailto:a@b.com)')).toEqual([link('写信', 'mailto:a@b.com')]);
  });

  it('协议大小写不敏感，URL 两端空白被 trim', () => {
    expect(parseInline('[x](HTTPS://Example.com)')).toEqual([link('x', 'HTTPS://Example.com')]);
    expect(parseInline('[x](  https://example.com  )')).toEqual([link('x', 'https://example.com')]);
  });

  // 危险协议必须在解析期就降级：下游拿不到可执行的 URL，也就无从「顺手」渲染成 href。
  const UNSAFE_URLS = [
    'javascript:alert(1)',
    'data:text/html;base64,PHN2Zz4=',
    'file:///etc/passwd',
    'vbscript:msgbox',
    'ftp://example.com/a',
  ];

  it.each(UNSAFE_URLS)('「%s」不在白名单，整串退化为字面文本', (url) => {
    const raw = `[点我](${url})`;
    expect(parseInline(raw)).toEqual([text(raw)]);
  });

  it.each(['https://example.com', 'http://example.com/a', 'mailto:a@b.com', 'HTTPS://X.Y'])(
    'isSafeLinkUrl 放行「%s」',
    (url) => {
      expect(isSafeLinkUrl(url)).toBe(true);
    },
  );

  it.each([...UNSAFE_URLS, '', 'example.com', '//example.com', 'javascript:alert(1)'])(
    'isSafeLinkUrl 拒绝「%s」',
    (url) => {
      expect(isSafeLinkUrl(url)).toBe(false);
    },
  );
});

describe('parseMarkdown：健壮性', () => {
  it('500 行正文可解析且不抛异常，块种类合法', () => {
    const lines: string[] = [];
    for (let index = 0; index < 500; index += 1) {
      const mod = index % 4;
      if (mod === 0) lines.push(`### 小节 ${index}`);
      else if (mod === 1) lines.push(`- 条目 ${index}`);
      else if (mod === 2) lines.push(`补充说明 ${index}，含 **重点** 与 \`code\``);
      else lines.push('');
    }
    const body = lines.join('\n');

    let blocks: MarkdownBlock[] = [];
    expect(() => {
      blocks = parseMarkdown(body);
    }).not.toThrow();
    expect(blocks.length).toBeGreaterThan(0);
    for (const block of blocks) {
      expect(['heading', 'list', 'paragraph']).toContain(block.type);
    }
  });

  it('病态输入（大量孤立标记）也不抛异常且不丢字符', () => {
    const body = `${'['.repeat(300)}${'`'.repeat(300)}${'*'.repeat(300)}`;
    expect(() => parseMarkdown(body)).not.toThrow();
    // 没有一条成立，所以整串应该原样留在一个 text span 里。
    expect(parseMarkdown(body)).toEqual([{ type: 'paragraph', spans: [text(body)] }]);
  });

  it('重复解析同一份正文结果相同，且不改动入参', () => {
    const body = '### 标题\n- 甲 **粗**\n- 乙 [站](https://example.com)\n\n正文段落';
    const snapshot = body;
    const first = parseMarkdown(body);
    const second = parseMarkdown(body);
    expect(second).toEqual(first);
    expect(body).toBe(snapshot);
    // 每次都是新建结构，渲染层 `useMemo` 才能按字符串正确判断「没变」。
    expect(second).not.toBe(first);
  });

  it('非字符串输入退化为空结果，不抛异常', () => {
    expect(parseMarkdown(null as unknown as string)).toEqual([]);
    expect(parseMarkdown(undefined as unknown as string)).toEqual([]);
    expect(parseMarkdown(42 as unknown as string)).toEqual([]);
    expect(parseInline(null as unknown as string)).toEqual([]);
  });

  it('HTML 片段保持字面文本，绝不成为结构', () => {
    const body = '<img src=x onerror=alert(1)>\n<script>alert(1)</script>';
    expect(parseMarkdown(body)).toEqual([{ type: 'paragraph', spans: [text(body)] }]);
  });
});
