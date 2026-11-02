/**
 * Textura · 织理 — 统一任务内核
 *
 * 这是全应用唯一的领域模型。OKR / GTD / 甘特 / SOP 四个视图共享同一个 Item 实体，
 * 只是以不同的字段组合与呈现方式出现。任何模块都不得扩展/重命名这里的字段。
 */

export type ItemKind =
  | 'objective'
  | 'keyresult'
  | 'project'
  | 'action'
  | 'sop'
  | 'step'
  | 'milestone'
  | 'note'
  | 'reference';

export type ItemStatus =
  | 'inbox'
  | 'next'
  | 'active'
  | 'waiting'
  | 'scheduled'
  | 'someday'
  | 'done'
  | 'dropped';

export type Energy = 'low' | 'medium' | 'high';

export type SopNodeType = 'start' | 'action' | 'decision' | 'check' | 'end' | 'note';

export type EdgeType = 'okr' | 'flow' | 'depends' | 'related';

export interface ChecklistEntry {
  id: string;
  text: string;
  done: boolean;
}

export interface OkrData {
  /** 周期，例如 '2026-Q1' */
  period: string;
  /** 1..10 */
  confidence: number;
  metric?: { start: number; target: number; current: number; unit: string };
  krOwner?: string;
}

export interface SopData {
  nodeType: SopNodeType;
  canvas: { x: number; y: number };
  checklist: ChecklistEntry[];
  owner?: string;
  durationMin?: number;
}

export interface GtdData {
  /** ISO 时间戳 */
  capturedAt: string;
  clarified: boolean;
  /** '电脑' '电话' 等，不带 @ */
  context?: string;
  energy?: Energy;
  waitingFor?: string;
  twoMinuteCandidate?: boolean;
}

export interface GanttData {
  /** 'YYYY-MM-DD' */
  start?: string | null;
  /** 'YYYY-MM-DD' */
  end?: string | null;
  progress: number;
}

export interface Item {
  id: string;
  kind: ItemKind;
  title: string;
  notes: string;
  parentId: string | null;
  order: number;
  status: ItemStatus;
  tags: string[];
  areaId: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
  okr?: OkrData;
  sop?: SopData;
  gtd?: GtdData;
  gantt?: GanttData;
}

export interface Edge {
  id: string;
  from: string;
  to: string;
  type: EdgeType;
  label: string;
}

export interface Area {
  id: string;
  name: string;
  color: string;
  order: number;
}

export interface SopRunEntry {
  id: string;
  sopId: string;
  stepId: string;
  at: string;
  result: 'pass' | 'fail' | 'skip';
  note: string;
}

/** 报告周期粒度：周报 / 月报 / 季报。 */
export type ReportPeriodKind = 'week' | 'month' | 'quarter';

/** 报告状态：草稿（可改）/ 已定稿（归档快照）。 */
export type ReportStatus = 'draft' | 'final';

/** 单个章节的来源：系统生成 / 手工编辑 / AI 生成。 */
export type ReportSectionOrigin = 'auto' | 'manual' | 'ai';

export interface ReportSection {
  /** 'overview' | 'progress' | 'metrics' | 'risks' | 'next' | 'okr' | 'support' */
  key: string;
  title: string;
  /** Markdown 纯文本 */
  body: string;
  origin: ReportSectionOrigin;
  updatedAt: string;
}

