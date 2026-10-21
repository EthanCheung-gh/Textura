import { Button } from '../../ui/Button';
import { IconButton } from '../../ui/IconButton';
import { Select } from '../../ui/Field';
import { Segmented } from '../../ui/Segmented';
import { Icon } from '../../ui/icons';
import type { CalendarView } from './calendarLogic';
import { monthOptions, yearOptions } from './calendarLogic';

const VIEW_OPTIONS = [
  { value: 'month' as const, label: '月', title: '月视图（6 × 7 网格）' },
  { value: 'week' as const, label: '周', title: '周视图（周一至周日）' },
];

const YEAR_OPTIONS = yearOptions();
const MONTH_OPTIONS = monthOptions();

export interface CalendarToolbarProps {
  view: CalendarView;
  onViewChange: (view: CalendarView) => void;
  year: number;
  month: number;
  panelOpen: boolean;
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
  onYearChange: (year: number) => void;
  onMonthChange: (month: number) => void;
  onTogglePanel: () => void;
}

export function CalendarToolbar({
  view,
  onViewChange,
  year,
  month,
  panelOpen,
  onPrev,
  onNext,
  onToday,
  onYearChange,
  onMonthChange,
  onTogglePanel,
}: CalendarToolbarProps) {
  return (
    <div className="cal-toolbar" role="toolbar" aria-label="日历工具栏">
      <Segmented options={VIEW_OPTIONS} value={view} onChange={onViewChange} size="sm" ariaLabel="视图切换" />

      <div className="cal-nav">
        <IconButton label="上一段" size="sm" onClick={onPrev}>
          <Icon name="chevron-left" size={15} />
        </IconButton>
        <Button size="sm" variant="ghost" onClick={onToday} title="回到今天并选中">
          今天
        </Button>
        <IconButton label="下一段" size="sm" onClick={onNext}>
          <Icon name="chevron-right" size={15} />
        </IconButton>
      </div>

      <div className="cal-selects">
        <Select
          aria-label="年份"
          className="cal-select cal-select--year"
          options={YEAR_OPTIONS}
          value={String(year)}
          onChange={(event) => onYearChange(Number(event.target.value))}
        />
        <Select
          aria-label="月份"
          className="cal-select cal-select--month"
          options={MONTH_OPTIONS}
          value={String(month)}
          onChange={(event) => onMonthChange(Number(event.target.value))}
        />
      </div>

      <Button
        size="sm"
        variant="ghost"
        className="cal-panel-toggle"
        aria-pressed={panelOpen}
        onClick={onTogglePanel}
        iconLeft={<Icon name="calendar" size={14} />}
      >
        {panelOpen ? '收起日程' : '展开日程'}
      </Button>
    </div>
  );
}
