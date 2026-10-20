import { useCallback, useEffect, useMemo, useState } from 'react';
import type { PointerEvent as ReactPointerEvent, RefObject } from 'react';
import clsx from 'clsx';
import type { Item, Workspace } from '../../core/model';
import { formatDateKey } from '../../core/utils';
import { GanttBar } from './GanttBar';
import type { DragMode } from './GanttBar';
import { GanttDependencies } from './GanttDependencies';
import type { DepRect } from './GanttDependencies';
import {
  HEADER_HEIGHT,
  ROW_HEIGHT,
  ZOOM_CONFIG,
  addDaysKey,
  barGeometry,
  buildHeader,
  dateToX,
  diffDays,
  itemRange,
  moveBar,
  resizeBar,
  toDate,
  totalWidth,
} from './scale';
import type { BarRange, DateRange, GanttRow, GanttZoom } from './scale';

export interface GanttViewport {
  scrollLeft: number;
  scrollTop: number;
  width: number;
  height: number;
}

interface DragState {
  id: string;
  mode: DragMode;
  pointerId: number;
  startX: number;
  origin: BarRange;
  deltaDays: number;
  rowIndex: number;
}

export interface GanttTimelineProps {
  workspace: Workspace;
  rows: GanttRow[];
  range: DateRange;
  zoom: GanttZoom;
  todayKey: string;
  selectedId: string | null;
  viewport: GanttViewport;
  scrollerRef: RefObject<HTMLDivElement>;
  onViewportChange: (viewport: GanttViewport) => void;
  onSelect: (id: string | null) => void;
  onDragCommit: (id: string, bar: BarRange) => void;
}

