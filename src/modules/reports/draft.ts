/**
 * 周报 / 月报 / 季报的草稿正文生成（纯函数）。
 *
 * 页面层只做纯文本展示，不解析 Markdown，因此这里输出的正文是「自解释」的：
 * 每节以 `### 小标题` 开头，条目统一 `- ` 列表，分组用 `#### 小标题`。
 * 空数据一律给明确文案，不允许留空字符串。
 *
 * 行格式契约（与 `facts.ts` 一致，**不存在外层括号**）：
 * - 列表行 = `- <主体> · <补充片段> · <补充片段>`，或「标签：值」用 `：`；
 * - 绝不把条目标题 / SOP 标题 / 等待对象 / 指标单位包进 `（）`——它们都是外部文本，
 *   一包就会出现 `（等待 9 天（张三））` 这种双层括号，对外汇报很难看；
 * - 唯一允许的括号是 `support` 节的固定占位文案（契约写死），且无外部文本进入。
 *
 * 性能契约：`buildReportSections` 只调用一次 `getWorkspaceIndex`，
 * 只调用一次 `collectFactsDetailed`（内部单次遍历工作区），
 * 之后所有节都由同一份 `BuildContext` 拼接。
 */
import type {
  Item,
  ReportPeriodKind,
  ReportSection,
  Workspace,
} from '../../core/model';
import { REPORT_TEMPLATE_BY_KIND } from '../../core/model';
import {
  getWorkspaceIndex,
  objectivesOfPeriod,
  rollupProgress,
  type WorkspaceIndex,
} from '../../core/selectors';
import {
  collectFactsDetailed,
  RISK_CATEGORY_LABELS,
  RISK_CATEGORY_ORDER,
  type ReportFactsDetailed,
} from './facts';
import { periodRange } from './period';

export interface ReportTemplateSection {
  key: string;
  title: string;
}

export interface ReportTemplate {
  id: string;
  kind: ReportPeriodKind;
  sections: ReportTemplateSection[];
}

/** 进度节每个领域最多列出的条目数，超出补「另有 N 条…」。 */
export const AREA_SECTION_LIMIT = 8;
/** 季报每个目标最多列出的 KR 进度条数。 */
export const OKR_KR_PREVIEW_LIMIT = 3;

export const SUPPORT_PLACEHOLDER = '- （待补充：需要哪些支持、决策或资源）';

export const REPORT_TEMPLATES: ReportTemplate[] = [
  {
    id: 'weekly-external',
    kind: 'week',
    sections: [
      { key: 'overview', title: '本周概览' },
      { key: 'progress', title: '本周进展' },
      { key: 'metrics', title: '量化指标' },
      { key: 'risks', title: '风险与阻塞' },
      { key: 'next', title: '下周计划' },
      { key: 'support', title: '需要的支持' },
    ],
  },
  {
    id: 'monthly-external',
    kind: 'month',
    sections: [
      { key: 'overview', title: '本月概览' },
      { key: 'progress', title: '本月进展' },
      { key: 'metrics', title: '量化指标' },
      { key: 'risks', title: '风险与阻塞' },
      { key: 'next', title: '下月计划' },
      { key: 'support', title: '需要的支持' },
    ],
  },
  {
    id: 'quarterly-external',
    kind: 'quarter',
    sections: [
      { key: 'overview', title: '本季概览' },
      { key: 'progress', title: '本季进展' },
      { key: 'okr', title: '目标与关键结果' },
      { key: 'metrics', title: '量化指标' },
      { key: 'risks', title: '风险与阻塞' },
      { key: 'next', title: '下季计划' },
      { key: 'support', title: '需要的支持' },
    ],
  },
];

/** 按粒度取模板。未知 / 非法粒度回落到周报模板。 */
export function templateFor(kind: ReportPeriodKind): ReportTemplate {
  return templateById(REPORT_TEMPLATE_BY_KIND[kind]);
}

