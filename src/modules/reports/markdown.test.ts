/**
 * `markdown.ts`（Obsidian 对齐的解析器）的表驱动单测。
 *
 * 测试环境是 node（无 DOM），所以全部断言都打在**解析结果**上，不碰渲染：渲染层只做
 * 结构 → 元素映射，风险都在这里。
 *
 * 用例按「一个语法一族」分组，覆盖四类风险：
 * 1. 对齐度：Obsidian 阅读视图认的语法，这里都要认（标题/列表/表格/代码/引用/callout/
 *    wikilink/embed/tag/frontmatter/公式/高亮/注释）；
 * 2. 安全性：HTML 只当文字、危险 URL 一律 `safe:false`、AST 里永不出现 `html` 块；
 * 3. 边界：不成立的标记退化成字面文本（一个字符都不丢），未闭合的注释/frontmatter 不吞内容；
 * 4. 健壮性：200k 正文、病态输入、重复调用、非字符串入参，以及**计时**的复杂度回归
 *    （`$$` 病态输入必须在预算内解析完，否则说明块级规则没进段落终止链）。
 */
import { describe, expect, it } from 'vitest';
import { CALLOUT_ALIASES, CALLOUT_KINDS, CALLOUT_TITLES, parseMarkdown } from './markdown';
import type { MarkdownBlock, MarkdownListItem, MarkdownSpan } from './markdown';

/* -------------------------------------------------------------------------- */
/* 断言用的小构造器：让期望值读起来就是 AST 本身                                */
/* -------------------------------------------------------------------------- */

const t = (text: string) => ({ type: 'text' as const, text });
const strong = (...spans: MarkdownSpan[]) => ({ type: 'strong' as const, spans });
const em = (...spans: MarkdownSpan[]) => ({ type: 'em' as const, spans });
const del = (...spans: MarkdownSpan[]) => ({ type: 'del' as const, spans });
const mark = (...spans: MarkdownSpan[]) => ({ type: 'highlight' as const, spans });
const code = (text: string) => ({ type: 'code' as const, text });
const link = (href: string, spans: MarkdownSpan[], safe = true) => ({ type: 'link' as const, href, safe, spans });
const unsafeLink = (href: string, spans: MarkdownSpan[]) => link(href, spans, false);
const wiki = (target: string, alias: string | null = null, anchor: string | null = null) => ({
  type: 'wikilink' as const,
  target,
  alias,
  anchor,
});
const embed = (
  target: string,
  alias: string | null = null,
  width: number | null = null,
  height: number | null = null,
  anchor: string | null = null,
) => ({ type: 'embed' as const, target, alias, anchor, width, height });
const tag = (name: string) => ({ type: 'tag' as const, tag: name });
const inlineMath = (tex: string) => ({ type: 'math' as const, tex, display: false as const });
const image = (src: string, alt: string, safe = true) => ({ type: 'image' as const, src, alt, safe });
const softBreak = () => ({ type: 'break' as const, hard: false });
const hardBreak = () => ({ type: 'break' as const, hard: true });

const p = (...spans: MarkdownSpan[]) => ({ type: 'paragraph' as const, spans });
const h = (level: 1 | 2 | 3 | 4 | 5 | 6, ...spans: MarkdownSpan[]) => ({
  type: 'heading' as const,
  level,
  spans,
});
const item = (spans: MarkdownSpan[], extra: Partial<MarkdownListItem> = {}): MarkdownListItem => ({
  spans,
  checked: null,
  ...extra,
});
const ul = (items: MarkdownListItem[]) => ({ type: 'list' as const, ordered: false, start: 1, items });
const ol = (start: number, items: MarkdownListItem[]) => ({ type: 'list' as const, ordered: true, start, items });

/** 只解析出一段纯文字时的便捷断言。 */
const onlyText = (body: string): MarkdownBlock[] => [p(t(body))];

/* -------------------------------------------------------------------------- */
/* 块级：标题 / 分隔线 / 段落                                                   */
/* -------------------------------------------------------------------------- */

describe('块级：标题', () => {
  const HEADINGS: [string, 1 | 2 | 3 | 4 | 5 | 6, string][] = [
    ['# 一级', 1, '一级'],
    ['## 二级', 2, '二级'],
    ['### 三级', 3, '三级'],
    ['#### 四级', 4, '四级'],
    ['##### 五级', 5, '五级'],
    ['###### 六级', 6, '六级'],
  ];

  it.each(HEADINGS)('「%s」解析为 %i 级标题', (line, level, body) => {
    expect(parseMarkdown(line)).toEqual([h(level, t(body))]);
  });

  it('「###」后面没有空格不是标题（必须 `#` + 空格）', () => {
    expect(parseMarkdown('###没有空格')).toEqual(onlyText('###没有空格'));
  });

  it('七个 # 不是标题', () => {
    expect(parseMarkdown('####### 七级')).toEqual(onlyText('####### 七级'));
  });

  it('只有前缀没有文字时仍是标题，spans 为空数组', () => {
    expect(parseMarkdown('## ')).toEqual([h(2)]);
  });

  it('标题内部支持行内标记（粗体 / 标签 / embed）', () => {
    expect(parseMarkdown('### 本周 **重点** #tag')).toEqual([h(3, t('本周 '), strong(t('重点')), t(' '), tag('tag'))]);
  });

  it('setext 写法（`===` / `---` 下划线）也是标题', () => {
    expect(parseMarkdown('标题\n===\n\n副标题\n---')).toEqual([h(1, t('标题')), h(2, t('副标题'))]);
  });

  it('标题里保留尾部空格（正文内容不动）', () => {
    expect(parseMarkdown('### 尾部空格保留 ')).toEqual([h(3, t('尾部空格保留'))]);
  });
});

describe('块级：分隔线', () => {
  it.each(['---', '***', '___', '- - -'])('「%s」解析为 hr', (line) => {
    expect(parseMarkdown(`前\n\n${line}\n\n后`)).toEqual([p(t('前')), { type: 'hr' }, p(t('后'))]);
  });

  it('文首的 `---` 后没有闭合 `---` 时不吞正文：hr + 段落', () => {
    expect(parseMarkdown('---\ntitle: x')).toEqual([{ type: 'hr' }, p(t('title: x'))]);
  });
});

