import { Button } from '../../ui/Button';
import { IconButton } from '../../ui/IconButton';
import { Segmented } from '../../ui/Segmented';
import { Icon } from '../../ui/icons';
import type { GanttZoom } from './scale';

export interface GanttToolbarProps {
  zoom: GanttZoom;
  onZoomChange: (zoom: GanttZoom) => void;
  rangeLabel: string;
  scheduledCount: number;
  totalCount: number;
  inspectorOpen: boolean;
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
  onFit: () => void;
  onCreate: () => void;
  onToggleInspector: () => void;
}

const ZOOM_OPTIONS = [
  { value: 'day' as const, label: '日', title: '按天查看（40px/天）' },
  { value: 'week' as const, label: '周', title: '按周查看（28px/天）' },
  { value: 'month' as const, label: '月', title: '按月查看（12px/天）' },
];

export function GanttToolbar({
  zoom,
  onZoomChange,
  rangeLabel,
  scheduledCount,
  totalCount,
  inspectorOpen,
  onPrev,
  onNext,
  onToday,
  onFit,
  onCreate,
  onToggleInspector,
}: GanttToolbarProps) {
  return (
    <div className="gantt-toolbar" role="toolbar" aria-label="甘特图工具栏">
      <Segmented
        options={ZOOM_OPTIONS}
        value={zoom}
        onChange={onZoomChange}
        size="sm"
        ariaLabel="时间轴缩放"
      />

      <div className="gantt-nav">
        <IconButton label="上一段" size="sm" onClick={onPrev}>
          <Icon name="chevron-left" size={15} />
        </IconButton>
        <Button size="sm" variant="ghost" onClick={onToday}>
          今天
        </Button>
        <IconButton label="下一段" size="sm" onClick={onNext}>
          <Icon name="chevron-right" size={15} />
        </IconButton>
      </div>

      <span className="gantt-range-label" title="当前可见区间">
        {rangeLabel}
      </span>

      <span className="gantt-toolbar-spacer" />

      <span className="gantt-count" title="已排期 / 可排期条目">
        {scheduledCount}/{totalCount} 已排期
      </span>

      <Button
        size="sm"
        variant="primary"
        iconLeft={<Icon name="plus" size={14} />}
        onClick={onCreate}
        title="在当前选中分组下新建任务（今天起 3 天）"
      >
        新建任务
      </Button>
      <Button
        size="sm"
        iconLeft={<Icon name="zoom-out" size={14} />}
        onClick={onFit}
        title="按全部有条目的日期范围重算起点"
      >
        适配窗口
      </Button>
      <Button
        size="sm"
        variant={inspectorOpen ? 'secondary' : 'ghost'}
        iconLeft={<Icon name="edit" size={14} />}
        aria-pressed={inspectorOpen}
        onClick={onToggleInspector}
      >
        {inspectorOpen ? '收起详情' : '详情'}
      </Button>
    </div>
  );
}
