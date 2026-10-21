import type { KeyboardEvent, MutableRefObject } from 'react';
import type { Area, Item } from '../../core/model';
import clsx from 'clsx';
import { WEEKDAY_LABELS, cellAriaLabelOf, lunarLabelOf, lunarOf } from './calendarLogic';
import type { MonthCell } from './calendarLogic';

export interface MonthGridProps {
  cells: MonthCell[];
  buckets: Map<string, Item[]>;
  areas: Map<string, Area>;
  today: string;
  selected: string;
  onSelect: (key: string) => void;
  onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => void;
  cellRefs: MutableRefObject<Map<string, HTMLDivElement>>;
}

function areaColor(areas: Map<string, Area>, item: Item): string {
  if (!item.areaId) return 'var(--text-faint)';
  return areas.get(item.areaId)?.color ?? 'var(--text-faint)';
}

export function MonthGrid({
  cells,
  buckets,
  areas,
  today,
  selected,
  onSelect,
  onKeyDown,
  cellRefs,
}: MonthGridProps) {
  const weeks = Array.from({ length: 6 }, (_, row) => cells.slice(row * 7, row * 7 + 7));

  return (
    <div className="cal-grid" role="grid" aria-label="月视图" onKeyDown={onKeyDown}>
      <div className="cal-grid-head" role="row">
        {WEEKDAY_LABELS.map((label, index) => (
          <div
            key={label}
            role="columnheader"
            aria-label={`星期${label}`}
            className={clsx('cal-grid-headcell', index >= 5 && 'is-weekend')}
          >
            {label}
          </div>
        ))}
      </div>

      <div className="cal-grid-body">
        {weeks.map((week) => (
          <div className="cal-week" role="row" key={week[0]?.key ?? 'row'}>
            {week.map((cell) => {
              const items = buckets.get(cell.key) ?? [];
              const lunar = lunarOf(cell.key);
              const label = lunarLabelOf(lunar);
              const isToday = cell.key === today;
              const isSelected = cell.key === selected;
              const hidden = items.length - 3;
              return (
                <div
                  key={cell.key}
                  role="gridcell"
                  aria-selected={isSelected}
                  aria-label={cellAriaLabelOf(cell.key, lunar, today)}
                  tabIndex={isSelected ? 0 : -1}
                  data-date={cell.key}
                  className={clsx(
                    'cal-cell',
                    !cell.inMonth && 'is-outside',
                    cell.weekend && 'is-weekend',
                    isToday && 'is-today',
                    isSelected && 'is-selected',
                  )}
                  onClick={() => onSelect(cell.key)}
                  ref={(node) => {
                    if (node) cellRefs.current.set(cell.key, node);
                    else cellRefs.current.delete(cell.key);
                  }}
                >
                  <div className="cal-cell-head">
                    <span className={clsx('cal-daynum', isToday && 'is-today')}>{cell.day}</span>
                  </div>
                  <span
                    className={clsx(
                      'cal-lunar',
                      label.kind !== 'none' && label.kind !== 'lunar' && `cal-lunar--${label.kind}`,
                    )}
                  >
                    {label.text || '\u00a0'}
                  </span>
                  <div className="cal-dots" title={items.length > 0 ? `${items.length} 项日程` : undefined}>
                    {items.slice(0, 3).map((item) => (
                      <span
                        key={item.id}
                        className="cal-dot"
                        style={{ background: areaColor(areas, item) }}
                        aria-hidden="true"
                      />
                    ))}
                    {hidden > 0 ? <span className="cal-dot-more">+{hidden}</span> : null}
                  </div>
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}
