/**
 * 报告正文预览：AST（`markdown.ts`）→ React 元素，对齐 **Obsidian 阅读视图**。
 *
 * ## 职责边界
 * `markdown.ts` 只产出结构，本文件只把结构画出来：块的种类、列表嵌套、表格对齐、callout 配色、
 * 公式/图表/语法高亮的**呈现**都在这里。解析结论（什么是块、链接安全不安全、callout 归一到哪个
 * 类型）一律照抄 AST，本文件不重新判断任何语法。
 *
 * ## 为什么没有 dangerouslySetInnerHTML
 * 正文可能整段来自大模型。把字符串当 HTML 塞进 DOM，就等于让模型输出变成可执行入口。这里
 * 只有两条「库自己写 DOM」的通道，且都是库的公开 API：
 * 1. KaTeX：`katex.render(tex, node, …)` 自己往 ref 节点里写；
 * 2. Prism：`node.textContent = code` 之后 `Prism.highlightElement(node)`。
 *    Prism **确实**自己写 `innerHTML`（高亮标记是拼出来的），但它拼进去的只有自己 tokenizer 产生的
 *    `<span class="token …">`，正文一律先经 `Prism.util.encode` 转义成实体（`<script>` 变成
 *    `&lt;script&gt;` 再入 DOM），所以它不是「把字符串当 HTML」的入口。
 * 本文件自己产出的元素里没有一处写 HTML 字符串；Mermaid 的 `svg` 也是**用 DOMParser 解析后
 * importNode 追加**的，不经过 innerHTML。全仓库没有 `dangerouslySetInnerHTML`。
 *
 * ## 为什么链接不可点
 * 桌面端是 Tauri webview：CSP `default-src 'self'`，也没有「用系统浏览器打开外链」的能力。渲染真正的
 * `<a href="https://…">`，点击会让 webview 自己导航（界面被替换、没有地址栏也没有后退）。所以
 * 安全链接渲染成「标签 + 灰色（url）」——地址可见可复制但不可点；`safe:false` 的链接连地址都不显示，
 * 只留文字加一句 `title` 解释。全组件不产生任何 `<a>`。
 *
 * ## 刻意的偏差（都是产品决定）
 * 1. **软换行也渲染 `<br>`**：Obsidian 阅读视图默认把软换行显示成换行，正文又是「一行一件事」的
 *    纯文本，折叠成空格会把清单挤成一坨。因此 `break{hard:false}` 与 `hard:true` 一样处理，
 *    段落的 `white-space` 也从 `pre-wrap` 收回默认值（换行已由 span 表达）。
 * 2. **图片是文字占位**：CSP `img-src 'self' asset: data:` 载不到远程图片，渲染 `<img src="http…">`
 *    只会留一个碎图标。所以固定输出 `图片：alt（src）`。
 * 3. **wikilink / embed 是只读 chip**：报告里没有 vault，不做路径补全也不跳转，`title` 里说明。
 * 4. **标题的标签降三级**：页面标题是 `<h1>`、每节的标题是 `<h3>`。正文里的 `#` 若原样输出
 *    `<h1>`/`<h2>`，读屏大纲里正文标题会跑到页标题与节标题**上面**；只降一级也不够——`#` → `<h2>`
 *    仍在节标题（`<h3>`）之上、`##` → `<h3>` 与它平级。所以标签按 `h{min(level + 3, 6)}` 降三级
 *    （`#` → `<h4>`，`###` 及更深一律 `<h6>` 封顶），**正文标题永远在节标题之下**；视觉尺寸仍按
 *    作者写的层级取 `.reports-md-h{level}`，且全部 ≤ 节标题的 13.5px / 620（见 `reports.css`）。
 * 5. **callout 标题是纯文本**：AST 里 `title` 就是 string（解析器不重解标题里的粗体/链接），
 *    这里也不猜。`title` 与 `CALLOUT_TITLES[kind]` 相同时只显示一次，不重复标题文字。
 * 6. **表格按 GFM 切分**：表行里的每一个 `|` 都是列分隔符，**行内代码里的 `|` 也切**
 *    （`| \`a|b\` |` 会被切成两格）。Obsidian 不切，但 GFM 是这么规定的，本渲染器跟随 GFM。
 *
 * ## 懒加载
 * KaTeX / Mermaid / Prism 全部走 `import()`，模块级 promise 缓存（每份只加载一次），加载失败
 * 一律降级成纯文本 / 纯代码块，绝不让整节变空白。三者因此落在**独立的异步 chunk**，不进
 * reports 入口 chunk——报告列表里绝大多数正文没有公式和图表，不该为它们付这份下载。
 *
 * Mermaid 的 `initialize` 是全局配置（主题就烘在里面），所以**主题变化时重新 initialize 并重画**
 * 当前视图里的图：`MarkdownView` 用 MutationObserver 订阅 `<html data-theme>`，经 context 传下去，
 * 图自己重画（见 `initializeMermaid` / `MermaidDiagram`）。
 */
