/**
 * 从工作区自动汇总报告素材（纯函数，无副作用）。
 *
 * 性能契约：整份工作区**只遍历一次**建立本次汇总需要的本地索引
 * （`ws.items` 一趟 + `ws.runs` 一趟），绝不在循环内调用
 * `getWorkspaceIndex()` / `itemById()`（它们不是缓存命中就是整树重建，
 * 10k 条目下会退化成平方复杂度）。本文件因此不从 `core/selectors` 取索引。
 *
 * 窗口契约：一律按「自然周期」`[start 00:00, end 24:00]` 的本地时区日键比较，
 * 所以 `completedAt` 这类 ISO 时间戳必须先转本地日键（`toLocalDayKey`），
 * 不能直接用 `core/utils.dateKey` 截取前 10 位（那会得到 UTC 日期）。
 *
 * 行格式契约（**不存在外层括号**，这是硬规则）：
 * - 每条 `line` = `- <标题> · <meta>`，`meta` 内部再用 ` · ` 串联若干片段；
 * - 本模块**绝不**把 `title` 或 `meta` 包进 `（）`：标题、SOP 标题、等待对象、单位
 *   都是外部文本，本身就可能带括号，一包就会出现 `（等待 9 天（张三））` 这种
 *   对外难看的双层括号；用 ` · ` 分隔则任意外部文本混入都不会产生嵌套括号；
 * - 同理 `meta` 自己也不写 `（）`：进度写成 `当前 12/20 单 · 60% · 信心 7/10`，
 *   等待写成 `等待 9 天 · 张三`（等待对象为空时省略该片段）；
 * - 标题 / meta 内部的括号（用户自己写的）原样保留，不转义、不裁剪。
 */
import type { Area, Item, ReportPeriodKind, SopRunEntry, Workspace } from '../../core/model';
import { isDone, isOpen } from '../../core/utils';
import { metricPercent } from '../okr/okrMath';
import { periodRange, shiftPeriod } from './period';

export type FactKind = 'completed' | 'risk' | 'kr' | 'run' | 'nextUp';

export interface ReportFact {
  /** 工作区实体 id（risk 用 item.id，run 用 run.id，拉到即稳定）。 */
  id: string;
  kind: FactKind;
  title: string;
  /**
   * 单行补充信息，如 '完成于 11/02'、'超期 3 天'、'等待 9 天 · 张三'、
   * '当前 12/20 单 · 60% · 信心 7/10'。片段用 ` · ` 串联，**不写外层括号**。
   */
  meta: string;
  /** 插入正文的 Markdown 单行（可直接拼到某节）：`- <title> · <meta>`。 */
  line: string;
}

export interface ReportFacts {
  stats: {
    completed: number;
    /** 周期内更新的未完成条目数。 */
    openInWindow: number;
    /** facts 中 risk 的总数。 */
    risks: number;
    runs: number;
    inboxRemaining: number;
    /** 0..100。 */
    inboxProgress: number;
  };
  /** 顺序：completed → risk → kr → run → nextUp，同类内按时间 / 严重度排序。 */
  facts: ReportFact[];
}

/** 风险四类。 */
export type RiskCategory = 'overdue' | 'stuck' | 'waiting' | 'undated';

export const RISK_CATEGORY_LABELS: Record<RiskCategory, string> = {
  overdue: '超期',
  stuck: '停滞项目',
  waiting: '等待超 7 天',
  undated: '无日期关键任务',
};

export const RISK_CATEGORY_ORDER: RiskCategory[] = ['overdue', 'stuck', 'waiting', 'undated'];

/** 每类风险最多 5 条，合计上限 20。 */
export const RISK_LIMIT_PER_CATEGORY = 5;
export const RISK_LIMIT_TOTAL = 20;
/** KR / 运行 / 下周期计划的事实上限。 */
export const KR_FACT_LIMIT = 10;
export const RUN_FACT_LIMIT = 10;
export const NEXT_UP_FACT_LIMIT = 10;
/** 等待超过 7 天（严格大于）算风险。 */
export const WAITING_WARN_DAYS = 7;
export const UNASSIGNED_AREA_LABEL = '未归属领域';

