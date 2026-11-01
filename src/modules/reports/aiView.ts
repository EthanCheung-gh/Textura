/**
 * 周报「AI 参考」区的纯逻辑（无 React、无 store、无网络，可直接单测）。
 *
 * 边界：
 * - 本文件只做四件事：上下文怎么拼、错误怎么说、整份结果怎么按模板筛、摘要多大；
 * - 发请求与加载 / 取消状态机在 `ReportAiPanel.tsx`，写回正文在 `ReportsPage.tsx`；
 * - 不缓存、不重试、不读取 `apiKey`（这里产出的任何文案都不含密钥）。
 */
import type { ReportPeriodKind } from '../../core/model';
import { AiRequestError } from '../ai/client';
import type { AiErrorKind } from '../ai/client';
import { MAX_DIGEST_CHARS } from '../ai/prompts';
import type { ReportAiContext } from '../ai/prompts';
import { templateFor } from './draft';
import type { ReportTemplate } from './draft';
import type { ReportFactsDetailed } from './facts';
import { periodLabel } from './period';
import type { PeriodRange } from './period';

/* ------------------------------------------------------------------ */
/* 上下文                                                              */
/* ------------------------------------------------------------------ */

export interface BuildAiContextInput {
  kind: ReportPeriodKind;
  /** 期次键，如 `2026-W44`；中文标题在这里由 `periodLabel` 反推，调用方不必再传。 */
  period: string;
  range: PeriodRange | null;
  author: string;
  /** 报告现有正文（草稿缓冲），key 不在当前模板里的节会被丢弃。 */
  sections: readonly { key: string; body: string }[];
  facts: ReportFactsDetailed;
  /** 报告自带模板（历史 templateId）；不传则按粒度回落 `templateFor(kind)`。 */
  template?: ReportTemplate;
}

/**
 * 拼出提示词层要的上下文。
 *
 * - 节清单**只取当前模板**：模板顺序与标题决定提示词里的章节清单，
 *   报告里多出来的旧节（模板改版前生成）不进入上下文；
 * - 模板里有、报告里没有的节保留为**空正文**（不从数组里删掉）：
 *   「本节还没有内容」是有效信息，删掉会让模型以为不需要写这一节；
 * - 同一 key 出现多次时取第一处（与 `filterSectionsByTemplate` 的去重口径一致）。
 */
export function buildAiContext(input: BuildAiContextInput): ReportAiContext {
  const template = input.template ?? templateFor(input.kind);
  const bodies = new Map<string, string>();
  for (const section of input.sections) {
    if (!bodies.has(section.key)) bodies.set(section.key, section.body);
  }
  const label = periodLabel(input.kind, input.period);
  return {
    kind: input.kind,
    periodLabel: label || input.period,
    range: input.range ? { start: input.range.start, end: input.range.end } : null,
    author: input.author,
    facts: input.facts,
    sections: template.sections.map((section) => ({
      key: section.key,
      title: section.title,
      body: bodies.get(section.key) ?? '',
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
 * 整份生成结果的模板过滤：丢掉模板里没有的 key、同一 key 只留第一条，
 * 输出顺序按模板顺序（与编辑器一致，避免模型返回顺序影响阅读）。
 */
export function filterSectionsByTemplate<T extends { key: string }>(
  result: T[],
  template: ReportTemplate,
): T[] {
  const allowed = new Set(template.sections.map((section) => section.key));
  const picked = new Map<string, T>();
  for (const entry of result) {
    if (!allowed.has(entry.key) || picked.has(entry.key)) continue;
    picked.set(entry.key, entry);
  }
  return template.sections
    .map((section) => picked.get(section.key))
    .filter((entry): entry is T => entry !== undefined);
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