import { createContext, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import { CALLOUT_TITLES, parseMarkdown } from './markdown';
import type { MarkdownBlock, MarkdownListItem, MarkdownSpan } from './markdown';

/* ========================================================================== */
/* 懒加载的第三方渲染库                                                        */
/* ========================================================================== */

/** 只用到 `render`：KaTeX 的 `render(tex, node, options)` 直接往节点里写 DOM。 */
type KatexRuntime = Pick<typeof import('katex'), 'render'>;
type PrismRuntime = Pick<typeof import('prismjs'), 'languages' | 'highlightElement'>;
type MermaidRuntime = (typeof import('mermaid'))['default'];

/**
 * CJS / ESM 互操作：`import()` 拿到的命名空间可能把真正的 API 挂在 `default` 上，
 * 也可能直接摊平成命名导出。两边都认，取到哪个都能用。
 */
function unwrapKatex(loaded: typeof import('katex')): KatexRuntime | null {
  if (typeof loaded.render === 'function') return loaded;
  return loaded.default ?? null;
}

function unwrapPrism(module: PrismRuntime & { default?: PrismRuntime }): PrismRuntime | null {
  if (typeof module.highlightElement === 'function') return module;
  return module.default ?? null;
}

let katexLoader: Promise<KatexRuntime | null> | null = null;

/** KaTeX + 它的样式表：一次加载，失败缓存成 `null`（不再反复重试）。 */
function loadKatex(): Promise<KatexRuntime | null> {
  if (katexLoader === null) {
    katexLoader = Promise.all([import('katex'), import('katex/dist/katex.min.css')])
      .then(([loaded]) => unwrapKatex(loaded))
      .catch(() => null);
  }
  return katexLoader;
}

/**
 * Prism 的语言组件是**浏览器脚本**（`Prism.languages.python = …` 直接写全局 Prism），
 * `@types/prismjs` 只为 core 和 `components/index` 提供声明，所以逐个 import 时显式忽略类型检查。
 *
 * 顺序不能乱：组件之间靠全局 Prism 互相 `extend`（javascript 依赖 clike，jsx 依赖 markup +
 * javascript，tsx 依赖 jsx + typescript）。串行 await 是最省心的保证方式，13 个组件都是几 KB，
 * 串行代价远小于「顺序错了导致高亮静默失效」。
 */
async function loadPrismLanguages(): Promise<void> {
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-markup');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-css');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-clike');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-javascript');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-typescript');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-jsx');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-tsx');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-python');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-bash');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-json');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-yaml');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-sql');
  // @ts-expect-error prismjs 没有为单个语言组件提供类型声明
  await import('prismjs/components/prism-markdown');
}

let prismLoader: Promise<PrismRuntime | null> | null = null;

/** Prism core + 13 个语言组件。加载失败 / 部分组件缺失都只是「没有高亮」，代码照样完整。 */
function loadPrism(): Promise<PrismRuntime | null> {
  if (prismLoader === null) {
    prismLoader = (async () => {
      try {
        // Prism core 会在 DOMContentLoaded 之后自动高亮整页。我们只手动高亮自己的代码块，
        // 所以载入前先在全局立一个 `manual: true`（core 会读它并继承到自己的配置上）。
        // 这里只是**占位**，不是 Prism 本体（见下面写回真正的模块）。
        const scope = window as Window & { Prism?: Partial<PrismRuntime> & { manual?: boolean } };
        if (scope.Prism === undefined) scope.Prism = { manual: true };
        const loaded = (await import('prismjs')) as PrismRuntime & { default?: PrismRuntime };
        const prism = unwrapPrism(loaded);
        if (prism === null) return null;
        // 语言组件是**浏览器脚本**：它们没有 `import`，只写全局 `Prism.languages.xxx`
        // （jsx/tsx 还会 `Prism.languages.extend(...)` 已有的 clike/javascript），所以全局上必须是
        // **真的** Prism，而不是上面那个 `{manual:true}` 占位。core 自己末尾也会执行
        // `_self.Prism = _`（prism.js 的 IIFE 内），也就是说现在能跑其实靠的是这个内部副作用；
        // 那是实现细节、不是 API：一旦它消失（或某个 bundler 把组件排在 core 之前求值），组件会读到
        // 没有 `languages` 的占位对象，注册直接 TypeError → 被下面的 catch 吞掉 → 代码块静默没有高亮。
        // 所以这里显式写回真正的模块，把顺序保证握在我们自己手里（生产里只是把同一个对象再赋一次）。
        scope.Prism = prism;
        await loadPrismLanguages();
        return prism;
      } catch {
        return null;
      }
    })();
  }
  return prismLoader;
}

