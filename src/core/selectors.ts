/**
 * 纯函数选择器。所有模块共用，禁止在模块内复制领域逻辑。
 *
 * 性能契约：同一 `Workspace` 对象身份只构建一次索引（WeakMap）；
 * 因此 store 必须保持 workspace 与 Item 的不可变更新。
 */
import type { Area, Edge, Item, ItemStatus, ItemKind, Workspace } from './model';
import { ITEM_STATUSES } from './model';
import { clamp, dateKey, isDone, isOpen } from './utils';

export interface WorkspaceIndex {
  byId: Map<string, Item>;
  children: Map<string | null, readonly Item[]>;
  byKind: Map<ItemKind, readonly Item[]>;
  objectivesByPeriod: Map<string, readonly Item[]>;
  byStatus: Map<ItemStatus, readonly Item[]>;
  edgesFrom: Map<string, readonly Edge[]>;
  edgesTo: Map<string, readonly Edge[]>;
  areas: Map<string, Area>;
  rollups: Map<string, number>;
  paths: Map<string, readonly Item[]>;
  memo: Map<string, unknown>;
}

const EMPTY_ITEMS: readonly Item[] = Object.freeze([]);
const EMPTY_EDGES: readonly Edge[] = Object.freeze([]);
const indexByWorkspace = new WeakMap<Workspace, WorkspaceIndex>();

function compareItems(a: Item, b: Item): number {
  return a.order - b.order || a.createdAt.localeCompare(b.createdAt);
}

function freezeItems(items: Item[]): readonly Item[] {
  return Object.freeze(items.sort(compareItems));
}

function pushGroup<T>(map: Map<string, T[]>, key: string, value: T): void {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

function buildIndex(ws: Workspace): WorkspaceIndex {
  const byId = new Map<string, Item>();
  const areas = new Map<string, Area>();
  const children = new Map<string | null, Item[]>();
  const byKind = new Map<ItemKind, Item[]>();
  const objectivesByPeriod = new Map<string, Item[]>();
  const byStatus = new Map<ItemStatus, Item[]>();
  const edgesFrom = new Map<string, Edge[]>();
  const edgesTo = new Map<string, Edge[]>();

  for (const status of ITEM_STATUSES) byStatus.set(status, []);

  for (const item of ws.items) {
    byId.set(item.id, item);
    if (item.parentId !== null) {
      const list = children.get(item.parentId);
      if (list) list.push(item);
      else children.set(item.parentId, [item]);
    } else {
      const list = children.get(null);
      if (list) list.push(item);
      else children.set(null, [item]);
    }

    const kindList = byKind.get(item.kind);
    if (kindList) kindList.push(item);
    else byKind.set(item.kind, [item]);

    byStatus.get(item.status)!.push(item);

    if (item.kind === 'objective' && item.okr?.period) {
      pushGroup(objectivesByPeriod, item.okr.period, item);
    }
  }

  for (const area of ws.areas) areas.set(area.id, area);
  for (const edge of ws.edges) {
    pushGroup(edgesFrom, edge.from, edge);
    pushGroup(edgesTo, edge.to, edge);
  }

  for (const [parentId, list] of children) {
    children.set(parentId, freezeItems(list) as Item[]);
  }
  for (const [kind, list] of byKind) byKind.set(kind, freezeItems(list) as Item[]);
  for (const [status, list] of byStatus) byStatus.set(status, freezeItems(list) as Item[]);
  for (const [period, list] of objectivesByPeriod) {
    objectivesByPeriod.set(period, freezeItems(list) as Item[]);
  }
  for (const [id, list] of edgesFrom) edgesFrom.set(id, Object.freeze(list) as Edge[]);
  for (const [id, list] of edgesTo) edgesTo.set(id, Object.freeze(list) as Edge[]);

  const memo = new Map<string, unknown>();
  memo.set('allEdges', Object.freeze([...ws.edges]));

  return {
    byId,
    children: children as Map<string | null, readonly Item[]>,
    byKind: byKind as Map<ItemKind, readonly Item[]>,
    objectivesByPeriod: objectivesByPeriod as Map<string, readonly Item[]>,
    byStatus: byStatus as Map<ItemStatus, readonly Item[]>,
    edgesFrom: edgesFrom as Map<string, readonly Edge[]>,
    edgesTo: edgesTo as Map<string, readonly Edge[]>,
    areas,
    rollups: new Map<string, number>(),
    paths: new Map<string, readonly Item[]>(),
    memo,
  };
}

/**
 * 取得（并缓存）工作区索引。
 *
 * **调用方必须保证 workspace 是不可变更新**：同一个 Workspace 对象身份
 * 只能对应同一份数据。store 的所有写操作都需要返回新的 workspace 对象。
 */
export function getWorkspaceIndex(ws: Workspace): WorkspaceIndex {
  const cached = indexByWorkspace.get(ws);
  if (cached) return cached;
  const index = buildIndex(ws);
  indexByWorkspace.set(ws, index);
  return index;
}

function memoValue<T>(index: WorkspaceIndex, key: string, create: () => T): T {
  if (index.memo.has(key)) return index.memo.get(key) as T;
  const value = create();
  index.memo.set(key, value);
  return value;
}

function readonlyItems(items: readonly Item[]): Item[] {
  return items as Item[];
}

export function itemById(ws: Workspace, id: string): Item | undefined {
  return getWorkspaceIndex(ws).byId.get(id);
}

export function areaById(ws: Workspace, id: string): Area | undefined {
  return getWorkspaceIndex(ws).areas.get(id);
}

/** 直接子项，按 order 升序。parentId 传 null 可取根级条目。 */
export function childrenOf(ws: Workspace, parentId: string | null): Item[] {
  return readonlyItems(getWorkspaceIndex(ws).children.get(parentId) ?? EMPTY_ITEMS);
}

/** 全部子孙（不含自身），深度优先、按 order。带 visited 保护，允许脏数据中存在环。 */
export function descendantsOf(ws: Workspace, id: string): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `descendants:${id}`, () => {
    const result: Item[] = [];
    const visited = new Set<string>([id]);
    const walk = (parentId: string) => {
      for (const child of index.children.get(parentId) ?? EMPTY_ITEMS) {
        if (visited.has(child.id)) continue;
        visited.add(child.id);
        result.push(child);
        walk(child.id);
      }
    };
    walk(id);
    return Object.freeze(result) as Item[];
  });
}

