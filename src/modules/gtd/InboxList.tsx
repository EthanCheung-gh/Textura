import { useMemo } from 'react';
import type { Item } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { contextOf, relativeTimeLabel, sortInboxItems } from './gtdLogic';
import { completeInboxItem, deleteInboxItem, promoteItemToNext } from './gtdMutations';
import { useRowKeyboard } from './useRowKeyboard';

export interface InboxListProps {
  items: Item[];
  onClarify: (item: Item) => void;
  onFocusNext: () => void;
}

/** 收集 → 澄清：收件箱列表与行内快捷动作。 */
export function InboxList({ items, onClarify, onFocusNext }: InboxListProps) {
  const sorted = useMemo(() => sortInboxItems(items), [items]);
  const ids = useMemo(() => sorted.map((item) => item.id), [sorted]);
  const { activeId, setActiveId, onKeyDown } = useRowKeyboard({
    ids,
    onDone: (id) => {
      const item = sorted.find((entry) => entry.id === id);
      if (item) completeInboxItem(item);
    },
    onEnter: (id) => {
      const item = sorted.find((entry) => entry.id === id);
      if (item) onClarify(item);
    },
  });

  if (sorted.length === 0) {
    return (
      <div className="gtd-section-body gtd-empty-body">
        <EmptyState
          icon={<Icon name="inbox" size={22} />}
          title="收件箱已清空，去推进下一步"
          description="所有收集到的事项都已澄清，系统重新变得可信。"
          action={
            <Button variant="primary" size="sm" iconRight={<Icon name="chevron-right" size={14} />} onClick={onFocusNext}>
              去推进下一步
            </Button>
          }
          compact
        />
      </div>
    );
  }

  return (
    <div
      className="gtd-rows"
      role="list"
      aria-label="收件箱"
      tabIndex={0}
      onKeyDown={onKeyDown}
      onFocus={() => {
        if (!activeId && sorted[0]) setActiveId(sorted[0].id);
      }}
    >
      {sorted.map((item) => {
        const context = contextOf(item);
        const twoMinute = Boolean(item.gtd?.twoMinuteCandidate);
        const capturedAt = item.gtd?.capturedAt ?? item.createdAt;
        const active = activeId === item.id;
        return (
          <div
            key={item.id}
            className="gtd-row gtd-inbox-row"
            data-active={active ? 'true' : 'false'}
            data-row-id={item.id}
            role="listitem"
            onMouseEnter={() => setActiveId(item.id)}
          >
            <div className="gtd-row-main">
              <button
                type="button"
                className="gtd-row-title"
                title="打开澄清（Enter）"
                onClick={() => onClarify(item)}
              >
                {item.title}
              </button>
              <div className="gtd-row-meta">
                {item.tags.map((tag) => (
                  <Badge key={tag} tone="neutral">
                    #{tag}
                  </Badge>
                ))}
                {context ? <Badge tone="info">@{context}</Badge> : null}
                {twoMinute ? (
                  <Badge tone="warn" dot>
                    2 分钟可完成
                  </Badge>
                ) : null}
                <span className="gtd-row-time">
                  <Icon name="clock" size={12} />
                  {relativeTimeLabel(capturedAt)}
                </span>
              </div>
            </div>
            <div className="gtd-row-actions">
              <Button
                variant="ghost"
                size="sm"
                iconLeft={<Icon name="check" size={13} />}
                onClick={() => completeInboxItem(item)}
                title="2 分钟内能完成的事，现在就做"
              >
                2 分钟处理
              </Button>
              <Button
                variant="secondary"
                size="sm"
                iconLeft={<Icon name="play" size={12} />}
                onClick={() => promoteItemToNext(item)}
              >
                转为下一步
              </Button>
              <IconButton
                label={`删除「${item.title}」`}
                variant="danger"
                size="sm"
                onClick={() => deleteInboxItem(item)}
              >
                <Icon name="trash" size={14} />
              </IconButton>
            </div>
          </div>
        );
      })}
    </div>
  );
}
