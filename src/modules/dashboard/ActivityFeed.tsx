import { formatDateTime } from '../../core/utils';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import type { ActivityEntry } from './today';
import { relativeTime } from './today';

export function ActivityFeed({ entries }: { entries: ActivityEntry[] }) {
  if (entries.length === 0) {
    return (
      <EmptyState
        compact
        icon={<Icon name="clock" size={20} />}
        title="还没有活动记录"
        description="完成一个行动，或在 SOP 视图里运行一次流程，这里就会出现时间线。"
      />
    );
  }

  return (
    <ol className="dash-activity-list" aria-label="最近活动">
      {entries.map((entry) => (
        <li
          className="dash-activity-row"
          key={entry.id}
          data-kind={entry.kind}
          data-result={entry.result ?? undefined}
        >
          <span className="dash-activity-icon" aria-hidden="true">
            <Icon
              name={entry.kind === 'run' ? (entry.result === 'fail' ? 'x' : 'play') : 'check'}
              size={13}
            />
          </span>
          <span className="dash-activity-main">
            <span className="dash-activity-title">{entry.title}</span>
            <span className="dash-activity-detail">{entry.detail}</span>
          </span>
          <time className="dash-activity-time" dateTime={entry.at} title={formatDateTime(entry.at)}>
            {relativeTime(entry.at)}
          </time>
        </li>
      ))}
    </ol>
  );
}