/** 完成事实的领域分组（进度节直接消费，避免二次遍历工作区）。 */
export interface CompletedAreaGroup {
  areaId: string | null;
  /** 领域名，未归属为 `未归属领域`。 */
  name: string;
  facts: ReportFact[];
}

/** 带分组信息的扩展结果，供 draft 一次成型地拼正文。 */
export interface ReportFactsDetailed extends ReportFacts {
  period: { kind: ReportPeriodKind; key: string; start: string; end: string };
  nextPeriod: { key: string; start: string; end: string } | null;
  /** 完成事实按领域分组，顺序＝`ws.areas.order`，未归属领域排最后。 */
  completedByArea: CompletedAreaGroup[];
  riskGroups: Record<RiskCategory, ReportFact[]>;
  runCounts: { total: number; pass: number; fail: number; skip: number };
}

/**
 * ISO 时间戳 / 日期串 → 运行环境本地日历日（`YYYY-MM-DD`）。
 *
 * - 已经是 `YYYY-MM-DD` 的排期字段直接原样返回（它本来就是本地日键）；
 * - 完整时间戳用 `new Date()` + 本地 getter，而不是 `date-fns.parseISO`
 *   （10k 条目下要转换 3~4 万次，parseISO 的正则解析会成为主要开销）；
 * - 不能用 `core/utils.dateKey`：那是截取 ISO 前 10 位，得到的是 UTC 日期。
 *
 * 刻意不从 `modules/gtd/gtdLogic` 复用，避免报告模块依赖 GTD 模块。
 */
const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function toLocalDayKey(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (trimmed.length === 10) return DAY_KEY_PATTERN.test(trimmed) ? trimmed : null;
  const date = new Date(trimmed);
  if (Number.isNaN(date.getTime())) return null;
  const month = date.getMonth() + 1;
  const day = date.getDate();
  return `${date.getFullYear()}-${month < 10 ? '0' : ''}${month}-${day < 10 ? '0' : ''}${day}`;
}

/** 日键 → 'MM/dd'（等价 `formatDateKey(key, 'MM/dd')`，但不需要解析日期）。 */
function monthDayOf(dayKey: string | null): string {
  return dayKey ? `${dayKey.slice(5, 7)}/${dayKey.slice(8, 10)}` : '—';
}

/** 'YYYY-MM-DD' → UTC 零点毫秒，用于纯日历天数差（与时区无关）。 */
function dayKeyToUtc(dayKey: string): number {
  return Date.UTC(Number(dayKey.slice(0, 4)), Number(dayKey.slice(5, 7)) - 1, Number(dayKey.slice(8, 10)));
}

/** 两个日键之间的日历天数差（to - from）。 */
function daysBetweenKeys(from: string, to: string): number {
  return Math.round((dayKeyToUtc(to) - dayKeyToUtc(from)) / 86_400_000);
}

function inWindow(day: string | null, start: string, end: string): boolean {
  return day !== null && day >= start && day <= end;
}

/** 行格式：`- <标题> · <meta>`，任何位置都不加外层括号（规则见 `makeFact`）。 */
function makeFact(id: string, kind: FactKind, title: string, meta: string): ReportFact {
  return { id, kind, title, meta, line: `- ${title} · ${meta}` };
}

export function factLine(fact: ReportFact): string {
  return fact.line;
}

function byOrderThenId(a: Item, b: Item): number {
  return a.order - b.order || a.id.localeCompare(b.id);
}

const RUN_RESULT_LABELS: Record<SopRunEntry['result'], string> = {
  pass: '通过',
  fail: '失败',
  skip: '跳过',
};

interface CompletedRow {
  item: Item;
  day: string;
  at: string;
}

interface RunRow {
  run: SopRunEntry;
  day: string;
  title: string;
  sopTitle: string;
}