/** 祖先链：从直接父级到根（最近优先）。带环保护。 */
export function ancestorsOf(ws: Workspace, id: string): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `ancestors:${id}`, () => {
    const result: Item[] = [];
    const seen = new Set<string>([id]);
    let current = index.byId.get(id)?.parentId ?? null;
    while (current && !seen.has(current)) {
      const parent = index.byId.get(current);
      if (!parent) break;
      result.push(parent);
      seen.add(current);
      current = parent.parentId;
    }
    return Object.freeze(result) as Item[];
  });
}

/**
 * 找出所有父子环，返回形如 ['a','b','a'] 的 id 路径（首尾为同一节点）。
 * 自环返回 ['a','a']；无环返回空数组。纯函数，不修改工作区。
 */
export function findParentCycles(ws: Workspace): string[][] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'parentCycles', () => {
    const finished = new Set<string>();
    const cycles: string[][] = [];

    for (const item of index.byId.values()) {
      if (finished.has(item.id)) continue;
      const path: string[] = [];
      const seenInPath = new Map<string, number>();
      let current: string | null = item.id;

      while (current) {
        if (finished.has(current)) break;
        const previous = seenInPath.get(current);
        if (previous !== undefined) {
          cycles.push(Object.freeze([...path.slice(previous), current]) as string[]);
          break;
        }
        const node = index.byId.get(current);
        if (!node) break;
        seenInPath.set(current, path.length);
        path.push(current);
        current = node.parentId;
      }
      for (const pathId of path) finished.add(pathId);
    }
    return Object.freeze(cycles) as string[][];
  });
}

export function itemsOfKind(ws: Workspace, kind: ItemKind): Item[] {
  return readonlyItems(getWorkspaceIndex(ws).byKind.get(kind) ?? EMPTY_ITEMS);
}

export function objectivesOfPeriod(ws: Workspace, period: string): Item[] {
  return readonlyItems(getWorkspaceIndex(ws).objectivesByPeriod.get(period) ?? EMPTY_ITEMS);
}

/** 所有 Objective 的周期，倒序（最新在前）。 */
export function okrPeriods(ws: Workspace): string[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'okrPeriods', () => {
    const periods = [...index.objectivesByPeriod.keys()].sort((a, b) => b.localeCompare(a));
    return Object.freeze(periods) as string[];
  });
}

function completion(children: readonly Item[]): number {
  if (children.length === 0) return 0;
  return (children.filter(isDone).length / children.length) * 100;
}

/**
 * 汇总进度 0..100 的整数：
 * - objective：其 KR 的平均；无 KR 时退回子项完成比
 * - keyresult：有 metric 用 (current-start)/(target-start)；否则 done?100:子项完成比
 * - project / sop：子项完成比
 * - 其余：done?100:0
 */
