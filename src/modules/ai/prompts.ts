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
 * - 整份生成：严格 JSON 数组 `[{"key":"overview","body":"..."}]`，key 只允许章节清单
 *   （模板节 + 用户自建节）里的 key；
 * - 中文文案，与项目风格一致，不使用 emoji。
 */
import { REPORT_TEMPLATES, templateFor } from '../reports/draft';
import type { FactKind, ReportFactsDetailed } from '../reports/facts';
import { isCustomSectionKey, MAX_SECTION_TITLE_CHARS } from '../reports/sections';
import { AiRequestError } from './client';
import type { AiMessage } from './client';

export interface ReportAiContext {
  kind: 'week' | 'month' | 'quarter';
  /** 如 `2026 年第 44 周`。 */
  periodLabel: string;
  range: { start: string; end: string } | null;
  author: string;
  facts: ReportFactsDetailed;
  /**
   * 章节清单（key / title / 当前正文），**顺序即编辑器展示顺序**。
   *
   * 不再等同于「当前模板的节」：用户可以自建章节（`custom-*`），模板节也可能被上移下移。
   * 模板节的标题来自模板，自建节的标题来自报告；调用方不给时回落到 `templateFor(kind)`。
   */
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

/**
 * 头部取值（周期、作者、章节标题）进提示词时的长度上限。
 *
 * 直接取 `sections.MAX_SECTION_TITLE_CHARS`：章节标题的预算只允许有一份真源，两处各写
 * 一个 120 早晚会走样。这里仍保留同名导出，因为提示层要**独立**再裁一次——标题的规范化
 * 只发生在编辑器写入（`addSection` / `renameSection`），导入 / 历史数据里的标题不经过它，
 * 提示层不能假设自己拿到的标题已经是单行且不超长的。
 */
export const MAX_HEADER_VALUE_CHARS = MAX_SECTION_TITLE_CHARS;

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

/**
 * 模板之外的章节（用户自建 `custom-*`、历史模板遗留 key）的写作提示。
 *
 * 为什么要点名「不在模板的固定章节里」：模型见过 overview / risks 这类模板 key 的既定骨架，
 * 遇到 `custom-3` 时容易去找「它对应的模板节」，甚至干脆不写；先说清「没有预设骨架、
 * 按标题自行组织」，既给出方向，又保留「不编造数据 + 中文 `- ` 列表」这两条底线。
 */
const CUSTOM_SECTION_SCOPE =
  '不在模板的固定章节里，没有预设骨架可依；按该节标题自行组织内容，沿用中文与「- 」列表格式，不编造数据。';

/** 模板外的节用标题兜底自称；标题可能被用户清空，此时退回 key。 */
function sectionScope(section: { key: string; title: string }): string {
  const scope = SECTION_SCOPES[section.key];
  if (scope) return scope;
  const title = sectionTitleText(section.title) || section.key;
  return `「${title}」${CUSTOM_SECTION_SCOPE}`;
}

function clipText(value: string, max: number): string {
  const text = value.trim();
  if (text.length <= max) return text;
  let cut = text.slice(0, Math.max(1, max - 1));
  // 不在代理对中间切断：否则留下孤立的高位代理，提示词里会出现乱码字符。
  const lastUnit = cut.charCodeAt(cut.length - 1);
  if (lastUnit >= 0xd800 && lastUnit <= 0xdbff) cut = cut.slice(0, -1);
  return `${cut}…`;
}

/**
 * 章节标题进提示词的唯一口径：先把换行 / 连续空白压成单个空格，再按
 * `MAX_HEADER_VALUE_CHARS` 截断；标题为空（或全空白）时退回 key。
 *
 * 为什么要在这里单独裁一次：编辑器写入（`sections.renameSection`）确实会压空白并限长，
 * 但那条路径只约束用户手输 / 粘贴的标题，**导入与历史数据不经过它**——工作区里完全可能
 * 存着一份多 KB、或者带换行的标题。提示词是多行文本，标题一旦超长或被换行拆开，
 * 「章节清单」那一行就会被撑成几千字或拆成多行，模型容易读成两个章节。压空白不改变正常
 * 标题的字节（`a b` / `复盘与改进` 原样保留），只有真的含换行 / 制表符 / 超长的标题才被
 * 改写。标题自带全角括号 `）` 时清单仍有歧义，但至少被压成一行且有长度上限，不会污染
 * 紧邻的其它章节。
 */
function sectionTitleText(title: string): string {
  return clipText(title.replace(/\s+/g, ' '), MAX_HEADER_VALUE_CHARS);
}

function resolveSections(
  ctx: ReportAiContext,
): { key: string; title: string; body?: string }[] {
  if (ctx.sections.length > 0) return ctx.sections;
  // 调用方没给节时回落到模板，保证 key 清单始终来自模板而不是凭空的字符串。
  return templateFor(ctx.kind).sections;
}

/**
 * 整份生成允许出现的 key 清单，**与提示词里列出的清单同源**。
 *
 * 必须由调用方（面板）把它传给 `parseReportSections`：提示词按 `ctx.sections` 列清单
 * （含用户自建节），解析层若还按模板并集卡 key，模型照清单写出来的 `custom-*` 会被静默丢掉，
 * 表现为「自建节的参考稿永远生成不出来」。`ctx.sections` 为空时按 `resolveSections` 回落模板。
 */
export function allowedSectionKeys(ctx: ReportAiContext): string[] {
  return resolveSections(ctx).map((entry) => entry.key);
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

  // 标题与 `sectionScope` 同口径裁剪：超长 / 带换行的自建节标题不该把这一行撑坏。
  const title = sectionTitleText(section.title) || section.key;
  const lines = [
    `请撰写这份${REPORT_TYPE_LABELS[ctx.kind]}的「${title}」一节。`,
    '',
    ...outputRules(),
    '',
    `本节范围：${sectionScope(section)}`,
    '',
    '事实摘要：',
    buildFactsDigest(ctx),
  ];

  return [{ role: 'user', content: lines.join('\n') }];
}

/**
 * 整份生成：要求返回严格 JSON 数组。
 *
 * key 清单直接就是章节清单（`ctx.sections`，含用户自建节；为空时回落模板），
 * 提示词里列什么、`allowedSectionKeys` 就放行什么，两边不允许各说各话。
 */
export function reportMessages(ctx: ReportAiContext): AiMessage[] {
  const sections = resolveSections(ctx);
  const allowed = sections.map((entry) => entry.key);
  // 只有存在自建节时才多说一句，纯模板场景的提示词逐字不变。
  const customNote = sections.some((entry) => isCustomSectionKey(entry.key))
    ? ['- 清单里 key 形如 custom-* 的是用户自建章节：按清单给出的标题写，不要合并进其它章节；']
    : [];
  const lines = [
    `请基于下面的事实摘要，写出这份${REPORT_TYPE_LABELS[ctx.kind]}的完整正文，周期为 ${ctx.periodLabel}。`,
    '',
    '输出要求：',
    '- 只返回一个 JSON 数组，不要 Markdown 代码围栏，不要在数组前后添加任何说明文字；',
    '- 数组每一项形如 {"key":"overview","body":"..."}，key 与 body 都必须是字符串；',
    `- key 只允许这些取值（即下方「章节清单」中的 key）：${allowed.join('、')}；不要新增、改名或省略，也不要出现其它 key；`,
    `- 每个 key 只出现一次，顺序为：${allowed.join('、')}；`,
    ...customNote,
    '- body 只写该节正文，使用 Markdown 列表，每条以「- 」开头，不要重复节标题；',
    '- 不要编造事实摘要里不存在的人名、数字或日期；该节没有记录时写「本周期无相关记录」；',
    '- 中文表达，不使用 emoji 或表情符号。',
    '',
    // 清单是**一行**结构：标题必须先压空白再截断，否则一个带换行的标题会把清单拆成多行。
    `章节清单：${sections
      .map((entry) => `${entry.key}（${sectionTitleText(entry.title) || entry.key}）`)
      .join('、')}`,
    '',
    '事实摘要：',
    buildFactsDigest(ctx),
  ];

  return [{ role: 'user', content: lines.join('\n') }];
}

/* ------------------------------------------------------------------ */
/* 解析                                                                */
/* ------------------------------------------------------------------ */

/**
 * 所有模板节 key 的并集：**调用方没给章节清单时的兜底白名单**。
 *
 * 自建节（`custom-*`）不可能出现在这里——它只存在于具体某份报告里。
 * 面板必须把 `allowedSectionKeys(ctx)` 传进 `parseReportSections`，自定义章节才能落地。
 */
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
 * 过滤：白名单外的 key、非字符串 body、空 body、重复 key。
 *
 * 白名单 `allowedKeys` 优先用调用方给的**章节清单**（模板节 + 自建节，见
 * `allowedSectionKeys`）；不传或传空时回落到所有模板 key 的并集，纯模板场景行为与以前一致。
 *
 * 失败（无数组 / 非法 JSON / 非数组 / 全部被过滤）一律抛
 * `AiRequestError('response', ...)`。
 */
export function parseReportSections(
  text: string,
  allowedKeys?: readonly string[],
): { key: string; body: string }[] {
  const allowed =
    allowedKeys && allowedKeys.length > 0 ? new Set(allowedKeys) : ALLOWED_SECTION_KEYS;
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
    if (!key || !allowed.has(key) || !body || seen.has(key)) {
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