/**
 * 子树里是否存在 next/active 条目（含自身）。
 * 迭代式后序遍历 + memo，整份工作区合计 O(n)，带环保护。
 */
function subtreeActive(
  root: Item,
  childrenByParent: Map<string, Item[]>,
  memo: Map<string, boolean>,
): boolean {
  const cached = memo.get(root.id);
  if (cached !== undefined) return cached;

  const stack: { item: Item; expanded: boolean }[] = [{ item: root, expanded: false }];
  const visited = new Set<string>();
  while (stack.length > 0) {
    const frame = stack.pop() as { item: Item; expanded: boolean };
    const { item } = frame;
    if (!frame.expanded) {
      if (memo.has(item.id) || visited.has(item.id)) continue;
      visited.add(item.id);
      stack.push({ item, expanded: true });
      for (const child of childrenByParent.get(item.id) ?? []) {
        if (!memo.has(child.id)) stack.push({ item: child, expanded: false });
      }
      continue;
    }
    let active = item.status === 'next' || item.status === 'active';
    if (!active) {
      for (const child of childrenByParent.get(item.id) ?? []) {
        if (memo.get(child.id) === true) {
          active = true;
          break;
        }
      }
    }
    memo.set(item.id, active);
  }
  return memo.get(root.id) ?? false;
}

/** 停滞项目：未完成、且整棵子树里没有任何 next/active 的子动作。 */
function isStuckProject(
  project: Item,
  childrenByParent: Map<string, Item[]>,
  memo: Map<string, boolean>,
): boolean {
  if (!isOpen(project)) return false;
  for (const child of childrenByParent.get(project.id) ?? []) {
    if (subtreeActive(child, childrenByParent, memo)) return false;
  }
  return true;
}

function collectRunRows(
  ws: Workspace,
  windowStart: string,
  windowEnd: string,
  titleById: Map<string, string>,
  dayOf: (value: string | null | undefined) => string | null,
): RunRow[] {
  const rows: RunRow[] = [];
  for (const run of ws.runs) {
    const day = dayOf(run.at);
    if (!inWindow(day, windowStart, windowEnd)) continue;
    const sopTitle = titleById.get(run.sopId) ?? '';
    const stepTitle = titleById.get(run.stepId) ?? '';
    rows.push({
      run,
      day: day as string,
      title: stepTitle || sopTitle || '未命名步骤',
      sopTitle,
    });
  }
  rows.sort((a, b) => b.run.at.localeCompare(a.run.at) || a.run.id.localeCompare(b.run.id));
  return rows;
}

/**
 * 收集周期内的报告素材。
 *
 * `period` 非法（`periodRange` 返回 null）时抛 `非法周期：<period>`：
 * 聚合层不允许产出归属不明的报告，静默返回空数据只会把错误推迟到页面层。
 *
 * 严重度基准日恒为**周期末日**（契约写法是「gantt.end < 周期末日」），
 * 因此 `now` 不参与判定；保留该参数只为与页面层 / `buildReportSections` 签名一致，
 * 以及将来需要「按今天截止」口径时不必改签名。
 */
