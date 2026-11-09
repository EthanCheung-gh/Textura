/**
 * 报告正文的 Markdown 解析：对齐 **Obsidian 阅读视图** 的解析器。
 *
 * 纯函数：无 React、无 DOM、无 `innerHTML`、无网络、无 `Date`/随机数；同一份正文永远解析出
 * 同一棵 AST。渲染全在渲染层（`MarkdownView.tsx` 及之后的渲染器），本文件只产出结构。
 *
 * ## 为什么换掉上一版手写解析
 * 上一版故意只认 `###`/`####`、`- `、段落、`**`、`` ` ``、`[x](url)` —— 那是对「应用自己产出的
 * 正文」的收敛。现在产品的口径变成「用户在报告里写什么，预览就该像 Obsidian 一样显示什么」，
 * 于是改用 markdown-it 承载 CommonMark + GFM（表格 / 删除线 / 自动链接），再把 Obsidian 独有
 * 的语法当作小插件补上。手写这套语法的成本与出错面都远大于「一个成熟解析器 + 几个小规则」。
 *
 * ## 依赖边界（刻意很窄）
 * 只新增 **markdown-it**（+ 类型）。以下能力全部在本仓库内实现，不引入任何 markdown-it-* 生态
 * 插件：任务列表、`==高亮==`、`%%注释%%`、wikilink/embed/tag、frontmatter、callout。它们的落点：
 * - 四个行内规则：`obs_highlight` / `obs_wikilink`（含 embed）/ `obs_tag` / `obs_math`；
 * - 一个块级规则：`obs_math_block`（`$$…$$`）；
 * - 一趟 token 后处理：`obs_structures`（任务列表 + callout，在 inline 解析之前改写 token 流）；
 * - 解析前的两段预扫描：frontmatter 与注释剥离（都在"块切分"之前，见各函数注释）。
 *
 * **KaTeX / Mermaid / 语法高亮不在这里**：本文件只把「这里有一段公式（原始 TeX）」「这段代码的
 * 语言是 mermaid」原样交给 AST，由渲染层决定装哪个库去画。所以这里一个渲染库都不装，
 * 打包体积的增量只有解析器本身。
 *
 * ## 与 Obsidian 对齐的部分
 * - 标题 1–6、分隔线、段落（软换行 → `break` span，硬换行 → `break{hard:true}`）；
 * - `**粗**` / `*斜*` / `***粗斜***`（按 CommonMark 嵌套为 em>strong）/ `~~删~~` / `==高亮==` /
 *   行内代码 / 链接 / 图片 / 裸链自动链接；
 * - 无序 / 有序列表（保留 `start`）、嵌套（子内容进 `blocks`）、松散与紧凑、
 *   GFM 任务列表（`checked` 取代 `[ ]` 文本）；
 * - 表格（三向对齐）、围栏代码（`lang` 取首个词并小写，`mermaid` 单独标记）、引用、
 *   callout（含别名归一、`+`/`-` 折叠、自定义标题、**嵌套 callout**）；
 * - 行内 `$…$` 与块级 `$$…$$`；
 * - `%%注释%%`（行内与跨行块）在 **AST 里彻底消失**（Obsidian 阅读视图不显示注释）。
 *
 * ## 刻意的偏差（是产品决定，不是遗漏）
 * 1. **没有 vault**：wikilink / embed 只解析成结构化 span（target / alias / anchor / 尺寸），
 *    **不做**任何文件解析、路径补全、图片存在性检查、正向链接解析，也不发网络请求。
 * 2. **原始 HTML 一律转义**：markdown-it `html: false`，正文里的 `<div>` / `<script>` 只会成为
 *    text span；`{type:'html'}` 变体只为向前兼容留在类型里，**本解析器从不产出它**。全仓库没有
 *    `dangerouslySetInnerHTML`。
 * 3. **frontmatter 用最小 YAML 读取器**：只认 `key: scalar`、`key: [a, b]`、`- item` 块列表
 *    （多值用 `, ` 连接）。不认嵌套 map、多行 `|`/`>`、锚点、类型推断、行尾 `#` 注释。够展示、
 *    绝不猜。未闭合的 `---` 块按普通正文处理；**读不出任何字段的空 frontmatter（`---\n---`）不产出
 *    块**（否则预览里会多一个空的「属性 0」面板）。
 * 4. **链接不做白名单过滤，而是打标记**：`href` 一律保留，`safe` 只对 `http(s):` / `mailto:`
 *    为 true；`javascript:` / `data:` / `file:` / 相对路径 / 锚点全部 `safe:false`，由渲染层降级为
 *    纯文本。之所以不在解析期就吞掉（上一版的做法），是因为渲染层需要知道「这里原本是链接、
 *    只是不安全」才能降级成文字；安全结论单点在 `safe` 上，本文件不产生任何可执行入口。
 * 5. **行内 `$$…$$`** 降级为 `display:false` 的 math span（AST 的行内 math 没有 display:true）。
 * 6. 反引号代码里的 `%%` 不参与注释剥离（代码是字面量）。缩进过的代码块（4 空格缩进的缩进代码、
 *    列表里缩进的围栏）里的 `%%` 会被剥离 —— 注释剥离发生在块解析之前，**这是有意的简化**：
 *    一段缩进内容是「代码」还是「列表里的普通段落」，要看它在不在列表里，预扫描阶段算不准。
 * 7. `==高亮==` 要求开始/结束的 `==` 紧贴非空白字符（与 `**` 同族），避免把 `a == b == c` 这种
 *    比较写法误判成高亮。
 * 8. `#标签` 前面不能是词字符（`a#b`）或另一个 `#`（`###没有空格` 这类写错的标题整体保持字面）；
 *    纯数字（`#2024`）不算标签，与 Obsidian 一致。
 * 9. callout 的**标题**按纯文本处理（Obsidian 会把标题里的 `**粗体**`、`[[链接]]` 再解析一遍）。
 *    AST 里 `title` 是 `string`，保留用户写的原文。
 *
 * ## 安全与复杂度
 * - 每个行内规则都是「找下一个闭合标记 → 切片」，闭合失败时用一次哨兵记住「后面再没有」，
 *   因此病态输入（几万个孤立 `$` / `[[`）也是线性而不是 O(n²)；注释剥离、frontmatter、
 *   token → AST 转换都是单趟。markdown-it 本身是线性的。
 * - 200k 字符正文在单测里跑过（见 `markdown.test.ts` 的「健壮性」）。
 */
