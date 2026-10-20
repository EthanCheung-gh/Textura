import clsx from 'clsx';
import type { PointerEvent as ReactPointerEvent } from 'react';
import type { Item } from '../../core/model';
import { ROW_HEIGHT, displayProgress } from './scale';
import type { BarGeometry } from './scale';

export type DragMode = 'move' | 'start' | 'end';

export interface GanttBarProps {
  item: Item;
  geometry: BarGeometry;
  rowIndex: number;
  selected: boolean;
  dragging: boolean;
  overdue: boolean;
  onSelect: (id: string) => void;
  onDragStart: (
    event: ReactPointerEvent<HTMLElement>,
    item: Item,
    mode: DragMode,
    capture: HTMLElement,
  ) => void;
  onDragMove: (event: ReactPointerEvent<HTMLElement>) => void;
  onDragEnd: (event: ReactPointerEvent<HTMLElement>) => void;
  onDragCancel: (event: ReactPointerEvent<HTMLElement>) => void;
}

export function GanttBar({
  item,
  geometry,
  rowIndex,
  selected,
  dragging,
  overdue,
  onSelect,
  onDragStart,
  onDragMove,
  onDragEnd,
  onDragCancel,
}: GanttBarProps) {
  const isMilestone = item.kind === 'milestone';
  const progress = displayProgress(item);

  return (
    <div
      className={clsx(
        'gantt-bar',
        `is-${item.status}`,
        isMilestone && 'is-milestone',
        overdue && 'is-overdue',
        selected && 'is-selected',
        dragging && 'is-dragging',
      )}
      style={{
        left: geometry.x,
        width: isMilestone ? 16 : geometry.width,
        top: rowIndex * ROW_HEIGHT + 7,
      }}
      role="button"
      tabIndex={0}
      aria-label={`${item.title}，${geometry.start} 至 ${geometry.end}，进度 ${progress}%`}
      title={`${item.title}\n${geometry.start} → ${geometry.end} · ${geometry.days} 天 · ${progress}%`}
      onPointerDown={(event) => {
        if (event.button !== 0) return;
        event.stopPropagation();
        onSelect(item.id);
        onDragStart(event, item, 'move', event.currentTarget);
      }}
      onPointerMove={onDragMove}
      onPointerUp={onDragEnd}
      onPointerCancel={onDragCancel}
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          event.stopPropagation();
          onSelect(item.id);
        }
      }}
    >
      {isMilestone ? (
        <>
          <span className="gantt-milestone-mark" aria-hidden="true" />
          <span className="gantt-bar-label">{item.title}</span>
        </>
      ) : (
        <>
          <span className="gantt-bar-fill" style={{ width: `${progress}%` }} aria-hidden="true" />
          <span className="gantt-bar-label">{item.title}</span>
          <span
            className="gantt-bar-handle is-start"
            aria-hidden="true"
            onPointerDown={(event) => {
              if (event.button !== 0) return;
              event.stopPropagation();
              const bar = event.currentTarget.closest('.gantt-bar');
              if (bar instanceof HTMLElement) {
                onSelect(item.id);
                onDragStart(event, item, 'start', bar);
              }
            }}
          />
          <span
            className="gantt-bar-handle is-end"
            aria-hidden="true"
            onPointerDown={(event) => {
              if (event.button !== 0) return;
              event.stopPropagation();
              const bar = event.currentTarget.closest('.gantt-bar');
              if (bar instanceof HTMLElement) {
                onSelect(item.id);
                onDragStart(event, item, 'end', bar);
              }
            }}
          />
        </>
      )}
    </div>
  );
}
