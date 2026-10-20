import { useEffect, useRef } from 'react';
import type { KeyboardEvent, RefObject } from 'react';
import clsx from 'clsx';
import type { Item } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { formatDateKey } from '../../core/utils';
import { Icon } from '../../ui/icons';
import { ROW_HEIGHT, displayProgress, itemRange } from './scale';
import type { GanttItemRow, GanttRow } from './scale';

export interface GanttEditing {
  id: string;
  value: string;
}

export interface GanttTreeProps {
  rows: GanttRow[];
  selectedId: string | null;
  todayKey: string;
  scrollTop: number;
  scrollerRef: RefObject<HTMLDivElement>;
  editing: GanttEditing | null;
  onToggleGroup: (id: string) => void;
  onSelect: (id: string | null) => void;
  onStartEdit: (item: Item) => void;
  onEditingChange: (value: string) => void;
  onCommitEdit: () => void;
  onCancelEdit: () => void;
  onSchedule: (id: string) => void;
}

function isOverdue(item: Item, todayKey: string): boolean {
  const range = itemRange(item);
  if (!range) return false;
  return range.end < todayKey && item.status !== 'done' && item.status !== 'dropped';
}

function InlineTitleInput({
  value,
  onChange,
  onCommit,
  onCancel,
}: {
  value: string;
  onChange: (value: string) => void;
  onCommit: () => void;
  onCancel: () => void;
}) {
  const ref = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const input = ref.current;
    if (!input) return;
    input.focus();
    input.select();
  }, []);

  return (
    <input
      ref={ref}
      className="gantt-inline-input"
      value={value}
      aria-label="任务标题"
      onChange={(event) => onChange(event.target.value)}
      onClick={(event) => event.stopPropagation()}
      onDoubleClick={(event) => event.stopPropagation()}
      onBlur={onCommit}
      onKeyDown={(event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          onCommit();
        } else if (event.key === 'Escape') {
          event.preventDefault();
          onCancel();
        }
      }}
    />
  );
}

function ItemRow({
  row,
  selected,
  todayKey,
  editing,
  onSelect,
  onStartEdit,
  onEditingChange,
  onCommitEdit,
  onCancelEdit,
  onSchedule,
}: {
  row: GanttItemRow;
  selected: boolean;
  todayKey: string;
  editing: GanttEditing | null;
  onSelect: (id: string | null) => void;
  onStartEdit: (item: Item) => void;
  onEditingChange: (value: string) => void;
  onCommitEdit: () => void;
  onCancelEdit: () => void;
  onSchedule: (id: string) => void;
}) {
  const { item } = row;
  const range = itemRange(item);
  const progress = displayProgress(item);
  const overdue = isOverdue(item, todayKey);
  const editingThis = editing?.id === item.id;
  const dateLabel = range ? `${formatDateKey(range.start, 'M/d')} – ${formatDateKey(range.end, 'M/d')}` : '未排期';

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.target !== event.currentTarget) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      onSelect(item.id);
    }
  };

  return (
    <div
      className={clsx(
        'gantt-tree-row',
        'is-item',
        selected && 'is-selected',
        item.status === 'done' && 'is-done',
        overdue && 'is-overdue',
      )}
      style={{ paddingLeft: 8 + row.depth * 14 }}
      onClick={() => onSelect(item.id)}
      onKeyDown={handleKeyDown}
      tabIndex={0}
      aria-selected={selected}
      title={`${item.title} · ${dateLabel} · ${STATUS_LABELS[item.status]}`}
    >
      <span className={clsx('gantt-status-dot', `is-${item.status}`)} aria-hidden="true" />
      {editingThis ? (
        <InlineTitleInput
          value={editing.value}
          onChange={onEditingChange}
          onCommit={onCommitEdit}
          onCancel={onCancelEdit}
        />
      ) : (
        <span
          className="gantt-item-title"
          onDoubleClick={(event) => {
            event.stopPropagation();
            onStartEdit(item);
          }}
        >
          {item.title}
        </span>
      )}

      {overdue ? <span className="gantt-overdue">超期</span> : null}

      {range ? (
        <span className="gantt-item-progress" title={`进度 ${progress}%`}>
          {progress}%
        </span>
      ) : (
        <>
          <span className="gantt-unscheduled">未排期</span>
          <button
            type="button"
            className="gantt-schedule-btn"
            title="排期到今天起 3 天"
            onClick={(event) => {
              event.stopPropagation();
              onSchedule(item.id);
            }}
          >
            排期
          </button>
        </>
      )}
    </div>
  );
}