export function GanttTimeline({
  workspace,
  rows,
  range,
  zoom,
  todayKey,
  selectedId,
  viewport,
  scrollerRef,
  onViewportChange,
  onSelect,
  onDragCommit,
}: GanttTimelineProps) {
  const px = ZOOM_CONFIG[zoom].pxPerDay;
  const [drag, setDrag] = useState<DragState | null>(null);

  const header = useMemo(() => buildHeader(range, zoom, todayKey), [range, zoom, todayKey]);
  const total = totalWidth(range, px) || header.width;
  // 行数不足时也让网格 / 今日线铺满可视高度，避免下半屏空白。
  const totalRowsHeight = Math.max(
    ROW_HEIGHT,
    rows.length * ROW_HEIGHT,
    Math.max(0, viewport.height - HEADER_HEIGHT),
  );
  const todayX = Math.min(total, Math.max(0, diffDays(range.start, todayKey) * px + px / 2));

  const visibleColumns = useMemo(() => {
    const fromX = viewport.scrollLeft - 320;
    const toX = viewport.scrollLeft + viewport.width + 320;
    return header.columns.filter((column) => column.x + column.width >= fromX && column.x <= toX);
  }, [header.columns, viewport.scrollLeft, viewport.width]);

  const visibleGroups = useMemo(() => {
    const fromX = viewport.scrollLeft - 320;
    const toX = viewport.scrollLeft + viewport.width + 320;
    return header.groups.filter((group) => group.x + group.width >= fromX && group.x <= toX);
  }, [header.groups, viewport.scrollLeft, viewport.width]);

  const stripes = useMemo(() => {
    const result: { key: string; x: number; width: number }[] = [];
    if (visibleColumns.length === 0) return result;
    const first = visibleColumns[0].start;
    const last = visibleColumns[visibleColumns.length - 1].end;
    let key = first;
    let guard = 0;
    while (key <= last && guard < 400) {
      const weekday = toDate(key).getDay();
      if (weekday === 0 || weekday === 6) {
        result.push({ key, x: dateToX(key, range.start, px), width: px });
      }
      key = addDaysKey(key, 1);
      guard += 1;
    }
    return result;
  }, [visibleColumns, range.start, px]);

  const firstRow = Math.max(0, Math.floor((viewport.scrollTop - HEADER_HEIGHT) / ROW_HEIGHT) - 4);
  const lastRow = Math.min(rows.length - 1, Math.ceil((viewport.scrollTop + viewport.height) / ROW_HEIGHT) + 6);
  const visibleRows = useMemo(
    () =>
      rows
        .map((row, index) => ({ row, index }))
        .filter(({ index }) => index >= firstRow && index <= lastRow),
    [rows, firstRow, lastRow],
  );

  const dragPreview = drag
    ? drag.mode === 'move'
      ? moveBar(drag.origin, drag.deltaDays)
      : resizeBar(drag.origin, drag.mode, drag.deltaDays)
    : null;

  const depsEdges = useMemo(
    () => workspace.edges.filter((edge) => edge.type === 'depends'),
    [workspace.edges],
  );
  const titles = useMemo(
    () => new Map(workspace.items.map((item) => [item.id, item.title])),
    [workspace.items],
  );

  const rects = new Map<string, DepRect>();
  const bars: { item: Item; geometry: ReturnType<typeof barGeometry>; rowIndex: number }[] = [];
  const viewLeft = viewport.scrollLeft - 400;
  const viewRight = viewport.scrollLeft + viewport.width + 400;
  for (const { row, index } of visibleRows) {
    if (row.type !== 'item') continue;
    const base = itemRange(row.item);
    if (!base) continue;
    const preview = drag?.id === row.id && dragPreview ? dragPreview : base;
    const geometry = barGeometry(preview, range.start, px);
    const keep = drag?.id === row.id || (geometry.x + geometry.width >= viewLeft && geometry.x <= viewRight);
    if (!keep) continue;
    bars.push({ item: row.item, geometry, rowIndex: index });
    rects.set(row.id, {
      x1: geometry.x,
      x2: geometry.x + geometry.width,
      cy: index * ROW_HEIGHT + ROW_HEIGHT / 2,
    });
  }

  const summaries = visibleRows
    .filter(({ row }) => row.type === 'group' && row.start !== null && row.end !== null)
    .map(({ row, index }) => {
      if (row.type !== 'group' || !row.start || !row.end) return null;
      const geometry = barGeometry({ start: row.start, end: row.end }, range.start, px);
      return { row, index, geometry };
    })
    .filter((entry): entry is NonNullable<typeof entry> => entry !== null);

  const report = useCallback(() => {
    const element = scrollerRef.current;
    if (!element) return;
    onViewportChange({
      scrollLeft: element.scrollLeft,
      scrollTop: element.scrollTop,
      width: element.clientWidth,
      height: element.clientHeight,
    });
  }, [onViewportChange, scrollerRef]);

  useEffect(() => {
    const element = scrollerRef.current;
    if (!element) return;
    report();
    const observer = new ResizeObserver(report);
    observer.observe(element);
    return () => observer.disconnect();
  }, [report, scrollerRef]);

  const dragId = drag?.id ?? null;
  useEffect(() => {
    if (!dragId) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      setDrag(null);
    };
    window.addEventListener('keydown', onKeyDown);
    document.body.classList.add('gantt-dragging');
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      document.body.classList.remove('gantt-dragging');
    };
  }, [dragId]);

  const handleDragStart = useCallback(
    (event: ReactPointerEvent<HTMLElement>, item: Item, mode: DragMode, capture: HTMLElement) => {
      const base = itemRange(item);
      if (!base) return;
      const rowIndex = rows.findIndex((row) => row.id === item.id);
      try {
        capture.setPointerCapture(event.pointerId);
      } catch {
        // 某些 WebView 在 pointerdown 同帧获取 capture 会抛错，退化为普通拖动。
      }
      setDrag({
        id: item.id,
        mode,
        pointerId: event.pointerId,
        startX: event.clientX,
        origin: base,
        deltaDays: 0,
        rowIndex: rowIndex < 0 ? 0 : rowIndex,
      });
    },
    [rows],
  );

  const handleDragMove = useCallback(
    (event: ReactPointerEvent<HTMLElement>) => {
      setDrag((current) => {
        if (!current || current.pointerId !== event.pointerId) return current;
        // 吸附：三种缩放都是 1 天粒度（scale.snapDate）。
        const delta = Math.round((event.clientX - current.startX) / px);
        return delta === current.deltaDays ? current : { ...current, deltaDays: delta };
      });
    },
    [px],
  );

  const handleDragEnd = useCallback(
    (event: ReactPointerEvent<HTMLElement>) => {
      if (!drag || drag.pointerId !== event.pointerId) return;
      const preview =
        drag.mode === 'move' ? moveBar(drag.origin, drag.deltaDays) : resizeBar(drag.origin, drag.mode, drag.deltaDays);
      if (preview.start !== drag.origin.start || preview.end !== drag.origin.end) {
        onDragCommit(drag.id, preview);
      }
      const capture = event.currentTarget;
      if (capture.hasPointerCapture(event.pointerId)) capture.releasePointerCapture(event.pointerId);
      setDrag(null);
    },
    [drag, onDragCommit],
  );

  const handleDragCancel = useCallback(
    (event: ReactPointerEvent<HTMLElement>) => {
      if (!drag || drag.pointerId !== event.pointerId) return;
      const capture = event.currentTarget;
      if (capture.hasPointerCapture(event.pointerId)) capture.releasePointerCapture(event.pointerId);
      setDrag(null);
    },
    [drag],
  );

  return (
    <div className="gantt-timeline">
      <div
        ref={scrollerRef}
        className="gantt-scroll"
        onScroll={report}
        onClick={(event) => {
          if (event.target === event.currentTarget) onSelect(null);
        }}
      >
        <div className="gantt-canvas" style={{ width: total, height: HEADER_HEIGHT + totalRowsHeight }}>
          <div className="gantt-header" style={{ height: HEADER_HEIGHT }}>
            <div className="gantt-header-primary">
              {visibleGroups.map((group) => {
                // 月份 / 季度标签贴住可视区左边缘，横向滚动时保持可读。
                const left = Math.max(group.x, viewport.scrollLeft);
                const width = Math.max(0, group.x + group.width - left);
                if (width < 2) return null;
                return (
                  <div
                    key={group.key}
                    className={clsx('gantt-header-group', left > group.x && 'is-pinned')}
                    style={{ left, width }}
                  >
                    {group.label}
                  </div>
                );
              })}
            </div>
            <div className="gantt-header-secondary">
              {visibleColumns.map((column) => (
                <div
                  key={column.key}
                  className={clsx(
                    'gantt-header-col',
                    column.weekend && 'is-weekend',
                    column.past && 'is-past',
                  )}
                  style={{ left: column.x, width: column.width }}
                >
                  <span className="gantt-header-col-label">{column.label}</span>
                  {column.sublabel ? <span className="gantt-header-col-sub">{column.sublabel}</span> : null}
                </div>
              ))}
            </div>
            <div className="gantt-today-marker" style={{ left: todayX }}>
              <span className="gantt-today-pill">今天</span>
            </div>
          </div>

          <div
            className="gantt-rows"
            style={{ height: totalRowsHeight }}
            onClick={(event) => {
              if (event.target === event.currentTarget) onSelect(null);
            }}
          >
            {visibleRows.map(({ row, index }) => (
              <div
                key={`row-${row.id}-${index}`}
                className={clsx(
                  'gantt-row',
                  row.type === 'group' && 'is-group',
                  selectedId !== null && selectedId === row.id && 'is-selected',
                )}
                style={{ top: index * ROW_HEIGHT, height: ROW_HEIGHT }}
                onClick={(event) => {
                  event.stopPropagation();
                  onSelect(row.type === 'group' ? (row.item?.id ?? null) : row.id);
                }}
              />
            ))}

            <div className="gantt-layer" aria-hidden="true">
              <div className="gantt-past" style={{ width: todayX }} />
              {stripes.map((stripe) => (
                <span
                  key={`weekend-${stripe.key}`}
                  className="gantt-weekend"
                  style={{ left: stripe.x, width: stripe.width }}
                />
              ))}
              {visibleColumns.map((column) => (
                <span key={`grid-${column.key}`} className="gantt-grid-line" style={{ left: column.x }} />
              ))}
              {visibleGroups.map((group) => (
                <span key={`month-${group.key}`} className="gantt-month-line" style={{ left: group.x }} />
              ))}
            </div>

            {summaries.map(({ row, index, geometry }) => (
              <div
                key={`summary-${row.id}`}
                className={clsx(
                  'gantt-summary-bar',
                  selectedId !== null && selectedId === row.id && 'is-selected',
                )}
                style={{ left: geometry.x, width: Math.max(6, geometry.width), top: index * ROW_HEIGHT + 14 }}
                role="button"
                tabIndex={0}
                aria-label={`项目汇总：${row.title}`}
                aria-roledescription="分组汇总条（不可拖拽）"
                title={`项目汇总：${row.title} · ${row.start} → ${row.end} · ${row.progress}% · 点击选中分组`}
                onClick={(event) => {
                  event.stopPropagation();
                  onSelect(row.item?.id ?? null);
                }}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    onSelect(row.item?.id ?? null);
                  }
                }}
              >
                <span className="gantt-summary-fill" style={{ width: `${row.progress}%` }} aria-hidden="true" />
              </div>
            ))}

            {bars.map(({ item, geometry, rowIndex }) => (
              <GanttBar
                key={`bar-${item.id}`}
                item={item}
                geometry={geometry}
                rowIndex={rowIndex}
                selected={selectedId === item.id}
                dragging={drag?.id === item.id}
                overdue={
                  item.status !== 'done' &&
                  item.status !== 'dropped' &&
                  Boolean(item.gantt?.end) &&
                  (item.gantt?.end ?? '') < todayKey
                }
                onSelect={(id) => onSelect(id)}
                onDragStart={handleDragStart}
                onDragMove={handleDragMove}
                onDragEnd={handleDragEnd}
                onDragCancel={handleDragCancel}
              />
            ))}

            <GanttDependencies
              edges={depsEdges}
              rects={rects}
              titles={titles}
              selectedId={selectedId}
              width={total}
              height={totalRowsHeight}
            />

            <div className="gantt-today-line" style={{ left: todayX }} />

            {drag && dragPreview ? (
              <div
                className="gantt-drag-tip"
                style={{
                  left: barGeometry(dragPreview, range.start, px).x,
                  top: Math.max(4, drag.rowIndex * ROW_HEIGHT - 22),
                }}
              >
                {formatDateKey(dragPreview.start, 'M/d')} → {formatDateKey(dragPreview.end, 'M/d')} ·{' '}
                {diffDays(dragPreview.start, dragPreview.end) + 1} 天
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}