/** Mermaid 的主题跟着 AppShell 写到 `<html data-theme>` 上的值走。 */
type MermaidTheme = 'default' | 'dark';

function readMermaidTheme(): MermaidTheme {
  // 单测 / SSR 里没有 document：当成浅色（这条路径只在浏览器里真正被调用）。
  if (typeof document === 'undefined') return 'default';
  return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'default';
}

/** 最近一次真正 `initialize` 用的主题；换主题才需要重跑（见 `initializeMermaid`）。 */
let mermaidThemeApplied: MermaidTheme | null = null;

/**
 * `initialize` 对 mermaid 是**全局**配置：主题被烘进内部状态和每次 render 的产物里，所以切主题必须
 * 重新 initialize 再重画，光靠 CSS 改不动图里的填充色。
 *
 * - `suppressErrorRendering: true`：mermaid 12 出错时默认会往 `<body>` 里塞一个临时节点
 *   （`<div id="d…">`）再把它留着；我们自己已经有「源码 + 灰色说明」的兜底，不需要它再插一手。
 * - 幂等：主题没变就跳过。重复 initialize 会重建内部配置（也会重复注册图类型），只在必要时做。
 */
function initializeMermaid(mermaid: MermaidRuntime, theme: MermaidTheme): void {
  if (mermaidThemeApplied === theme) return;
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    suppressErrorRendering: true,
    theme,
  });
  mermaidThemeApplied = theme;
}

let mermaidLoader: Promise<MermaidRuntime | null> | null = null;

/**
 * 只负责**加载**和首次 initialize。之后主题变化由 `MermaidDiagram` 在重画前调用
 * `initializeMermaid` 补上（同一个 loader 复用，不重新 import）。
 */
function loadMermaid(): Promise<MermaidRuntime | null> {
  if (mermaidLoader === null) {
    mermaidLoader = import('mermaid')
      .then((loaded) => {
        const mermaid: MermaidRuntime | undefined = loaded.default;
        if (mermaid === undefined) return null;
        initializeMermaid(mermaid, readMermaidTheme());
        return mermaid;
      })
      .catch(() => null);
  }
  return mermaidLoader;
}

/** Mermaid 要求每次 render 的 id 全局唯一（它用 id 建临时节点、也写进 svg 的 aria 引用）。 */
let mermaidRenderSeq = 0;

/**
 * 当前主题。主题是**文档级**状态（AppShell 只改 `<html data-theme>`），预览可能同时存在多份
 * （每节一个），用 context 比逐层传 prop 更省事：`MermaidDiagram` 自己订阅，切主题就重画自己那张图。
 */
const MermaidThemeContext = createContext<MermaidTheme>('default');

/* ========================================================================== */
/* 懒加载渲染组件                                                              */
/* ========================================================================== */

type AsyncStatus = 'loading' | 'ready' | 'failed';

/**
 * 公式槽：KaTeX 只往 ref 节点里写，React 不碰那个节点。
 *
 * 三种状态各有兜底：加载中显示原始 TeX（不闪空白）；成功就把兜底摘掉；失败/库没加载成功时
 * 把原始 TeX 留在 `<code>` 里——公式至少还能读。
 */
