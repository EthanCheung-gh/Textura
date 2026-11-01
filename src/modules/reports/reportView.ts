/**
 * 周报页面的纯展示逻辑（无 React、无 store、无副作用，可直接单测）。
 *
 * 这里只做「列表怎么排、怎么筛、哪一节属于第几个位置」这类确定性转换，
 * 真正的正文聚合仍由 `draft.ts` / `facts.ts` 负责，本文件不重算任何数据。
 */
import { REPORT_PERIOD_LABELS } from '../../core/model';
import type {
  Report,
  ReportPeriodKind,
  ReportSection,
  ReportSectionOrigin,
} from '../../core/model';
import type { ReportTemplate } from './draft';

/** 粒度中文名（周报 / 月报 / 季报），直接复用模型层常量，避免两处各写一份。 */
export const REPORT_KIND_LABELS = REPORT_PERIOD_LABELS;

/** 编辑缓冲：标题 / 报告人 / 正文都先落在这里，防抖后整份写回 store。 */
export interface ReportDraft {
  id: string;
  title: string;
  author: string;
  sections: ReportSection[];
}

export function draftFromReport(report: Report): ReportDraft {
  return {
    id: report.id,
    title: report.title,
    author: report.author,
    sections: report.sections,
  };
}

/** 单一粒度下的报告（`workspace.reports` 是可缺省字段，入参允许 undefined / null）。 */
export function reportsOfKind(
  reports: Report[] | undefined | null,
  kind: ReportPeriodKind,
): Report[] {
  if (!reports || reports.length === 0) return [];
  return reports.filter((report) => report.kind === kind);
}

/** 同粒度同期次唯一：按 id 找到那份报告，找不到返回 null。 */
export function findReport(
  reports: Report[] | undefined | null,
  kind: ReportPeriodKind,
  period: string,
): Report | null {
  if (!reports || reports.length === 0) return null;
  for (const report of reports) {
    if (report.kind === kind && report.period === period) return report;
  }
  return null;
}

/**
 * 按期次倒序（新在前）。
 * 同一粒度的期次键是定宽字符串，字典序＝时间序（`2026-W09` < `2026-W10`），
 * 同键时按 `updatedAt` 倒序、再按 id 兜底，保证排序稳定。
 */
export function sortReportsDesc(reports: Report[]): Report[] {
  return [...reports].sort(
    (a, b) =>
      b.period.localeCompare(a.period) ||
      b.updatedAt.localeCompare(a.updatedAt) ||
      a.id.localeCompare(b.id),
  );
}

/**
 * 搜索：匹配期次键 / 标题 / 任一节正文，大小写不敏感。
 * 空查询原样返回（保持调用方传入的顺序），不复制数组。
 */
export function filterReports(reports: Report[], query: string): Report[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return reports;
  return reports.filter(
    (report) =>
      report.period.toLowerCase().includes(needle) ||
      report.title.toLowerCase().includes(needle) ||
      report.sections.some((section) => section.body.toLowerCase().includes(needle)),
  );
}

/**
 * 按模板顺序取节：模板里有、报告里没有的 key 用模板标题兜底成空节，
 * 这样旧报告（模板改版前生成）也不会在编辑器里少一节。
 * 报告里多出来的节（不在当前模板里）不参与渲染，但 `mergeSectionBodies`
 * 是整份写回的，因此它们不会被静默丢弃。
 */
export function orderedSections(template: ReportTemplate, report: Report): ReportSection[] {
  return template.sections.map((templateSection) => {
    const existing = report.sections.find((section) => section.key === templateSection.key);
    if (existing) return existing;
    return {
      key: templateSection.key,
      title: templateSection.title,
      body: '',
      origin: 'auto',
      updatedAt: report.updatedAt,
    };
  });
}

/** 字数：所有章节正文去掉空白后的字符数（中英混排下的近似「字数」）。 */
export function wordCount(report: Pick<Report, 'sections'>): number {
  let total = 0;
  for (const section of report.sections) total += section.body.replace(/\s+/g, '').length;
  return total;
}

/** 把一条素材行追加到节正文末尾（空正文直接放行，不留前导空行）。 */
export function appendLine(body: string, line: string): string {
  const trimmed = body.trimEnd();
  if (!trimmed) return line;
  return `${trimmed}\n${line}`;
}

export interface SectionMergeMeta {
  /** 不传则保留原节的 origin。 */
  origin?: ReportSectionOrigin;
  /** 不传则保留原节的 updatedAt。 */
  updatedAt?: string;
  /** 目标节不存在（旧报告 / 模板改版）时新节的标题。 */
  title?: string;
}

/**
 * 单节正文替换，返回**整份新数组**（其余节与入参同一引用），
 * 供 `updateReport(id, { sections })` 的整份替换语义使用。
 * 目标 key 不存在时追加到末尾，绝不静默丢输入。
 */
export function mergeSectionBodies(
  sections: ReportSection[],
  key: string,
  body: string,
  meta: SectionMergeMeta = {},
): ReportSection[] {
  const index = sections.findIndex((section) => section.key === key);
  if (index < 0) {
    return [
      ...sections,
      {
        key,
        title: meta.title ?? key,
        body,
        origin: meta.origin ?? 'auto',
        updatedAt: meta.updatedAt ?? new Date().toISOString(),
      },
    ];
  }
  const target = sections[index] as ReportSection;
  const next: ReportSection = {
    ...target,
    body,
    origin: meta.origin ?? target.origin,
    updatedAt: meta.updatedAt ?? target.updatedAt,
  };
  const result = [...sections];
  result[index] = next;
  return result;
}
