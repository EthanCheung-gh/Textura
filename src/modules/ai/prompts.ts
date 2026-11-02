/**
 * 报告生成的提示词层（纯函数，无网络、无副作用）。
 *
 * 职责边界：
 * - 本文件**不写人格设定**：系统提示词一律来自 `AiConfig.systemPrompt`，由调用方
 *   作为 `{ role: 'system' }` 注入 messages 头；这里只产出 user 内容与输出约束；
 * - 只发「紧凑事实摘要」，绝不把整个工作区塞进上下文：`buildFactsDigest` 只用
 *   facts 的 title / meta / line 与 stats，按 kind 设上限，超出写「另有 N 条略」；
 * - 摘要总长受 `MAX_DIGEST_CHARS` 约束，超预算时按整条丢弃并在末尾注明省略数量。
 *
 * 长度口径（唯一真源）：
 * - `MAX_DIGEST_CHARS`、`DIGEST_NOTE_RESERVE`、单行裁剪与 `push` 的预算判定
 *   **全部按 UTF-16 长度计**（即 `String.length`，也是 `text.length`）；
 * - 不用码点（`[...text].length`）计数：代理对（emoji 等）按 2 计，`slice` / `length`
 *   天然同一口径，避免「显示还有余量、实际已到上限」；
 * - UI 侧的 `digestSizeText` 也按 `.length` 显示，两边共用同一个口径。
 *
 * 输出契约：
 * - 单节生成：只输出该节正文（Markdown 列表，不重复节标题，不编造数据）；
 * - 整份生成：严格 JSON 数组 `[{"key":"overview","body":"..."}]`，key 只允许模板节 key；
 * - 中文文案，与项目风格一致，不使用 emoji。
 */
import { REPORT_TEMPLATES, templateFor } from '../reports/draft';
import type { FactKind, ReportFactsDetailed } from '../reports/facts';
import { AiRequestError } from './client';
import type { AiMessage } from './client';

export interface ReportAiContext {
  kind: 'week' | 'month' | 'quarter';
  /** 如 `2026 年第 44 周`。 */
  periodLabel: string;
  range: { start: string; end: string } | null;
  author: string;
  facts: ReportFactsDetailed;
  /** 模板节（key / title / 当前正文），由调用方按 `templateFor(kind)` 提供。 */
  sections: { key: string; title: string; body: string }[];
}

/**
 * 摘要硬预算。留给模型的是事实，不是整个工作区。
 *
 * 口径是 **UTF-16 长度（`String.length`）**，与 `buildFactsDigest` 内部的预算判定、
 * 单行裁剪以及 UI 的 `digestSizeText` 完全一致；代理对（emoji）按 2 计。
 */
export const MAX_DIGEST_CHARS = 4000;

/** 摘要里每类事实的条目上限（与报告素材上限对齐）。 */
export const DIGEST_KIND_LIMITS: Record<FactKind, number> = {
  completed: 30,
  risk: 20,
  kr: 10,
  run: 10,
  nextUp: 10,
};

const DIGEST_KIND_TITLES: Record<FactKind, string> = {
  completed: '完成事项',
  risk: '风险与阻塞',
  kr: '关键结果',
  run: 'SOP 运行',
  nextUp: '下周期排期',
};

const FACT_KIND_ORDER: FactKind[] = ['completed', 'risk', 'kr', 'run', 'nextUp'];

/** 给末尾「另有 N 条略」预留的字符数（含换行）。 */
const DIGEST_NOTE_RESERVE = 32;
/** 单条事实行的长度上限，避免一条超长标题吃光预算。 */
const MAX_DIGEST_LINE_CHARS = 200;
const MAX_HEADER_VALUE_CHARS = 120;

const REPORT_TYPE_LABELS: Record<ReportAiContext['kind'], string> = {
  week: '周报',
  month: '月报',
  quarter: '季报',
};

/** 各节的写作范围提示（只说「写什么」，不写「你是谁」）。 */
const SECTION_SCOPES: Record<string, string> = {
  overview: '用三到五条概述本周期整体产出与节奏，只做归纳，不重复罗列明细。',
  progress: '按完成情况归纳关键进展，同类事项可合并成一条，突出结果而非过程。',
  okr: '围绕目标与关键结果写明完成度与偏差，没有目标时直接说明本周期未设置目标。',
  metrics: '只使用事实摘要里的量化数据（关键结果、SOP 运行次数等），不要估算或推算。',
  risks: '按超期、停滞、等待、未排期分类列出风险与阻塞，必要时给出可执行的处理建议。',
  next: '根据下周期排期给出计划，没有排期就明确说明尚未排期。',
  support: '写出需要的支持、决策或资源；摘要里没有依据的内容不要编造，可标注为待补充。',
};

function clipText(value: string, max: number): string {
  const text = value.trim();
  if (text.length <= max) return text;
  let cut = text.slice(0, Math.max(1, max - 1));
  // 不在代理对中间切断：否则留下孤立的高位代理，提示词里会出现乱码字符。
  const lastUnit = cut.charCodeAt(cut.length - 1);
  if (lastUnit >= 0xd800 && lastUnit <= 0xdbff) cut = cut.slice(0, -1);
  return `${cut}…`;
}

