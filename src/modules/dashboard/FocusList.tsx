import { memo, useMemo, useState } from 'react';
import { KIND_LABELS } from '../../core/model';
import type { Item } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { formatDateKey } from '../../core/utils';
import { FOCUS_PAGE_SIZE, paginateFocus } from './today';
import type { FocusBucket, FocusEntry, FocusSource } from './today';

export interface FocusListProps {
  entries: FocusEntry[];
  onToggle: (id: string) => void;
  onOpen: (item: Item) => void;
}

export function FocusList({ entries, onToggle, onOpen }: FocusListProps) {
  const [limit, setLimit] = useState(FOCUS_PAGE_SIZE);
  const page = useMemo(() => paginateFocus(entries, limit), [entries, limit]);

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
    <>
      <div className="dash-focus-list" role="list" aria-label="今日聚焦条目">
        {page.items.map((entry) => (
          <FocusRow
            key={entry.item.id}
            item={entry.item}
            bucket={entry.bucket}
            due={entry.due}
            daysLate={entry.daysLate}
            source={entry.source}
            parentsText={entry.pathTitles.slice(0, -1).join(' › ')}
            onToggle={onToggle}
            onOpen={onOpen}
          />
        ))}
      </div>
      {page.remaining > 0 ? (
        <div className="dash-show-more">
          <button
            type="button"
            className="dash-link"
            onClick={() => setLimit((current) => current + FOCUS_PAGE_SIZE)}
          >
            显示更多（剩余 {page.remaining} 条）
          </button>
          <span className="dash-show-more-note">
            已显示 {page.shown} / {page.total} 条
          </span>
        </div>
      ) : null}
    </>
  );
}

interface FocusRowProps {
  item: Item;
  bucket: FocusBucket;
  due: string | null;
  daysLate: number;
  source: FocusSource;
  /** 根 → 父级，已拼成字符串：原始值，便于 memo 比较。 */
  parentsText: string;
  onToggle: (id: string) => void;
  onOpen: (item: Item) => void;
}

const FocusRow = memo(function FocusRow({
  item,
  bucket,
  due,
  daysLate,
  source,
  parentsText,
  onToggle,
  onOpen,
}: FocusRowProps) {
  const dueLabel =
    bucket === 'overdue'
      ? `逾期 ${daysLate} 天`
      : bucket === 'today'
        ? '今天到期'
        : due
          ? formatDateKey(due, 'MM/dd')
          : null;

  return (
    <div className="dash-focus-row" role="listitem" data-bucket={bucket}>
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
          onClick={() => onOpen(item)}
        >
          {item.title}
        </button>
        <span className="dash-focus-meta">
          {parentsText ? (
            <span className="dash-crumb" title={parentsText}>
              {parentsText}
            </span>
          ) : (
            <span className="dash-crumb faint">{KIND_LABELS[item.kind]}</span>
          )}
          {source ? (
            <Badge tone={source === 'sop' ? 'info' : 'accent'}>
              {source === 'sop' ? 'SOP' : 'OKR'}
            </Badge>
          ) : null}
        </span>
      </span>

      <span className="dash-focus-side">
        {bucket === 'overdue' && due ? (
          <span className="dash-due faint" title={`截止 ${due}`}>
            {formatDateKey(due, 'MM/dd')}
          </span>
        ) : null}
        {dueLabel ? (
          <Badge tone={bucket === 'overdue' ? 'danger' : bucket === 'today' ? 'warn' : 'neutral'}>
            {dueLabel}
          </Badge>
        ) : null}
      </span>
    </div>
  );
});