function MathSlot({ tex, display }: { tex: string; display: boolean }) {
  const nodeRef = useRef<HTMLSpanElement | null>(null);
  const [status, setStatus] = useState<AsyncStatus>('loading');

  useEffect(() => {
    let cancelled = false;
    void loadKatex().then((katex) => {
      const node = nodeRef.current;
      if (cancelled || node === null) return;
      if (katex === null) {
        setStatus('failed');
        return;
      }
      try {
        katex.render(tex, node, { displayMode: display, throwOnError: false, strict: 'ignore' });
        if (!cancelled) setStatus('ready');
      } catch {
        if (!cancelled) setStatus('failed');
      }
    });
    return () => {
      cancelled = true;
    };
  }, [tex, display]);

  const fallback =
    status === 'ready' ? null : (
      <code className="reports-md-code reports-md-math-src" aria-label="公式原文">
        {tex}
      </code>
    );
  const body = (
    <>
      <span className="reports-md-math-node" ref={nodeRef} />
      {fallback}
    </>
  );

  return display ? (
    <div className="reports-md-math reports-md-math-display" data-status={status}>
      {body}
    </div>
  ) : (
    <span className="reports-md-math reports-md-math-inline" data-status={status}>
      {body}
    </span>
  );
}

/**
 * 代码块：Prism 高亮是**渐进增强**。
 *
 * 布局阶段先把纯文本写进 `<code>`（首帧就是完整代码，不留空白），随后异步拿到 Prism 再
 * `highlightElement`。未知语言 / 加载失败 / 组件没装到 → 保持纯文本，什么都不提示。
 */
function CodeBlock({ lang, code }: { lang: string | null; code: string }) {
  const codeRef = useRef<HTMLElement | null>(null);

  useLayoutEffect(() => {
    const node = codeRef.current;
    if (node === null) return;
    let cancelled = false;
    // 先给纯文本：高亮失败时这里就是最终形态。
    node.textContent = code;
    if (lang === null) return;
    void loadPrism().then((prism) => {
      if (cancelled || prism === null || codeRef.current === null) return;
      const grammar = (prism.languages as Record<string, unknown>)[lang];
      if (grammar === undefined) return;
      try {
        prism.highlightElement(codeRef.current);
      } catch {
        // Prism 自己也会吞异常；这里再兜一层，保证「没有高亮」而不是「没有代码」。
      }
    });
    return () => {
      cancelled = true;
    };
  }, [lang, code]);

  return (
    <pre
      className="reports-md-pre"
      // 横向滚动的代码块要能被键盘聚焦，否则纯键盘用户滚不到被裁掉的部分。
      tabIndex={0}
      aria-label={lang === null ? '代码块' : `代码块（${lang}）`}
    >
      <code
        className={lang === null ? 'reports-md-codeblock' : `reports-md-codeblock language-${lang}`}
        ref={codeRef}
      />
    </pre>
  );
}

/**
 * Mermaid 图：`mermaid.render()` 只给我们一段 svg **字符串**。这段字符串不经过 innerHTML——
 * 用 DOMParser 解析成 SVG 文档，再 `importNode` 追加进容器，浏览器因此只把 `<svg>` 子树挂上去。
 * 失败时保留原始代码 + 一行灰色说明，用户还能看到自己写的图定义。
 *
 * 主题进 effect 依赖：`initialize` 是全局的、主题被烘进 render 产物，所以切主题时这个 effect 重跑，
 * 先按新主题重新 initialize（幂等），再用新的唯一 id 重画这一张图；旧的 svg 一直留在原地直到新图
 * 顶上来（不闪空白），卸载时 `cancelled` 保证迟到的那次 render 不会再写进 DOM。
 */
function MermaidDiagram({ code }: { code: string }) {
  const canvasRef = useRef<HTMLDivElement | null>(null);
  const [status, setStatus] = useState<AsyncStatus>('loading');
  const theme = useContext(MermaidThemeContext);

  useEffect(() => {
    let cancelled = false;
    void loadMermaid().then(async (mermaid) => {
      if (cancelled) return;
      if (mermaid === null) {
        setStatus('failed');
        return;
      }
      // 主题变了才真正重新 initialize；随后重画，让图里的填充/边框跟着走。
      initializeMermaid(mermaid, theme);
      mermaidRenderSeq += 1;
      const id = `reports-md-mermaid-${mermaidRenderSeq}`;
      try {
        const { svg } = await mermaid.render(id, code);
        const canvas = canvasRef.current;
        if (cancelled || canvas === null) return;
        const parsed = new DOMParser().parseFromString(svg, 'image/svg+xml');
        if (parsed.querySelector('parsererror') !== null) throw new Error('mermaid svg 解析失败');
        canvas.replaceChildren(document.importNode(parsed.documentElement, true));
        if (!cancelled) setStatus('ready');
      } catch {
        if (!cancelled) setStatus('failed');
      }
    });
    return () => {
      cancelled = true;
    };
  }, [code, theme]);

  return (
    <div className="reports-md-mermaid" data-status={status}>
      <div className="reports-md-mermaid-canvas" ref={canvasRef} role="img" aria-label="Mermaid 图表" />
      {status === 'ready' ? null : (
        <pre className="reports-md-pre reports-md-mermaid-src" tabIndex={0} aria-label="Mermaid 源码">
          <code className="reports-md-codeblock">{code}</code>
        </pre>
      )}
      {status === 'failed' ? <p className="reports-md-mermaid-note">Mermaid 渲染失败</p> : null}
    </div>
  );
}

