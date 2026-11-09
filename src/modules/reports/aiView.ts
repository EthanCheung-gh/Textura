/**
 * 周报「AI 参考」区的纯逻辑（无 React、无 store、无网络，可直接单测）。
 *
 * 边界：
 * - 本文件只做四件事：上下文怎么拼、错误怎么说、整份结果怎么按展示清单筛、摘要多大；
 * - 发请求与加载 / 取消状态机在 `ReportAiPanel.tsx`，写回正文在 `ReportsPage.tsx`；
 * - 不缓存、不重试、不读取 `apiKey`（这里产出的任何文案都不含密钥）。
 */
import type { ReportPeriodKind, ReportSection } from '../../core/model';
import { AiRequestError } from '../ai/client';
import type { AiErrorKind } from '../ai/client';
import { MAX_DIGEST_CHARS } from '../ai/prompts';
import type { ReportAiContext } from '../ai/prompts';
import { templateFor } from './draft';
import type { ReportTemplate } from './draft';
import type { ReportFactsDetailed } from './facts';
import { periodLabel } from './period';
import type { PeriodRange } from './period';
import { displaySections } from './sections';

/* ------------------------------------------------------------------ */
/* 上下文                                                              */
/* ------------------------------------------------------------------ */

/**
 * AI 上下文里的一节：只需要「哪个节、写了什么」。
 *
 * 标题对模板节由模板给（模板标题是口径来源），对自建节由报告给，因此这里允许缺省，
 * 调用方（页面层）直接把草稿节数组传进来即可，不必先补一份标题。
 */
export interface AiContextSection {
  key: string;
  body: string;
  title?: string;
}

export interface BuildAiContextInput {
  kind: ReportPeriodKind;
  /** 期次键，如 `2026-W44`；中文标题在这里由 `periodLabel` 反推，调用方不必再传。 */
  period: string;
  range: PeriodRange | null;
  author: string;
  /**
   * 报告现有正文（草稿缓冲）。
   *
   * **key 不再按模板裁剪**：自建节（`custom-*`）与历史模板遗留的 key 同样在编辑器里可见、
   * 可写、可被选为 AI 目标，丢掉它们等于让用户加的节永远拿不到参考稿。
   */
  sections: readonly AiContextSection[];
  facts: ReportFactsDetailed;
  /** 报告自带模板（历史 templateId）；不传则按粒度回落 `templateFor(kind)`。 */
  template?: ReportTemplate;
}

/**
 * 拼出提示词层要的上下文。
 *
 * - 节清单取**展示顺序**（`displaySections`，与编辑器同一口径）：模板节的先后以报告存储顺序
 *   为准（用户上移 / 下移过的位置生效），自建节与历史遗留 key 留在自己的槽位上；
 * - 模板里有、报告里没有的节保留为**空正文**（不从数组里删掉）：
 *   「本节还没有内容」是有效信息，删掉会让模型以为不需要写这一节；
 * - 同一 key 出现多次时**取第一处**：去重由 `displaySections` 负责（存储层出现过重复追加），
 *   因此这里不再自己建 Map 判重，去重口径只有一份；
 * - 标题：模板节一律取**模板标题**（`sections.ts` 契约第 4 条——模板节标题不可改，旧报告里
 *   残留的旧标题不该漂进提示词），模板外的节取**报告自己存的标题**（自建节的标题是用户起的名字）。
 */
export function buildAiContext(input: BuildAiContextInput): ReportAiContext {
  const template = input.template ?? templateFor(input.kind);
  // `displaySections` 的入参签名要求完整 `ReportSection`（它可能原样复用报告里的节对象），
  // 而这里只关心 key / body / title；这一处收窄是为了在**不复制**调用方数组的前提下复用
  // 同一份排序口径（顺序口径只能有一处，见 `sections.ts` 文件头）。
  // `updatedAt: ''` 只影响补出来的空节的字段，AI 上下文不读该字段。
  const display = displaySections(template, {
    sections: input.sections as unknown as ReportSection[],
    updatedAt: '',
  });

  const templateTitles = new Map<string, string>();
  for (const section of template.sections) templateTitles.set(section.key, section.title);

  const label = periodLabel(input.kind, input.period);
  return {
    kind: input.kind,
    periodLabel: label || input.period,
    range: input.range ? { start: input.range.start, end: input.range.end } : null,
    author: input.author,
    facts: input.facts,
    sections: display.map((section) => ({
      key: section.key,
      title: templateTitles.get(section.key) ?? (section.title || section.key),
      body: section.body,
    })),
  };
}

/* ------------------------------------------------------------------ */
/* 错误文案分流                                                        */
/* ------------------------------------------------------------------ */

export interface AiErrorView {
  /** 主文案：一句话说明发生了什么，直接展示给用户。 */
  title: string;
  /** 补充说明：HTTP 状态码 / 已脱敏的网关回包片段，没有就是空串。 */
  hint: string;
  /** 同一请求直接重发是否有意义（不做自动重试，只决定是否给「重试」按钮）。 */
  canRetry: boolean;
  /** 是否要去「设置 → 大模型」改配置（决定是否给「去设置」按钮）。 */
  needsSettings: boolean;
}