describe('块级：段落与换行', () => {
  it('空行分隔两个段落', () => {
    expect(parseMarkdown('第一段\n\n第二段')).toEqual([p(t('第一段')), p(t('第二段'))]);
  });

  it('段内软换行变成 break{hard:false}', () => {
    expect(parseMarkdown('第一行\n第二行')).toEqual([p(t('第一行'), softBreak(), t('第二行'))]);
  });

  it('行尾两个空格是硬换行 break{hard:true}', () => {
    expect(parseMarkdown('甲  \n乙')).toEqual([p(t('甲'), hardBreak(), t('乙'))]);
  });

  it('行尾反斜杠也是硬换行', () => {
    expect(parseMarkdown('甲\\\n乙')).toEqual([p(t('甲'), hardBreak(), t('乙'))]);
  });

  it('首尾空行与连续空行都忽略，不产生空块', () => {
    expect(parseMarkdown('\n\n## 标题\n\n\n- 甲\n\n')).toEqual([h(2, t('标题')), ul([item([t('甲')])])]);
  });

  it('空正文、纯空白正文、非字符串入参都返回空数组', () => {
    expect(parseMarkdown('')).toEqual([]);
    expect(parseMarkdown('   \n\n \t \n')).toEqual([]);
    expect(parseMarkdown(null as unknown as string)).toEqual([]);
    expect(parseMarkdown(undefined as unknown as string)).toEqual([]);
    expect(parseMarkdown(42 as unknown as string)).toEqual([]);
  });

  it('CRLF 与孤立 \\r 都按换行处理，正文里不残留 \\r', () => {
    expect(parseMarkdown('# 标题\r\n- 甲\r\n\r\n正文\r尾')).toEqual([
      h(1, t('标题')),
      ul([item([t('甲')])]),
      p(t('正文'), softBreak(), t('尾')),
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 行内：强调 / 删除线 / 高亮 / 代码                                            */
/* -------------------------------------------------------------------------- */

describe('行内：强调、删除线、高亮、代码', () => {
  it('粗体、斜体、粗斜体、删除线、高亮、行内代码各成一个 span', () => {
    expect(parseMarkdown('**粗** *斜* ~~删~~ ==高亮== `码`')).toEqual([
      p(
        strong(t('粗')),
        t(' '),
        em(t('斜')),
        t(' '),
        del(t('删')),
        t(' '),
        mark(t('高亮')),
        t(' '),
        code('码'),
      ),
    ]);
  });

  it('`***x***` 按 CommonMark 嵌套为 em > strong', () => {
    expect(parseMarkdown('***粗斜***')).toEqual([p(em(strong(t('粗斜'))))]);
  });

  it('标记可以互相嵌套（粗体里放代码、高亮里放粗体）', () => {
    expect(parseMarkdown('**a `b` c**')).toEqual([p(strong(t('a '), code('b'), t(' c')))]);
    expect(parseMarkdown('==**重点**==')).toEqual([p(mark(strong(t('重点'))))]);
  });

  it('`==` 两侧紧贴非空白字符，`a == b == c` 保持字面（避免误判比较符）', () => {
    expect(parseMarkdown('a == b == c')).toEqual(onlyText('a == b == c'));
  });

  it('未闭合的标记退化成字面文本，字符一个不丢', () => {
    expect(parseMarkdown('**未闭合 `未闭合 ==未闭合 ~~未闭合')).toEqual(onlyText('**未闭合 `未闭合 ==未闭合 ~~未闭合'));
  });

  it('`****` / `====` 这类空标记不是语法（行内保持字面）', () => {
    expect(parseMarkdown('a **** b')).toEqual(onlyText('a **** b'));
    expect(parseMarkdown('a ==== b')).toEqual(onlyText('a ==== b'));
  });

  it('反斜杠转义让标记变文字', () => {
    expect(parseMarkdown('\\*\\*不是粗体\\*\\*')).toEqual(onlyText('**不是粗体**'));
  });
});

/* -------------------------------------------------------------------------- */
/* 行内：链接 / 图片 / 裸链                                                     */
/* -------------------------------------------------------------------------- */

describe('行内：链接与图片', () => {
  it('https 与 mailto 链接 safe:true，标签内容仍参与行内解析', () => {
    expect(parseMarkdown('[说明](https://example.com/a?b=1) [写信](mailto:a@b.com)')).toEqual([
      p(link('https://example.com/a?b=1', [t('说明')]), t(' '), link('mailto:a@b.com', [t('写信')])),
    ]);
    expect(parseMarkdown('[**重点**](https://e.com)')).toEqual([p(link('https://e.com', [strong(t('重点'))]))]);
  });

  // 危险协议 / 相对路径 / 页内锚点：href 保留、safe:false，渲染层据此降级为纯文本。
  const UNSAFE: [string, string][] = [
    ['javascript:alert(1)', 'javascript:alert(1)'],
    ['data:text/html;base64,PHN2Zz4=', 'data:text/html;base64,PHN2Zz4='],
    ['file:///etc/passwd', 'file:///etc/passwd'],
    ['vbscript:msgbox', 'vbscript:msgbox'],
    ['./rel/path.md', './rel/path.md'],
    ['../up.md', '../up.md'],
    ['#anchor', '#anchor'],
  ];

  it.each(UNSAFE)('「%s」的链接 safe:false', (url, href) => {
    expect(parseMarkdown(`[点我](${url})`)).toEqual([p(unsafeLink(href, [t('点我')]))]);
  });

  it('裸链自动变成链接（linkify）', () => {
    expect(parseMarkdown('见 https://example.com/a 一节')).toEqual([
      p(t('见 '), link('https://example.com/a', [t('https://example.com/a')]), t(' 一节')),
    ]);
  });

  it('尖括号自动链接同样成立', () => {
    expect(parseMarkdown('<https://x.y>')).toEqual([p(link('https://x.y', [t('https://x.y')]))]);
  });

  it('图片带 alt 与 safe 标记', () => {
    expect(parseMarkdown('![架构图](https://e.com/a.png)')).toEqual([
      p(image('https://e.com/a.png', '架构图')),
    ]);
    expect(parseMarkdown('![x](javascript:alert(1))')).toEqual([
      p(image('javascript:alert(1)', 'x', false)),
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 列表                                                                        */
/* -------------------------------------------------------------------------- */

describe('列表：无序 / 有序 / 嵌套 / 松散', () => {
  it('连续的 `- ` 行合成一个列表块', () => {
    expect(parseMarkdown('- 甲\n- 乙\n- 丙')).toEqual([ul([item([t('甲')]), item([t('乙')]), item([t('丙')])])]);
  });

  it('`*` 与 `+` 也是无序列表标记（换标记字符会另起一个列表）', () => {
    expect(parseMarkdown('* 甲\n* 乙')).toEqual([ul([item([t('甲')]), item([t('乙')])])]);
    expect(parseMarkdown('+ 甲\n+ 乙')).toEqual([ul([item([t('甲')]), item([t('乙')])])]);
    expect(parseMarkdown('* 甲\n+ 乙')).toEqual([ul([item([t('甲')])]), ul([item([t('乙')])])]);
  });

  it('有序列表保留起始序号 start', () => {
    expect(parseMarkdown('3. 甲\n4. 乙')).toEqual([ol(3, [item([t('甲')]), item([t('乙')])])]);
  });

  it('嵌套列表进 items[].blocks', () => {
    expect(parseMarkdown('- 甲\n  - 子\n- 乙')).toEqual([
      ul([item([t('甲')], { blocks: [ul([item([t('子')])])] }), item([t('乙')])]),
    ]);
  });

  it('松散列表里第二段进 items[].blocks', () => {
    expect(parseMarkdown('- 甲\n\n  补充\n\n- 乙')).toEqual([
      ul([item([t('甲')], { blocks: [p(t('补充'))] }), item([t('乙')])]),
    ]);
  });

  it('列表项支持行内标记；紧跟的非空行是懒续行，空行才另起段落', () => {
    expect(parseMarkdown('- 完成 `v0.2` 发布\n说明')).toEqual([
      ul([item([t('完成 '), code('v0.2'), t(' 发布'), softBreak(), t('说明')])]),
    ]);
    expect(parseMarkdown('- 完成 `v0.2` 发布\n\n说明')).toEqual([
      ul([item([t('完成 '), code('v0.2'), t(' 发布')])]),
      p(t('说明')),
    ]);
  });

  it('`-` 后没有空格不是列表', () => {
    expect(parseMarkdown('-不是列表')).toEqual(onlyText('-不是列表'));
    expect(parseMarkdown('正文\n-不是列表')).toEqual([p(t('正文'), softBreak(), t('-不是列表'))]);
  });

  it('空列表项得到 spans: []', () => {
    expect(parseMarkdown('- \n- 乙')).toEqual([ul([item([]), item([t('乙')])])]);
  });
});

describe('列表：GFM 任务列表', () => {
  const TASKS: [string, boolean][] = [
    ['- [ ] 未完成', false],
    ['- [x] 已完成', true],
    ['- [X] 大写也算完成', true],
  ];

  it.each(TASKS)('「%s」→ checked:%s 且标记不出现在 spans 里', (line, checked) => {
    expect(parseMarkdown(line)).toEqual([ul([item([t(line.slice(6))], { checked })])]);
  });

  it('任务与非任务混排：非任务是 checked:null', () => {
    expect(parseMarkdown('- [ ] 甲\n- 乙')).toEqual([ul([item([t('甲')], { checked: false }), item([t('乙')])])]);
  });

  it('任务列表项里的行内标记照常解析', () => {
    expect(parseMarkdown('- [x] **完成** `v1`')).toEqual([
      ul([item([strong(t('完成')), t(' '), code('v1')], { checked: true })]),
    ]);
  });

  it('任务标记只在项首生效，正文中间的 `[ ]` 保持字面', () => {
    expect(parseMarkdown('- 看 [ ] 这个')).toEqual([ul([item([t('看 [ ] 这个')])])]);
  });

  it('嵌套任务列表的 sub-items 也带 checked', () => {
    expect(parseMarkdown('- [x] 甲\n  - [ ] 子')).toEqual([
      ul([item([t('甲')], { checked: true, blocks: [ul([item([t('子')], { checked: false })])] })]),
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 表格                                                                        */
/* -------------------------------------------------------------------------- */

describe('表格（GFM）', () => {
  it('三向对齐写进 align，表头与数据行分开', () => {
    expect(parseMarkdown('| 左 | 中 | 右 |\n|:--|:-:|--:|\n| 1 | 2 | 3 |')).toEqual([
      {
        type: 'table',
        align: ['left', 'center', 'right'],
        header: [[t('左')], [t('中')], [t('右')]],
        rows: [[[t('1')], [t('2')], [t('3')]]],
      },
    ]);
  });

  it('没写对齐标记时 align 全是 null', () => {
    expect(parseMarkdown('| a | b |\n| - | - |\n| 1 | 2 |')).toEqual([
      {
        type: 'table',
        align: [null, null],
        header: [[t('a')], [t('b')]],
        rows: [[[t('1')], [t('2')]]],
      },
    ]);
  });

  it('单元格内的行内标记照常解析，多行数据按行分组', () => {
    expect(parseMarkdown('| a |\n| - |\n| **粗** |\n| `码` |')).toEqual([
      {
        type: 'table',
        align: [null],
        header: [[t('a')]],
        rows: [[[strong(t('粗'))]], [[code('码')]]],
      },
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 代码块                                                                      */
/* -------------------------------------------------------------------------- */

describe('代码块', () => {
  it('围栏代码保留原文，lang 取首个词并小写', () => {
    expect(parseMarkdown('```JS extra\nlet a = 1;\n```')).toEqual([
      { type: 'code', lang: 'js', code: 'let a = 1;\n', mermaid: false },
    ]);
  });

  it('没有 info string 时 lang 为 null', () => {
    expect(parseMarkdown('```\nx\n```')).toEqual([{ type: 'code', lang: null, code: 'x\n', mermaid: false }]);
  });

  it('mermaid 单独标记，代码原文不动', () => {
    expect(parseMarkdown('```mermaid\ngraph TD;\n  A-->B;\n```')).toEqual([
      { type: 'code', lang: 'mermaid', code: 'graph TD;\n  A-->B;\n', mermaid: true },
    ]);
  });

  it('缩进 4 空格的代码块 lang 为 null', () => {
    expect(parseMarkdown('    const a = 1;')).toEqual([
      { type: 'code', lang: null, code: 'const a = 1;\n', mermaid: false },
    ]);
  });

  it('代码块里的 Markdown 标记不被解析', () => {
    expect(parseMarkdown('```\n**不是粗体** #不是标签\n```')).toEqual([
      { type: 'code', lang: null, code: '**不是粗体** #不是标签\n', mermaid: false },
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 引用与 callout                                                              */
/* -------------------------------------------------------------------------- */

describe('引用', () => {
  it('引用里的块按原结构保留', () => {
    expect(parseMarkdown('> ## 标题\n> 正文')).toEqual([
      { type: 'blockquote', blocks: [h(2, t('标题')), p(t('正文'))] },
    ]);
  });

  it('嵌套引用递归成 blockquote.blocks', () => {
    expect(parseMarkdown('> 甲\n> > 乙')).toEqual([
      { type: 'blockquote', blocks: [p(t('甲')), { type: 'blockquote', blocks: [p(t('乙'))] }] },
    ]);
  });

  it('空的 `>` 是一个空引用块', () => {
    expect(parseMarkdown('>')).toEqual([{ type: 'blockquote', blocks: [] }]);
  });
});

describe('callout：规范类型与默认标题', () => {
  it.each(CALLOUT_KINDS)('「%s」用默认中文标题', (kind) => {
    expect(parseMarkdown(`> [!${kind}]\n> 正文`)).toEqual([
      { type: 'callout', kind, title: CALLOUT_TITLES[kind], fold: null, blocks: [p(t('正文'))] },
    ]);
  });

  it('CALLOUT_KINDS 与 CALLOUT_TITLES 一一对应，且是 13 个规范类型', () => {
    expect([...CALLOUT_KINDS].sort()).toEqual(Object.keys(CALLOUT_TITLES).sort());
    expect(CALLOUT_KINDS).toHaveLength(13);
  });
});

describe('callout：别名归一', () => {
  it.each(Object.entries(CALLOUT_ALIASES))('「%s」归一为 %s', (alias, kind) => {
    expect(parseMarkdown(`> [!${alias}] 自定义\n> 正文`)).toEqual([
      { type: 'callout', kind, title: '自定义', fold: null, blocks: [p(t('正文'))] },
    ]);
  });

  it('别名大小写不敏感（`[!Summary]` → abstract）', () => {
    expect(parseMarkdown('> [!Summary]\n> x')).toEqual([
      { type: 'callout', kind: 'abstract', title: CALLOUT_TITLES.abstract, fold: null, blocks: [p(t('x'))] },
    ]);
  });
});

describe('callout：标题 / 折叠 / 嵌套 / 不成立', () => {
  it('自定义标题覆盖默认标题，marker 行不出现在正文里', () => {
    expect(parseMarkdown('> [!note] 我的标题\n> 第一段\n> 第二段')).toEqual([
      { type: 'callout', kind: 'note', title: '我的标题', fold: null, blocks: [p(t('第一段'), softBreak(), t('第二段'))] },
    ]);
  });

  it('`+` → fold:open，`-` → fold:closed，不写 → null', () => {
    const foldOf = (marker: string) => {
      const blocks = parseMarkdown(`> [!tip]${marker}\n> x`);
      const block = blocks[0];
      if (block.type !== 'callout') throw new Error('应为 callout');
      return block.fold;
    };
    expect(foldOf('+')).toBe('open');
    expect(foldOf('-')).toBe('closed');
    expect(foldOf('')).toBe(null);
  });

  it('只有 marker 没有正文时 blocks 为空', () => {
    expect(parseMarkdown('> [!info]')).toEqual([
      { type: 'callout', kind: 'info', title: CALLOUT_TITLES.info, fold: null, blocks: [] },
    ]);
  });

  it('callout 里的列表/代码等块照常解析', () => {
    expect(parseMarkdown('> [!warning] 注意\n> - 甲\n> - 乙')).toEqual([
      {
        type: 'callout',
        kind: 'warning',
        title: '注意',
        fold: null,
        blocks: [ul([item([t('甲')]), item([t('乙')])])],
      },
    ]);
  });

  it('嵌套 callout 递归成立', () => {
    expect(parseMarkdown('> [!note] 外层\n> > [!tip] 内层\n> > 深层正文')).toEqual([
      {
        type: 'callout',
        kind: 'note',
        title: '外层',
        fold: null,
        blocks: [
          {
            type: 'callout',
            kind: 'tip',
            title: '内层',
            fold: null,
            blocks: [p(t('深层正文'))],
          },
        ],
      },
    ]);
  });

  it('未知 kind：kind 原样保留，缺标题时标题也用 kind', () => {
    expect(parseMarkdown('> [!mything]\n> x')).toEqual([
      { type: 'callout', kind: 'mything', title: 'mything', fold: null, blocks: [p(t('x'))] },
    ]);
  });

  it('marker 不在引用首行时仍然是普通引用（不吞正文）', () => {
    expect(parseMarkdown('> 正文\n> [!note] 标题')).toEqual([
      { type: 'blockquote', blocks: [p(t('正文'), softBreak(), t('[!note] 标题'))] },
    ]);
  });

  it('畸形的 `[!kind` 不成立，按普通引用保留', () => {
    expect(parseMarkdown('> [!note\n> 正文')).toEqual([
      { type: 'blockquote', blocks: [p(t('[!note'), softBreak(), t('正文'))] },
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 注释                                                                        */
/* -------------------------------------------------------------------------- */

describe('注释 `%%…%%`：从 AST 里彻底消失', () => {
  it('行内注释被删掉，前后文字保留', () => {
    expect(parseMarkdown('前 %%隐藏%% 后')).toEqual([p(t('前  后'))]);
  });

  it('跨行注释块被删掉，上下两段各自成段（不粘连、不泄漏）', () => {
    expect(parseMarkdown('甲\n%%\n隐藏的文字\n还在注释里\n%%\n乙')).toEqual([p(t('甲')), p(t('乙'))]);
  });

  it('引用里的跨行注释同样删除', () => {
    expect(parseMarkdown('> 甲 %%注\n> 释%% 乙')).toEqual([
      { type: 'blockquote', blocks: [p(t('甲'), softBreak(), t('乙'))] },
    ]);
  });

  it('围栏代码里的 `%%` 是字面量，不删', () => {
    expect(parseMarkdown('```\n%%kept%%\n```')).toEqual([
      { type: 'code', lang: null, code: '%%kept%%\n', mermaid: false },
    ]);
  });

  it('行内代码里的 `%%` 是字面量，不删', () => {
    expect(parseMarkdown('a `%%kept%%` b')).toEqual([p(t('a '), code('%%kept%%'), t(' b'))]);
  });

  it('未闭合的 `%%` 吃到文末（Obsidian 同款）', () => {
    expect(parseMarkdown('甲\n%%从这里开始\n乙\n丙')).toEqual([p(t('甲'))]);
  });

  it('纯注释正文解析为空数组', () => {
    expect(parseMarkdown('%%只有注释%%')).toEqual([]);
  });
});

/* -------------------------------------------------------------------------- */
/* wikilink / embed / tag                                                      */
/* -------------------------------------------------------------------------- */

describe('wikilink', () => {
  const WIKILINKS: [string, MarkdownSpan][] = [
    ['[[目标]]', wiki('目标')],
    ['[[目标|别名]]', wiki('目标', '别名')],
    ['[[目标#标题]]', wiki('目标', null, '标题')],
    ['[[#标题]]', wiki('', null, '标题')],
    ['[[目标#^块引用]]', wiki('目标', null, '^块引用')],
    ['[[ 目标 | 别名 ]]', wiki('目标', '别名')],
  ];

  it.each(WIKILINKS)('「%s」解析为 wikilink span', (raw, span) => {
    expect(parseMarkdown(raw)).toEqual([p(span)]);
  });

  // 数字别名：`|300` 只有在 embed 上才是尺寸，wikilink 上必须原样当成显示文本。
  it('wikilink 的纯数字管道是别名，不是尺寸', () => {
    expect(parseMarkdown('[[Page|300]]')).toEqual([p(wiki('Page', '300'))]);
    expect(parseMarkdown('[[Page|640x480]]')).toEqual([p(wiki('Page', '640x480'))]);
  });

  it('同一种写法在 embed 上仍是尺寸（wikilink 与 embed 的分支互不牵连）', () => {
    expect(parseMarkdown('![[Page|300]]')).toEqual([p(embed('Page', null, 300, null))]);
    expect(parseMarkdown('![[Page|640x480]]')).toEqual([p(embed('Page', null, 640, 480))]);
  });

  it('wikilink 与文字/标签共处一行时顺序不乱', () => {
    expect(parseMarkdown('见 [[文档]] #标签')).toEqual([p(t('见 '), wiki('文档'), t(' '), tag('标签'))]);
  });

  it('未闭合的 `[[` 与空目标 `[[]]` 都不是语法', () => {
    expect(parseMarkdown('[[未闭合')).toEqual(onlyText('[[未闭合'));
    expect(parseMarkdown('[[]]')).toEqual(onlyText('[[]]'));
  });
});

describe('embed `![[…]]`', () => {
  const EMBEDS: [string, MarkdownSpan][] = [
    ['![[图片.png]]', embed('图片.png')],
    ['![[图片.png|300]]', embed('图片.png', null, 300)],
    ['![[图片.png|640x480]]', embed('图片.png', null, 640, 480)],
    ['![[文档|别名]]', embed('文档', '别名')],
    ['![[文档#标题]]', embed('文档', null, null, null, '标题')],
    ['![[文档#^块引用]]', embed('文档', null, null, null, '^块引用')],
    ['![[文档#标题|别名]]', embed('文档', '别名', null, null, '标题')],
  ];

  it.each(EMBEDS)('「%s」解析为 embed span', (raw, span) => {
    expect(parseMarkdown(raw)).toEqual([p(span)]);
  });

  // 锚点是 embed 契约的一部分（渲染层的 caption 要显示「嵌入的是哪个标题」）。
  it('embed 保留锚点，块锚点仍带 `^` 前缀', () => {
    expect(parseMarkdown('![[架构.png#本周]]')).toEqual([p(embed('架构.png', null, null, null, '本周'))]);
    expect(parseMarkdown('![[架构.png#^结论]]')).toEqual([p(embed('架构.png', null, null, null, '^结论'))]);
  });

  it('尺寸解析：只有宽 / 宽×高', () => {
    const first = parseMarkdown('![[a.png|640x480]]')[0];
    expect(first).toEqual(p(embed('a.png', null, 640, 480)));
    expect(parseMarkdown('![[a.png|480]]')).toEqual([p(embed('a.png', null, 480, null))]);
  });

  it('embed 可以出现在标题里', () => {
    expect(parseMarkdown('# ![[a.png]]')).toEqual([h(1, embed('a.png'))]);
  });
});

describe('标签', () => {
  const TAGS: [string, string][] = [
    ['#tag', 'tag'],
    ['#nested/tag', 'nested/tag'],
    ['#with-dash', 'with-dash'],
    ['#with_underscore', 'with_underscore'],
    ['#中文标签', '中文标签'],
    ['#tag-1', 'tag-1'],
  ];

  it.each(TAGS)('「%s」解析为 tag span', (raw, name) => {
    expect(parseMarkdown(`前 ${raw} 后`)).toEqual([p(t('前 '), tag(name), t(' 后'))]);
  });

  it('行首标签与括号里的标签都成立', () => {
    expect(parseMarkdown('#tag 开头')).toEqual([p(tag('tag'), t(' 开头'))]);
    expect(parseMarkdown('(#tag)')).toEqual([p(t('('), tag('tag'), t(')'))]);
  });

  it('`#` 标题不算标签（块级标题）', () => {
    expect(parseMarkdown('# 标题')).toEqual([h(1, t('标题'))]);
    expect(parseMarkdown('### 标题')).toEqual([h(3, t('标题'))]);
  });

  it('代码里的 `#` 不算标签', () => {
    expect(parseMarkdown('`#tag`')).toEqual([p(code('#tag'))]);
    expect(parseMarkdown('```\n#tag\n```')).toEqual([{ type: 'code', lang: null, code: '#tag\n', mermaid: false }]);
  });

  it('前面是词字符的 `#` 不算标签（`a#b` / ISBN#）', () => {
    expect(parseMarkdown('a#b')).toEqual(onlyText('a#b'));
  });

  it('纯数字或空的 `#` 不算标签', () => {
    expect(parseMarkdown('#123')).toEqual(onlyText('#123'));
    expect(parseMarkdown('孤立的 # 号')).toEqual(onlyText('孤立的 # 号'));
    expect(parseMarkdown('a # b')).toEqual(onlyText('a # b'));
  });

  it('写错的标题（`###没有空格`）整体保持字面，不产生标签', () => {
    expect(parseMarkdown('###没有空格')).toEqual(onlyText('###没有空格'));
  });

  it('标题内部的标签仍然成立', () => {
    expect(parseMarkdown('## 关于 #tag')).toEqual([h(2, t('关于 '), tag('tag'))]);
  });
});

/* -------------------------------------------------------------------------- */
/* frontmatter                                                                 */
/* -------------------------------------------------------------------------- */

describe('frontmatter（最小 YAML 读取器）', () => {
  it('scalar 字段按文档顺序保留', () => {
    expect(parseMarkdown('---\ntitle: 周报\nauthor: 张三\n---\n正文')).toEqual([
      {
        type: 'frontmatter',
        fields: [
          { key: 'title', value: '周报' },
          { key: 'author', value: '张三' },
        ],
      },
      p(t('正文')),
    ]);
  });

  it('`[a, b]` 数组连接成 `a, b`', () => {
    expect(parseMarkdown('---\ntags: [甲, 乙, 丙]\n---\n正文')).toEqual([
      { type: 'frontmatter', fields: [{ key: 'tags', value: '甲, 乙, 丙' }] },
      p(t('正文')),
    ]);
  });

  it('`- item` 块列表用 `, ` 连接', () => {
    expect(parseMarkdown('---\ntags:\n  - 甲\n  - 乙\n---\n正文')).toEqual([
      { type: 'frontmatter', fields: [{ key: 'tags', value: '甲, 乙' }] },
      p(t('正文')),
    ]);
  });

  it('值的引号被剥掉，空行与无 key 的行被忽略', () => {
    expect(parseMarkdown('---\na: "x y"\nb: \'z\'\n\n这一行没有冒号\n---\n正文')).toEqual([
      {
        type: 'frontmatter',
        fields: [
          { key: 'a', value: 'x y' },
          { key: 'b', value: 'z' },
        ],
      },
      p(t('正文')),
    ]);
  });

  it('未闭合的 `---` 块按普通正文处理（一点内容都不吞）', () => {
    expect(parseMarkdown('---\ntitle: x\n正文也没有闭合')).toEqual([
      { type: 'hr' },
      p(t('title: x'), softBreak(), t('正文也没有闭合')),
    ]);
  });

  it('只有 frontmatter 时没有多余块', () => {
    expect(parseMarkdown('---\nk: v\n---')).toEqual([{ type: 'frontmatter', fields: [{ key: 'k', value: 'v' }] }]);
  });

  // 空 frontmatter 曾经产出 `fields: []` 的块，预览里就多一个「属性 0」的空面板。
  it('空 frontmatter（`---` 紧接 `---`）不产出 frontmatter 块', () => {
    expect(parseMarkdown('---\n---')).toEqual([]);
    expect(parseMarkdown('---\n---\n正文')).toEqual([p(t('正文'))]);
    expect(parseMarkdown('---\n\n---\n正文')).toEqual([p(t('正文'))]);
  });

  it('frontmatter 里有内容但一行都读不出字段时同样不产出块', () => {
    expect(parseMarkdown('---\n这一行没有冒号\n---\n正文')).toEqual([p(t('正文'))]);
  });

  it('frontmatter 里的 `%%` 是数据，不是注释', () => {
    expect(parseMarkdown('---\nnote: 50%% 完成\n---\n正文')).toEqual([
      { type: 'frontmatter', fields: [{ key: 'note', value: '50%% 完成' }] },
      p(t('正文')),
    ]);
  });

  it('重复 key 取最后一次的值，位置保留在第一次出现处', () => {
    expect(parseMarkdown('---\nk: 1\nj: 2\nk: 3\n---\n正文')).toEqual([
      {
        type: 'frontmatter',
        fields: [
          { key: 'k', value: '3' },
          { key: 'j', value: '2' },
        ],
      },
      p(t('正文')),
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 数学                                                                        */
/* -------------------------------------------------------------------------- */

describe('数学公式', () => {
  it('行内 `$…$` 保留原始 TeX', () => {
    expect(parseMarkdown('质能方程 $E = mc^2$ 对吧')).toEqual([
      p(t('质能方程 '), inlineMath('E = mc^2'), t(' 对吧')),
    ]);
  });

  it('块级 `$$…$$` 支持单行与多行', () => {
    expect(parseMarkdown('$$E = mc^2$$')).toEqual([{ type: 'math', tex: 'E = mc^2', display: true }]);
    expect(parseMarkdown('$$\n\\int_0^1 x dx\n$$')).toEqual([
      { type: 'math', tex: '\\int_0^1 x dx', display: true },
    ]);
  });

  it('行内的 `$$…$$` 降级为 display:false（AST 的行内 math 没有块级语义）', () => {
    expect(parseMarkdown('前 $$x$$ 后')).toEqual([p(t('前 '), inlineMath('x'), t(' 后'))]);
  });

  // 块级公式是段落终止符（`obs_math_block` 注册时带 `alt: ['paragraph']`）：没有空行时也另起一块。
  // 少了这个标记，段落会一直吞到 `$$` 之后，这里就只能得到一个行内 display:false 的公式。
  it('紧贴段落的 `$$…$$`（没有空行）仍解析成块级公式 display:true', () => {
    expect(parseMarkdown('文本\n$$\nx^2\n$$')).toEqual([p(t('文本')), { type: 'math', tex: 'x^2', display: true }]);
  });

  // 公式最容易误伤普通文本，这里把边界钉住（标题用文字描述，不用原始串，避免 `$` 干扰用例名）。
  const LITERAL_DOLLARS: [string, string][] = [
    ['开头紧跟空白', '$ x$'],
    ['闭合前是空白', '$x $'],
    ['孤立的 $', '$'],
    ['货币金额', '$5 and $10'],
    ['空公式', '$$'],
    ['两个 $ 之间跨越普通文字', '价格 $100，预算 $200'],
  ];

  it.each(LITERAL_DOLLARS)('%s：不成公式，保持字面', (_label, raw) => {
    expect(parseMarkdown(raw)).toEqual(onlyText(raw));
  });

  it('未闭合的 `$$` 块当普通文字，不吞后续内容', () => {
    expect(parseMarkdown('$$\nx\n正文')).toEqual([p(t('$$'), softBreak(), t('x'), softBreak(), t('正文'))]);
  });

  it('`\\$` 转义后是普通美元符号', () => {
    expect(parseMarkdown('花了 \\$5 块')).toEqual([p(t('花了 $5 块'))]);
  });
});

/*
 * 容器里的块级公式：TeX 必须从**块状态自己的偏移**逐行取（`bMarks[i] + tShift[i]` … `eMarks[i]`），
 * 而不是从 `state.src` 一把切片。一把切会把容器标记留进 TeX：`> E = mc^2` 交给 KaTeX 会画成
 * 「大于号 + 变量」，**并且不报错**——这是最隐蔽的一类错误（报告里最常见的 Obsidian 写法恰好全中）。
 * 所以每个用例都断言 `tex` 逐字相等（等于也就排除 `>` 与缩进）。
 */
describe('数学公式：容器里的块级公式（TeX 里不该有 `>` 或缩进）', () => {
  it('引用里的块级公式：tex 不含 `>`', () => {
    expect(parseMarkdown('> $$\n> E = mc^2\n> $$')).toEqual([
      { type: 'blockquote', blocks: [{ type: 'math', tex: 'E = mc^2', display: true }] },
    ]);
  });

  it('callout 正文里的块级公式：tex 不含 `>`，marker 行照常摘掉', () => {
    expect(parseMarkdown('> [!note]\n> $$\n> E = mc^2\n> $$')).toEqual([
      {
        type: 'callout',
        kind: 'note',
        title: CALLOUT_TITLES.note,
        fold: null,
        blocks: [{ type: 'math', tex: 'E = mc^2', display: true }],
      },
    ]);
  });

  it('列表项里的块级公式：tex 不含缩进', () => {
    expect(parseMarkdown('- $$\n  a\n  b\n  $$')).toEqual([
      ul([item([], { blocks: [{ type: 'math', tex: 'a\nb', display: true }] })]),
    ]);
  });

  it('嵌套列表项里的块级公式：每一层缩进都不进 TeX', () => {
    expect(parseMarkdown('- 甲\n  - $$\n    a\n    b\n    $$')).toEqual([
      ul([
        item([t('甲')], {
          blocks: [ul([item([], { blocks: [{ type: 'math', tex: 'a\nb', display: true }] })])],
        }),
      ]),
    ]);
  });

  it('嵌套引用里的块级公式同样只剩表达式', () => {
    expect(parseMarkdown('> > $$\n> > y\n> > $$')).toEqual([
      { type: 'blockquote', blocks: [{ type: 'blockquote', blocks: [{ type: 'math', tex: 'y', display: true }] }] },
    ]);
  });

  // 对照组：没有容器时行为不变（上面的用例证明的是「去掉装饰」，不是「改了切法」）。
  it('顶层 `$$…$$` 是同一套逐行取法的对照组', () => {
    expect(parseMarkdown('$$\nx\n$$')).toEqual([{ type: 'math', tex: 'x', display: true }]);
    expect(parseMarkdown('$$\nE = mc^2\n$$')).toEqual([{ type: 'math', tex: 'E = mc^2', display: true }]);
    expect(parseMarkdown('$$E = mc^2$$')).toEqual([{ type: 'math', tex: 'E = mc^2', display: true }]);
  });

  it('引用里公式体跨软换行（懒续行）也不带 `>`', () => {
    expect(parseMarkdown('> $$\n> a\nb\n> $$')).toEqual([
      { type: 'blockquote', blocks: [{ type: 'math', tex: 'a\nb', display: true }] },
    ]);
  });
});

/*
 * 块级公式是**叶子块终止符**（`alt: ['paragraph', 'blockquote', 'list', 'reference']`，与 markdown-it
 * 15 的 fence / hr / heading / html_block 同一条链）。链里缺 `blockquote` / `list` 时，引用与列表会把
 * 后面的 `$$…$$` 当成**懒续行**吸进上一个段落（公式退化成 display:false 的行内公式），而同一位置的
 * 围栏代码 / 标题 / 分隔线都会另起一块——同一个「块级语法打断了段落」在这里必须同款成立。
 * 下面 5 条里，前两条是「探针」：先证明围栏代码在同位置确实跳出容器（上游口径），再钉住公式本身。
 */
describe('数学公式：块级公式打断容器里的懒续行', () => {
  // 探针：围栏代码在同位置确实另起一块（对照组，证明「打断」这件事是上游口径）。
  it('对照：引用后的围栏代码会跳出引用（上游口径）', () => {
    expect(parseMarkdown('> 文本\n```\nx\n```')).toEqual([
      { type: 'blockquote', blocks: [p(t('文本'))] },
      { type: 'code', lang: null, code: 'x\n', mermaid: false },
    ]);
  });

  it('引用后的 `$$x$$` 跳出引用：引用里是段落，外面是块级公式', () => {
    expect(parseMarkdown('> 文本\n$$x$$')).toEqual([
      { type: 'blockquote', blocks: [p(t('文本'))] },
      { type: 'math', tex: 'x', display: true },
    ]);
  });

  it('多行写法同样跳出引用（不是只在单行 `$$x$$` 上成立）', () => {
    expect(parseMarkdown('> 文本\n$$\nx\n$$')).toEqual([
      { type: 'blockquote', blocks: [p(t('文本'))] },
      { type: 'math', tex: 'x', display: true },
    ]);
  });

  it('列表项的懒续行同样被块级公式打断（与围栏代码一致）', () => {
    expect(parseMarkdown('- 文本\n$$x$$')).toEqual([
      ul([item([t('文本')])]),
      { type: 'math', tex: 'x', display: true },
    ]);
    expect(parseMarkdown('- 文本\n```\nx\n```')).toEqual([
      ul([item([t('文本')])]),
      { type: 'code', lang: null, code: 'x\n', mermaid: false },
    ]);
  });

  it('callout 正文后的 `$$x$$` 跳出 callout', () => {
    expect(parseMarkdown('> [!tip]\n> 文本\n$$x$$')).toEqual([
      { type: 'callout', kind: 'tip', title: CALLOUT_TITLES.tip, fold: null, blocks: [p(t('文本'))] },
      { type: 'math', tex: 'x', display: true },
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* 安全：HTML 永远是文字                                                        */
/* -------------------------------------------------------------------------- */

describe('安全：原始 HTML 只当文字', () => {
  const HTML_LITERALS = [
    '<div>内容</div>',
    '<script>alert(1)</script>',
    '<img src=x onerror=alert(1)>',
    'a <b>粗</b> c',
    '<iframe src=evil.example></iframe>',
  ];

  it.each(HTML_LITERALS)('「%s」保持纯文本，不成为结构', (raw) => {
    expect(parseMarkdown(raw)).toEqual(onlyText(raw));
  });

  it('任何输入都不会产出 html 块（类型里保留该变体只为向前兼容）', () => {
    const blocks = parseMarkdown('<div>x</div>\n\n<script>y</script>\n\n<span>z</span>');
    expect(blocks.some((block) => block.type === 'html')).toBe(false);
    expect(blocks.every((block) => block.type === 'paragraph')).toBe(true);
  });
});

/* -------------------------------------------------------------------------- */
/* 健壮性                                                                      */
/* -------------------------------------------------------------------------- */

describe('健壮性：规模 / 病态输入 / 纯函数', () => {
  it('20 万字符正文可解析且块数量正确', () => {
    const line = '段落 **粗体** 与 `代码` 与 [[链接]] 与 #标签\n\n';
    const body = line.repeat(7000);
    expect(body.length).toBeGreaterThan(200000);

    let blocks: MarkdownBlock[] = [];
    expect(() => {
      blocks = parseMarkdown(body);
    }).not.toThrow();
    expect(blocks).toHaveLength(7000);
    for (const block of blocks) expect(block.type).toBe('paragraph');
  });

  // 每个单元都是「不成立的前缀」，用 2 万次重复放大最坏情况（孤立标记不应触发 O(n²)）。
  const PATHOLOGICAL_UNITS = ['$', '[', '[[a', '==', '`', '#', '>', '%%', '***', '| a |'];

  it.each(PATHOLOGICAL_UNITS)('病态输入「%s」×20000 不抛异常', (unit) => {
    expect(() => parseMarkdown(unit.repeat(20000))).not.toThrow();
  });

  /*
   * 真正**计时**的回归（上面那张表只断言「不抛异常」，抓不到复杂度问题）。
   *
   * 判据是「块级公式规则注册时带 `alt: ['paragraph', 'blockquote', 'list', 'reference']`」：缺了它，
   * markdown-it 的 `lheading` 会从每个块起点重扫到文末，整体退化成 O(n²)。取三次里最快的一次
   * （削弱 CI 抖动）。
   *
   * **规模为什么是 8000 行而不是 4000**：4000 行在修复前实测 250 ms，只比 200 ms 的预算高 1.4 倍——
   * 一台快 30 % 的机器就会让回归**静默通过**。8000 行修复前约 935 ms（本机），与预算差 4.7 倍，
   * 而修复后只要约 3 ms，两侧余量都够。
   *
   * 本机实测（取三次最快一次）：
   * - `'$$x\n' × 2000`：修复前 62.8 ms / 修复后 0.75 ms；
   * - `'$$x\n' × 4000`：修复前 250.7 ms / 修复后 1.6 ms；
   * - `'$$x\n' × 8000`：修复前 935.1 ms / 修复后 3.2 ms；
   * - `'$$x\n' × 16000`：修复前 3714 ms / 修复后 7.7 ms（4 倍规模 4 倍耗时 = 线性）。
   *
   * 两条判据都留着：绝对预算防「整体变慢」，增长倍率防「绝对预算暂时没超、但已经是平方」。
   */
  const PERF_BUDGET_MS = 200;
  /** 4 倍规模：线性 ≈ 4×，二次方 ≈ 16×。取 12 留出抖动余量。 */
  const PERF_GROWTH_RATIO = 12;
  /** 小样本的计时下限：修复后 2000 行只有亚毫秒级，直接相除会被计时噪声放大。 */
  const PERF_TIMING_FLOOR_MS = 3;

  const fastestParseMs = (body: string): number => {
    let best = Number.POSITIVE_INFINITY;
    for (let round = 0; round < 3; round += 1) {
      const started = performance.now();
      parseMarkdown(body);
      best = Math.min(best, performance.now() - started);
    }
    return best;
  };

  it('多行 `$$x` 的病态输入（8000 行）在线性时间内解析', () => {
    const smallMs = Math.max(fastestParseMs('$$x\n'.repeat(2000)), PERF_TIMING_FLOOR_MS);
    const body = '$$x\n'.repeat(8000);
    const bigMs = fastestParseMs(body);

    expect(bigMs).toBeLessThan(PERF_BUDGET_MS);
    // 4 倍规模最多 12 倍耗时：修复前这一条是 935 / 62.8 ≈ 15 倍（会红），修复后约 4 倍。
    expect(bigMs).toBeLessThan(smallMs * PERF_GROWTH_RATIO);

    // 形状：每两行合成一个块级公式，没有段落，内容就是 `x`。
    const blocks = parseMarkdown(body);
    expect(blocks).toHaveLength(4000);
    expect(blocks.every((block) => block.type === 'math')).toBe(true);
    expect(blocks[0]).toEqual({ type: 'math', tex: 'x', display: true });
  });

  it('2000 个完整 `$$…$$` 块在线性时间内解析', () => {
    const body = '$$\nx\n$$\n'.repeat(2000);
    expect(fastestParseMs(body)).toBeLessThan(PERF_BUDGET_MS);
    const blocks = parseMarkdown(body);
    expect(blocks).toHaveLength(2000);
    expect(blocks.every((block) => block.type === 'math')).toBe(true);
  });

  it('病态的未闭合标记整串留在字面文本里', () => {
    const body = `${'['.repeat(300)}${'`'.repeat(300)}${'*'.repeat(300)}`;
    const blocks = parseMarkdown(body);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe('paragraph');
    if (blocks[0].type !== 'paragraph') throw new Error('应为段落');
    expect(blocks[0].spans.map((span) => (span.type === 'text' ? span.text : '#')).join('')).toContain(
      '['.repeat(300),
    );
  });

  it('重复解析同一份正文结果相同，每次都是新对象，且不改动入参', () => {
    const body = '## 标题\n- [x] 甲 **粗**\n- 乙 [[链接]]\n\n> [!note] 提示\n> 正文 $x$\n\n```js\ncode\n```';
    const snapshot = body;
    const first = parseMarkdown(body);
    const second = parseMarkdown(body);
    expect(second).toEqual(first);
    expect(second).not.toBe(first);
    expect(body).toBe(snapshot);
  });

  it('解析结果不共享可变结构（改一处不会污染下一次解析）', () => {
    const body = '- 甲\n- 乙';
    const first = parseMarkdown(body);
    if (first[0].type !== 'list') throw new Error('应为列表');
    first[0].items[0].spans.push({ type: 'text', text: '污染' });
    expect(parseMarkdown(body)).toEqual([ul([item([t('甲')]), item([t('乙')])])]);
  });
});