import MarkdownIt from 'markdown-it';
import type {
  Env,
  MarkdownIt as MarkdownItInstance,
  StateBlock,
  StateCore,
  StateInline,
  Token,
} from 'markdown-it';

/** 表格列对齐。`null` = 该列没写对齐标记（GFM 的默认左对齐由渲染层决定）。 */
export type MarkdownAlign = 'left' | 'center' | 'right' | null;

/**
 * 行内 span。
 *
 * `link` / `image` 都带 `safe`：只有 `http(s):` 与 `mailto:` 为 true。`safe:false` 的链接渲染层
 * 必须降级为纯文本（不可点、不产生 href），这是本模块唯一的链接安全契约。
 *
 * `wikilink` / `embed` 都有 `anchor`：`[[a#标题]]` 与 `![[a#^块]]` 的 `#` 之后部分原样保留（块锚点
 * 带着 `^` 前缀）。embed 曾经只有 target/alias/尺寸，锚点在这一层被丢掉，渲染层的 chip 就永远显示
 * 不出「嵌入的是哪个标题」，所以锚点是 embed 契约的一部分。
 *
 * `break` 由解析器统一表示换行：`hard:true` 是行尾两个空格或 `\` 造成的硬换行，
 * `hard:false` 是段内的软换行（Obsidian 默认把软换行也显示成换行，渲染层可自行决定用 `<br>` 还是空格）。
 */
export type MarkdownSpan =
  | { type: 'text'; text: string }
  | { type: 'strong' | 'em' | 'del' | 'highlight'; spans: MarkdownSpan[] }
  | { type: 'code'; text: string }
  | { type: 'link'; href: string; safe: boolean; spans: MarkdownSpan[] }
  | { type: 'wikilink'; target: string; alias: string | null; anchor: string | null }
  | {
      type: 'embed';
      target: string;
      alias: string | null;
      anchor: string | null;
      width: number | null;
      height: number | null;
    }
  | { type: 'tag'; tag: string }
  | { type: 'math'; tex: string; display: false }
  | { type: 'image'; src: string; alt: string; safe: boolean }
  | { type: 'break'; hard: boolean };

/**
 * 列表项。
 * - `spans`：首个段落的内容（紧凑列表就是这一行）；
 * - `blocks`：其余内容（嵌套列表、松散列表里的第二段、代码块…），没有则**不出现**该字段；
 * - `checked`：任务列表勾选状态，`null` = 不是任务项。
 */
export interface MarkdownListItem {
  spans: MarkdownSpan[];
  blocks?: MarkdownBlock[];
  checked: boolean | null;
}

/**
 * 块。`table.header` 是表头行（每格一组 span），`rows` 是数据行；`align` 与列一一对应。
 * `code.mermaid` 只是「语言是 mermaid」的事实，画图是渲染层的事；`math.display:true` 是块级公式。
 */
export type MarkdownBlock =
  | { type: 'heading'; level: 1 | 2 | 3 | 4 | 5 | 6; spans: MarkdownSpan[] }
  | { type: 'paragraph'; spans: MarkdownSpan[] }
  | { type: 'list'; ordered: boolean; start: number; items: MarkdownListItem[] }
  | { type: 'blockquote'; blocks: MarkdownBlock[] }
  | { type: 'callout'; kind: string; title: string; fold: 'open' | 'closed' | null; blocks: MarkdownBlock[] }
  | { type: 'code'; lang: string | null; code: string; mermaid: boolean }
  | { type: 'math'; tex: string; display: true }
  | { type: 'table'; align: MarkdownAlign[]; header: MarkdownSpan[][]; rows: MarkdownSpan[][][] }
  | { type: 'hr' }
  | { type: 'frontmatter'; fields: { key: string; value: string }[] }
  | { type: 'html'; text: string };

/** Obsidian 的 13 个规范 callout 类型（顺序即官方文档的表格顺序）。 */
export const CALLOUT_KINDS: readonly string[] = [
  'note',
  'abstract',
  'info',
  'todo',
  'tip',
  'success',
  'question',
  'warning',
  'failure',
  'danger',
  'bug',
  'example',
  'quote',
];

/**
 * 别名 → 规范类型。Obsidian 认这些同义写法（`[!summary]` 与 `[!abstract]` 等价）。
 * 键是小写：比较前会把用户写的 kind 小写化。
 */
export const CALLOUT_ALIASES: Record<string, string> = {
  summary: 'abstract',
  tldr: 'abstract',
  hint: 'tip',
  important: 'tip',
  check: 'success',
  done: 'success',
  help: 'question',
  faq: 'question',
  caution: 'warning',
  attention: 'warning',
  fail: 'failure',
  missing: 'failure',
  error: 'danger',
  cite: 'quote',
};

/** 规范类型 → 默认标题（用户没写标题时用它；渲染层也可据此做本地化覆盖）。 */
export const CALLOUT_TITLES: Record<string, string> = {
  note: '笔记',
  abstract: '摘要',
  info: '信息',
  todo: '待办',
  tip: '提示',
  success: '成功',
  question: '疑问',
  warning: '警告',
  failure: '失败',
  danger: '危险',
  bug: 'Bug',
  example: '示例',
  quote: '引用',
};

/**
 * 链接安全白名单：只有 `http(s):` 与 `mailto:`。
 *
 * 只判前 8 个字符（`https://` 最长），大小写不敏感是 URL 协议本身的规定。相对路径（`./`、`../`）、
 * 页内锚点（`#x`）、`javascript:`、`data:`、`file:` 一律不安全：桌面端是 Tauri webview，
 * CSP 为 `default-src 'self'`，且没有「用系统浏览器打开外链」的能力，交给渲染层当文字更安全。
 */
function isSafeLinkUrl(url: string): boolean {
  const head = url.slice(0, 8).toLowerCase();
  return head.startsWith('http://') || head.startsWith('https://') || head.startsWith('mailto:');
}

/* -------------------------------------------------------------------------- */
/* 行内规则                                                                    */
/* -------------------------------------------------------------------------- */

/** 行内解析的 per-block 备忘：某个标记「后面再也不会有闭合」时只失败一次，避免 O(n²) 扫描。 */
interface InlineMemo {
  noDoubleDollar?: boolean;
  noWikilinkClose?: boolean;
}