export function GanttTree({
  rows,
  selectedId,
  todayKey,
  scrollTop,
  scrollerRef,
  editing,
  onToggleGroup,
  onSelect,
  onStartEdit,
  onEditingChange,
  onCommitEdit,
  onCancelEdit,
  onSchedule,
}: GanttTreeProps) {
  const viewportRef = useRef<HTMLDivElement>(null);
  const itemCount = rows.filter((row) => row.type === 'item').length;

  // 左侧树自己没有滚动条：滚轮直接驱动右侧时间轴的纵向滚动，保证两边行对齐。
  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    const handleWheel = (event: WheelEvent) => {
      const scroller = scrollerRef.current;
      if (!scroller) return;
      const before = scroller.scrollTop;
      scroller.scrollTop += event.deltaY;
      if (scroller.scrollTop !== before) event.preventDefault();
    };
    viewport.addEventListener('wheel', handleWheel, { passive: false });
    return () => viewport.removeEventListener('wheel', handleWheel);
  }, [scrollerRef]);

  return (
    <div className="gantt-tree">
      <div className="gantt-tree-head">
        <span>任务</span>
        <span className="gantt-tree-head-count">{itemCount} 条</span>
      </div>

      <div
        ref={viewportRef}
        className="gantt-tree-viewport"
        onClick={(event) => {
          if (event.target === event.currentTarget) onSelect(null);
        }}
      >
        <div
          className="gantt-tree-inner"
          style={{ transform: `translateY(${-scrollTop}px)` }}
          onClick={(event) => {
            if (event.target === event.currentTarget) onSelect(null);
          }}
        >
          {rows.length === 0 ? <p className="gantt-tree-empty">暂无项目或行动。</p> : null}

          {rows.map((row) => {
            if (row.type === 'group') {
              const selected = selectedId === row.id && row.item !== null;
              const rangeLabel =
                row.start && row.end
                  ? `${formatDateKey(row.start, 'M/d')}–${formatDateKey(row.end, 'M/d')}`
                  : '未排期';
              return (
                <div
                  key={`group-${row.id}`}
                  className={clsx('gantt-tree-row', 'is-group', selected && 'is-selected')}
                  style={{ height: ROW_HEIGHT }}
                  onClick={() => onSelect(row.item?.id ?? null)}
                  onKeyDown={(event) => {
                    if (event.target !== event.currentTarget) return;
                    if (event.key === 'Enter' || event.key === ' ') {
                      event.preventDefault();
                      onSelect(row.item?.id ?? null);
                    }
                  }}
                  tabIndex={0}
                  aria-expanded={!row.collapsed}
                  title={`${row.title} · ${row.count} 项 · ${rangeLabel} · ${row.progress}%`}
                >
                  <button
                    type="button"
                    className="gantt-group-toggle"
                    aria-label={row.collapsed ? `展开 ${row.title}` : `折叠 ${row.title}`}
                    aria-expanded={!row.collapsed}
                    onClick={(event) => {
                      event.stopPropagation();
                      onToggleGroup(row.id);
                    }}
                  >
                    <Icon name={row.collapsed ? 'chevron-right' : 'chevron-down'} size={14} />
                  </button>
                  <span className="gantt-group-icon" aria-hidden="true">
                    <Icon name="folder" size={14} />
                  </span>
                  <span className="gantt-group-main">
                    <span className="gantt-group-title">
                      {row.title}
                      <span className="gantt-group-count">{row.count}</span>
                    </span>
                    <span className="gantt-group-meta">
                      {rangeLabel} · {row.progress}%
                    </span>
                  </span>
                  <span
                    className="gantt-group-progress"
                    style={{ width: `${Math.min(100, Math.max(0, row.progress))}%` }}
                    aria-hidden="true"
                  />
                </div>
              );
            }

            return (
              <ItemRow
                key={`item-${row.id}`}
                row={row}
                selected={selectedId === row.id}
                todayKey={todayKey}
                editing={editing}
                onSelect={onSelect}
                onStartEdit={onStartEdit}
                onEditingChange={onEditingChange}
                onCommitEdit={onCommitEdit}
                onCancelEdit={onCancelEdit}
                onSchedule={onSchedule}
              />
            );
          })}
        </div>
      </div>
    </div>
  );
}
