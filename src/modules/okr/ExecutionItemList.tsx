import clsx from 'clsx';
import { STATUS_LABELS } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { Progress } from '../../ui/Progress';
import type { ExecutionItemRef } from './okrMath';
import { formatSchedule, progressTone, statusTone } from './okrDisplay';

interface ExecutionItemListProps {
  /** 用于生成无障碍名称，而不是重新查询 */
  krTitle: string;
  items: ExecutionItemRef[];
}

/** KR 关联的执行项：标题、状态、排期、完成勾选、进度、解除关联。 */
export function ExecutionItemList({ krTitle, items }: ExecutionItemListProps) {
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const deleteEdge = useWorkspace((state) => state.deleteEdge);

  if (items.length === 0) {
    return (
      <p className="okr-exec-empty">
        尚无执行项 · 点击「关联执行项」把项目或行动挂到这条 KR 上。
      </p>
    );
  }

  return (
    <div className="okr-exec">
      <div className="okr-exec-head">
        <span>执行项 · {items.length}</span>
        <span className="okr-exec-hint">勾选可直接标记完成</span>
      </div>
      <ul className="okr-exec-list" aria-label={`${krTitle} 关联的执行项`}>
        {items.map(({ item, via, edgeId }) => {
          const done = item.status === 'done';
          const progress = done ? 100 : (item.gantt?.progress ?? 0);
          return (
            <li key={item.id} className={clsx('okr-exec-row', done && 'is-done')}>
              <input
                type="checkbox"
                className="okr-check"
                checked={done}
                aria-label={`标记「${item.title}」${done ? '未完成' : '完成'}`}
                onChange={() => toggleDone(item.id)}
              />
              <span className="okr-exec-main">
                <span className="okr-exec-title">{item.title}</span>
                <Badge tone={statusTone(item.status)}>{STATUS_LABELS[item.status]}</Badge>
                {via === 'child' ? <Badge tone="neutral">子项</Badge> : null}
              </span>
              <span className="okr-exec-dates mono">{formatSchedule(item)}</span>
              <Progress
                value={progress}
                tone={progressTone(progress, false)}
                size="sm"
                ariaLabel={`${item.title} 进度`}
              />
              <span className="okr-exec-pct mono">{progress}%</span>
              {edgeId ? (
                <IconButton
                  label={`解除「${item.title}」与 KR 的关联`}
                  size="sm"
                  onClick={() => deleteEdge(edgeId)}
                >
                  <Icon name="x" size={13} />
                </IconButton>
              ) : (
                <span className="okr-exec-lock" title="该执行项通过层级挂在 KR 下">
                  <Icon name="folder" size={13} />
                </span>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