export function collectFactsDetailed(
  ws: Workspace,
  kind: ReportPeriodKind,
  period: string,
  now: Date = new Date(),
): ReportFactsDetailed {
  const range = periodRange(kind, period);
  if (!range) throw new Error('非法周期：' + period);

  const windowStart = range.start;
  const windowEnd = range.end;
  /** 风险严重度基准日 = 周期末日（含），契约见模块头注释。 */
  const referenceDay = windowEnd;
  void now;

  const nextKey = shiftPeriod(kind, period, 1);
  const nextRange = nextKey ? periodRange(kind, nextKey) : null;

  /** 同一次汇总内复用日键换算（真实工作区里大量排期/时间戳是重复值）。 */
  const dayCache = new Map<string, string | null>();
  const dayOf = (value: string | null | undefined): string | null => {
    if (!value) return null;
    const cached = dayCache.get(value);
    if (cached !== undefined) return cached;
    const key = toLocalDayKey(value);
    dayCache.set(value, key);
    return key;
  };

  // 只在真的有 SOP 运行时收集标题表，省掉 10k 条目下的一次全量 Map 填充。
  const titleById = new Map<string, string>();
  const needRunTitles = ws.runs.length > 0;

  const completedRows: CompletedRow[] = [];
  const overdueCandidates: Item[] = [];
  const waitingCandidates: { item: Item; sinceDay: string }[] = [];
  const undatedCandidates: Item[] = [];
  const krCandidates: { item: Item; percent: number | null }[] = [];
  const nextUpCandidates: Item[] = [];
  const projectCandidates: Item[] = [];
  /** parentId → 子项，用于停滞项目判定（本次遍历顺手建立）。 */
  const childrenByParent = new Map<string, Item[]>();

  let openInWindow = 0;
  let inboxRemaining = 0;
  let capturedInWindow = 0;
  let clearedInWindow = 0;

  for (const item of ws.items) {
    // SOP / 步骤标题（run 事实用）顺手在同一趟里收齐，避免第二遍全量遍历。
    if (needRunTitles && (item.kind === 'sop' || item.kind === 'step')) {
      titleById.set(item.id, item.title);
    }

    if (item.parentId !== null) {
      const siblings = childrenByParent.get(item.parentId);
      if (siblings) siblings.push(item);
      else childrenByParent.set(item.parentId, [item]);
    }

    // 完成：completedAt 的本地日落在窗口内（含首尾两天）。
    const completedDay = dayOf(item.completedAt);
    if (inWindow(completedDay, windowStart, windowEnd)) {
      completedRows.push({ item, day: completedDay as string, at: item.completedAt as string });
    }

    const open = isOpen(item);

    // 进行中：窗口内被更新过且仍未完成。
    if (open && inWindow(dayOf(item.updatedAt), windowStart, windowEnd)) {
      openInWindow += 1;
    }

    if (item.status === 'inbox') inboxRemaining += 1;

    // 收件箱清理：本周期内收集的条目里已澄清并离开收件箱的比例。
    const capturedDay = dayOf(item.gtd?.capturedAt);
    if (inWindow(capturedDay, windowStart, windowEnd)) {
      capturedInWindow += 1;
      if (item.gtd?.clarified && item.status !== 'inbox') clearedInWindow += 1;
    }

    if (!open) continue;

    const endDay = dayOf(item.gantt?.end);

    // 风险 1：超期——截止日早于基准日（= 周期末日）。
    if (endDay && endDay < referenceDay) {
      overdueCandidates.push(item);
    }

    // 风险 3：等待超 7 天。
    if (item.status === 'waiting' && item.gtd?.waitingFor) {
      const sinceDay = dayOf(item.gtd.capturedAt ?? item.updatedAt ?? item.createdAt);
      if (sinceDay && daysBetweenKeys(sinceDay, referenceDay) > WAITING_WARN_DAYS) {
        waitingCandidates.push({ item, sinceDay });
      }
    }

    // 风险 4：无日期关键任务（next/active 的 action / project 且没有 gantt.end）。
    if (
      (item.kind === 'action' || item.kind === 'project') &&
      (item.status === 'next' || item.status === 'active') &&
      !endDay
    ) {
      undatedCandidates.push(item);
    }

    if (item.kind === 'keyresult' && !isDone(item)) {
      krCandidates.push({ item, percent: metricPercent(item.okr?.metric) });
    }

    if (item.kind === 'project') projectCandidates.push(item);

    // 下周期候选：下个自然周期内到期且仍待办。
    if (
      nextRange &&
      (item.status === 'next' || item.status === 'active') &&
      inWindow(endDay, nextRange.start, nextRange.end)
    ) {
      nextUpCandidates.push(item);
    }
  }

  /* ---------------- 风险 2：停滞项目 ---------------- */

  const activeMemo = new Map<string, boolean>();
  const stuckProjects = projectCandidates.filter((project) =>
    isStuckProject(project, childrenByParent, activeMemo),
  );

  /* ---------------- 事实成型 ---------------- */

  const areaNameById = new Map<string, string>();
  const areaOrderById = new Map<string, number>();
  const areaByIdMap = new Map<string, Area>();
  for (const area of ws.areas) {
    areaNameById.set(area.id, area.name);
    areaOrderById.set(area.id, area.order);
    areaByIdMap.set(area.id, area);
  }

  const completedEntries = [...completedRows]
    .sort(
      (a, b) =>
        b.at.localeCompare(a.at) || a.item.order - b.item.order || a.item.id.localeCompare(b.item.id),
    )
    .map((row) => ({
      row,
      fact: makeFact(row.item.id, 'completed', row.item.title, `完成于 ${monthDayOf(row.day)}`),
    }));
  const completed = completedEntries.map((entry) => entry.fact);

  const overdueFacts: ReportFact[] = [...overdueCandidates]
    .sort((a, b) => {
      const aEnd = dayOf(a.gantt?.end) ?? '';
      const bEnd = dayOf(b.gantt?.end) ?? '';
      return aEnd.localeCompare(bEnd) || byOrderThenId(a, b);
    })
    .slice(0, RISK_LIMIT_PER_CATEGORY)
    .map((item) => {
      const endDay = dayOf(item.gantt?.end) as string;
      const days = Math.max(1, daysBetweenKeys(endDay, referenceDay));
      return makeFact(item.id, 'risk', item.title, `超期 ${days} 天`);
    });

  const stuckFacts: ReportFact[] = [...stuckProjects]
    .sort(byOrderThenId)
    .slice(0, RISK_LIMIT_PER_CATEGORY)
    .map((item) => makeFact(item.id, 'risk', item.title, '无下一步动作'));

  const waitingFacts: ReportFact[] = [...waitingCandidates]
    .sort((a, b) => a.sinceDay.localeCompare(b.sinceDay) || byOrderThenId(a.item, b.item))
    .slice(0, RISK_LIMIT_PER_CATEGORY)
    .map(({ item, sinceDay }) => {
      const days = daysBetweenKeys(sinceDay, referenceDay);
      const waitingFor = item.gtd?.waitingFor?.trim();
      // 等待对象是外部文本，只用 ` · ` 追加，不加括号。
      const meta = waitingFor ? `等待 ${days} 天 · ${waitingFor}` : `等待 ${days} 天`;
      return makeFact(item.id, 'risk', item.title, meta);
    });

  const undatedFacts: ReportFact[] = [...undatedCandidates]
    .sort(byOrderThenId)
    .slice(0, RISK_LIMIT_PER_CATEGORY)
    .map((item) => makeFact(item.id, 'risk', item.title, '未排期'));

  const riskGroups: Record<RiskCategory, ReportFact[]> = {
    overdue: overdueFacts,
    stuck: stuckFacts,
    waiting: waitingFacts,
    undated: undatedFacts,
  };

  const riskFacts: ReportFact[] = [];
  for (const category of RISK_CATEGORY_ORDER) {
    for (const entry of riskGroups[category]) {
      if (riskFacts.length >= RISK_LIMIT_TOTAL) break;
      riskFacts.push(entry);
    }
    if (riskFacts.length >= RISK_LIMIT_TOTAL) break;
  }

  const krFacts: ReportFact[] = [...krCandidates]
    .sort((a, b) => (a.percent ?? -1) - (b.percent ?? -1) || byOrderThenId(a.item, b.item))
    .slice(0, KR_FACT_LIMIT)
    .map(({ item }) => {
      const metric = item.okr?.metric;
      const confidence = item.okr?.confidence ?? 5;
      const percent = metricPercent(metric);
      // 片段一律用 ` · ` 串联，不用括号：`当前 12/20 单 · 60% · 信心 7/10`。
      const segments: string[] = [];
      if (metric) {
        const unit = metric.unit ? ` ${metric.unit}` : '';
        segments.push(`当前 ${metric.current}/${metric.target}${unit}`);
        if (percent !== null) segments.push(`${percent}%`);
      }
      segments.push(`信心 ${confidence}/10`);
      return makeFact(item.id, 'kr', item.title, segments.join(' · '));
    });

  const runRows = collectRunRows(ws, windowStart, windowEnd, titleById, dayOf);
  const runFacts: ReportFact[] = runRows.slice(0, RUN_FACT_LIMIT).map((row) => {
    const result = RUN_RESULT_LABELS[row.run.result];
    const suffix = row.sopTitle && row.sopTitle !== row.title ? `${row.sopTitle} · ` : '';
    return makeFact(row.run.id, 'run', row.title, `${suffix}${result} · ${monthDayOf(row.day)}`);
  });

  const nextUpFacts: ReportFact[] = [...nextUpCandidates]
    .sort((a, b) => {
      const aEnd = dayOf(a.gantt?.end) ?? '';
      const bEnd = dayOf(b.gantt?.end) ?? '';
      return aEnd.localeCompare(bEnd) || byOrderThenId(a, b);
    })
    .slice(0, NEXT_UP_FACT_LIMIT)
    .map((item) =>
      makeFact(item.id, 'nextUp', item.title, `截止 ${monthDayOf(dayOf(item.gantt?.end))}`),
    );

  /* ---------------- 按领域分组 ---------------- */

  const areaBuckets = new Map<string | null, ReportFact[]>();
  for (const entry of completedEntries) {
    const areaId = entry.row.item.areaId;
    const bucketKey = areaId && areaByIdMap.has(areaId) ? areaId : null;
    const bucket = areaBuckets.get(bucketKey);
    if (bucket) bucket.push(entry.fact);
    else areaBuckets.set(bucketKey, [entry.fact]);
  }
  const completedByArea: CompletedAreaGroup[] = [...areaBuckets.entries()]
    .map(([areaId, facts]) => ({
      areaId,
      name: areaId ? (areaNameById.get(areaId) ?? UNASSIGNED_AREA_LABEL) : UNASSIGNED_AREA_LABEL,
      facts,
    }))
    .sort((a, b) => {
      const aOrder = a.areaId
        ? (areaOrderById.get(a.areaId) ?? Number.MAX_SAFE_INTEGER)
        : Number.MAX_SAFE_INTEGER;
      const bOrder = b.areaId
        ? (areaOrderById.get(b.areaId) ?? Number.MAX_SAFE_INTEGER)
        : Number.MAX_SAFE_INTEGER;
      return aOrder - bOrder || a.name.localeCompare(b.name);
    });

  const runCounts = { total: runRows.length, pass: 0, fail: 0, skip: 0 };
  for (const row of runRows) runCounts[row.run.result] += 1;

  const inboxProgress =
    capturedInWindow > 0
      ? Math.round((clearedInWindow / capturedInWindow) * 100)
      : inboxRemaining === 0
        ? 100
        : 0;

  const facts: ReportFact[] = [...completed, ...riskFacts, ...krFacts, ...runFacts, ...nextUpFacts];

  return {
    period: { kind, key: period, start: windowStart, end: windowEnd },
    nextPeriod:
      nextRange && nextKey ? { key: nextKey, start: nextRange.start, end: nextRange.end } : null,
    stats: {
      completed: completedRows.length,
      openInWindow,
      risks: riskFacts.length,
      runs: runRows.length,
      inboxRemaining,
      inboxProgress,
    },
    facts,
    completedByArea,
    riskGroups,
    runCounts,
  };
}

/**
 * 契约面：只暴露 `{ stats, facts }`。
 * 需要分组信息（进度节按领域、风险节按类别、SOP 运行计数）时用 `collectFactsDetailed`，
 * 两者结果里的 stats / facts 完全一致（同一份计算结果）。
 */
export function collectFacts(
  ws: Workspace,
  kind: ReportPeriodKind,
  period: string,
  now: Date = new Date(),
): ReportFacts {
  const { stats, facts } = collectFactsDetailed(ws, kind, period, now);
  return { stats, facts };
}
