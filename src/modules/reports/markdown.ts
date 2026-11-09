/**
 * 报告正文的 Markdown 解析（纯函数：无 React、无 DOM、无第三方依赖、无正则回溯风险）。
 *
 * ## 为什么只认这么窄的一套语法
 * 报告正文不是「用户随便写的 Markdown」，而是应用自己产出的东西：`draft.ts` /
 * `facts.ts` / AI 参考稿只会写 `### 标题`、`#### 标题`、`- 列表项` 和普通段落，AI 偶尔
 * 补 `**粗体**`、`` `行内代码` ``、`[文字](https://…)`。所以这里**只承诺应用自己会产出的
 * 子集；未支持的语法原样显示，绝不丢内容**——用户手写的表格、引用、围栏代码块、嵌套
 * 列表、任务列表都以字面文本出现在预览里，而不是被「半解析」成错位的结构或干脆消失。
 * 少认一点，代价只是「预览不如导出好看」；多认一点，代价是用户的正文被吃掉。
 *
 * ## 为什么链接要带协议白名单
 * `[文字](url)` 只有在 url 匹配 `^https?://` 或 `^mailto:` 时才成为链接 span；其它协议
 * （`javascript:`、`data:`、`file:` …）连同标记一起退化成字面文本。这不是渲染层疏忽，
 * 而是把防御前移到解析期：正文可能整段来自大模型，一旦危险 URL 被当成「链接」交给
 * 下游，今后任何一次「顺手加个 <a href>」的改动都会变成可执行入口。白名单在这里就把
 * 它降级成普通文字，下游就算想执行也拿不到可执行的 URL。
 *
 * ## 为什么永远不产生 HTML
 * 本文件只输出结构化数据（块 + 行内 span），渲染层 `MarkdownView.tsx` 把它们映射成
 * React 元素，转义由 React 负责。全仓库没有 `dangerouslySetInnerHTML`，解析器里也没有
 * 任何「原样透传 HTML」的通道：正文里的 `<script>`、`<img onerror=…>` 只会显示成字面量。
 *
 * ## 复杂度
 * 块切分是一趟 `split('\n')` + 顺序扫描；行内是 `indexOf` 前进式扫描（不是正则回溯），
 * 并且对「后面不会再有匹配」的失败做了记忆（见 `parseInline` 里的哨兵），因此病态输入
 * （几百个孤立 `[` 或反引号）也是线性而不是 O(n²)。500 行正文是常态上限，常数极小。
 */

/** 行内 span。刻意**不支持嵌套**：粗体 / 代码里再写标记，内容按字面显示（见文件头）。 */
export type MarkdownSpan =
  | { type: 'text'; text: string }
  | { type: 'strong'; text: string }
  | { type: 'code'; text: string }
  | { type: 'link'; label: string; url: string };

/** 列表项。`spans` 是这一行的行内内容（不含行首的 `- `）。 */
export interface MarkdownListItem {
  spans: MarkdownSpan[];
  /**
   * 预留字段：任务列表（`- [ ]`）不在本批方言内，解析器**从不**写它。
   * 类型上留 `never` 是为了让「本批不支持勾选框」成为类型事实，而不是口头约定。
   */
  checked?: never;
}

export type MarkdownBlock =
  | { type: 'heading'; level: 3 | 4; spans: MarkdownSpan[] }
  | { type: 'list'; items: MarkdownListItem[] }
  | { type: 'paragraph'; spans: MarkdownSpan[] };

/**
 * 允许成为链接的协议：只有 http(s) 与 mailto。
 *
 * 只取前 8 个字符判前缀（`https://` 最长）。大小写不敏感是 URL 协议本身的规定，而白名单
 * 只放行「安全的」，放宽大小写不可能放宽到危险协议上（`JaVaScRiPt:` 依旧不匹配）。
 */
export function isSafeLinkUrl(url: string): boolean {
  const head = url.slice(0, 8).toLowerCase();
  return head.startsWith('http://') || head.startsWith('https://') || head.startsWith('mailto:');
}

/**
 * 行内解析：把一行（或整段）纯文本切成 span 序列。
 *
 * 任何不成立的标记（未闭合、空标签、空 URL、协议不在白名单）都**退化成字面文本**，
 * 一个字符都不丢：`[a](javascript:alert(1))` 在预览里就是这串原样字符。
 *
 * 四个哨兵（`noBacktick` / `noStrongClose` / `noLabelEnd` / `noParenClose`）记录「该标记
 * 后面再也不会出现」：`indexOf` 失败一次之后，后续同类字符直接走字面分支，避免对每个
 * `[` 都重新扫一遍剩余字符串。
 */
