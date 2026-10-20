/** 运行模式顶部条：进度、当前步骤、检查项、通过 / 未通过 / 跳过、分支选择。 */
import { useWorkspace } from '../../core/store';
import type { Item } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import type { BranchOption, RunResult } from './runLogic';
import { NODE_TYPE_LABELS } from './SopNode';
import type { RunSession } from './types';

export interface SopRunBarProps {
  current: Item | null;
  nodes: Item[];
  session: RunSession;
  branch: { options: BranchOption[]; result: RunResult } | null;
  onResult: (result: RunResult) => void;
  onChoose: (edgeId: string) => void;
  onCancelBranch: () => void;
  onExit: () => void;
}

export function SopRunBar({
  current,
  nodes,
  session,
  branch,
  onResult,
  onChoose,
  onCancelBranch,
  onExit,
}: SopRunBarProps) {
  const updateItem = useWorkspace((state) => state.updateItem);
  const total = nodes.length;
  const index = Math.min(session.visited.length, Math.max(total, 1));
  const checklist = current?.sop?.checklist ?? [];
  const doneCount = checklist.filter((entry) => entry.done).length;

  const toggleChecklist = (entryId: string) => {
    if (!current) return;
    updateItem(current.id, {
      sop: {
        checklist: checklist.map((entry) =>
          entry.id === entryId ? { ...entry, done: !entry.done } : entry,
        ),
      },
    });
  };

  return (
    <section className="sop-runbar" aria-label="SOP 运行条">
      <div className="sop-runbar-main">
        <div className="sop-runbar-top">
          <Badge tone="accent" dot>
            运行中
          </Badge>
          <span className="sop-runbar-progress">
            第 {index}/{total} 步
          </span>
          <span className="sop-runbar-divider" aria-hidden="true" />
          <h2 className="sop-runbar-title">{current?.title ?? '流程结束'}</h2>
          {current?.sop?.nodeType ? (
            <Badge tone="neutral">{NODE_TYPE_LABELS[current.sop.nodeType]}</Badge>
          ) : null}
          {current?.sop?.owner ? (
            <span className="sop-runbar-meta">{current.sop.owner}</span>
          ) : null}
          {current?.sop?.durationMin ? (
            <span className="sop-runbar-meta">{current.sop.durationMin} 分钟</span>
          ) : null}
        </div>

        {checklist.length > 0 ? (
          <ul className="sop-runbar-checklist" aria-label="当前步骤检查项">
            {checklist.map((entry) => (
              <li key={entry.id} className="sop-runbar-check" data-done={entry.done ? 'true' : 'false'}>
                <label className="sop-runbar-check-label">
                  <input
                    type="checkbox"
                    className="sop-checkbox"
                    checked={entry.done}
                    onChange={() => toggleChecklist(entry.id)}
                  />
                  <span>{entry.text}</span>
                </label>
              </li>
            ))}
            <li className="sop-runbar-check-count">
              {doneCount}/{checklist.length}
            </li>
          </ul>
        ) : (
          <p className="sop-runbar-hint">
            {current ? '这一步没有检查项，直接记录结果即可。' : '流程已结束。'}
          </p>
        )}
      </div>

      <div className="sop-runbar-actions">
        <Button
          variant="primary"
          size="sm"
          iconLeft={<Icon name="check" size={14} />}
          disabled={!current}
          onClick={() => onResult('pass')}
        >
          通过
        </Button>
        <Button
          variant="danger"
          size="sm"
          iconLeft={<Icon name="x" size={14} />}
          disabled={!current}
          onClick={() => onResult('fail')}
        >
          未通过
        </Button>
        <Button
          variant="secondary"
          size="sm"
          iconLeft={<Icon name="chevron-right" size={14} />}
          disabled={!current}
          onClick={() => onResult('skip')}
        >
          跳过
        </Button>
        <Button variant="ghost" size="sm" onClick={onExit}>
          退出
        </Button>
      </div>

      <Modal
        open={branch !== null}
        onClose={onCancelBranch}
        title="选择下一步"
        description={
          current ? `「${current.title}」有多条出边，选择要走的分支。` : '选择要走的分支。'
        }
        width={440}
        footer={
          <Button variant="ghost" onClick={onCancelBranch}>
            取消
          </Button>
        }
      >
        <div className="sop-branch-options">
          {(branch?.options ?? []).map((option) => {
            const target = nodes.find((node) => node.id === option.to);
            return (
              <Button
                key={option.edgeId}
                variant="secondary"
                block
                onClick={() => onChoose(option.edgeId)}
              >
                <span className="sop-branch-option">
                  <span className="sop-branch-label">{option.label || '继续'}</span>
                  <span className="sop-branch-target">→ {target?.title ?? '未知步骤'}</span>
                </span>
              </Button>
            );
          })}
        </div>
      </Modal>
    </section>
  );
}