/* ========================================================================== */
/* 行内 span                                                                   */
/* ========================================================================== */

/** 行内 span → 元素。`key` 用 span 下标（AST 只由 `body` 决定，顺序稳定）。 */
function renderSpan(span: MarkdownSpan, key: number): ReactNode {
  switch (span.type) {
    case 'text':
      return span.text;
    case 'strong':
      return <strong key={key}>{span.spans.map(renderSpan)}</strong>;
    case 'em':
      return <em key={key}>{span.spans.map(renderSpan)}</em>;
    case 'del':
      return <del key={key}>{span.spans.map(renderSpan)}</del>;
    case 'highlight':
      return (
        <mark className="reports-md-mark" key={key}>
          {span.spans.map(renderSpan)}
        </mark>
      );
    case 'code':
      return (
        <code className="reports-md-code" key={key}>
          {span.text}
        </code>
      );
    case 'break':
      // hard / soft 都渲染 <br>：Obsidian 阅读视图默认把软换行也当换行（见文件头「刻意的偏差」）。
      return <br key={key} />;
    case 'link':
      return span.safe ? (
        <span className="reports-md-link" key={key}>
          {span.spans.map(renderSpan)}
          <span className="reports-md-link-url">（{span.href}）</span>
        </span>
      ) : (
        <span
          className="reports-md-link-rejected"
          key={key}
          title="链接已拦截：只认 http(s) 与 mailto，其余协议与相对路径只保留文字"
        >
          {span.spans.map(renderSpan)}
        </span>
      );
    case 'image':
      // 不渲染 <img src="http…">：CSP 的 img-src 载不到远程图片，占位文字至少把 alt 和地址留住。
      return (
        <span className="reports-md-image" key={key} title="远程图片不会被加载（CSP 只允许本地资源）">
          {`图片：${span.alt}（${span.src}）`}
        </span>
      );
    case 'wikilink': {
      const anchor = span.anchor === null ? '' : `#${span.anchor}`;
      const alias = span.alias === null ? '' : `|${span.alias}`;
      return (
        <span className="reports-md-wikilink" key={key} title="报告内没有库，链接不会跳转">
          {`[[${span.target}${anchor}${alias}]]`}
        </span>
      );
    }
    case 'embed': {
      const size =
        span.width === null ? '' : span.height === null ? `${span.width}` : `${span.width}×${span.height}`;
      const suffix = [size, span.alias ?? ''].filter((part) => part.length > 0).join(' · ');
      // 锚点（含 `#^块引用` 的 `^`）原样显示：嵌入的是「哪个标题」，是用户判断内容的一部分。
      const anchor = span.anchor === null ? '' : `#${span.anchor}`;
      return (
        <span className="reports-md-embed" key={key} title="报告内没有库，嵌入内容不会加载">
          {`嵌入：${span.target}${anchor}${suffix.length > 0 ? `（${suffix}）` : ''}`}
        </span>
      );
    }
    case 'tag':
      return (
        <span className="reports-md-tag" key={key}>
          {`#${span.tag}`}
        </span>
      );
    case 'math':
      return <MathSlot key={key} tex={span.tex} display={false} />;
    default:
      // 未知 span（解析器先加、渲染器还没跟上）：只保证文字不丢，绝不让整段消失。
      return typeof (span as { text?: unknown }).text === 'string' ? (span as { text: string }).text : null;
  }
}

/* ========================================================================== */
/* 块                                                                          */
/* ========================================================================== */

