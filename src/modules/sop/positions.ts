/**
 * 画布坐标写回的纯函数层。
 *
 * 拖动结束 / 自动布局结束后，先把 React Flow 的节点位置整理成「只包含变化项」的补丁，
 * 再交给 store 一次性写回 `item.sop.canvas`。组件里不散落取整 / 去重逻辑。
 */
import { canvasPositionsToPatch } from './layout';
import type { LayoutPosition } from './layout';
import type { ItemPatch } from '../../core/model';

export interface FlowNodePosition {
  id: string;
  position: { x: number; y: number };
}

export interface CanvasPatch {
  id: string;
  canvas: { x: number; y: number };
}

/** `store.updateItems` 的单条载荷。 */
export interface CanvasPatchUpdate {
  id: string;
  patch: ItemPatch;
}

/**
 * @param nodes React Flow 节点（或任何带 id + position 的形状）
 * @param current 现有 `sop.canvas` 映射；提供时只返回位置真正变化的节点
 */
export function positionsToPatch(
  nodes: readonly FlowNodePosition[],
  current?: Readonly<Record<string, LayoutPosition>>,
): CanvasPatch[] {
  const flat = nodes.map((node) => ({
    id: node.id,
    x: node.position.x,
    y: node.position.y,
  }));
  return canvasPositionsToPatch(flat, current).map((entry) => ({
    id: entry.id,
    canvas: { x: entry.x, y: entry.y },
  }));
}

/**
 * 把整批画布补丁整理成 `updateItems` 载荷：调用方只需触发一次批量写入，
 * 从而只产生一条历史快照与一次防抖保存。
 */
export function canvasPatchesToUpdateItems(
  patches: readonly CanvasPatch[],
): CanvasPatchUpdate[] {
  return patches.map((patch) => ({
    id: patch.id,
    patch: { sop: { canvas: patch.canvas } },
  }));
}