type MemoState = StateInline & { obsMemo?: InlineMemo };

function memoOf(state: StateInline): InlineMemo {
  const carrier = state as MemoState;
  if (!carrier.obsMemo) carrier.obsMemo = {};
  return carrier.obsMemo;
}

function isWhitespaceCode(code: number): boolean {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0b || code === 0x0c || code === 0x0d;
}

function isDigitCode(code: number): boolean {
  return code >= 0x30 && code <= 0x39;
}

/** 词字符（只判 ASCII）：`a#b` 里的 `#` 不是标签。 */
function isWordCode(code: number): boolean {
  return (
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a) ||
    code === 0x5f
  );
}

/**
 * `==高亮==` → 一个自带内容的 token（内容在转 AST 时再递归解析，因此高亮里可以有粗体/代码）。
 *
 * 要求 `==` 后面紧跟非空白、闭合 `==` 前面也非空白：否则 `a == b == c` 会被误判。找不到闭合时
 * 整串退化成字面文本（一个字符都不丢）。
 */
function highlightRule(state: StateInline, silent: boolean): boolean {
  if (state.src.charCodeAt(state.pos) !== 0x3d /* = */) return false;
  if (state.src.charCodeAt(state.pos + 1) !== 0x3d) return false;

  const close = state.src.indexOf('==', state.pos + 2);
  if (close < 0 || close + 2 > state.posMax) return false;
  const inner = state.src.slice(state.pos + 2, close);
  if (inner.length === 0) return false;
  if (isWhitespaceCode(inner.charCodeAt(0))) return false;
  if (isWhitespaceCode(inner.charCodeAt(inner.length - 1))) return false;
  if (silent) return false;

  const token = state.push('obs_highlight', '', 0);
  token.content = inner;
  state.pos = close + 2;
  return true;
}

/**
 * `[[target]]` / `[[target|alias]]` / `[[target#heading]]` / `[[#heading]]` / `[[target#^block]]`
 * 与 `![[target]]` / `![[img.png|300]]` / `![[a.png|640x480]]`。
 *
 * **不做 vault 解析**：`target` 就是用户写的字符串（已 trim），`anchor` 原样保留（块引用带着 `^`，
 * 这样渲染层还能区分「标题锚点」与「块锚点」）。空 target（如 `[[]]`）不算语法，退化为文字。
 *
 * 管道之后的部分：**embed** 才可能是尺寸（`|300` / `|640x480`），wikilink 一律当别名。
 */
function wikilinkRule(state: StateInline, silent: boolean): boolean {
  const start = state.pos;
  const head = state.src.charCodeAt(start);
  let embed = false;
  let open = start;
  if (head === 0x21 /* ! */) {
    if (state.src.charCodeAt(start + 1) !== 0x5b) return false;
    embed = true;
    open = start + 1;
  } else if (head !== 0x5b /* [ */) {
    return false;
  }
  if (state.src.charCodeAt(open + 1) !== 0x5b) return false;

  // 哨兵：某个位置之后再没有 `]]`，那更靠后的位置也一定没有，因此只失败一次。
  const memo = memoOf(state);
  if (memo.noWikilinkClose) return false;

  const bodyStart = open + 2;
  const close = state.src.indexOf(']]', bodyStart);
  if (close < 0) {
    memo.noWikilinkClose = true;
    return false;
  }
  if (close + 2 > state.posMax) return false;
  const body = state.src.slice(bodyStart, close);
  // wikilink 是单行语法；换行或空内容都不成立。
  if (body.length === 0 || body.includes('\n')) return false;

  const pipe = body.indexOf('|');
  const targetPart = (pipe < 0 ? body : body.slice(0, pipe)).trim();
  const spec = pipe < 0 ? null : body.slice(pipe + 1).trim();

  let alias: string | null = null;
  let width: number | null = null;
  let height: number | null = null;
  if (spec !== null && spec.length > 0) {
    // `|300` / `|640x480` 只是 **embed** 的尺寸。`[[Page|300]]` 里的 300 是显示文本（Obsidian 的
    // 别名本来就可以是纯数字），若在 wikilink 上也走尺寸分支，别名会被整段吞掉、chip 只剩目标。
    const size = embed ? /^(\d+)(?:x(\d+))?$/i.exec(spec) : null;
    if (size) {
      width = Number.parseInt(size[1], 10);
      height = size[2] === undefined ? null : Number.parseInt(size[2], 10);
    } else {
      alias = spec;
    }
  }

  let target = targetPart;
  let anchor: string | null = null;
  const hash = targetPart.indexOf('#');
  if (hash >= 0) {
    target = targetPart.slice(0, hash).trim();
    const rawAnchor = targetPart.slice(hash + 1).trim();
    anchor = rawAnchor.length > 0 ? rawAnchor : null;
  }
  if (target.length === 0 && anchor === null) return false;
  if (silent) return false;

  const token = state.push(embed ? 'obs_embed' : 'obs_wikilink', '', 0);
  token.content = body;
  token.meta = embed
    ? ({ target, alias, anchor, width, height } satisfies EmbedMeta)
    : ({ target, alias, anchor } satisfies WikilinkMeta);
  state.pos = close + 2;
  return true;
}

/** 标签字符：字母（含 CJK）/ 数字 / `_` / `-` / `/`。 */
const TAG_PATTERN = /^#([\p{L}\p{N}_/-]+)/u;
/** 纯数字或纯分隔符不算标签（Obsidian 要求至少一个非数字字符，所以 `#2024` 是文字）。 */
const TAG_ONLY_DIGITS = /^[\p{N}/-]+$/u;

/**
 * `#tag` / `#nested/tag` / `#with-dash` / `#with_underscore` / CJK 标签 → `tag` span。
 *
 * 不触发的情况：`#` 后面是空白或标点（`#` + 空格是块级标题）、前面是词字符（`a#b`、`C#`）
 * 或另一个 `#`（`###没有空格` 这类「写错的标题」整体保持字面）、代码里（代码是独立 token，
 * 规则根本不会跑）。
 */