export function parseInline(raw: string): MarkdownSpan[] {
  const spans: MarkdownSpan[] = [];
  if (typeof raw !== 'string' || raw.length === 0) return spans;

  let pending = ''; // 连续普通字符累积成一个 text span，避免逐字符建对象
  let index = 0;
  let noBacktick = false;
  let noStrongClose = false;
  let noLabelEnd = false;
  let noParenClose = false;

  const flush = () => {
    if (pending) {
      spans.push({ type: 'text', text: pending });
      pending = '';
    }
  };

  while (index < raw.length) {
    const char = raw[index];

    if (char === '`' && !noBacktick) {
      const close = raw.indexOf('`', index + 1);
      if (close < 0) {
        noBacktick = true;
      } else if (close > index + 1) {
        flush();
        spans.push({ type: 'code', text: raw.slice(index + 1, close) });
        index = close + 1;
        continue;
      }
      // 空代码（两个反引号连写）不是语法：当作字面，继续逐字符扫。
    } else if (char === '*' && !noStrongClose) {
      if (raw[index + 1] === '*') {
        const close = raw.indexOf('**', index + 2);
        if (close < 0) {
          noStrongClose = true;
        } else if (close > index + 2) {
          flush();
          spans.push({ type: 'strong', text: raw.slice(index + 2, close) });
          index = close + 2;
          continue;
        }
        // `****`（空粗体）不是语法：当作字面。
      }
      // 单个 `*`（斜体）不在方言内，也当作字面。
    } else if (char === '[' && !noLabelEnd && !noParenClose) {
      const labelEnd = raw.indexOf('](', index + 1);
      if (labelEnd < 0) {
        noLabelEnd = true;
      } else if (labelEnd > index + 1) {
        const urlEnd = raw.indexOf(')', labelEnd + 2);
        if (urlEnd < 0) {
          // `](` 之后再没有 `)`：后面任何 `[` 都不可能凑成链接，永久跳过这条分支。
          noParenClose = true;
        } else if (urlEnd > labelEnd + 2) {
          // URL 两端空白是常见的 AI 排版习惯（`[文档]( https://… )`），trim 掉再判协议；
          // 只 trim URL，不动标签——标签里的空格是正文内容。
          const url = raw.slice(labelEnd + 2, urlEnd).trim();
          if (isSafeLinkUrl(url)) {
            flush();
            spans.push({ type: 'link', label: raw.slice(index + 1, labelEnd), url });
            index = urlEnd + 1;
            continue;
          }
          // 协议不在白名单：整个标记退回字面文本（只前进一个字符，后面照样能识别新链接）。
        }
        // 空标签 `[](url)` / 空 URL `[a]()` 同样按字面处理。
      }
    }

    pending += char;
    index += 1;
  }

  flush();
  return spans;
}

/** `### ` → 3、`#### ` → 4。`#`/`##`/`#####`、以及「# 号后没有空格」一律不算标题。 */
function headingLevel(line: string): 0 | 3 | 4 {
  // 先判四级：`#### x` 不会命中 `### `（第四个字符是 `#` 而不是空格），顺序不影响结果，
  // 但从长到短写更不容易在以后加级别时出错。
  if (line.startsWith('#### ')) return 4;
  if (line.startsWith('### ')) return 3;
  return 0;
}

/**
 * 把一节正文解析成块序列。任何输入都不抛异常、不丢字符。
 *
 * 规则（就是导出的 Markdown 形态本身）：
 * - `### ` / `#### ` 起一行标题，其余 `#` 级数按普通段落文字显示；
 * - 连续的 `- ` 行合成**一个**列表块；
 * - 空行分隔块；连续空行不产生空块；首尾空行忽略；
 * - 其余连续非空行合成**一个**段落，行内 `\n` 原样保留（靠 CSS `pre-wrap` 呈现）；
 * - `\r\n` 与孤立 `\r` 先归一化成 `\n`。
 */
export function parseMarkdown(body: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  // 类型上 body 是 string，但正文可能来自磁盘上的 JSON，运行时兜一层：非字符串当空正文。
  if (typeof body !== 'string' || body.length === 0) return blocks;

  // 只归一化一次 \r：之后所有切分都只认 `\n`，不必在每处再处理回车。
  const text = body.indexOf('\r') < 0 ? body : body.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

  let paragraph: string[] | null = null;
  let items: MarkdownListItem[] | null = null;

  const flushParagraph = () => {
    if (paragraph === null) return;
    const lines = paragraph;
    paragraph = null;
    blocks.push({ type: 'paragraph', spans: parseInline(lines.join('\n')) });
  };

  const flushList = () => {
    if (items === null) return;
    const list = items;
    items = null;
    blocks.push({ type: 'list', items: list });
  };

  for (const line of text.split('\n')) {
    // 空行（含只有空白的行）是块分隔符：空行本身不是内容，因此不产生空块。
    if (!line.trim()) {
      flushParagraph();
      flushList();
      continue;
    }

    const level = headingLevel(line);
    if (level !== 0) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'heading', level, spans: parseInline(line.slice(level + 1)) });
      continue;
    }

    if (line.startsWith('- ')) {
      // 连续 `- ` 行归入同一个列表：导出里是一组条目，预览也该是一组。
      flushParagraph();
      if (items === null) items = [];
      items.push({ spans: parseInline(line.slice(2)) });
      continue;
    }

    // 其余非空行：连续多行合成一段，`\n` 留在 text span 里（硬换行是正文内容，不能折平）。
    flushList();
    if (paragraph === null) paragraph = [];
    paragraph.push(line);
  }

  flushParagraph();
  flushList();
  return blocks;
}