export function rollupProgress(ws: Workspace, id: string): number {
  const index = getWorkspaceIndex(ws);
  const cached = index.rollups.get(id);
  if (cached !== undefined) return cached;

  const target = index.byId.get(id);
  if (!target) return 0;

  const visiting = new Set<string>();
  const compute = (item: Item): number => {
    const cachedRollup = index.rollups.get(item.id);
    if (cachedRollup !== undefined) return cachedRollup;
    if (visiting.has(item.id)) return 0;
    visiting.add(item.id);

    const children = index.children.get(item.id) ?? EMPTY_ITEMS;
    let value = 0;
    switch (item.kind) {
      case 'objective': {
        const keyResults = children.filter((child) => child.kind === 'keyresult');
        if (keyResults.length > 0) {
          value = keyResults.reduce((sum, child) => sum + compute(child), 0) / keyResults.length;
        } else {
          value = completion(children);
        }
        break;
      }
      case 'keyresult': {
        const metric = item.okr?.metric;
        if (metric && metric.target !== metric.start) {
          value = ((metric.current - metric.start) / (metric.target - metric.start)) * 100;
        } else if (isDone(item)) {
          value = 100;
        } else {
          value = completion(children);
        }
        break;
      }
      case 'project':
      case 'sop':
        value = completion(children);
        break;
      default:
        value = isDone(item) ? 100 : 0;
    }

    const result = clamp(Math.round(value), 0, 100);
    index.rollups.set(item.id, result);
    visiting.delete(item.id);
    return result;
  };

  return compute(target);
}

function statusItems(ws: Workspace, status: ItemStatus): readonly Item[] {
  return getWorkspaceIndex(ws).byStatus.get(status) ?? EMPTY_ITEMS;
}

export function inboxItems(ws: Workspace): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'inbox', () => readonlyItems(statusItems(ws, 'inbox')));
}

/** 可执行的「下一步」：action / project 且 status 为 next（SOP step 由流程视图负责）。 */
export function nextActions(ws: Workspace): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'nextActions', () => {
    const result = statusItems(ws, 'next').filter(
      (item) => item.kind === 'action' || item.kind === 'project',
    );
    return Object.freeze(result) as Item[];
  });
}

export function waitingItems(ws: Workspace): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'waiting', () => readonlyItems(statusItems(ws, 'waiting')));
}

export function somedayItems(ws: Workspace): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'someday', () => readonlyItems(statusItems(ws, 'someday')));
}

/** 预计算所有有日期的 item（start/end 已归一化为日期键），供区间查询复用。 */
function scheduledRows(
  index: WorkspaceIndex,
): readonly { item: Item; start: string; end: string }[] {
  return memoValue(index, 'scheduledRows', () => {
    const rows: { item: Item; start: string; end: string }[] = [];
    for (const item of index.byId.values()) {
      if (!item.gantt) continue;
      const start = dateKey(item.gantt.start) ?? dateKey(item.gantt.end);
      const end = dateKey(item.gantt.end) ?? dateKey(item.gantt.start);
      if (!start || !end) continue;
      rows.push({ item, start, end });
    }
    rows.sort((a, b) => a.start.localeCompare(b.start) || a.item.order - b.item.order);
    return Object.freeze(rows);
  });
}

/** 与 [fromISO, toISO] 有交集的排期条目（按 start 升序）。含已完成条目。 */
export function scheduledItemsInRange(ws: Workspace, fromISO: string, toISO: string): Item[] {
  let from = dateKey(fromISO);
  let to = dateKey(toISO);
  if (!from || !to) return readonlyItems(EMPTY_ITEMS);
  if (from > to) [from, to] = [to, from];

  const lower = from;
  const upper = to;
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `scheduled:${lower}|${upper}`, () => {
    const rows = scheduledRows(index);
    // rows 已按 start 排序：二分到 start <= upper 的前缀，再过滤 end >= lower。
    // 这样早期区间不需要扫描整张 10k 表。
    let low = 0;
    let high = rows.length;
    while (low < high) {
      const mid = (low + high) >>> 1;
      if (rows[mid].start <= upper) low = mid + 1;
      else high = mid;
    }
    const result: Item[] = [];
    for (let position = 0; position < low; position += 1) {
      const row = rows[position];
      if (row.end >= lower) result.push(row.item);
    }
    return Object.freeze(result) as Item[];
  });
}

