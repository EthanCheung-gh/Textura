/**
 * 画布渲染的纯函数层：把领域节点整理成 React Flow 节点，并尽量复用上一次的对象引用。
 *
 * 目的：在数百节点规模下，选中/运行态/拖动等高频变化只重建真正变化的节点对象，
 * 未变化节点保持引用稳定，配合 React.memo 与 onlyRenderVisibleElements 避免整图重渲染。
 */
import type { Item } from '../../core/model';
import type { CanvasRunState, SopFlowNode, SopNodeData, SopNodeState } from './types';

export interface BuildCanvasNodesInput {
  /** 当前 SOP 的 step 条目（稳定顺序） */
  steps: readonly Item[];
  /** areaId -> color */
  areaColors: Readonly<Record<string, string>>;
  /** 展示坐标（已合并预览/拖拽草稿）；缺失时回落到 item.sop.canvas */
  positions: Readonly<Record<string, { x: number; y: number }>>;
  selectedId: string | null;
  run: CanvasRunState | null;
  previous?: readonly SopFlowNode[];
}

export function nodeStateFor(id: string, run: CanvasRunState | null): SopNodeState {
  if (!run) return 'idle';
  if (run.currentId === id) return 'current';
  if (run.failed.includes(id)) return 'failed';
  if (run.visited.includes(id)) return 'visited';
  return 'idle';
}

export function sameNodeData(a: SopNodeData, b: SopNodeData): boolean {
  return (
    a.title === b.title &&
    a.nodeType === b.nodeType &&
    a.owner === b.owner &&
    a.durationMin === b.durationMin &&
    a.checklistDone === b.checklistDone &&
    a.checklistTotal === b.checklistTotal &&
    a.areaColor === b.areaColor &&
    a.state === b.state
  );
}

function samePosition(
  a: { x: number; y: number },
  b: { x: number; y: number },
): boolean {
  return a.x === b.x && a.y === b.y;
}

/**
 * 构建画布节点：
 * - 未变化节点的**对象引用保持不变**（选中切换、运行高亮、拖动其它节点时）；
 * - `data` 只含原始值，便于 SopNode 的 memo 比较；
 * - 缺失坐标时回落到 `item.sop.canvas`，不会产生共享可变对象。
 */
export function buildCanvasNodes({
  steps,
  areaColors,
  positions,
  selectedId,
  run,
  previous,
}: BuildCanvasNodesInput): SopFlowNode[] {
  const previousById = new Map<string, SopFlowNode>();
  if (previous) {
    for (const node of previous) previousById.set(node.id, node);
  }

  return steps.map((item) => {
    const previousNode = previousById.get(item.id);
    const checklist = item.sop?.checklist ?? [];
    let checklistDone = 0;
    for (const entry of checklist) {
      if (entry.done) checklistDone += 1;
    }
    const title = item.title;
    const nodeType = item.sop?.nodeType ?? 'action';
    const owner = item.sop?.owner ?? '';
    const durationMin = item.sop?.durationMin ?? null;
    const areaColor = item.areaId ? (areaColors[item.areaId] ?? null) : null;
    const state = nodeStateFor(item.id, run);
    const selected = selectedId === item.id;
    const position = positions[item.id] ?? item.sop?.canvas ?? { x: 0, y: 0 };

    const previousData = previousNode?.data;
    const dataUnchanged =
      previousData !== undefined &&
      previousData.title === title &&
      previousData.nodeType === nodeType &&
      previousData.owner === owner &&
      previousData.durationMin === durationMin &&
      previousData.checklistDone === checklistDone &&
      previousData.checklistTotal === checklist.length &&
      previousData.areaColor === areaColor &&
      previousData.state === state;

    const data: SopNodeData = dataUnchanged
      ? (previousData as SopNodeData)
      : {
          title,
          nodeType,
          owner,
          durationMin,
          checklistDone,
          checklistTotal: checklist.length,
          areaColor,
          state,
        };

    if (previousNode && dataUnchanged && samePosition(previousNode.position, position)) {
      if (previousNode.selected === selected) return previousNode;
      return { ...previousNode, selected };
    }

    return {
      id: item.id,
      type: 'sop',
      position,
      selected,
      data,
    };
  });
}
