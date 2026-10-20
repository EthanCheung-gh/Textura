/**
 * dagre 分层布局封装（纯函数，可在 node 环境测试）。
 *
 * 只处理「节点 id + 边 from/to」这样的最小输入，输出画布绝对坐标；
 * 不接触 store、不接触 React，便于单测与复用。
 */
import dagre from '@dagrejs/dagre';

/** 与 SopNode 的视觉尺寸保持一致。 */
export const SOP_NODE_WIDTH = 200;
export const SOP_NODE_HEIGHT = 60;

export interface LayoutNodeInput {
  id: string;
}

export interface LayoutEdgeInput {
  from: string;
  to: string;
}

export interface LayoutOptions {
  rankdir?: 'TB' | 'LR';
  nodeWidth?: number;
  nodeHeight?: number;
  /** 同层节点间距 */
  nodesep?: number;
  /** 层间距 */
  ranksep?: number;
  /** 画布内边距（左上角留白） */
  margin?: number;
}

export interface LayoutPosition {
  x: number;
  y: number;
}

/**
 * 计算分层布局坐标（左上角锚点）。层级沿 `rankdir` 递进：
 * - TB（默认）：y 随层级递增，同层 y 相同；
 * - LR：x 随层级递增，同层 x 相同。
 *
 * 自环与重复边会被忽略；未知节点的边会被忽略。
 */
export function layoutPositions(
  nodes: readonly LayoutNodeInput[],
  edges: readonly LayoutEdgeInput[],
  options: LayoutOptions = {},
): Record<string, LayoutPosition> {
  const {
    rankdir = 'TB',
    nodeWidth = SOP_NODE_WIDTH,
    nodeHeight = SOP_NODE_HEIGHT,
    nodesep = 60,
    ranksep = 90,
    margin = 24,
  } = options;

  const graph = new dagre.graphlib.Graph();
  graph.setGraph({ rankdir, nodesep, ranksep, marginx: margin, marginy: margin });
  graph.setDefaultEdgeLabel(() => ({}));

  const ids = new Set<string>();
  for (const node of nodes) {
    if (!node.id || ids.has(node.id)) continue;
    ids.add(node.id);
    graph.setNode(node.id, { width: nodeWidth, height: nodeHeight });
  }

  const seenEdges = new Set<string>();
  for (const edge of edges) {
    if (!ids.has(edge.from) || !ids.has(edge.to) || edge.from === edge.to) continue;
    const key = `${edge.from}->${edge.to}`;
    if (seenEdges.has(key)) continue;
    seenEdges.add(key);
    graph.setEdge(edge.from, edge.to);
  }

  dagre.layout(graph);

  const positions: Record<string, LayoutPosition> = {};
  for (const id of ids) {
    const laid = graph.node(id) as { x?: number; y?: number } | undefined;
    if (!laid || typeof laid.x !== 'number' || typeof laid.y !== 'number') continue;
    positions[id] = {
      x: Math.round(laid.x - nodeWidth / 2),
      y: Math.round(laid.y - nodeHeight / 2),
    };
  }
  return positions;
}

export interface CanvasPosition {
  id: string;
  x: number;
  y: number;
}

/**
 * 把画布坐标整理成 store 可用的补丁列表：
 * 取整、去重（同 id 取最后一次）、可选的「与现有坐标比较后只保留变化项」。
 */
export function canvasPositionsToPatch(
  positions: readonly CanvasPosition[],
  current?: Readonly<Record<string, LayoutPosition>>,
): CanvasPosition[] {
  const latest = new Map<string, CanvasPosition>();
  for (const entry of positions) {
    if (!entry.id) continue;
    latest.set(entry.id, { id: entry.id, x: Math.round(entry.x), y: Math.round(entry.y) });
  }
  const result: CanvasPosition[] = [];
  for (const entry of latest.values()) {
    const before = current?.[entry.id];
    if (before && before.x === entry.x && before.y === entry.y) continue;
    result.push(entry);
  }
  return result;
}
