import { memo, useEffect, useMemo, useRef } from 'react';
import type { KeyboardEvent, RefObject } from 'react';
import clsx from 'clsx';
import type { Item } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { formatDateKey } from '../../core/utils';
import { Icon } from '../../ui/icons';
import { HEADER_HEIGHT, ROW_HEIGHT, displayProgress, itemRange } from './scale';
import type { GanttGroupRow, GanttItemRow, GanttRow } from './scale';
import { visibleRows } from './virtual';

export interface GanttEditing {
  id: string;
  value: string;
}

export interface GanttTreeProps {
  rows: GanttRow[];
  selectedId: string | null;
  todayKey: string;
  scrollTop: number;
  /** 时间轴整体的可视高度（含 52px 吸顶表头），用于计算树窗口。 */
  viewportHeight: number;
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

interface ItemRowProps {
  row: GanttItemRow;
  selected: boolean;
  todayKey: string;
  /** null 表示不在编辑；字符串（含空串）表示当前行正在编辑。 */
  editingValue: string | null;
  onSelect: (id: string | null) => void;
  onStartEdit: (item: Item) => void;
  onEditingChange: (value: string) => void;
  onCommitEdit: () => void;
  onCancelEdit: () => void;
  onSchedule: (id: string) => void;
}

const ItemRow = memo(function ItemRow({
  row,
  selected,
  todayKey,
  editingValue,
  onSelect,
  onStartEdit,
  onEditingChange,
  onCommitEdit,
  onCancelEdit,
  onSchedule,
}: ItemRowProps) {
  const { item } = row;
  const range = itemRange(item);
  const progress = displayProgress(item);
  const overdue = isOverdue(item, todayKey);
  const editingThis = editingValue !== null;
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
      data-row-id={item.id}
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
          value={editingValue ?? ''}
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
});

interface GroupRowProps {
  row: GanttGroupRow;
  selected: boolean;
  onToggleGroup: (id: string) => void;
  onSelect: (id: string | null) => void;
}

const GroupRow = memo(function GroupRow({ row, selected, onToggleGroup, onSelect }: GroupRowProps) {
  const rangeLabel =
    row.start && row.end
      ? `${formatDateKey(row.start, 'M/d')}–${formatDateKey(row.end, 'M/d')}`
      : '未排期';

  return (
    <div
      data-row-id={row.id}
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
});

export function GanttTree({
  rows,
  selectedId,
  todayKey,
  scrollTop,
  viewportHeight,
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
  const itemCount = useMemo(
    () => rows.reduce((count, row) => count + (row.type === 'item' ? 1 : 0), 0),
    [rows],
  );

  // 行窗口：可视行数取实际行区域高度，缓冲为可视行数的 50%（至少 10 行）。
  const rowViewportHeight = Math.max(0, viewportHeight - HEADER_HEIGHT);
  const visibleRowCount = Math.max(1, Math.ceil(rowViewportHeight / ROW_HEIGHT));
  const buffer = Math.max(10, Math.ceil(visibleRowCount * 0.5));
  const rowScrollTop = Math.max(0, scrollTop - HEADER_HEIGHT);
  const rowWindow = useMemo(
    () => visibleRows(rowScrollTop, rowViewportHeight, ROW_HEIGHT, buffer, rows.length),
    [rowScrollTop, rowViewportHeight, buffer, rows.length],
  );
  const windowRows = useMemo(
    () => rows.slice(rowWindow.start, rowWindow.end),
    [rows, rowWindow.start, rowWindow.end],
  );
  const topSpacerHeight = rowWindow.start * ROW_HEIGHT;
  const bottomSpacerHeight = Math.max(0, (rows.length - rowWindow.end) * ROW_HEIGHT);

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
    <div className="gantt-tree" data-total-rows={rows.length}>
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

          {topSpacerHeight > 0 ? <div style={{ height: topSpacerHeight }} aria-hidden="true" /> : null}

          {windowRows.map((row) => {
            if (row.type === 'group') {
              return (
                <GroupRow
                  key={`group-${row.id}`}
                  row={row}
                  selected={selectedId === row.id && row.item !== null}
                  onToggleGroup={onToggleGroup}
                  onSelect={onSelect}
                />
              );
            }

            return (
              <ItemRow
                key={`item-${row.id}`}
                row={row}
                selected={selectedId === row.id}
                todayKey={todayKey}
                editingValue={editing?.id === row.id ? editing.value : null}
                onSelect={onSelect}
                onStartEdit={onStartEdit}
                onEditingChange={onEditingChange}
                onCommitEdit={onCommitEdit}
                onCancelEdit={onCancelEdit}
                onSchedule={onSchedule}
              />
            );
          })}

          {bottomSpacerHeight > 0 ? <div style={{ height: bottomSpacerHeight }} aria-hidden="true" /> : null}
        </div>
      </div>
    </div>
  );
}
