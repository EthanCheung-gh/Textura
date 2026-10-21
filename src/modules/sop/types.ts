import type { Node } from '@xyflow/react';
import type { SopNodeType } from '../../core/model';
import type { RunResult } from './runLogic';

/** 画布选中态（节点 / 连线），与 store 的 selectedId（条目选中）互不干扰。 */
export type SopSelection =
  | { kind: 'node'; id: string }
  | { kind: 'edge'; id: string }
  | null;

/** 一次运行会话。产生于「运行」按钮，结束于流程终点或手动退出。 */
export interface RunSession {
  currentId: string;
  visited: string[];
  failed: string[];
  startedAt: string;
  results: RunResult[];
}

export type SopNodeState = 'idle' | 'current' | 'visited' | 'failed';

/** 传给自定义节点的数据：只含原始值，便于 memo 比较。 */
export type SopNodeData = {
  title: string;
  nodeType: SopNodeType;
  owner: string;
  durationMin: number | null;
  checklistDone: number;
  checklistTotal: number;
  areaColor: string | null;
  state: SopNodeState;
};

export type SopFlowNode = Node<SopNodeData, 'sop'>;

/** 构建节点所需的运行高亮信息（只读、原始值）。 */
export interface CanvasRunState {
  currentId: string | null;
  visited: readonly string[];
  failed: readonly string[];
}