export interface Report {
  id: string;
  kind: ReportPeriodKind;
  /** '2026-W44' | '2026-11' | '2026-Q4' */
  period: string;
  title: string;
  /** 报告人，空串表示未填 */
  author: string;
  status: ReportStatus;
  /** 'weekly-external' | 'monthly-external' | 'quarterly-external' */
  templateId: string;
  sections: ReportSection[];
  generatedAt: string | null;
  finalizedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Workspace {
  version: number;
  items: Item[];
  edges: Edge[];
  areas: Area[];
  runs: SopRunEntry[];
  /**
   * 周报 / 月报 / 季报。v1 新增字段，缺省即空数组：
   * 旧文件、以及尚未更新的模块内 Workspace 字面量都可能没有这个键，
   * 所以类型上保持可选，读侧统一 `ws.reports ?? []`（归一化后一定有值）。
   */
  reports?: Report[];
  updatedAt: string;
}

export const WORKSPACE_VERSION = 1;

/** createItem 的输入（其余字段由 store 补默认值）。 */
export interface NewItemInput {
  kind: ItemKind;
  title: string;
  notes?: string;
  parentId?: string | null;
  status?: ItemStatus;
  tags?: string[];
  areaId?: string | null;
  order?: number;
  okr?: Partial<OkrData>;
  sop?: Partial<SopData>;
  gtd?: Partial<GtdData>;
  gantt?: Partial<GanttData>;
}

/**
 * updateItem 的补丁：顶层字段可选，四个 data 块按块浅合并。
 * 传入 `undefined` 的字段会被忽略（不会清除已有值）。
 */
export type ItemPatch = Partial<Omit<Item, 'id' | 'kind' | 'createdAt' | 'okr' | 'sop' | 'gtd' | 'gantt'>> & {
  okr?: Partial<OkrData>;
  sop?: Partial<SopData>;
  gtd?: Partial<GtdData>;
  gantt?: Partial<GanttData>;
};

/** createReport 的输入（其余字段由 store 补默认值）。 */
export interface NewReportInput {
  kind: ReportPeriodKind;
  /** '2026-W44' | '2026-11' | '2026-Q4'，由上层聚合层计算并负责合法性。 */
  period: string;
  title?: string;
  author?: string;
  templateId?: string;
  sections?: ReportSection[];
}

/**
 * updateReport 的补丁：只允许改标题、报告人与章节。
 * `sections` 传入时整份替换（不做逐节合并），未传的字段保持原值。
 */
export type ReportPatch = Partial<Pick<Report, 'title' | 'author' | 'sections'>>;

/** 周期粒度 -> 默认模板 id。聚合层生成草稿时也用它，避免两处各写一份映射。 */
export const REPORT_TEMPLATE_BY_KIND: Record<ReportPeriodKind, string> = {
  week: 'weekly-external',
  month: 'monthly-external',
  quarter: 'quarterly-external',
};

export const ITEM_KINDS: ItemKind[] = [
  'objective',
  'keyresult',
  'project',
  'action',
  'sop',
  'step',
  'milestone',
  'note',
  'reference',
];

export const ITEM_STATUSES: ItemStatus[] = [
  'inbox',
  'next',
  'active',
  'waiting',
  'scheduled',
  'someday',
  'done',
  'dropped',
];

export const STATUS_LABELS: Record<ItemStatus, string> = {
  inbox: '收件箱',
  next: '下一步',
  active: '进行中',
  waiting: '等待中',
  scheduled: '已排期',
  someday: '将来',
  done: '已完成',
  dropped: '已放弃',
};

export const KIND_LABELS: Record<ItemKind, string> = {
  objective: '目标',
  keyresult: '关键结果',
  project: '项目',
  action: '行动',
  sop: 'SOP',
  step: '步骤',
  milestone: '里程碑',
  note: '笔记',
  reference: '资料',
};

export const REPORT_PERIOD_KINDS: ReportPeriodKind[] = ['week', 'month', 'quarter'];

export const REPORT_STATUSES: ReportStatus[] = ['draft', 'final'];

export const REPORT_SECTION_ORIGINS: ReportSectionOrigin[] = ['auto', 'manual', 'ai'];

export const REPORT_PERIOD_LABELS: Record<ReportPeriodKind, string> = {
  week: '周报',
  month: '月报',
  quarter: '季报',
};

export const REPORT_STATUS_LABELS: Record<ReportStatus, string> = {
  draft: '草稿',
  final: '已定稿',
};