function tagRule(state: StateInline, silent: boolean): boolean {
  if (state.src.charCodeAt(state.pos) !== 0x23 /* # */) return false;
  if (state.pos > 0) {
    const prev = state.src.charCodeAt(state.pos - 1);
    if (isWordCode(prev) || prev === 0x23) return false;
  }

  const rest = state.src.slice(state.pos, state.posMax);
  const match = TAG_PATTERN.exec(rest);
  if (!match) return false;
  const trimmed = match[1].replace(/[/-]+$/u, '');
  if (trimmed.length === 0) return false;
  if (TAG_ONLY_DIGITS.test(trimmed)) return false;
  if (silent) return false;

  const token = state.push('obs_tag', '', 0);
  token.content = trimmed;
  state.pos += 1 + trimmed.length;
  return true;
}

/**
 * 行内公式 `$…$`（以及出现在行内的 `$$…$$`，降级为 `display:false`，见文件头偏差 5）。
 *
 * 不触发：`$` 后面是空白或已到末尾、闭合 `$` 前面是空白、闭合 `$` 后面紧跟数字（`$5 and $10`
 * 是价钱不是公式）、没有闭合（孤立的 `$` 就是文字）。
 */
function mathInlineRule(state: StateInline, silent: boolean): boolean {
  if (state.src.charCodeAt(state.pos) !== 0x24 /* $ */) return false;
  const start = state.pos;
  const max = state.posMax;

  if (state.src.charCodeAt(start + 1) === 0x24) {
    const memo = memoOf(state);
    if (memo.noDoubleDollar) return false;
    const close = state.src.indexOf('$$', start + 2);
    if (close < 0 || close + 2 > max) {
      memo.noDoubleDollar = true;
      return false;
    }
    const tex = state.src.slice(start + 2, close).trim();
    if (tex.length === 0) return false;
    if (silent) return false;
    const token = state.push('obs_math', '', 0);
    token.content = tex;
    state.pos = close + 2;
    return true;
  }

  if (start + 1 >= max) return false;
  if (isWhitespaceCode(state.src.charCodeAt(start + 1))) return false;
  const close = state.src.indexOf('$', start + 1);
  if (close < 0 || close >= max) return false;
  if (isWhitespaceCode(state.src.charCodeAt(close - 1))) return false;
  if (close + 1 < max && isDigitCode(state.src.charCodeAt(close + 1))) return false;
  const tex = state.src.slice(start + 1, close);
  if (tex.trim().length === 0) return false;
  if (silent) return false;

  const token = state.push('obs_math', '', 0);
  token.content = tex;
  state.pos = close + 1;
  return true;
}

/**
 * 块级公式 `$$…$$`：以 `$$` 开头的行到下一个含 `$$` 的行（含同行 `$$x$$`）。
 *
 * 没有闭合 → 返回 false，交给段落规则当普通文字（不吞内容）。闭合 `$$` 之后的同行残余文本被忽略
 * —— 那是排版失误，Obsidian 也不会把它当公式的一部分。
 *
 * **TeX 必须逐行从块状态自己的偏移里取**（`bMarks[i] + tShift[i]` … `eMarks[i]`，闭合行取到
 * `closeAt`），不能拿 `state.src.slice(begin + 2, closeAt)` 一把切：容器（引用 / callout / 列表）
 * 里的行首 `>` 与缩进在 `state.src` 里还在，一把切会把它们留在 TeX 里——`> E = mc^2` 交给 KaTeX
 * 会渲染出一个「大于号 + 变量」，且**没有报错态**（最隐蔽的那一类错误）。块状态的
 * `bMarks/tShift/eMarks` 已经被 blockquote / list 的 tokenization 去掉容器标记，逐行取才是原文。
 *
 * `alt: ['paragraph', 'blockquote', 'list', 'reference']`（见 `createEngine`）让它同时充当
 * **段落终止符**与**容器惰性续行的终止符**，因此这里的 `silent` 分支必须真的判出「这一行是不是
 * 块级公式的开头」：这些规则只关心 true/false，不消费 token。
 */
function mathBlockRule(state: StateBlock, startLine: number, endLine: number, silent: boolean): boolean {
  const begin = state.bMarks[startLine] + state.tShift[startLine];
  const firstEnd = state.eMarks[startLine];
  if (begin + 2 > firstEnd) return false;
  if (state.src.charCodeAt(begin) !== 0x24 || state.src.charCodeAt(begin + 1) !== 0x24) return false;

  let line = startLine;
  let searchFrom = begin + 2;
  let closeAt = -1;
  while (line < endLine) {
    const lineEnd = state.eMarks[line];
    if (searchFrom <= lineEnd) {
      const hit = state.src.slice(searchFrom, lineEnd).indexOf('$$');
      if (hit >= 0) {
        closeAt = searchFrom + hit;
        break;
      }
    }
    line += 1;
    if (line < endLine) searchFrom = state.bMarks[line] + state.tShift[line];
  }
  if (closeAt < 0) return false;

  // 逐行取内容：首行从 `$$` 之后开始，闭合行只取到 `closeAt`，中间行整行。每行的起点用
  // `bMarks + tShift`（容器标记已被 blockquote/list 的 tokenization 从偏移里摘掉），终点用
  // `eMarks`——这样引用里的 `> ` 与列表里的缩进都不会漏进 TeX（见函数头注释）。
  const lines: string[] = [];
  for (let index = startLine; index <= line; index += 1) {
    const lineBegin = index === startLine ? begin + 2 : state.bMarks[index] + state.tShift[index];
    const lineEnd = index === line ? closeAt : state.eMarks[index];
    lines.push(lineEnd > lineBegin ? state.src.slice(lineBegin, lineEnd) : '');
  }

  const tex = lines.join('\n').trim();
  if (tex.length === 0) return false;
  if (silent) return true;

  const token = state.push('math_block', 'math', 0);
  token.block = true;
  token.markup = '$$';
  token.content = tex;
  token.map = [startLine, line + 1];
  state.line = line + 1;
  return true;
}

/* -------------------------------------------------------------------------- */
/* 块级后处理（任务列表 / callout）                                             */
/* -------------------------------------------------------------------------- */

interface WikilinkMeta {
  target: string;
  alias: string | null;
  anchor: string | null;
}

interface EmbedMeta extends WikilinkMeta {
  width: number | null;
  height: number | null;
}

interface ListItemMeta {
  checked?: boolean;
}

interface CalloutMeta {
  kind: string;
  title: string;
  fold: 'open' | 'closed' | null;
}

/** 任务列表标记：`[ ]` / `[x]` / `[X]`，后面必须是空白或行尾。 */
const TASK_MARKER = /^\[([ xX])\](?:[ \t]+|$)/;
/** callout 首行：`[!kind]` + 可选 `+`/`-` + 可选标题。 */
const CALLOUT_MARKER = /^\[!([^\]\n]+)\]([+-]?)[ \t]*(.*)$/;

