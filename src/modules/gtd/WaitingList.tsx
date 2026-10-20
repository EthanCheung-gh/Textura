import type { Item } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { isWaitingOverdue, waitingDays } from './gtdLogic';
import { nudgeWaitingItem } from './gtdMutations';

export interface WaitingListProps {
  items: Item[];
  today: string;
}

/** 等待中：等待对象、已等待天数、超过 7 天的催办。 */
export function WaitingList({ items, today }: WaitingListProps) {
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const notify = useWorkspace((state) => state.notify);

  if (items.length === 0) {
    return (
      <div className="gtd-section-body gtd-empty-body">
        <EmptyState
          icon={<Icon name="clock" size={20} />}
          title="没有等待中的事项"
          description="委派出去的事会在这里跟踪。"
          compact
        />
      </div>
    );
  }

  const sorted = [...items].sort((a, b) => waitingDays(b, today) - waitingDays(a, today));

  return (
    <div className="gtd-side-list">
      {sorted.map((item) => {
        const days = waitingDays(item, today);
        const overdue = isWaitingOverdue(item, today);
        const waitingFor = item.gtd?.waitingFor?.trim() || '未填写等待对象';
        return (
          <div key={item.id} className="gtd-side-row">
            <button
              type="button"
              className="gtd-check"
              aria-label={`完成「${item.title}」`}
              onClick={() => {
                toggleDone(item.id);
                notify(`等待事项已完成「${item.title}」`, 'success');
              }}
            >
              <Icon name="check" size={12} />
            </button>
            <div className="gtd-side-body">
              <span className="gtd-row-title gtd-row-title--static">{item.title}</span>
              <div className="gtd-row-meta">
                <Badge tone="info" dot>
                  等待 {waitingFor}
                </Badge>
                <span className={`gtd-deadline gtd-deadline--${overdue ? 'danger' : 'muted'}`}>
                  <Icon name="clock" size={12} />已等待 {days} 天
                </span>
                {overdue ? <Badge tone="warn">超过 7 天</Badge> : null}
              </div>
            </div>
            <Button
              variant={overdue ? 'secondary' : 'ghost'}
              size="sm"
              onClick={() => nudgeWaitingItem(item)}
              title="在备注里追加一条催办记录"
            >
              催办
            </Button>
          </div>
        );
      })}
    </div>
  );
}
