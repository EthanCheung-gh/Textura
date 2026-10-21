import { useState } from 'react';
import type { FormEvent, RefObject } from 'react';
import clsx from 'clsx';
import type { Area, Item } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { TextInput } from '../../ui/Field';
import { IconButton } from '../../ui/IconButton';
import { Icon } from '../../ui/icons';
import {
  fullDateLabel,
  itemSpan,
  lunarFullLabel,
  relativeDayLabel,
  spanDayIndex,
} from './calendarLogic';
import { solarToLunar } from './lunar';
import { kindIcon, statusTone } from './itemDisplay';

export interface DayPanelProps {
  dateKey: string;
  today: string;
  items: Item[];
  areas: Map<string, Area>;
  selectedId: string | null;
  panelRef: RefObject<HTMLElement>;
  inputRef: RefObject<HTMLInputElement>;
  onCreate: (title: string) => void;
  onOpenItem: (item: Item) => void;
  onToggleDone: (id: string) => void;
  onOpenGantt: () => void;
  onClose?: () => void;
  className?: string;
}

function shortDate(key: string): string {
  return `${Number(key.slice(5, 7))}月${Number(key.slice(8, 10))}日`;
}

function spanText(item: Item, day: string): string {
  const span = itemSpan(item);
  if (!span) return '';
  const onlyDue = !item.gantt?.start && Boolean(item.gantt?.end);
  if (span.days > 1) {
    const index = spanDayIndex(item, day);
    return `第 ${index} 天 · ${shortDate(span.start)} – ${shortDate(span.end)}`;
  }
  return onlyDue ? '截止当天' : '';
}

export function DayPanel({
  dateKey,
  today,
  items,
  areas,
  selectedId,
  panelRef,
  inputRef,
  onCreate,
  onOpenItem,
  onToggleDone,
  onOpenGantt,
  onClose,
  className,
}: DayPanelProps) {
  const [draft, setDraft] = useState('');
  const lunar = solarToLunar(dateKey);
  const festival = lunar?.festival ?? null;
  const solarTerm = lunar?.solarTerm ?? null;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const title = draft.trim();
    if (!title) return;
    onCreate(title);
    setDraft('');
  };

  const focusInput = () => inputRef.current?.focus();

  return (
    <section
      ref={panelRef}
      className={clsx('cal-panel', className)}
      aria-label="当日日程"
      tabIndex={-1}
    >
      <header className="cal-panel-head">
        <div className="cal-panel-head-top">
          <div className="cal-panel-head-titles">
            <h2 className="cal-panel-date">{fullDateLabel(dateKey)}</h2>
            <p className="cal-panel-lunar">
              {lunar ? lunarFullLabel(lunar) : '农历数据超出 1900–2100 支持范围'}
            </p>
          </div>
          {onClose ? (
            <IconButton
              label="关闭日程面板"
              size="sm"
              className="cal-panel-close"
              onClick={onClose}
            >
              <Icon name="close" size={15} />
            </IconButton>
          ) : null}
        </div>
        <div className="cal-panel-meta">
          <span className="cal-panel-distance">{relativeDayLabel(dateKey, today)}</span>
          {festival ? <Badge tone="accent">{festival}</Badge> : null}
          {solarTerm && solarTerm !== festival ? <Badge tone="info">{solarTerm}</Badge> : null}
          <Badge tone="neutral">{items.length} 项</Badge>
        </div>
      </header>

      <div className="cal-panel-body">
        {items.length === 0 ? (
          <EmptyState
            compact
            icon={<Icon name="calendar" size={18} />}
            title="这一天还没有安排"
            description="把要做的事写进下方输入框，按 Enter 直接排到这一天。"
            action={
              <Button size="sm" variant="secondary" onClick={focusInput}>
                快速添加
              </Button>
            }
          />
        ) : (
          <ul className="cal-item-list">
            {items.map((item) => {
              const done = item.status === 'done';
              const area = item.areaId ? areas.get(item.areaId) : undefined;
              const extra = spanText(item, dateKey);
              return (
                <li
                  key={item.id}
                  className={clsx('cal-item', done && 'is-done')}
                  data-current={item.id === selectedId ? 'true' : undefined}
                >
                  <button
                    type="button"
                    className="cal-item-main"
                    onClick={() => onOpenItem(item)}
                    title={`${item.title} · 打开${STATUS_LABELS[item.status]}`}
                  >
                    <span className="cal-item-icon" aria-hidden="true">
                      <Icon name={kindIcon(item.kind)} size={15} />
                    </span>
                    <span className="cal-item-body">
                      <span className="cal-item-title">{item.title}</span>
                      <span className="cal-item-meta">
                        {area ? (
                          <span className="cal-area">
                            <span
                              className="cal-area-dot"
                              style={{ background: area.color }}
                              aria-hidden="true"
                            />
                            {area.name}
                          </span>
                        ) : null}
                        <Badge tone={statusTone(item.status)} dot>
                          {STATUS_LABELS[item.status]}
                        </Badge>
                        {extra ? <span className="cal-item-span">{extra}</span> : null}
                      </span>
                    </span>
                  </button>
                  <IconButton
                    label={done ? '标记为未完成' : '标记完成'}
                    size="sm"
                    className={clsx('cal-item-check', done && 'is-done')}
                    aria-pressed={done}
                    onClick={() => onToggleDone(item.id)}
                  >
                    <span className={clsx('cal-check-box', done && 'is-done')}>
                      {done ? <Icon name="check" size={11} /> : null}
                    </span>
                  </IconButton>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <form className="cal-quick" onSubmit={submit}>
        <TextInput
          ref={inputRef}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="添加一条日程，按 Enter 保存"
          aria-label="添加到这一天的日程标题"
          maxLength={120}
        />
        <Button
          type="submit"
          size="sm"
          variant="primary"
          disabled={draft.trim().length === 0}
          iconLeft={<Icon name="plus" size={14} />}
        >
          添加
        </Button>
      </form>

      <div className="cal-panel-footer">
        <Button
          block
          size="sm"
          variant="secondary"
          iconLeft={<Icon name="timeline" size={14} />}
          onClick={onOpenGantt}
        >
          在甘特中查看
        </Button>
      </div>
    </section>
  );
}