/** 按 id 取模板；未知 id 回落到周报模板（最完整的兜底，不会返回 undefined）。 */
export function templateById(templateId: string): ReportTemplate {
  return (
    REPORT_TEMPLATES.find((template) => template.id === templateId) ??
    (REPORT_TEMPLATES[0] as ReportTemplate)
  );
}

interface BuildContext {
  ws: Workspace;
  index: WorkspaceIndex;
  kind: ReportPeriodKind;
  period: string;
  facts: ReportFactsDetailed;
  now: Date;
}

function buildContext(
  ws: Workspace,
  kind: ReportPeriodKind,
  period: string,
  now: Date,
): BuildContext {
  // 一次取索引、一次汇总事实，节构造全部复用。
  const index = getWorkspaceIndex(ws);
  const facts = collectFactsDetailed(ws, kind, period, now);
  return { ws, index, kind, period, facts, now };
}

function krProgressOf(ctx: BuildContext, kr: Item): number {
  // 无 metric 的 KR 由 rollupProgress 回退到完成状态 / 子项完成比，与 OKR 视图一致。
  return rollupProgress(ctx.ws, kr.id);
}

/* ------------------------------------------------------------------ */
/* 各节正文                                                            */
/* ------------------------------------------------------------------ */

function overviewBody(ctx: BuildContext, title: string): string {
  const { stats } = ctx.facts;
  return [
    `### ${title}`,
    `- 完成：${stats.completed} 项`,
    `- 进行中：${stats.openInWindow} 项`,
    `- 风险：${stats.risks} 项`,
    `- 收件箱：剩余 ${stats.inboxRemaining} 项 · 清理进度 ${stats.inboxProgress}%`,
  ].join('\n');
}

function progressBody(ctx: BuildContext, title: string): string {
  const lines: string[] = [`### ${title}`];
  const groups = ctx.facts.completedByArea;
  if (groups.length === 0) {
    lines.push('- 本周期无完成记录');
    return lines.join('\n');
  }
  for (const group of groups) {
    lines.push(`#### ${group.name}`);
    for (const entry of group.facts.slice(0, AREA_SECTION_LIMIT)) lines.push(entry.line);
    const rest = group.facts.length - AREA_SECTION_LIMIT;
    if (rest > 0) lines.push(`- 另有 ${rest} 条…`);
  }
  return lines.join('\n');
}

function metricsBody(ctx: BuildContext, title: string): string {
  const lines: string[] = [`### ${title}`, '#### 关键结果'];
  const krFacts = ctx.facts.facts.filter((entry) => entry.kind === 'kr');
  if (krFacts.length === 0) {
    lines.push('- 本周期无关键结果数据');
  } else {
    for (const entry of krFacts) lines.push(entry.line);
  }

  lines.push('#### SOP 运行');
  const { runCounts } = ctx.facts;
  if (runCounts.total === 0) {
    lines.push('- 本周期无 SOP 运行记录');
  } else {
    lines.push(
      `- 运行 ${runCounts.total} 次：通过 ${runCounts.pass} / 失败 ${runCounts.fail} / 跳过 ${runCounts.skip}`,
    );
    for (const entry of ctx.facts.facts) {
      if (entry.kind === 'run') lines.push(entry.line);
    }
  }
  return lines.join('\n');
}

function risksBody(ctx: BuildContext, title: string): string {
  const lines: string[] = [`### ${title}`];
  for (const category of RISK_CATEGORY_ORDER) {
    lines.push(`#### ${RISK_CATEGORY_LABELS[category]}`);
    const entries = ctx.facts.riskGroups[category];
    if (entries.length === 0) lines.push('- 无');
    else for (const entry of entries) lines.push(entry.line);
  }
  return lines.join('\n');
}

