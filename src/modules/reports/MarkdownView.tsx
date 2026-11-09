/**
 * 报告正文的 Markdown 预览（薄渲染层：解析全在 `markdown.ts`，这里只做「结构 → 元素」映射）。
 *
 * ## 为什么没有 dangerouslySetInnerHTML
 * 正文可能整段来自大模型。任何「把字符串当 HTML 塞进 DOM」的写法都会让模型输出变成
 * 可执行入口。这里只把 `parseMarkdown` 的结构映射成 React 元素，转义交给 React：正文里的
 * `<img onerror=…>` 只会显示成字面量，不会成为节点。
 *
 * ## 为什么链接不是 <a href>
 * 桌面端是 Tauri webview：CSP 为 `default-src 'self'`，且只装了 dialog 插件，**没有
 * 「用系统浏览器打开外链」的 API**（无 shell.open / openExternal）。此时渲染真正的
 * `<a href="https://…">`，点击只会让 webview 自己导航到外站——应用界面被替换，没有地址栏
 * 也没有后退，等于把当前报告弄丢。所以链接渲染成「标签 + 灰色（url）」：地址原样可见、
 * 可复制，但不可点。等哪天接了 openExternal 能力，只需改这一处 `renderSpan`。
 *
 * ## 为什么标题降一级
 * 每节自己的标题已经是 `<h3>`（见 ReportEditor 的 section head）。正文里的 `###` 是
 * 「节内小标题」，语义上应嵌在节标题之下，因此映射为 `<h4>`；`####` 映射为 `<h5>`。
 * class 名仍按 Markdown 级数命名（`reports-md-h3` / `reports-md-h4`），这样样式与测试都
 * 对着「源语法」而不是 DOM 标签，以后调标签层级不会连带动样式。
 */
import { useMemo } from 'react';
import type { ReactNode } from 'react';
import { parseMarkdown } from './markdown';
import type { MarkdownBlock, MarkdownSpan } from './markdown';

/**
 * 行内 span → 元素。
 *
 * `key` 用 span 在数组里的下标：内容只由 `body` 决定、span 本身无状态，同一份正文每次
 * 解析出的顺序完全一致，用下标不会引起错位（真正的 memo 边界在下面的 `useMemo`）。
 */
function renderSpan(span: MarkdownSpan, key: number): ReactNode {
  switch (span.type) {
    case 'strong':
      return (
        <strong className="reports-md-strong" key={key}>
          {span.text}
        </strong>
      );
    case 'code':
      return (
        <code className="reports-md-code" key={key}>
          {span.text}
        </code>
      );
    case 'link':
      return (
        <span className="reports-md-link" key={key}>
          {span.label}
          <span className="reports-md-link-url">（{span.url}）</span>
        </span>
      );
    default:
      // 剩下只可能是 text（union 已穷尽）：直接交给 React 转义，不加额外节点，
      // `pre-wrap` 才能原样呈现段落内的换行。
      return span.text;
  }
}

/** 块 → 元素。块种类只有三种，这里刻意不引入任何配置化抽象。 */
function renderBlock(block: MarkdownBlock, key: number): ReactNode {
  switch (block.type) {
    case 'heading':
      return block.level === 3 ? (
        <h4 className="reports-md-h3" key={key}>
          {block.spans.map(renderSpan)}
        </h4>
      ) : (
        <h5 className="reports-md-h4" key={key}>
          {block.spans.map(renderSpan)}
        </h5>
      );
    case 'list':
      return (
        <ul className="reports-md-list" key={key}>
          {block.items.map((item, index) => (
            <li key={index}>{item.spans.map(renderSpan)}</li>
          ))}
        </ul>
      );
    case 'paragraph':
      return (
        <p className="reports-md-p" key={key}>
          {block.spans.map(renderSpan)}
        </p>
      );
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

  return (
    <div className="reports-md" role="region" aria-label={ariaLabel}>
      {blocks.length === 0 ? (
        <p className="reports-md-empty">本节暂无内容</p>
      ) : (
        blocks.map(renderBlock)
      )}
    </div>
  );
}