/** 找到与 `tokens[start]`（blockquote/callout 的 open）配对的 close 下标。 */
function findBlockquoteClose(tokens: Token[], start: number): number {
  let depth = 0;
  for (let index = start; index < tokens.length; index += 1) {
    const type = tokens[index].type;
    if (type === 'blockquote_open' || type === 'callout_open') depth += 1;
    else if (type === 'blockquote_close') {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

/**
 * 把 callout 的 kind 归一：规范类型 → 自身；别名 → 规范类型；都不认识 → 用户写的原文。
 * 大小写不敏感（`[!Summary]` 等价 `[!summary]`）。
 */
function normalizeCalloutKind(raw: string): string {
  const key = raw.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(CALLOUT_TITLES, key)) return key;
  const alias = CALLOUT_ALIASES[key];
  return alias === undefined ? raw : alias;
}

/**
 * 在 inline 解析**之前**改 token 流：
 * 1. 任务列表：从项首段落内容里摘掉 `[ ]` / `[x]`，把状态记到 `list_item_open.meta`；
 * 2. callout：把首行是 `[!kind]` 的 blockquote 改写成 `callout_open`（marker 行从正文里去掉）。
 *
 * 必须在 `inline` 之前：这样被摘掉标记后的内容才参与行内解析（而不是先解析成一堆 span 再回填）。
 * blockquote 是扁平 token 流，嵌套靠 open/close 配对，因此**嵌套 callout 天然成立**（递归）。
 */
function structureRule(state: StateCore): void {
  const tokens = state.tokens;

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.type !== 'list_item_open') continue;
    const paragraph = tokens[index + 1];
    const inline = tokens[index + 2];
    if (!paragraph || paragraph.type !== 'paragraph_open') continue;
    if (!inline || inline.type !== 'inline') continue;
    const match = TASK_MARKER.exec(inline.content);
    if (!match) continue;
    (token as Token & { meta: ListItemMeta }).meta = {
      ...(token.meta as ListItemMeta | undefined),
      checked: match[1].toLowerCase() === 'x',
    };
    inline.content = inline.content.slice(match[0].length);
  }

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.type !== 'blockquote_open') continue;

    const paragraphOpen = tokens[index + 1];
    const inline = tokens[index + 2];
    const paragraphClose = tokens[index + 3];
    if (!paragraphOpen || paragraphOpen.type !== 'paragraph_open') continue;
    if (!inline || inline.type !== 'inline') continue;
    if (!paragraphClose || paragraphClose.type !== 'paragraph_close') continue;

    const firstLineEnd = inline.content.indexOf('\n');
    const firstLine = firstLineEnd < 0 ? inline.content : inline.content.slice(0, firstLineEnd);
    const match = CALLOUT_MARKER.exec(firstLine);
    if (!match) continue;
    // 防御：markdown-it 的 token 流总是配平的；万一不配平就不改写，保持「普通引用」更安全。
    // 只有真的命中 marker 才做这次配对扫描，普通引用不付这份代价。
    if (findBlockquoteClose(tokens, index) < 0) continue;

    const kind = normalizeCalloutKind(match[1].trim());
    const fold: CalloutMeta['fold'] = match[2] === '+' ? 'open' : match[2] === '-' ? 'closed' : null;
    const customTitle = match[3].trim();
    const defaultTitle = CALLOUT_TITLES[kind];
    const title = customTitle.length > 0 ? customTitle : defaultTitle === undefined ? kind : defaultTitle;

    const rest = firstLineEnd < 0 ? '' : inline.content.slice(firstLineEnd + 1);
    if (rest.trim().length === 0) tokens.splice(index + 1, 3);
    else inline.content = rest;

    token.type = 'callout_open';
    (token as Token & { meta: CalloutMeta }).meta = { kind, title, fold };
  }
}

/* -------------------------------------------------------------------------- */
/* 引擎                                                                        */
/* -------------------------------------------------------------------------- */

function createEngine(): MarkdownItInstance {
  const engine = new MarkdownIt({
    // 原始 HTML 一律当文字（见文件头偏差 2）。
    html: false,
    // 裸链自动链接（`https://…` 不需要尖括号）。
    linkify: true,
    typographer: false,
    breaks: false,
  });

  // 解析期不做 URL 白名单，全部保留；安全结论单点放在 span 的 `safe` 上（见文件头偏差 4）。
  // markdown-it 默认的 validateLink 会把 `javascript:` 直接吞成字面文本，AST 里就看不见这个
  // 链接了，渲染层也就无法「降级成纯文本」而不是「把整串标记显示出来」。
  engine.validateLink = () => true;

  engine.inline.ruler.push('obs_highlight', highlightRule);
  engine.inline.ruler.push('obs_wikilink', wikilinkRule);
  engine.inline.ruler.push('obs_tag', tagRule);
  engine.inline.ruler.push('obs_math', mathInlineRule);
  /*
   * `{ alt: [...] }` 不是可选项，是**性能与对齐**的硬要求。
   *
   * 性能：markdown-it 的 `paragraph` / `lheading` 会从每个块起点开始，用 `getRules('paragraph')`
   * 里的规则逐行试探终止位置。块级公式不在这个链里时，一段没有空行的正文里每遇到一个新块起点，
   * `lheading` 都会一直扫到文末（O(n) 次），整体退化成 O(n²)：实测 200k 的 `'$$x\n'×50000`
   * 要 36.7 s，加了这个标记后 linear（约 10 ms 级）。
   *
   * 对齐：整条链与 markdown-it 15 自己的叶子块（fence / hr / heading / html_block）**完全相同**
   * （`['paragraph', 'blockquote', 'list', 'reference']`），否则「块级公式在哪些容器里能打断上一块」
   * 就会和围栏代码 / 标题 / 分隔线不一致：
   * - `paragraph`：`文本\n$$\nx^2\n$$` 没有空行时，段落不会吞到 `$$` 之后，`$$…$$` 才另起一个
   *   display:true 的块级公式（少了它只能退化成行内公式）；
   * - `blockquote`：引用 / callout 的**惰性续行**靠这条链判断终止。只有 `['paragraph']` 时
   *   `> 文本\n$$x$$` 会把 `$$x$$` 当成引用的懒续行吸进段落（display:false），而同样位置的围栏
   *   代码 / 标题 / 分隔线都会另起一块——同一个「块级语法打断了段落」在这里必须同款成立。
   * - `list` / `reference`：与 fence / hr 一致，列表项的懒续行与链接引用定义处同样被公式打断。
   */
  engine.block.ruler.before('paragraph', 'obs_math_block', mathBlockRule, {
    alt: ['paragraph', 'blockquote', 'list', 'reference'],
  });
  engine.core.ruler.before('inline', 'obs_structures', structureRule);
  return engine;
}

