import { memo, useMemo, useState } from 'react';
import type { Item } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { LIST_PAGE_SIZE, buildWaitingRows, paginateItems } from './gtdLogic';
import { nudgeWaitingItem } from './gtdMutations';

export interface WaitingListProps {
  items: Item[];
  today: string;
}

/** 等待中：等待对象、已等待天数、超过 7 天的催办。 */
export function WaitingList({ items, today }: WaitingListProps) {
  const rows = useMemo(() => buildWaitingRows(items, today), [items, today]);
  const [limit, setLimit] = useState(LIST_PAGE_SIZE);
  const page = useMemo(() => paginateItems(rows, limit), [rows, limit]);

  if (rows.length === 0) {
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

  return (
    <div className="gtd-side-list">
      {page.items.map((row) => (
        <WaitingRow key={row.item.id} item={row.item} days={row.days} overdue={row.overdue} />
      ))}
      {page.remaining > 0 ? (
        <div className="gtd-show-more">
          <button
            type="button"
            className="gtd-linkbtn"
            onClick={() => setLimit((current) => current + LIST_PAGE_SIZE)}
          >
            显示更多（剩余 {page.remaining} 条）
          </button>
        </div>
      ) : null}
    </div>
  );
}

interface WaitingRowProps {
  item: Item;
  days: number;
  overdue: boolean;
}

const WaitingRow = memo(function WaitingRow({ item, days, overdue }: WaitingRowProps) {
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const notify = useWorkspace((state) => state.notify);
  const waitingFor = item.gtd?.waitingFor?.trim() || '未填写等待对象';
  return (
    <div className="gtd-side-row">
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
});