function resolveSections(
  ctx: ReportAiContext,
): { key: string; title: string; body?: string }[] {
  if (ctx.sections.length > 0) return ctx.sections;
  // 调用方没给节时回落到模板，保证 key 清单始终来自模板而不是凭空的字符串。
  return templateFor(ctx.kind).sections;
}

function headerLines(ctx: ReportAiContext): string[] {
  const { stats, runCounts } = ctx.facts;
  const period = clipText(ctx.periodLabel, MAX_HEADER_VALUE_CHARS) || '未命名周期';
  const range = ctx.range
    ? `（${clipText(ctx.range.start, 32)} 至 ${clipText(ctx.range.end, 32)}）`
    : '';
  const author = clipText(ctx.author, MAX_HEADER_VALUE_CHARS) || '未署名';
  return [
    `报告类型：${REPORT_TYPE_LABELS[ctx.kind]}`,
    `周期：${period}${range}`,
    `作者：${author}`,
    `概览：完成 ${stats.completed} 项 · 进行中 ${stats.openInWindow} 项 · 风险 ${stats.risks} 项 · 收件箱剩余 ${stats.inboxRemaining} 项 · 清理进度 ${stats.inboxProgress}%`,
    runCounts.total === 0
      ? 'SOP 运行：本周期无运行记录'
      : `SOP 运行：共 ${runCounts.total} 次 · 通过 ${runCounts.pass} · 失败 ${runCounts.fail} · 跳过 ${runCounts.skip}`,
  ];
}

/**
 * 紧凑事实摘要：头部统计 + 按 kind 分组的条目行。
 *
 * 预算策略：头部永远保留（本身很短），条目按 `DIGEST_KIND_LIMITS` 先裁上限，
 * 再从头逐行装入预算；装不下的条目不写入，统一在末尾写一次「另有 N 条略」。
 * 因此返回值 `text.length`（UTF-16 长度）恒 ≤ `MAX_DIGEST_CHARS`。
 */
export function buildFactsDigest(ctx: ReportAiContext): string {
  const budget = MAX_DIGEST_CHARS - DIGEST_NOTE_RESERVE;
  const lines: string[] = [];
  let used = 0;

  const push = (line: string): boolean => {
    const cost = line.length + (lines.length > 0 ? 1 : 0);
    if (used + cost > budget) return false;
    lines.push(line);
    used += cost;
    return true;
  };

  for (const line of headerLines(ctx)) push(line);

  let omitted = 0;
  for (const kind of FACT_KIND_ORDER) {
    const all = ctx.facts.facts.filter((fact) => fact.kind === kind);
    const limit = DIGEST_KIND_LIMITS[kind];
    const shown = all.slice(0, limit);
    omitted += all.length - shown.length;
    if (shown.length === 0) continue;

    const heading =
      shown.length === all.length
        ? `【${DIGEST_KIND_TITLES[kind]}】共 ${all.length} 条`
        : `【${DIGEST_KIND_TITLES[kind]}】共 ${all.length} 条，下列 ${shown.length} 条`;
    if (!push(heading)) {
      omitted += shown.length;
      continue;
    }
    for (const fact of shown) {
      if (!push(clipText(fact.line, MAX_DIGEST_LINE_CHARS))) omitted += 1;
    }
  }

  if (omitted > 0) lines.push(`另有 ${omitted} 条略`);
  return lines.join('\n');
}

function outputRules(): string[] {
  return [
    '输出要求：',
    '- 只输出该节正文，使用 Markdown 列表，每条以「- 」开头；',
    '- 不要重复节标题，也不要输出其它章节的内容；',
    '- 不要编造事实摘要里不存在的人名、数字或日期，信息不足时如实说明；',
    '- 该节没有相关记录时，明确写出「本周期无相关记录」；',
    '- 中文表达，不使用 emoji 或表情符号。',
  ];
}

/** 单节生成：要求只输出该节正文，并附紧凑摘要。 */
export function sectionMessages(ctx: ReportAiContext, sectionKey: string): AiMessage[] {
  const sections = resolveSections(ctx);
  const section = sections.find((entry) => entry.key === sectionKey);
  if (!section) {
    throw new AiRequestError('config', `未知的报告章节：${sectionKey}`, {
      detail: `可用章节：${sections.map((entry) => entry.key).join('、')}`,
    });
  }

  const lines = [
    `请撰写这份${REPORT_TYPE_LABELS[ctx.kind]}的「${section.title}」一节。`,
    '',
    ...outputRules(),
    '',
    `本节范围：${SECTION_SCOPES[sectionKey] ?? '只写与本节标题相关的内容，全部依据下方事实摘要。'}`,
    '',
    '事实摘要：',
    buildFactsDigest(ctx),
  ];

  return [{ role: 'user', content: lines.join('\n') }];
}