/**
 * 正文标题的**标签**整体比作者写的层级低三级（见文件头偏差 4）：页面标题是 `<h1>`、本页的节标题
 * 是 `<h3>`，正文标题必须排在两者**之下**才不会把文档大纲读反。只降一级不够——`#` → `<h2>` 仍在
 * 节标题（`<h3>`）之上，`##` → `<h3>` 与节标题平级。所以按 `min(level + 3, 6)`：
 * `#` → `<h4>`、`##` → `<h5>`、`###` 及更深 → `<h6>`（6 级封顶，不再往下溢出）。
 * 视觉尺寸仍按**作者写的层级**取 `.reports-md-h{level}`，样式表里每一级都 ≤ 节标题的 13.5px。
 */
const HEADING_TAGS = {
  1: 'h4',
  2: 'h5',
  3: 'h6',
  4: 'h6',
  5: 'h6',
  6: 'h6',
} as const;

/** callout 的装饰性字符：都是几何/标点符号（不是 emoji），读屏一律 `aria-hidden`。 */
const CALLOUT_GLYPHS: Record<string, string> = {
  note: '●',
  abstract: '▤',
  info: 'i',
  todo: '☐',
  tip: '✦',
  success: '✓',
  question: '?',
  warning: '!',
  failure: '✕',
  danger: '▲',
  bug: '✳',
  example: '≡',
  quote: '“',
};

function renderItem(item: MarkdownListItem, index: number): ReactNode {
  const blocks = item.blocks ?? [];
  if (item.checked === null) {
    return (
      <li className="reports-md-item" key={index}>
        {item.spans.map(renderSpan)}
        {blocks.length === 0 ? null : <div className="reports-md-item-blocks">{blocks.map(renderBlock)}</div>}
      </li>
    );
  }
  return (
    <li className="reports-md-item reports-md-task" key={index}>
      <input
        type="checkbox"
        className="reports-md-check"
        checked={item.checked}
        disabled
        readOnly
        aria-label={item.checked ? '已完成' : '未完成'}
      />
      {/* 包装层与嵌套容器都用 <div>：`reports-md-item-blocks` 里是块级元素（列表/段落/代码），
          放在 <span> 里是非法嵌套（浏览器会自行拆开，React 也会警告）。与上面的非任务分支一致。 */}
      <div className="reports-md-task-body">
        {item.spans.map(renderSpan)}
        {blocks.length === 0 ? null : <div className="reports-md-item-blocks">{blocks.map(renderBlock)}</div>}
      </div>
    </li>
  );
}

function CalloutBlock({ block }: { block: Extract<MarkdownBlock, { type: 'callout' }> }) {
  const defaultLabel = CALLOUT_TITLES[block.kind];
  const title = block.title.length > 0 ? block.title : (defaultLabel ?? block.kind);
  // 标题与类型默认名一致时（`[!note]` 没写标题）只显示一次；写了自定义标题才补一个类型徽标。
  const showKindLabel = defaultLabel !== undefined && title !== defaultLabel;
  const head = (
    <>
      <span className="reports-md-callout-glyph" aria-hidden="true">
        {CALLOUT_GLYPHS[block.kind] ?? '●'}
      </span>
      <span className="reports-md-callout-title">{title}</span>
      {showKindLabel ? <span className="reports-md-callout-kind">{defaultLabel}</span> : null}
    </>
  );
  const body = <div className="reports-md-callout-body">{block.blocks.map(renderBlock)}</div>;

  return (
    <div className="reports-md-callout" data-kind={block.kind}>
      {block.fold === null ? (
        <>
          <div className="reports-md-callout-head">{head}</div>
          {body}
        </>
      ) : (
        // <details>/<summary> 是原生的可折叠语义：键盘可操作、读屏会报展开状态，不用自己造开关。
        <details className="reports-md-callout-fold" open={block.fold === 'open'}>
          <summary className="reports-md-callout-head">{head}</summary>
          {body}
        </details>
      )}
    </div>
  );
}

function FrontmatterBlock({ fields }: { fields: { key: string; value: string }[] }) {
  return (
    <details className="reports-md-frontmatter">
      <summary className="reports-md-frontmatter-summary">
        <span>属性</span>
        <span className="reports-md-frontmatter-count">{fields.length}</span>
      </summary>
      <dl className="reports-md-frontmatter-list">
        {fields.map((field, index) => (
          <div className="reports-md-frontmatter-row" key={index}>
            <dt>{field.key}</dt>
            <dd>{field.value}</dd>
          </div>
        ))}
      </dl>
    </details>
  );
}