/** 详情片段上限：面板只有 280px 宽，再长也没有可读性。 */
const MAX_HINT_CHARS = 160;

function clipHint(value: string): string {
  const text = value.replace(/\s+/g, ' ').trim();
  return text.length > MAX_HINT_CHARS ? `${text.slice(0, MAX_HINT_CHARS - 1)}…` : text;
}

function messageOf(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  return '';
}

function hintOf(request: AiRequestError | null): string {
  if (!request) return '';
  const parts: string[] = [];
  if (request.status !== undefined) parts.push(`HTTP ${request.status}`);
  if (request.detail) parts.push(clipHint(request.detail));
  return parts.join(' · ');
}

/** 调用层把「浏览器 fetch 抛 TypeError」统一标成 network，并在 detail 里写了 CORS 提示。 */
function isCorsHint(request: AiRequestError | null): boolean {
  return Boolean(request?.detail && request.detail.includes('跨域'));
}

/**
 * 错误 → 面板文案。按 `AiRequestError.kind` 分流，未知类型回落到 `message`。
 *
 * `aborted` 走不到这里（面板对取消静默忽略），保留分支只是为了穷尽所有 kind。
 */
export function aiErrorText(error: unknown): AiErrorView {
  const request = error instanceof AiRequestError ? error : null;
  const hint = hintOf(request);
  const kind: AiErrorKind | undefined = request?.kind;

  switch (kind) {
    case 'auth':
      return {
        title: '密钥被拒绝，请到设置检查 API Key',
        hint,
        canRetry: false,
        needsSettings: true,
      };
    case 'rate-limit':
      return { title: '请求过于频繁，稍后重试', hint, canRetry: true, needsSettings: false };
    case 'timeout':
      return { title: '请求超时，可重试', hint, canRetry: true, needsSettings: false };
    case 'network':
      return isCorsHint(request)
        ? {
            title: '疑似跨域被拒（CORS）或网关不可达，请改用允许浏览器直连的网关',
            hint,
            canRetry: false,
            needsSettings: true,
          }
        : { title: '网络请求失败，请检查网络或网关地址', hint, canRetry: true, needsSettings: false };
    case 'server':
      return { title: '网关返回错误，稍后重试', hint, canRetry: true, needsSettings: false };
    case 'response':
      return { title: '模型输出格式异常，可重新生成', hint, canRetry: true, needsSettings: false };
    case 'config':
      return {
        title: '配置未就绪，请先到设置完成配置',
        hint,
        canRetry: false,
        needsSettings: true,
      };
    case 'aborted':
      return { title: '已取消生成', hint, canRetry: true, needsSettings: false };
    default:
      // unknown（含非 AiRequestError 的异常）：直接把原始 message 交给用户，比笼统文案有用。
      return {
        title: messageOf(error) || '大模型请求失败',
        hint,
        canRetry: true,
        needsSettings: false,
      };
  }
}

/* ------------------------------------------------------------------ */
/* 结果筛选                                                            */
/* ------------------------------------------------------------------ */

/**
 * 整份生成结果的筛选：按 `orderedKeys`（编辑器展示顺序的 key 清单，模板节 + 自建节）
 * 挑出允许的节——清单外的 key 丢掉、同一 key 只留第一条，输出顺序 = 清单顺序
 * （与编辑器一致，模型返回顺序不影响阅读）。
 *
 * 为什么筛选口径是「展示清单」而不是「模板」：用户可以自建章节，`custom-*` 不在模板里，
 * 但它确实是这份报告的一节，整份结果必须能采用它；清单越界（例如模型编了个 key）一律丢弃。
 * 只要模板口径时，把模板节的 key 序列当 `orderedKeys` 传进来即可（不再另留模板版封装，
 * 免得出现「两个筛选函数、其中一个会静默丢掉自建节」的分叉）。
 */
export function filterSectionsByDisplay<T extends { key: string }>(
  result: readonly T[],
  orderedKeys: readonly string[],
): T[] {
  const allowed = new Set(orderedKeys);
  const picked = new Map<string, T>();
  for (const entry of result) {
    if (!allowed.has(entry.key) || picked.has(entry.key)) continue;
    picked.set(entry.key, entry);
  }
  const ordered: T[] = [];
  for (const key of orderedKeys) {
    const entry = picked.get(key);
    if (entry !== undefined) ordered.push(entry);
  }
  return ordered;
}

/* ------------------------------------------------------------------ */
/* 摘要尺寸                                                            */
/* ------------------------------------------------------------------ */

/**
 * 「本次摘要 N 字符」。
 *
 * 口径与 `prompts.ts` 的 `MAX_DIGEST_CHARS` 完全一致：都按 UTF-16 长度（`String.length`）计，
 * 因此 emoji 等代理对字符算 2 个。显示口径必须与预算执行口径相同，
 * 否则会出现「显示未到上限，摘要却已经被截断」的矛盾。
 */
export function digestSizeText(digest: string): string {
  const size = digest.length;
  if (size >= MAX_DIGEST_CHARS) return `本次摘要 ${size} 字符（已到上限，部分条目未计入）`;
  return `本次摘要 ${size} 字符`;
}
