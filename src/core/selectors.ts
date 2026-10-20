/**
 * 纯函数选择器。所有模块共用，禁止在模块内复制领域逻辑。
 */
import type { Area, Edge, Item, ItemStatus, ItemKind, Workspace } from './model';
import { ITEM_STATUSES } from './model';
import { clamp, dateKey, isDone, isOpen } from './utils';

function itemMap(ws: Workspace): Map<string, Item> {
  return new Map(ws.items.map((item) => [item.id, item]));
}

function sortByOrder(items: Item[]): Item[] {
  return [...items].sort((a, b) => a.order - b.order || a.createdAt.localeCompare(b.createdAt));
}

export function itemById(ws: Workspace, id: string): Item | undefined {
  return ws.items.find((item) => item.id === id);
}

export function areaById(ws: Workspace, id: string): Area | undefined {
  return ws.areas.find((area) => area.id === id);
}

/** 直接子项，按 order 升序。parentId 传 null 可取根级条目。 */
export function childrenOf(ws: Workspace, parentId: string | null): Item[] {
  return sortByOrder(ws.items.filter((item) => item.parentId === parentId));
}

/** 全部子孙（不含自身），深度优先、按 order。 */
export function descendantsOf(ws: Workspace, id: string): Item[] {
  const result: Item[] = [];
  const walk = (parentId: string) => {
    for (const child of childrenOf(ws, parentId)) {
      result.push(child);
      walk(child.id);
    }
  };
  walk(id);
  return result;
}

/** 祖先链：从直接父级到根（最近优先）。带环保护。 */
export function ancestorsOf(ws: Workspace, id: string): Item[] {
  const map = itemMap(ws);
  const result: Item[] = [];
  const seen = new Set<string>([id]);
  let current = map.get(id)?.parentId ?? null;
  while (current && !seen.has(current)) {
    const parent = map.get(current);
    if (!parent) break;
    result.push(parent);
    seen.add(current);
    current = parent.parentId;
  }
  return result;
}

export function itemsOfKind(ws: Workspace, kind: ItemKind): Item[] {
  return sortByOrder(ws.items.filter((item) => item.kind === kind));
}

export function objectivesOfPeriod(ws: Workspace, period: string): Item[] {
  return sortByOrder(ws.items.filter((item) => item.kind === 'objective' && item.okr?.period === period));
}

/** 所有 Objective 的周期，倒序（最新在前）。 */
export function okrPeriods(ws: Workspace): string[] {
  const periods = new Set<string>();
  for (const item of ws.items) {
    if (item.kind === 'objective' && item.okr?.period) periods.add(item.okr.period);
  }
  return [...periods].sort((a, b) => b.localeCompare(a));
}

/**
 * 汇总进度 0..100 的整数：
 * - objective：其 KR 的平均；无 KR 时退回子项完成比
 * - keyresult：有 metric 用 (current-start)/(target-start)；否则 done?100:子项完成比
 * - project / sop：子项完成比
 * - 其余：done?100:0
 */
export function rollupProgress(ws: Workspace, id: string): number {
  const map = itemMap(ws);
  const childrenByParent = new Map<string, Item[]>();
  for (const item of ws.items) {
    if (!item.parentId) continue;
    const list = childrenByParent.get(item.parentId);
    if (list) list.push(item);
    else childrenByParent.set(item.parentId, [item]);
  }
  const visiting = new Set<string>();

  const childrenOfId = (parentId: string): Item[] =>
    sortByOrder(childrenByParent.get(parentId) ?? []);

  const compute = (item: Item): number => {
    if (visiting.has(item.id)) return 0;
    visiting.add(item.id);
    const children = childrenOfId(item.id);
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
    visiting.delete(item.id);
    return clamp(Math.round(value), 0, 100);
  };

  const target = map.get(id);
  return target ? compute(target) : 0;
}

function completion(children: Item[]): number {
  if (children.length === 0) return 0;
  return (children.filter(isDone).length / children.length) * 100;
}

export function inboxItems(ws: Workspace): Item[] {
  return sortByOrder(ws.items.filter((item) => item.status === 'inbox'));
}

/** 可执行的「下一步」：action / project 且 status 为 next（SOP step 由流程视图负责）。 */
export function nextActions(ws: Workspace): Item[] {
  return sortByOrder(
    ws.items.filter(
      (item) => item.status === 'next' && (item.kind === 'action' || item.kind === 'project'),
    ),
  );
}

