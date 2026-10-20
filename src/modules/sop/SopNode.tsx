/** SOP 画布自定义节点：按 nodeType 区分形状与语义色。 */
import { Handle, Position } from '@xyflow/react';
import type { Node, NodeProps } from '@xyflow/react';
import clsx from 'clsx';
import type { SopNodeType } from '../../core/model';

export type SopNodeState = 'idle' | 'current' | 'visited' | 'failed';

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

export const NODE_TYPE_LABELS: Record<SopNodeType, string> = {
  start: '开始',
  action: '行动',
  decision: '判断',
  check: '检查',
  end: '结束',
  note: '便签',
};

export function SopNodeView({ data, selected }: NodeProps<SopFlowNode>) {
  const total = data.checklistTotal;
  const done = data.checklistDone;
  const percent = total > 0 ? Math.round((done / total) * 100) : 0;

  return (
    <div
      className={clsx('sop-node', `sop-node--${data.nodeType}`)}
      data-selected={selected ? 'true' : 'false'}
      data-state={data.state}
    >
      <Handle type="target" position={Position.Top} className="sop-node-handle" />
      <Handle type="target" position={Position.Left} id="left" className="sop-node-handle" />
      <div className="sop-node-surface">
        <div className="sop-node-head">
          {data.areaColor ? (
            <span
              className="sop-node-area"
              style={{ background: data.areaColor }}
              aria-hidden="true"
            />
          ) : null}
          <span className="sop-node-title">{data.title}</span>
        </div>
        <div className="sop-node-meta">
          <span className="sop-node-kind">{NODE_TYPE_LABELS[data.nodeType]}</span>
          {data.owner ? (
            <>
              <span className="sop-node-sep" aria-hidden="true">
                ·
              </span>
              <span className="sop-node-owner">{data.owner}</span>
            </>
          ) : null}
          {data.durationMin ? (
            <>
              <span className="sop-node-sep" aria-hidden="true">
                ·
              </span>
              <span className="sop-node-duration">{data.durationMin} 分钟</span>
            </>
          ) : null}
          {total > 0 ? (
            <span className="sop-node-checkcount">
              {done}/{total}
            </span>
          ) : null}
        </div>
        {total > 0 ? (
          <div className="sop-node-progress" aria-hidden="true">
            <span className="sop-node-progress-fill" style={{ width: `${percent}%` }} />
          </div>
        ) : null}
      </div>
      <Handle type="source" position={Position.Bottom} className="sop-node-handle" />
      <Handle type="source" position={Position.Right} id="right" className="sop-node-handle" />
    </div>
  );
}
