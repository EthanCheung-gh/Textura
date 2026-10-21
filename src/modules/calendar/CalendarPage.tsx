import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import clsx from 'clsx';
import type { Item } from '../../core/model';
import { scheduledItemsInRange } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { CalendarToolbar } from './CalendarToolbar';
import { DayPanel } from './DayPanel';
import { MonthGrid } from './MonthGrid';
import { WeekView } from './WeekView';
import {
  buildMonthGrid,
  bucketItemsByDay,
  daysInMonth,
  makeKey,
  monthLabel,
  shiftMonth,
  shouldAutoOpenPanel,
  visibleItems,
  weekDays,
  weekLabel,
  weekRange,
} from './calendarLogic';
import type { CalendarView } from './calendarLogic';
import { routeForKind } from './itemDisplay';
import { addDaysToKey, solarToLunar } from './lunar';
import './calendar.css';

/** 本地日历日（用户所在时区的今天），不使用 UTC，避免跨时区错位一天。 */
function localTodayKey(): string {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${month}-${day}`;
}

function initialPanelOpen(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true;
  return !window.matchMedia('(max-width: 1180px)').matches;
}

/**
 * 模块本地记忆：视图与当前日期在模块内保留，切换到其它路由再回来时不丢失。
 * 只存在于本模块内存中，不写入 store / URL / localStorage。
 */
interface CalendarMemory {
  view: CalendarView;
  selected: string;
}

let calendarMemory: CalendarMemory | null = null;

function readMemory(today: string): CalendarMemory {
  if (calendarMemory && /^\d{4}-\d{2}-\d{2}$/.test(calendarMemory.selected)) return calendarMemory;
  return { view: 'month', selected: today };
}

export function CalendarPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const selectedId = useWorkspace((state) => state.selectedId);
  const select = useWorkspace((state) => state.select);
  const setUi = useWorkspace((state) => state.setUi);
  const createItem = useWorkspace((state) => state.createItem);
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const notify = useWorkspace((state) => state.notify);

  const today = localTodayKey();
  const [todayKey] = useState(today);
  const [initial] = useState(() => readMemory(today));
  const [view, setView] = useState<CalendarView>(initial.view);
  const [selected, setSelected] = useState(initial.selected);
  const [cursor, setCursor] = useState(() => ({
    year: Number(initial.selected.slice(0, 4)),
    month: Number(initial.selected.slice(5, 7)),
  }));
  const [panelOpen, setPanelOpen] = useState(initialPanelOpen);
  /** 用户在本会话中手动收起过面板：选中日期时不再强行展开 */
  const [userCollapsed, setUserCollapsed] = useState(false);

  const panelRef = useRef<HTMLElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const cellRefs = useRef(new Map<string, HTMLDivElement>());
  const pendingFocus = useRef(false);
  const pendingPanelFocus = useRef(false);

  const monthCells = useMemo(
    () => buildMonthGrid(cursor.year, cursor.month),
    [cursor.year, cursor.month],
  );
  const weekCells = useMemo(() => weekDays(selected), [selected]);
  const activeDays = view === 'month' ? monthCells : weekCells;
  const from = activeDays[0]?.key ?? todayKey;
  const to = activeDays[activeDays.length - 1]?.key ?? todayKey;

  const items = useMemo(
    () => visibleItems(scheduledItemsInRange(workspace, from, to)),
    [workspace, from, to],
  );
  const buckets = useMemo(() => bucketItemsByDay(items, from, to), [items, from, to]);
  const areas = useMemo(
    () => new Map(workspace.areas.map((area) => [area.id, area])),
    [workspace.areas],
  );

  const dayItems = buckets.get(selected) ?? [];
  const selectedLunar = solarToLunar(selected);

  const subtitle = selectedLunar
    ? `${view === 'month' ? monthLabel(cursor.year, cursor.month) : weekLabel(selected)} · ${
        selectedLunar.ganzhiYear
      }${selectedLunar.zodiac}年 · 农历${selectedLunar.monthName}`
    : `${
        view === 'month' ? monthLabel(cursor.year, cursor.month) : weekLabel(selected)
      } · 农历数据仅支持 1900–2100`;

  /** 选中某天，并把可见月份同步到该天（跨月/跨年导航一致）。 */
  const goToDate = useCallback((key: string, focusGrid = false) => {
    if (focusGrid) pendingFocus.current = true;
    setSelected(key);
    setCursor({ year: Number(key.slice(0, 4)), month: Number(key.slice(5, 7)) });
  }, []);

  /** 显式选中日期（点击 / 方向键 / 今天 / 周视图表头）：窄屏下自动展开面板。 */
  const selectDate = useCallback(
    (key: string, focusGrid = false) => {
      goToDate(key, focusGrid);
      if (typeof window === 'undefined') return;
      if (shouldAutoOpenPanel(panelOpen, window.innerWidth, userCollapsed)) {
        setPanelOpen(true);
      }
    },
    [goToDate, panelOpen, userCollapsed],
  );

  const closePanel = useCallback(() => {
    setPanelOpen(false);
    setUserCollapsed(true);
  }, []);

  const togglePanel = useCallback(() => {
    if (panelOpen) {
      closePanel();
      return;
    }
    setPanelOpen(true);
    setUserCollapsed(false);
  }, [closePanel, panelOpen]);

  // 模块本地记忆：切换路由再回来时恢复视图与当前日期
  useEffect(() => {
    calendarMemory = { view, selected };
  }, [view, selected]);

  // 键盘移动后把焦点落到新的选中格
  useEffect(() => {
    if (!pendingFocus.current) return;
    pendingFocus.current = false;
    if (view !== 'month') return;
    cellRefs.current.get(selected)?.focus();
  }, [selected, view]);

  // Enter 时若面板处于折叠状态，先展开再聚焦
  useEffect(() => {
    if (!pendingPanelFocus.current) return;
    pendingPanelFocus.current = false;
    if (panelOpen) panelRef.current?.focus();
  }, [panelOpen]);

  const stepSegment = (direction: number) => {
    if (view === 'week') {
      goToDate(addDaysToKey(selected, direction * 7));
      return;
    }
    const next = shiftMonth(cursor.year, cursor.month, direction);
    const day = Math.min(Number(selected.slice(8, 10)), daysInMonth(next.year, next.month));
    goToDate(makeKey(next.year, next.month, day));
  };

  const handleGridKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    switch (event.key) {
      case 'ArrowLeft':
      case 'ArrowRight':
      case 'ArrowUp':
      case 'ArrowDown': {
        event.preventDefault();
        const delta =
          event.key === 'ArrowLeft' ? -1 : event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' ? -7 : 7;
        selectDate(addDaysToKey(selected, delta), true);
        return;
      }
      case 'Home':
      case 'End': {
        event.preventDefault();
        const range = weekRange(selected);
        selectDate(event.key === 'Home' ? range.start : range.end, true);
        return;
      }
      case 'PageUp':
      case 'PageDown': {
        event.preventDefault();
        const direction = event.key === 'PageUp' ? -1 : 1;
        const next = shiftMonth(cursor.year, cursor.month, direction);
        const day = Math.min(Number(selected.slice(8, 10)), daysInMonth(next.year, next.month));
        selectDate(makeKey(next.year, next.month, day), true);
        return;
      }
      case 'Enter': {
        event.preventDefault();
        if (!panelOpen) {
          pendingPanelFocus.current = true;
          setPanelOpen(true);
          setUserCollapsed(false);
        } else {
          panelRef.current?.focus();
        }
        return;
      }
      default:
        return;
    }
  };

  const handleOpenItem = (item: Item) => {
    select(item.id);
    setUi({ route: routeForKind(item.kind) });
  };

  const handleCreate = (title: string) => {
    createItem({
      kind: 'action',
      title,
      status: 'next',
      gantt: { start: selected, end: selected, progress: 0 },
      gtd: { clarified: true },
    });
    const short = `${Number(selected.slice(5, 7))}月${Number(selected.slice(8, 10))}日`;
    notify(`已添加到 ${short}`, 'success');
  };

  const handleOpenGantt = () => {
    const current = dayItems.find((item) => item.id === selectedId) ?? dayItems[0];
    if (current) select(current.id);
    setUi({ route: 'gantt' });
  };

  return (
    <div className="page cal-page">
      <div className="page-header cal-header">
        <div className="page-header-titles">
          <h1>日历</h1>
          <p className="cal-subtitle" title="当前区间 · 干支生肖 · 农历月">
            {subtitle}
          </p>
        </div>
        <CalendarToolbar
          view={view}
          onViewChange={setView}
          year={cursor.year}
          month={cursor.month}
          panelOpen={panelOpen}
          onPrev={() => stepSegment(-1)}
          onNext={() => stepSegment(1)}
          onToday={() => selectDate(todayKey)}
          onYearChange={(year) => {
            const day = Math.min(Number(selected.slice(8, 10)), daysInMonth(year, cursor.month));
            goToDate(makeKey(year, cursor.month, day));
          }}
          onMonthChange={(month) => {
            const day = Math.min(Number(selected.slice(8, 10)), daysInMonth(cursor.year, month));
            goToDate(makeKey(cursor.year, month, day));
          }}
          onTogglePanel={togglePanel}
        />
      </div>

      <div className={clsx('cal-layout', !panelOpen && 'cal-layout--panel-closed')}>
        <div className="cal-main">
          {view === 'month' ? (
            <MonthGrid
              cells={monthCells}
              buckets={buckets}
              areas={areas}
              today={todayKey}
              selected={selected}
              onSelect={selectDate}
              onKeyDown={handleGridKeyDown}
              cellRefs={cellRefs}
            />
          ) : (
            <WeekView
              days={weekCells}
              buckets={buckets}
              areas={areas}
              today={todayKey}
              selected={selected}
              selectedId={selectedId}
              onSelectDay={selectDate}
              onOpenItem={handleOpenItem}
            />
          )}
          <p className="cal-hint">
            <span className="cal-hint-item">
              <span className="cal-dot cal-dot--today" aria-hidden="true" /> 今天
            </span>
            <span className="cal-hint-item">
              <span className="cal-dot cal-dot--selected" aria-hidden="true" /> 选中
            </span>
            {view === 'month' ? (
              <span className="cal-hint-item">
                方向键 / Home / End / PageUp / PageDown 导航，Enter 进入日程面板
              </span>
            ) : (
              <span className="cal-hint-item">点击星期标题切换日期，点击卡片打开条目</span>
            )}
          </p>
        </div>

        <DayPanel
          dateKey={selected}
          today={todayKey}
          items={dayItems}
          areas={areas}
          selectedId={selectedId}
          panelRef={panelRef}
          inputRef={inputRef}
          onCreate={handleCreate}
          onOpenItem={handleOpenItem}
          onToggleDone={toggleDone}
          onOpenGantt={handleOpenGantt}
          onClose={closePanel}
          className={clsx(!panelOpen && 'is-collapsed')}
        />
      </div>
    </div>
  );
}