export function waitingItems(ws: Workspace): Item[] {
  return sortByOrder(ws.items.filter((item) => item.status === 'waiting'));
}

export function somedayItems(ws: Workspace): Item[] {
  return sortByOrder(ws.items.filter((item) => item.status === 'someday'));
}

/** 与 [fromISO, toISO] 有交集的排期条目（按 start 升序）。含已完成条目。 */
export function scheduledItemsInRange(ws: Workspace, fromISO: string, toISO: string): Item[] {
  let from = dateKey(fromISO);
  let to = dateKey(toISO);
  if (!from || !to) return [];
  if (from > to) [from, to] = [to, from];
  return ws.items
    .filter((item) => {
      if (!item.gantt) return false;
      const start = dateKey(item.gantt.start) ?? dateKey(item.gantt.end);
      const end = dateKey(item.gantt.end) ?? dateKey(item.gantt.start);
      if (!start || !end) return false;
      return start <= to && end >= from;
    })
    .sort((a, b) => {
      const aStart = dateKey(a.gantt?.start) ?? dateKey(a.gantt?.end) ?? '';
      const bStart = dateKey(b.gantt?.start) ?? dateKey(b.gantt?.end) ?? '';
      return aStart.localeCompare(bStart) || a.order - b.order;
    });
}

/** 已过截止日期且未完成/未放弃的条目。 */
export function overdueItems(ws: Workspace, today: string): Item[] {
  const todayKey = dateKey(today);
  if (!todayKey) return [];
  return ws.items
    .filter((item) => {
      const end = dateKey(item.gantt?.end);
      return Boolean(end) && end! < todayKey && isOpen(item);
    })
    .sort((a, b) => (dateKey(a.gantt?.end) ?? '').localeCompare(dateKey(b.gantt?.end) ?? ''));
}

/** 今天到期且未完成/未放弃的条目。 */
export function dueTodayItems(ws: Workspace, today: string): Item[] {
  const todayKey = dateKey(today);
  if (!todayKey) return [];
  return ws.items.filter((item) => {
    const end = dateKey(item.gantt?.end);
    return Boolean(end) && end === todayKey && isOpen(item);
  });
}

export function edgeTargetsOf(ws: Workspace, id: string, type: Edge['type']): Item[] {
  const map = itemMap(ws);
  const seen = new Set<string>();
  const result: Item[] = [];
  for (const edge of ws.edges) {
    if (edge.from !== id || edge.type !== type) continue;
    const target = map.get(edge.to);
    if (target && !seen.has(target.id)) {
      seen.add(target.id);
      result.push(target);
    }
  }
  return result;
}

export function edgeSourcesOf(ws: Workspace, id: string, type: Edge['type']): Item[] {
  const map = itemMap(ws);
  const seen = new Set<string>();
  const result: Item[] = [];
  for (const edge of ws.edges) {
    if (edge.to !== id || edge.type !== type) continue;
    const source = map.get(edge.from);
    if (source && !seen.has(source.id)) {
      seen.add(source.id);
      result.push(source);
    }
  }
  return result;
}

/** SOP 画布图：属于该 SOP 的 step 节点 + 两端都在节点集中的 flow 边。 */
export function sopGraph(ws: Workspace, sopId: string): { nodes: Item[]; edges: Edge[] } {
  const nodes = sortByOrder(
    ws.items.filter((item) => {
      if (item.kind !== 'step') return false;
      if (item.parentId === sopId) return true;
      return ancestorsOf(ws, item.id).some((ancestor) => ancestor.id === sopId);
    }),
  );
  const ids = new Set(nodes.map((node) => node.id));
  const edges = ws.edges.filter(
    (edge) => edge.type === 'flow' && ids.has(edge.from) && ids.has(edge.to),
  );
  return { nodes, edges };
}

export function countByStatus(ws: Workspace): Record<ItemStatus, number> {
  const counts = Object.fromEntries(ITEM_STATUSES.map((status) => [status, 0])) as Record<
    ItemStatus,
    number
  >;
  for (const item of ws.items) counts[item.status] += 1;
  return counts;
}

/** 层级深度：根级为 0。 */
export function treeDepth(ws: Workspace, id: string): number {
  return ancestorsOf(ws, id).length;
}

/** 从根到自身的标题路径。 */
export function itemPathTitles(ws: Workspace, id: string): string[] {
  const item = itemById(ws, id);
  if (!item) return [];
  return [...ancestorsOf(ws, id).reverse().map((ancestor) => ancestor.title), item.title];
}
