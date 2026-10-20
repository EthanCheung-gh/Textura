import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { Item } from '../../core/model';
import { itemById } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { GanttInspector } from './GanttInspector';
import { GanttTimeline } from './GanttTimeline';
import type { GanttViewport } from './GanttTimeline';
import { GanttToolbar } from './GanttToolbar';
import { GanttTree } from './GanttTree';
import type { GanttEditing } from './GanttTree';
import {
  HEADER_HEIGHT,
  ROW_HEIGHT,
  UNGROUPED_ID,
  ZOOM_CONFIG,
  addDaysKey,
  buildRange,
  buildRows,
  dateToX,
  formatRangeLabel,
  isGanttableItem,
  itemRange,
  toKey,
  visibleRange,
  xToDate,
} from './scale';
import type { BarRange, GanttZoom } from './scale';
import './gantt.css';

/** 适配窗口 / 首次进入时，最早任务左侧保留的天数。 */
const FIT_MARGIN_DAYS = 4;

export function GanttPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const selectedId = useWorkspace((state) => state.selectedId);
  const zoom = useWorkspace((state) => state.ui.ganttZoom);
  const inspectorOpen = useWorkspace((state) => state.ui.inspectorOpen);
  const select = useWorkspace((state) => state.select);
  const setUi = useWorkspace((state) => state.setUi);
  const createItem = useWorkspace((state) => state.createItem);
  const updateItem = useWorkspace((state) => state.updateItem);
  const notify = useWorkspace((state) => state.notify);

  const scrollerRef = useRef<HTMLDivElement>(null);
  const [viewport, setViewport] = useState<GanttViewport>({
    scrollLeft: 0,
    scrollTop: 0,
    width: 800,
    height: 480,
  });
  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set());
  const [extra, setExtra] = useState({ before: 0, after: 0 });
  const [editing, setEditing] = useState<GanttEditing | null>(null);
  const editingRef = useRef<GanttEditing | null>(null);
  const pendingScroll = useRef<number | null>(null);
  const pendingLeft = useRef<string | null>(null);
  const initialScrollDone = useRef(false);

  const todayKey = useMemo(() => toKey(new Date()), []);

  const ganttItems = useMemo(() => workspace.items.filter(isGanttableItem), [workspace.items]);
  const baseRange = useMemo(() => buildRange(ganttItems, zoom, todayKey), [ganttItems, zoom, todayKey]);
  const range = useMemo(
    () => ({
      start: addDaysKey(baseRange.start, -extra.before),
      end: addDaysKey(baseRange.end, extra.after),
    }),
    [baseRange, extra.before, extra.after],
  );
  const rows = useMemo(() => buildRows(workspace, collapsed), [workspace, collapsed]);
  const scheduledCount = useMemo(
    () => ganttItems.filter((item) => itemRange(item) !== null).length,
    [ganttItems],
  );

  const px = ZOOM_CONFIG[zoom].pxPerDay;
  const visible = visibleRange(range, viewport.scrollLeft, viewport.width, px);
  const rangeLabel = formatRangeLabel(visible.start, visible.end);

  const updateEditing = useCallback((updater: (current: GanttEditing | null) => GanttEditing | null) => {
    setEditing((current) => {
      const next = updater(current);
      editingRef.current = next;
      return next;
    });
  }, []);

  const handleViewportChange = useCallback((next: GanttViewport) => setViewport(next), []);

  const handleSelect = useCallback(
    (id: string | null) => {
      const current = editingRef.current;
      if (current && current.id !== id) {
        // 点击其它条目时先提交正在编辑的标题，避免输入丢失。
        editingRef.current = null;
        setEditing(null);
        const item = itemById(workspace, current.id);
        const next = current.value.trim();
        if (item && next && next !== item.title) updateItem(item.id, { title: next });
      }
      select(id);
    },
    [select, workspace, updateItem],
  );

  const handleToggleGroup = useCallback((id: string) => {
    setCollapsed((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const handleStartEdit = useCallback(
    (item: Item) => {
      updateEditing(() => ({ id: item.id, value: item.title }));
    },
    [updateEditing],
  );

  const handleEditingChange = useCallback(
    (value: string) => {
      updateEditing((current) => (current ? { ...current, value } : current));
    },
    [updateEditing],
  );

  const handleCommitEdit = useCallback(() => {
    const current = editingRef.current;
    if (!current) return;
    editingRef.current = null;
    setEditing(null);
    const item = itemById(workspace, current.id);
    const next = current.value.trim();
    if (item && next && next !== item.title) updateItem(item.id, { title: next });
  }, [workspace, updateItem]);

  const handleCancelEdit = useCallback(() => {
    editingRef.current = null;
    setEditing(null);
  }, []);

  const expandAncestors = useCallback(
    (rootId: string | null) => {
      setCollapsed((previous) => {
        const next = new Set(previous);
        next.delete(UNGROUPED_ID);
        let cursor: Item | undefined = rootId ? itemById(workspace, rootId) : undefined;
        let guard = 0;
        while (cursor && guard < 20) {
          next.delete(cursor.id);
          cursor = cursor.parentId ? itemById(workspace, cursor.parentId) : undefined;
          guard += 1;
        }
        return next;
      });
    },
    [workspace],
  );

  const handleSchedule = useCallback(
    (id: string) => {
      const item = itemById(workspace, id);
      if (!item) return;
      updateItem(id, { gantt: { start: todayKey, end: addDaysKey(todayKey, 2) } });
      expandAncestors(item.parentId);
      select(id);
      notify(`「${item.title}」已排期到今天起 3 天`, 'success');
    },
    [workspace, todayKey, updateItem, expandAncestors, select, notify],
  );

  const handleCreate = useCallback(() => {
    const selected = selectedId ? itemById(workspace, selectedId) : undefined;
    const parentId = selected
      ? selected.kind === 'project' || selected.kind === 'sop'
        ? selected.id
        : selected.parentId
      : null;
    const item = createItem({
      kind: 'action',
      title: '新任务',
      parentId,
      areaId: selected?.areaId ?? null,
      gantt: { start: todayKey, end: addDaysKey(todayKey, 2), progress: 0 },
    });
    expandAncestors(parentId);
    select(item.id);
    updateEditing(() => ({ id: item.id, value: item.title }));
    notify('已创建任务，直接输入标题', 'success');
  }, [selectedId, workspace, createItem, todayKey, expandAncestors, select, updateEditing, notify]);

  const handleDragCommit = useCallback(
    (id: string, bar: BarRange) => {
      const item = itemById(workspace, id);
      if (!item) return;
      updateItem(id, { gantt: { start: bar.start, end: bar.end } });
      const parent = item.parentId ? itemById(workspace, item.parentId) : undefined;
      const parentRange = parent ? itemRange(parent) : null;
      if (parent && parentRange && (bar.start < parentRange.start || bar.end > parentRange.end)) {
        notify(
          `「${item.title}」已超出父级「${parent.title}」的区间，仍按拖拽结果保存`,
          'info',
        );
      }
    },
    [workspace, updateItem, notify],
  );

  const handleZoomChange = useCallback(
    (next: GanttZoom) => {
      if (next === zoom) return;
      pendingLeft.current = xToDate(viewport.scrollLeft, range.start, ZOOM_CONFIG[zoom].pxPerDay);
      setExtra({ before: 0, after: 0 });
      setUi({ ganttZoom: next });
    },
    [zoom, viewport.scrollLeft, range.start, setUi],
  );

  const handleToday = useCallback(() => {
    const element = scrollerRef.current;
    if (!element) return;
    const x = dateToX(todayKey, range.start, ZOOM_CONFIG[zoom].pxPerDay);
    element.scrollLeft = Math.max(0, Math.min(element.scrollWidth - element.clientWidth, x - element.clientWidth * 0.35));
  }, [todayKey, range.start, zoom]);

  const handleFit = useCallback(() => {
    setExtra({ before: 0, after: 0 });
    const scale = ZOOM_CONFIG[zoom].pxPerDay;
    let earliest: string | null = null;
    for (const item of ganttItems) {
      const itemDates = itemRange(item);
      if (itemDates && (!earliest || itemDates.start < earliest)) earliest = itemDates.start;
    }
    const target = earliest
      ? Math.max(0, dateToX(earliest, baseRange.start, scale) - FIT_MARGIN_DAYS * scale)
      : 0;
    pendingScroll.current = target;
    const element = scrollerRef.current;
    if (element) element.scrollLeft = target;
  }, [ganttItems, baseRange.start, zoom]);

  const handleNav = useCallback(
    (direction: -1 | 1) => {
      const element = scrollerRef.current;
      if (!element) return;
      const scale = ZOOM_CONFIG[zoom].pxPerDay;
      const step = Math.max(160, Math.round(element.clientWidth * 0.8));
      if (direction < 0) {
        if (element.scrollLeft <= 2) {
          const days = Math.max(14, Math.ceil(step / scale) + 7);
          pendingScroll.current = days * scale - step;
          setExtra((previous) => ({ ...previous, before: previous.before + days }));
          return;
        }
        element.scrollLeft = Math.max(0, element.scrollLeft - step);
        return;
      }
      const remaining = element.scrollWidth - element.scrollLeft - element.clientWidth;
      if (remaining < 2) {
        const days = Math.max(14, Math.ceil(step / scale) + 7);
        pendingScroll.current = element.scrollLeft + step;
        setExtra((previous) => ({ ...previous, after: previous.after + days }));
        return;
      }
      element.scrollLeft += Math.min(step, remaining);
    },
    [zoom],
  );

  // 扩展画布后恢复滚动位置（向左扩展时保持当前日期不跳动）。
  useLayoutEffect(() => {
    const element = scrollerRef.current;
    if (!element) return;
    if (pendingScroll.current !== null) {
      element.scrollLeft = Math.max(0, pendingScroll.current);
      pendingScroll.current = null;
    }
  }, [extra.before, extra.after]);

  // 切换缩放时把原来的左边缘日期留在左边缘。
  useLayoutEffect(() => {
    if (!pendingLeft.current) return;
    const element = scrollerRef.current;
    if (element) {
      element.scrollLeft = Math.max(
        0,
        dateToX(pendingLeft.current, range.start, ZOOM_CONFIG[zoom].pxPerDay),
      );
    }
    pendingLeft.current = null;
  }, [zoom, range.start]);

  // 首次进入时把视口滚到最早任务附近，保证演示数据的任务条整体可见。
  useLayoutEffect(() => {
    if (initialScrollDone.current) return;
    const element = scrollerRef.current;
    if (!element) return;
    let earliest: string | null = null;
    for (const item of ganttItems) {
      const itemDates = itemRange(item);
      if (itemDates && (!earliest || itemDates.start < earliest)) earliest = itemDates.start;
    }
    if (earliest) {
      const scale = ZOOM_CONFIG[zoom].pxPerDay;
      element.scrollLeft = Math.max(0, dateToX(earliest, range.start, scale) - FIT_MARGIN_DAYS * scale);
    }
    initialScrollDone.current = true;
  }, [ganttItems, range.start, zoom]);

  // 新建 / 双击编辑时确保目标行进入可视区。
  useEffect(() => {
    if (!editing) return;
    const index = rows.findIndex((row) => row.type === 'item' && row.id === editing.id);
    const element = scrollerRef.current;
    if (index < 0 || !element) return;
    const rowTop = HEADER_HEIGHT + index * ROW_HEIGHT;
    if (rowTop < element.scrollTop + HEADER_HEIGHT) {
      element.scrollTop = Math.max(0, rowTop - HEADER_HEIGHT);
    } else if (rowTop + ROW_HEIGHT > element.scrollTop + element.clientHeight) {
      element.scrollTop = rowTop + ROW_HEIGHT - element.clientHeight;
    }
  }, [editing, rows]);

  return (
    <div className="page gantt-page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>甘特</h1>
          <p>时间轴上的承诺与依赖。</p>
        </div>
      </div>

      <GanttToolbar
        zoom={zoom}
        onZoomChange={handleZoomChange}
        rangeLabel={rangeLabel}
        scheduledCount={scheduledCount}
        totalCount={ganttItems.length}
        inspectorOpen={inspectorOpen}
        onPrev={() => handleNav(-1)}
        onNext={() => handleNav(1)}
        onToday={handleToday}
        onFit={handleFit}
        onCreate={handleCreate}
        onToggleInspector={() => setUi({ inspectorOpen: !inspectorOpen })}
      />

      <div className="gantt-body">
        <GanttTree
          rows={rows}
          selectedId={selectedId}
          todayKey={todayKey}
          scrollTop={viewport.scrollTop}
          scrollerRef={scrollerRef}
          editing={editing}
          onToggleGroup={handleToggleGroup}
          onSelect={handleSelect}
          onStartEdit={handleStartEdit}
          onEditingChange={handleEditingChange}
          onCommitEdit={handleCommitEdit}
          onCancelEdit={handleCancelEdit}
          onSchedule={handleSchedule}
        />

        <div className="gantt-timeline-wrap">
          <GanttTimeline
            workspace={workspace}
            rows={rows}
            range={range}
            zoom={zoom}
            todayKey={todayKey}
            selectedId={selectedId}
            viewport={viewport}
            scrollerRef={scrollerRef}
            onViewportChange={handleViewportChange}
            onSelect={handleSelect}
            onDragCommit={handleDragCommit}
          />

          {scheduledCount === 0 ? (
            <div className="gantt-empty-overlay">
              <div className="gantt-empty-card">
                <EmptyState
                  icon={<Icon name="timeline" size={20} />}
                  title="还没有排期条目"
                  description="从 GTD 的下一步或 OKR 的执行项排期，时间轴就会亮起来。未排期的条目仍保留在左侧，可点「排期」快速落位。"
                  action={
                    <Button variant="primary" size="sm" onClick={() => setUi({ route: 'gtd' })}>
                      去 GTD 看看下一步
                    </Button>
                  }
                />
              </div>
            </div>
          ) : null}
        </div>

        {inspectorOpen ? (
          <GanttInspector
            workspace={workspace}
            selectedId={selectedId}
            onSelect={handleSelect}
            onClose={() => setUi({ inspectorOpen: false })}
          />
        ) : null}
      </div>
    </div>
  );
}