function nextBody(ctx: BuildContext, title: string): string {
  const lines: string[] = [`### ${title}`];
  const nextUp = ctx.facts.facts.filter((entry) => entry.kind === 'nextUp');
  if (nextUp.length === 0) {
    lines.push('- 下周期尚未排期');
  } else {
    for (const entry of nextUp) lines.push(entry.line);
  }
  return lines.join('\n');
}

function okrBody(ctx: BuildContext, title: string): string {
  const lines: string[] = [`### ${title}`];
  const objectives = objectivesOfPeriod(ctx.ws, ctx.period);
  if (objectives.length === 0) {
    lines.push('- 本季度未设置目标');
    return lines.join('\n');
  }
  for (const objective of objectives) {
    const progress = rollupProgress(ctx.ws, objective.id);
    const keyResults = (ctx.index.children.get(objective.id) ?? []).filter(
      (child) => child.kind === 'keyresult',
    );
    const preview = keyResults
      .slice(0, OKR_KR_PREVIEW_LIMIT)
      .map((kr) => `${kr.title} ${krProgressOf(ctx, kr)}%`);
    const rest = keyResults.length - preview.length;
    // KR 标题是外部文本，只用 ` · ` / ` / ` 串联，不加括号。
    const tail =
      preview.length === 0
        ? '暂无 KR'
        : `${preview.join(' / ')}${rest > 0 ? ` / 另有 ${rest} 个 KR` : ''}`;
    lines.push(`- ${objective.title}：完成度 ${progress}% · ${tail}`);
  }
  return lines.join('\n');
}

function supportBody(_ctx: BuildContext, title: string): string {
  return [`### ${title}`, SUPPORT_PLACEHOLDER].join('\n');
}

const SECTION_BUILDERS: Record<string, (ctx: BuildContext, title: string) => string> = {
  overview: overviewBody,
  progress: progressBody,
  metrics: metricsBody,
  risks: risksBody,
  next: nextBody,
  okr: okrBody,
  support: supportBody,
};

function renderSection(ctx: BuildContext, section: ReportTemplateSection): string {
  const builder = SECTION_BUILDERS[section.key];
  // 模板里出现未知 key 属实现错误：给出明确占位而不是空串。
  if (!builder) return `### ${section.title}\n- 未知章节：${section.key}`;
  return builder(ctx, section.title);
}

function toReportSection(
  ctx: BuildContext,
  section: ReportTemplateSection,
  body: string,
): ReportSection {
  return {
    key: section.key,
    title: section.title,
    body,
    origin: 'auto',
    updatedAt: ctx.now.toISOString(),
  };
}

/**
 * 按粒度模板生成完整草稿。
 *
 * `period` 非法（`periodRange` 返回 null）时抛 `非法周期：<period>`，
 * 绝不静默产出归属不明的报告。
 */
export function buildReportSections(
  ws: Workspace,
  kind: ReportPeriodKind,
  period: string,
  now: Date = new Date(),
): ReportSection[] {
  if (!periodRange(kind, period)) throw new Error('非法周期：' + period);
  const ctx = buildContext(ws, kind, period, now);
  return templateFor(kind).sections.map((section) =>
    toReportSection(ctx, section, renderSection(ctx, section)),
  );
}

/**
 * 重算单节正文（页面层「重算本节」按钮用）。
 *
 * - `sectionKey` 不在该粒度模板里 → 返回 `null`（不改动任何东西）；
 * - `period` 非法 → 抛 `非法周期：<period>`（先校验周期，再判 key）。
 */
export function rebuildSection(
  ws: Workspace,
  kind: ReportPeriodKind,
  period: string,
  sectionKey: string,
  now: Date = new Date(),
): string | null {
  if (!periodRange(kind, period)) throw new Error('非法周期：' + period);
  const section = templateFor(kind).sections.find((entry) => entry.key === sectionKey);
  if (!section) return null;
  const ctx = buildContext(ws, kind, period, now);
  return renderSection(ctx, section);
}