/** 整份生成：要求返回严格 JSON 数组，key 只允许模板节 key。 */
export function reportMessages(ctx: ReportAiContext): AiMessage[] {
  const sections = resolveSections(ctx);
  const allowed = sections.map((entry) => entry.key);
  const lines = [
    `请基于下面的事实摘要，写出这份${REPORT_TYPE_LABELS[ctx.kind]}的完整正文，周期为 ${ctx.periodLabel}。`,
    '',
    '输出要求：',
    '- 只返回一个 JSON 数组，不要 Markdown 代码围栏，不要在数组前后添加任何说明文字；',
    '- 数组每一项形如 {"key":"overview","body":"..."}，key 与 body 都必须是字符串；',
    `- key 只允许这些取值：${allowed.join('、')}；不要新增、改名或省略，也不要出现其它 key；`,
    `- 每个 key 只出现一次，顺序为：${allowed.join('、')}；`,
    '- body 只写该节正文，使用 Markdown 列表，每条以「- 」开头，不要重复节标题；',
    '- 不要编造事实摘要里不存在的人名、数字或日期；该节没有记录时写「本周期无相关记录」；',
    '- 中文表达，不使用 emoji 或表情符号。',
    '',
    `章节清单：${sections.map((entry) => `${entry.key}（${entry.title}）`).join('、')}`,
    '',
    '事实摘要：',
    buildFactsDigest(ctx),
  ];

  return [{ role: 'user', content: lines.join('\n') }];
}

/* ------------------------------------------------------------------ */
/* 解析                                                                */
/* ------------------------------------------------------------------ */

/** 所有模板节 key 的并集：整份结构里只接受这些 key。 */
const ALLOWED_SECTION_KEYS: Set<string> = new Set(
  REPORT_TEMPLATES.flatMap((template) => template.sections.map((section) => section.key)),
);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * 从模型输出里截出 JSON 数组：容忍 ```json 围栏与前后说明文字。
 *
 * 找不到数组边界、或模型直接给了对象包装（`{"sections":[...]}`）时返回 null：
 * 后者不是契约要求的数组结构，交给上层统一报 `response`，而不是静默拆包装。
 */
function extractJsonArray(text: string): string | null {
  const source = text.trim();
  if (!source) return null;
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(source);
  const candidate = (fenced?.[1] ?? source).trim();
  if (!candidate || candidate.startsWith('{')) return null;
  const start = candidate.indexOf('[');
  const end = candidate.lastIndexOf(']');
  if (start === -1 || end === -1 || end <= start) return null;
  return candidate.slice(start, end + 1);
}

/**
 * 去掉 `}` / `]` 前的尾随逗号。
 * 逐字符扫描并跟踪字符串状态，避免把字符串内容里的 `, }` 一起改掉。
 */
function stripTrailingCommas(json: string): string {
  let out = '';
  let inString = false;
  let escaped = false;
  for (let index = 0; index < json.length; index += 1) {
    const char = json[index] as string;
    if (inString) {
      out += char;
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
      out += char;
      continue;
    }
    if (char === ',') {
      let next = index + 1;
      while (next < json.length && /\s/.test(json[next] as string)) next += 1;
      const nextChar = json[next];
      if (nextChar === '}' || nextChar === ']') continue;
    }
    out += char;
  }
  return out;
}

/**
 * 解析整份生成结果。
 *
 * 容忍：```json 围栏、前后说明文字、尾随逗号。
 * 过滤：未知 key、非字符串 body、空 body、重复 key。
 * 失败（无数组 / 非法 JSON / 非数组 / 全部被过滤）一律抛
 * `AiRequestError('response', ...)`。
 */
export function parseReportSections(text: string): { key: string; body: string }[] {
  const raw = extractJsonArray(text);
  const detail = clipText(text, 200) || undefined;
  if (raw === null) {
    throw new AiRequestError('response', '模型返回内容中找不到 JSON 数组', { detail });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripTrailingCommas(raw)) as unknown;
  } catch (error) {
    throw new AiRequestError('response', '模型返回内容不是合法 JSON', { detail, cause: error });
  }
  if (!Array.isArray(parsed)) {
    throw new AiRequestError('response', '模型返回的 JSON 不是数组', { detail });
  }

  const sections: { key: string; body: string }[] = [];
  const seen = new Set<string>();
  let dropped = 0;
  for (const entry of parsed) {
    if (!isRecord(entry)) {
      dropped += 1;
      continue;
    }
    const key = typeof entry.key === 'string' ? entry.key.trim() : '';
    const body = typeof entry.body === 'string' ? entry.body.trim() : '';
    if (!key || !ALLOWED_SECTION_KEYS.has(key) || !body || seen.has(key)) {
      dropped += 1;
      continue;
    }
    seen.add(key);
    sections.push({ key, body });
  }

  if (sections.length === 0) {
    throw new AiRequestError('response', '模型返回的章节全部无效', {
      detail: detail ? `丢弃 ${dropped} 项；返回内容：${detail}` : `丢弃 ${dropped} 项`,
    });
  }
  return sections;
}