/** 已过截止日期且未完成/未放弃的条目。 */
export function overdueItems(ws: Workspace, today: string): Item[] {
  const todayKey = dateKey(today);
  if (!todayKey) return readonlyItems(EMPTY_ITEMS);
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `overdue:${todayKey}`, () => {
    const result = [...index.byId.values()]
      .filter((item) => {
        const end = dateKey(item.gantt?.end);
        return Boolean(end) && end! < todayKey && isOpen(item);
      })
      .sort((a, b) =>
        (dateKey(a.gantt?.end) ?? '').localeCompare(dateKey(b.gantt?.end) ?? ''),
      );
    return Object.freeze(result) as Item[];
  });
}

/** 今天到期且未完成/未放弃的条目。 */
export function dueTodayItems(ws: Workspace, today: string): Item[] {
  const todayKey = dateKey(today);
  if (!todayKey) return readonlyItems(EMPTY_ITEMS);
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `dueToday:${todayKey}`, () => {
    const result = [...index.byId.values()].filter((item) => {
      const end = dateKey(item.gantt?.end);
      return Boolean(end) && end === todayKey && isOpen(item);
    });
    return Object.freeze(result) as Item[];
  });
}

export function edgeTargetsOf(ws: Workspace, id: string, type: Edge['type']): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `edgeTargets:${id}:${type}`, () => {
    const seen = new Set<string>();
    const result: Item[] = [];
    for (const edge of index.edgesFrom.get(id) ?? EMPTY_EDGES) {
      if (edge.type !== type) continue;
      const target = index.byId.get(edge.to);
      if (target && !seen.has(target.id)) {
        seen.add(target.id);
        result.push(target);
      }
    }
    return Object.freeze(result) as Item[];
  });
}

export function edgeSourcesOf(ws: Workspace, id: string, type: Edge['type']): Item[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `edgeSources:${id}:${type}`, () => {
    const seen = new Set<string>();
    const result: Item[] = [];
    for (const edge of index.edgesTo.get(id) ?? EMPTY_EDGES) {
      if (edge.type !== type) continue;
      const source = index.byId.get(edge.from);
      if (source && !seen.has(source.id)) {
        seen.add(source.id);
        result.push(source);
      }
    }
    return Object.freeze(result) as Item[];
  });
}

/** SOP 画布图：属于该 SOP 的 step 节点 + 两端都在节点集中的 flow 边。 */
export function sopGraph(ws: Workspace, sopId: string): { nodes: Item[]; edges: Edge[] } {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `sopGraph:${sopId}`, () => {
    const nodes = (index.byKind.get('step') ?? EMPTY_ITEMS).filter((item) => {
      if (item.parentId === sopId) return true;
      return ancestorsOf(ws, item.id).some((ancestor) => ancestor.id === sopId);
    });
    const ids = new Set(nodes.map((node) => node.id));
    const allEdges = (index.memo.get('allEdges') as Edge[] | undefined) ?? [];
    const edges = allEdges.filter(
      (edge) => edge.type === 'flow' && ids.has(edge.from) && ids.has(edge.to),
    );
    return Object.freeze({
      nodes: Object.freeze([...nodes]) as Item[],
      edges: Object.freeze(edges) as Edge[],
    });
  });
}

export function countByStatus(ws: Workspace): Record<ItemStatus, number> {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, 'countByStatus', () => {
    const counts = Object.fromEntries(
      ITEM_STATUSES.map((status) => [status, index.byStatus.get(status)?.length ?? 0]),
    ) as Record<ItemStatus, number>;
    return Object.freeze(counts);
  });
}

function pathOf(index: WorkspaceIndex, id: string): readonly Item[] {
  const cached = index.paths.get(id);
  if (cached) return cached;
  const item = index.byId.get(id);
  if (!item) {
    const empty: readonly Item[] = EMPTY_ITEMS;
    index.paths.set(id, empty);
    return empty;
  }
  const ancestors: Item[] = [];
  const seen = new Set<string>([id]);
  let current = item.parentId;
  while (current && !seen.has(current)) {
    const parent = index.byId.get(current);
    if (!parent) break;
    ancestors.push(parent);
    seen.add(current);
    current = parent.parentId;
  }
  const path = Object.freeze([...ancestors.reverse(), item]) as readonly Item[];
  index.paths.set(id, path);
  return path;
}

/** 层级深度：根级为 0。 */
export function treeDepth(ws: Workspace, id: string): number {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `treeDepth:${id}`, () => {
    const path = pathOf(index, id);
    return path.length === 0 ? 0 : path.length - 1;
  });
}

/** 从根到自身的标题路径。 */
export function itemPathTitles(ws: Workspace, id: string): string[] {
  const index = getWorkspaceIndex(ws);
  return memoValue(index, `pathTitles:${id}`, () => {
    const titles = pathOf(index, id).map((item) => item.title);
    return Object.freeze(titles) as string[];
  });
}
