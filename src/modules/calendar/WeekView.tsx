import clsx from 'clsx';
import type { Area, Item } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { Icon } from '../../ui/icons';
import { itemSpan, lunarLabel, spanDayIndex, weekdayLabel } from './calendarLogic';
import type { MonthCell } from './calendarLogic';
import { kindIcon, statusColor } from './itemDisplay';

const WEEKDAY_SHORT = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

export interface WeekViewProps {
  days: MonthCell[];
  buckets: Map<string, Item[]>;
  areas: Map<string, Area>;
  today: string;
  selected: string;
  selectedId: string | null;
  onSelectDay: (key: string) => void;
  onOpenItem: (item: Item) => void;
}

function areaColor(areas: Map<string, Area>, item: Item): string {
  if (!item.areaId) return 'var(--text-faint)';
  return areas.get(item.areaId)?.color ?? 'var(--text-faint)';
}

function spanText(item: Item, day: string): string {
  const span = itemSpan(item);
  if (!span) return '';
  if (span.days > 1) {
    const index = spanDayIndex(item, day);
    return index > 0 ? `第 ${index}/${span.days} 天` : '';
  }
  const onlyDue = !item.gantt?.start && Boolean(item.gantt?.end);
  return onlyDue ? '截止' : '';
}

export function WeekView({
  days,
  buckets,
  areas,
  today,
  selected,
  selectedId,
  onSelectDay,
  onOpenItem,
}: WeekViewProps) {
  return (
    <div className="cal-week-view" role="group" aria-label="周视图">
      {days.map((day, index) => {
        const items = buckets.get(day.key) ?? [];
        const isToday = day.key === today;
        const isSelected = day.key === selected;
        return (
          <section
            key={day.key}
            className={clsx('cal-week-col', day.weekend && 'is-weekend', isToday && 'is-today', isSelected && 'is-selected')}
            aria-label={`${weekdayLabel(day.key)} ${day.month}月${day.day}日`}
          >
            <button
              type="button"
              className="cal-week-head"
              onClick={() => onSelectDay(day.key)}
              aria-pressed={isSelected}
            >
              <span className="cal-week-head-weekday">{WEEKDAY_SHORT[index]}</span>
              <span className={clsx('cal-week-head-day', isToday && 'is-today')}>{day.day}</span>
              <span className="cal-week-head-lunar">{lunarLabel(day.key) || '\u00a0'}</span>
            </button>

            <div className="cal-week-body">
              {items.length === 0 ? (
                <p className="cal-week-empty" aria-hidden="true">
                  —
                </p>
              ) : (
                items.map((item) => {
                  const extra = spanText(item, day.key);
                  const done = item.status === 'done';
                  return (
                    <button
                      key={item.id}
                      type="button"
                      className={clsx('cal-week-card', done && 'is-done')}
                      aria-current={item.id === selectedId ? 'true' : undefined}
                      title={`${item.title} · ${STATUS_LABELS[item.status]}${extra ? ` · ${extra}` : ''}`}
                      onClick={() => onOpenItem(item)}
                    >
                      <span className="cal-week-card-title">
                        <Icon name={kindIcon(item.kind)} size={12} />
                        <span>{item.title}</span>
                      </span>
                      <span className="cal-week-card-meta">
                        <span
                          className="cal-area-dot"
                          style={{ background: areaColor(areas, item) }}
                          aria-hidden="true"
                        />
                        <span
                          className="cal-status-dot"
                          style={{ borderColor: statusColor(item.status) }}
                          title={STATUS_LABELS[item.status]}
                          aria-hidden="true"
                        />
                        {extra ? <span className="cal-week-card-span">{extra}</span> : null}
                      </span>
                    </button>
                  );
                })
              )}
            </div>
          </section>
        );
      })}
    </div>
  );
}