/** 引擎无状态（每次 parse 都新建 state/env），可以安全地全局复用。 */
const engine: MarkdownItInstance = createEngine();

/* -------------------------------------------------------------------------- */
/* 解析前处理：frontmatter + 注释剥离                                           */
/* -------------------------------------------------------------------------- */

const FENCE_PATTERN = /^ {0,3}(`{3,}|~{3,})(.*)$/;

/**
 * 剥掉 `%%注释%%`（行内与跨行）——注释在 Obsidian 阅读视图里不显示，所以必须**在块解析之前**删掉：
 * 只是「解析成 span 后再丢弃」的话，注释占据的换行/空行会留在段落里，把本该相邻的内容拆开或粘死。
 *
 * 预扫描是单趟的，并且跳过围栏代码块（代码里的 `%%` 是字面量）与行内代码（反引号成对时整体保留）。
 * 未闭合的 `%%` 会一直吃到文末（与 Obsidian 一致：那之后都是注释）。
 */
function stripComments(source: string): string {
  if (source.indexOf('%%') < 0) return source;

  const total = source.length;
  const parts: string[] = [];
  let inComment = false;
  let fence: string | null = null;
  let index = 0;

  while (index < total) {
    const newline = source.indexOf('\n', index);
    const lineEnd = newline < 0 ? total : newline;
    const line = source.slice(index, lineEnd);

    // 行首：先更新围栏状态。围栏内的行（含开/闭围栏本身）整行原样保留。
    const wasFenced = fence !== null;
    if (!inComment) {
      const fenceMatch = FENCE_PATTERN.exec(line);
      if (wasFenced) {
        if (
          fenceMatch &&
          fenceMatch[1][0] === fence![0] &&
          fenceMatch[1].length >= fence!.length &&
          fenceMatch[2].trim() === ''
        ) {
          fence = null;
        }
      } else if (fenceMatch && !(fenceMatch[1][0] === '`' && fenceMatch[2].includes('`'))) {
        fence = fenceMatch[1];
      }
    }

    if (wasFenced || fence !== null) {
      parts.push(line);
    } else {
      let cursor = index;
      while (cursor < lineEnd) {
        if (inComment) {
          const close = source.indexOf('%%', cursor);
          if (close < 0 || close >= lineEnd) {
            cursor = lineEnd;
            break;
          }
          inComment = false;
          cursor = close + 2;
          continue;
        }
        const char = source[cursor];
        if (char === '`') {
          let run = 1;
          while (cursor + run < lineEnd && source[cursor + run] === '`') run += 1;
          const marker = '`'.repeat(run);
          const close = source.indexOf(marker, cursor + run);
          if (close >= 0 && close + run <= lineEnd) {
            parts.push(source.slice(cursor, close + run));
            cursor = close + run;
            continue;
          }
          parts.push(marker);
          cursor += run;
          continue;
        }
        if (char === '%' && cursor + 1 < lineEnd && source[cursor + 1] === '%') {
          inComment = true;
          cursor += 2;
          continue;
        }
        parts.push(char);
        cursor += 1;
      }
    }

    if (newline >= 0) parts.push('\n');
    index = newline < 0 ? total : newline + 1;
  }

  return parts.join('');
}

/** 去掉值两端成对的引号（`"x"` / `'x'`）；不做转义还原。 */
function unquote(value: string): string {
  if (value.length >= 2) {
    const first = value[0];
    const last = value[value.length - 1];
    if ((first === '"' || first === "'") && last === first) return value.slice(1, -1);
  }
  return value;
}

/**
 * 最小 YAML 读取器：只认 `key: 值`、`key: [a, b]`、`- item` 块列表（多值 `, ` 连接）。
 *
 * 刻意不做的事：嵌套 map、多行 `|`/`>`、锚点/别名、行尾 `#` 注释、类型推断（全是 string）、
 * 重复 key 合并。够把常见的报告头信息显示出来就够了；复杂 YAML 由用户自己保证好看。
 */
function parseFrontmatterFields(lines: string[]): { key: string; value: string }[] {
  const fields: { key: string; value: string }[] = [];
  const positions = new Map<string, number>();
  let current: { key: string; value: string } | null = null;

  const appendItem = (item: string) => {
    if (current === null) return; // 没有归属 key 的 `- item`：最小读取器不猜
    current.value = current.value.length > 0 ? `${current.value}, ${item}` : item;
  };

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0) continue;

    if (line === '-' || line.startsWith('- ')) {
      appendItem(unquote(line.slice(1).trim()));
      continue;
    }

    const colon = line.indexOf(':');
    if (colon <= 0) continue; // 不是 `key: …`：忽略（不猜语义）
    const key = unquote(line.slice(0, colon).trim());
    if (key.length === 0) continue;

    const rawValue = line.slice(colon + 1).trim();
    let value: string;
    if (rawValue.startsWith('[') && rawValue.endsWith(']')) {
      value = rawValue
        .slice(1, -1)
        .split(',')
        .map((item) => unquote(item.trim()))
        .filter((item) => item.length > 0)
        .join(', ');
    } else {
      value = unquote(rawValue);
    }

    const existing = positions.get(key);
    if (existing === undefined) {
      positions.set(key, fields.length);
      const field = { key, value };
      fields.push(field);
      current = field;
    } else {
      // 重复 key：位置保持第一次出现的地方，值取最后一次（最小读取器的确定性选择）。
      fields[existing].value = value;
      current = fields[existing];
    }
  }

  return fields;
}

/**
 * 开头 `---` … `---` 之间的 frontmatter。**未闭合就当普通正文**（`---` 会变成分隔线，
 * 后面的 `key: value` 就是普通段落），这样半截粘贴的内容不会整段消失。
 */