/** 块 → 元素。列表项与 callout 体走同一套递归，因此嵌套多深都一样。 */
function renderBlock(block: MarkdownBlock, key: number): ReactNode {
  switch (block.type) {
    case 'heading': {
      const Tag = HEADING_TAGS[block.level];
      return (
        <Tag className={`reports-md-h${block.level}`} key={key}>
          {block.spans.map(renderSpan)}
        </Tag>
      );
    }
    case 'paragraph':
      return (
        <p className="reports-md-p" key={key}>
          {block.spans.map(renderSpan)}
        </p>
      );
    case 'list': {
      const items = block.items.map(renderItem);
      return block.ordered ? (
        <ol className="reports-md-list reports-md-ordered" key={key} start={block.start}>
          {items}
        </ol>
      ) : (
        <ul className="reports-md-list reports-md-bullet" key={key}>
          {items}
        </ul>
      );
    }
    case 'blockquote':
      return (
        <blockquote className="reports-md-quote" key={key}>
          {block.blocks.map(renderBlock)}
        </blockquote>
      );
    case 'callout':
      return <CalloutBlock block={block} key={key} />;
    case 'code':
      return block.mermaid ? (
        <MermaidDiagram code={block.code} key={key} />
      ) : (
        <CodeBlock lang={block.lang} code={block.code} key={key} />
      );
    case 'math':
      return <MathSlot tex={block.tex} display key={key} />;
    case 'table': {
      // 每列的对齐来自 GFM 的三向标记；`textAlign` 写在 th/td 上（内联样式优先级高于表头底色规则）。
      const cellStyle = (index: number): CSSProperties => {
        const align = block.align[index];
        return align === null || align === undefined ? {} : { textAlign: align };
      };
      return (
        <div className="reports-md-table-wrap" key={key}>
          <table className="reports-md-table">
            <thead>
              <tr>
                {block.header.map((cell, index) => (
                  <th key={index} scope="col" style={cellStyle(index)}>
                    {cell.map(renderSpan)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((row, rowIndex) => (
                <tr key={rowIndex}>
                  {row.map((cell, cellIndex) => (
                    <td key={cellIndex} style={cellStyle(cellIndex)}>
                      {cell.map(renderSpan)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    case 'hr':
      return <hr className="reports-md-hr" key={key} />;
    case 'frontmatter':
      return <FrontmatterBlock fields={block.fields} key={key} />;
    case 'html':
      // 解析器从不产出该块（HTML 一律当文字）；这里只保类型完整。
      return (
        <p className="reports-md-p" key={key}>
          {block.text}
        </p>
      );
    default:
      return null;
  }
}

export interface MarkdownViewProps {
  /** 该节正文的原始 Markdown 纯文本（与编辑框、导出用的是同一份字符串）。 */
  body: string;
  /** 预览区可访问名：调用方拼「预览：<节名>」，屏幕阅读器据此知道这是哪一节。 */
  ariaLabel: string;
}

export function MarkdownView({ body, ariaLabel }: MarkdownViewProps) {
  // 正文一变就重解析；其它 prop 变化不重算（解析是纯函数，缓存 key 就是正文本身）。
  const blocks = useMemo(() => parseMarkdown(body), [body]);

  /*
   * 主题跟着 `<html data-theme>` 走。AppShell 切主题只改这一个属性、不重挂载预览，所以必须**订阅**
   * 而不是在挂载时读一次：用 MutationObserver 观察 attributes（只筛 data-theme），变化就更新 state，
   * 把新主题经 context 传给每张 mermaid 图（图自己重新 initialize + 重画）。
   * 卸载时 disconnect：预览会随「编辑/预览」切换反复挂载。
   */
  const [theme, setTheme] = useState<MermaidTheme>(readMermaidTheme);
  useEffect(() => {
    // 挂载与 observer 建立之间有窗口期：先同步对齐一次，避免漏掉刚发生的变化。
    setTheme(readMermaidTheme());
    if (typeof MutationObserver === 'undefined') return;
    const observer = new MutationObserver(() => setTheme(readMermaidTheme()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return () => observer.disconnect();
  }, []);

  return (
    <MermaidThemeContext.Provider value={theme}>
      <div className="reports-md" role="region" aria-label={ariaLabel}>
        {blocks.length === 0 ? (
          <p className="reports-md-empty">本节暂无内容</p>
        ) : (
          blocks.map(renderBlock)
        )}
      </div>
    </MermaidThemeContext.Provider>
  );
}
