import { KIND_LABELS } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { formatDateKey } from '../../core/utils';
import type { FocusEntry } from './today';

export interface FocusListProps {
  entries: FocusEntry[];
  onToggle: (id: string) => void;
  onOpen: (entry: FocusEntry) => void;
}

export function FocusList({ entries, onToggle, onOpen }: FocusListProps) {
  if (entries.length === 0) {
    return (
      <EmptyState
        compact
        icon={<Icon name="check" size={20} />}
        title="今天没有截止或下一步"
        description="清空了。可以收集一点新想法，或者去 SOP / OKR 视图补充长期工作。"
      />
    );
  }

  return (
    <div className="dash-focus-list" role="list" aria-label="今日聚焦条目">
      {entries.map((entry) => {
        const { item } = entry;
        const parents = entry.pathTitles.slice(0, -1);
        const dueLabel =
          entry.bucket === 'overdue'
            ? `逾期 ${entry.daysLate} 天`
            : entry.bucket === 'today'
              ? '今天到期'
              : entry.due
                ? formatDateKey(entry.due, 'MM/dd')
                : null;

        return (
          <div className="dash-focus-row" role="listitem" key={item.id} data-bucket={entry.bucket}>
            <button
              type="button"
              role="checkbox"
              aria-checked="false"
              className="dash-check"
              aria-label={`完成「${item.title}」`}
              onClick={() => onToggle(item.id)}
            >
              <Icon name="check" size={11} />
            </button>

            <span className="dash-focus-main">
              <button
                type="button"
                className="dash-focus-title"
                aria-label={`打开${KIND_LABELS[item.kind]}「${item.title}」`}
                onClick={() => onOpen(entry)}
              >
                {item.title}
              </button>
              <span className="dash-focus-meta">
                {parents.length > 0 ? (
                  <span className="dash-crumb" title={entry.pathTitles.join(' / ')}>
                    {parents.map((title, index) => (
                      <span className="dash-crumb" key={`${item.id}-${index}`}>
                        {index > 0 ? <span className="dash-crumb-sep">›</span> : null}
                        <span>{title}</span>
                      </span>
                    ))}
                  </span>
                ) : (
                  <span className="dash-crumb faint">{KIND_LABELS[item.kind]}</span>
                )}
                {entry.source ? (
                  <Badge tone={entry.source === 'sop' ? 'info' : 'accent'}>
                    {entry.source === 'sop' ? 'SOP' : 'OKR'}
                  </Badge>
                ) : null}
              </span>
            </span>

            <span className="dash-focus-side">
              {entry.bucket === 'overdue' && entry.due ? (
                <span className="dash-due faint" title={`截止 ${entry.due}`}>
                  {formatDateKey(entry.due, 'MM/dd')}
                </span>
              ) : null}
              {dueLabel ? (
                <Badge tone={entry.bucket === 'overdue' ? 'danger' : entry.bucket === 'today' ? 'warn' : 'neutral'}>
                  {dueLabel}
                </Badge>
              ) : null}
            </span>
          </div>
        );
      })}
    </div>
  );
}