function splitFrontmatter(body: string): { fields: { key: string; value: string }[] | null; rest: string } {
  const lines = body.split('\n');
  if (lines.length === 0 || lines[0].trim() !== '---') return { fields: null, rest: body };

  let close = -1;
  for (let index = 1; index < lines.length; index += 1) {
    if (lines[index].trim() === '---') {
      close = index;
      break;
    }
  }
  if (close < 0) return { fields: null, rest: body };

  return {
    fields: parseFrontmatterFields(lines.slice(1, close)),
    rest: lines.slice(close + 1).join('\n'),
  };
}

/* -------------------------------------------------------------------------- */
/* token → AST                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * 读 token 的字符串属性。markdown-it 的类型把属性值写成 `string | number`（渲染器会把数字原样
 * 输出），这里统一成字符串：AST 只承诺 `string`，渲染层不必再判类型。
 */
function attrString(token: Token, name: string): string | null {
  const value = token.attrGet(name);
  if (value === null || value === undefined) return null;
  return String(value);
}

function headingLevel(tag: string): 1 | 2 | 3 | 4 | 5 | 6 {
  const level = Number.parseInt(tag.slice(1), 10);
  if (level >= 1 && level <= 6) return level as 1 | 2 | 3 | 4 | 5 | 6;
  return 1;
}

/** 相邻的 text span 合并成一个（markdown-it 的 text_join 已经做了一轮，这里兜住插件造成的碎块）。 */
function pushText(spans: MarkdownSpan[], text: string): void {
  if (text.length === 0) return;
  const last = spans[spans.length - 1];
  if (last !== undefined && last.type === 'text') {
    spans[spans.length - 1] = { type: 'text', text: last.text + text };
    return;
  }
  spans.push({ type: 'text', text });
}

interface SpanFrame {
  type: 'strong' | 'em' | 'del' | 'link';
  href: string;
  spans: MarkdownSpan[];
}

function tokenMeta<T>(token: Token): Partial<T> {
  return (token.meta ?? {}) as Partial<T>;
}

/** 行内 token 序列 → span 序列。容器（strong/em/del/link）用显式栈配对，嵌套顺序由 token 决定。 */
function convertInline(children: Token[], env: Env): MarkdownSpan[] {
  const spans: MarkdownSpan[] = [];
  const stack: SpanFrame[] = [];
  const target = (): MarkdownSpan[] => (stack.length === 0 ? spans : stack[stack.length - 1].spans);

  for (const token of children) {
    switch (token.type) {
      case 'text':
        pushText(target(), token.content);
        break;
      case 'softbreak':
        target().push({ type: 'break', hard: false });
        break;
      case 'hardbreak':
        target().push({ type: 'break', hard: true });
        break;
      case 'code_inline':
        target().push({ type: 'code', text: token.content });
        break;
      case 'strong_open':
        stack.push({ type: 'strong', href: '', spans: [] });
        break;
      case 'em_open':
        stack.push({ type: 'em', href: '', spans: [] });
        break;
      case 's_open':
        stack.push({ type: 'del', href: '', spans: [] });
        break;
      case 'strong_close':
      case 'em_close':
      case 's_close': {
        const frame = stack.pop();
        if (frame === undefined) break;
        const type = token.type === 'strong_close' ? 'strong' : token.type === 'em_close' ? 'em' : 'del';
        target().push({ type, spans: frame.spans });
        break;
      }
      case 'link_open':
        stack.push({ type: 'link', href: attrString(token, 'href') ?? '', spans: [] });
        break;
      case 'link_close': {
        const frame = stack.pop();
        if (frame === undefined || frame.type !== 'link') break;
        target().push({
          type: 'link',
          href: frame.href,
          safe: isSafeLinkUrl(frame.href),
          spans: frame.spans,
        });
        break;
      }
      case 'image': {
        const src = attrString(token, 'src') ?? '';
        target().push({ type: 'image', src, alt: token.content, safe: isSafeLinkUrl(src) });
        break;
      }
      case 'obs_highlight': {
        // 高亮内容递归解析：`==**重点**==` 里仍然有粗体。
        const inner: Token[] = [];
        engine.inline.parse(token.content, engine, env, inner);
        target().push({ type: 'highlight', spans: convertInline(inner, env) });
        break;
      }
      case 'obs_math':
        target().push({ type: 'math', tex: token.content, display: false });
        break;
      case 'obs_tag':
        target().push({ type: 'tag', tag: token.content });
        break;
      case 'obs_wikilink': {
        const meta = tokenMeta<WikilinkMeta>(token);
        target().push({
          type: 'wikilink',
          target: meta.target ?? '',
          alias: meta.alias ?? null,
          anchor: meta.anchor ?? null,
        });
        break;
      }
      case 'obs_embed': {
        const meta = tokenMeta<EmbedMeta>(token);
        target().push({
          type: 'embed',
          target: meta.target ?? '',
          alias: meta.alias ?? null,
          anchor: meta.anchor ?? null,
          width: meta.width ?? null,
          height: meta.height ?? null,
        });
        break;
      }
      case 'html_inline':
        // html:false 下不该出现；真出现了也只当文字（永不产出 HTML 节点）。
        pushText(target(), token.content);
        break;
      default:
        // 未识别的行内 token（例如配对失败的 close）：忽略，不产生结构。
        break;
    }
  }

  return spans;
}

function inlineSpansOf(token: Token | undefined, env: Env): MarkdownSpan[] {
  if (token === undefined || token.type !== 'inline') return [];
  if (token.children === null) return [];
  return convertInline(token.children, env);
}

function codeBlockOf(token: Token): MarkdownBlock {
  if (token.type === 'code_block') {
    // 缩进代码块没有 info string，语言未知。
    return { type: 'code', lang: null, code: token.content, mermaid: false };
  }
  const info = typeof token.info === 'string' ? token.info.trim() : '';
  const first = info.length === 0 ? '' : info.split(/\s+/)[0].toLowerCase();
  const lang = first.length === 0 ? null : first;
  return { type: 'code', lang, code: token.content, mermaid: lang === 'mermaid' };
}

/** 表格单元格对齐：markdown-it 把对齐写成 `style="text-align:center"`。 */
function alignOf(token: Token): MarkdownAlign {
  const style = attrString(token, 'style');
  if (style === null) return null;
  if (style.includes('text-align:center')) return 'center';
  if (style.includes('text-align:right')) return 'right';
  if (style.includes('text-align:left')) return 'left';
  return null;
}

/** 把扁平 token 流（markdown-it 的块级结构就是扁平的）转成嵌套 AST。 */
function convertBlocks(tokens: Token[], env: Env): MarkdownBlock[] {
  let pos = 0;

  const parseUntil = (stopType: string | null): MarkdownBlock[] => {
    const blocks: MarkdownBlock[] = [];

    while (pos < tokens.length) {
      const token = tokens[pos];
      if (stopType !== null && token.type === stopType) {
        pos += 1;
        return blocks;
      }

      switch (token.type) {
        case 'heading_open': {
          const level = headingLevel(token.tag);
          const spans = inlineSpansOf(tokens[pos + 1], env);
          pos += 2;
          if (pos < tokens.length && tokens[pos].type === 'heading_close') pos += 1;
          blocks.push({ type: 'heading', level, spans });
          break;
        }
        case 'paragraph_open': {
          const spans = inlineSpansOf(tokens[pos + 1], env);
          pos += 2;
          if (pos < tokens.length && tokens[pos].type === 'paragraph_close') pos += 1;
          blocks.push({ type: 'paragraph', spans });
          break;
        }
        case 'bullet_list_open':
        case 'ordered_list_open': {
          const ordered = token.type === 'ordered_list_open';
          const startAttr = attrString(token, 'start');
          const start = ordered && startAttr !== null ? Number.parseInt(startAttr, 10) || 1 : 1;
          const stop = ordered ? 'ordered_list_close' : 'bullet_list_close';
          const items: MarkdownListItem[] = [];
          pos += 1;
          while (pos < tokens.length && tokens[pos].type !== stop) {
            const itemToken = tokens[pos];
            if (itemToken.type !== 'list_item_open') {
              pos += 1;
              continue;
            }
            const checkedRaw = tokenMeta<ListItemMeta>(itemToken).checked;
            pos += 1;
            const itemBlocks = parseUntil('list_item_close');
            const first = itemBlocks[0];
            const spans = first !== undefined && first.type === 'paragraph' ? first.spans : [];
            const rest = first !== undefined && first.type === 'paragraph' ? itemBlocks.slice(1) : itemBlocks;
            const item: MarkdownListItem = {
              spans,
              checked: typeof checkedRaw === 'boolean' ? checkedRaw : null,
            };
            if (rest.length > 0) item.blocks = rest;
            items.push(item);
          }
          if (pos < tokens.length) pos += 1;
          blocks.push({ type: 'list', ordered, start, items });
          break;
        }
        case 'blockquote_open': {
          pos += 1;
          const inner = parseUntil('blockquote_close');
          blocks.push({ type: 'blockquote', blocks: inner });
          break;
        }
        case 'callout_open': {
          const meta = tokenMeta<CalloutMeta>(token);
          pos += 1;
          const inner = parseUntil('blockquote_close');
          blocks.push({
            type: 'callout',
            kind: meta.kind ?? 'note',
            title: meta.title ?? '',
            fold: meta.fold ?? null,
            blocks: inner,
          });
          break;
        }
        case 'fence':
        case 'code_block':
          blocks.push(codeBlockOf(token));
          pos += 1;
          break;
        case 'math_block':
          blocks.push({ type: 'math', tex: token.content, display: true });
          pos += 1;
          break;
        case 'hr':
          blocks.push({ type: 'hr' });
          pos += 1;
          break;
        case 'table_open': {
          const align: MarkdownAlign[] = [];
          let header: MarkdownSpan[][] = [];
          const rows: MarkdownSpan[][][] = [];
          let currentRow: MarkdownSpan[][] | null = null;
          let inHead = false;
          pos += 1;
          while (pos < tokens.length && tokens[pos].type !== 'table_close') {
            const cell = tokens[pos];
            if (cell.type === 'thead_open') inHead = true;
            else if (cell.type === 'thead_close') inHead = false;
            else if (cell.type === 'tr_open') currentRow = [];
            else if (cell.type === 'tr_close') {
              if (currentRow !== null) {
                if (inHead && header.length === 0) header = currentRow;
                else rows.push(currentRow);
              }
              currentRow = null;
            } else if (cell.type === 'th_open') {
              align.push(alignOf(cell));
            } else if (cell.type === 'inline' && currentRow !== null) {
              currentRow.push(inlineSpansOf(cell, env));
            }
            pos += 1;
          }
          if (pos < tokens.length) pos += 1;
          blocks.push({ type: 'table', align, header, rows });
          break;
        }
        case 'html_block':
          // html:false 下不会出现；保留分支只为类型完整（永不由本解析器产生）。
          blocks.push({ type: 'html', text: token.content });
          pos += 1;
          break;
        default:
          // tbody/tr/td 等容器 token 已在表格分支内消费；其余未知 token 直接跳过。
          pos += 1;
          break;
      }
    }

    return blocks;
  };

  return parseUntil(null);
}

/**
 * 把一节正文解析成块序列。纯函数：不读全局状态、不改入参、结果只由 `body` 决定。
 *
 * 处理顺序很关键：
 * 1. `\r\n` / 孤立 `\r` 归一化成 `\n`（frontmatter 按行切分要靠它）；
 * 2. 开头 frontmatter（必须在注释剥离之前：frontmatter 里的 `%%` 是数据，不是注释）；
 * 3. `%%注释%%` 剥离（必须在块解析之前，见 `stripComments`）；
 * 4. markdown-it 解析 → token 流（任务列表 / callout 已在 inline 之前改写）；
 * 5. token → AST。
 */
export function parseMarkdown(body: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  // 类型上 body 是 string，但正文可能来自磁盘上的 JSON，运行时兜一层：非字符串当空正文。
  if (typeof body !== 'string' || body.length === 0) return blocks;

  const normalized = body.indexOf('\r') < 0 ? body : body.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const front = splitFrontmatter(normalized);
  // 空的 frontmatter（`---\n---`）不产出块：字段全被最小读取器忽略时，块本身没有任何信息，
  // 渲染层却会画出一个「属性 0」的空面板。没有字段就等于没有 frontmatter。
  if (front.fields !== null && front.fields.length > 0) blocks.push({ type: 'frontmatter', fields: front.fields });

  const source = stripComments(front.rest);
  if (source.trim().length === 0) return blocks;

  const env: Env = {};
  const tokens = engine.parse(source, env);
  blocks.push(...convertBlocks(tokens, env));
  return blocks;
}
