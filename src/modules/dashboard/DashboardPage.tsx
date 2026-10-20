// TODO(module): 由 appshell Worker 重写为真正的「今日」工作台。
import { useWorkspace } from '../../core/store';
import { countByStatus, dueTodayItems, nextActions, overdueItems } from '../../core/selectors';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { Badge } from '../../ui/Badge';

export function DashboardPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const today = new Date().toISOString().slice(0, 10);
  const counts = countByStatus(workspace);
  const due = dueTodayItems(workspace, today);
  const overdue = overdueItems(workspace, today);
  const next = nextActions(workspace);

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>今日</h1>
          <p>今天要推进的事，一屏看完。</p>
        </div>
        <div className="page-actions">
          <Badge tone="accent">收件箱 {counts.inbox}</Badge>
          <Badge tone="info">下一步 {next.length}</Badge>
          <Badge tone={overdue.length > 0 ? 'danger' : 'neutral'}>逾期 {overdue.length}</Badge>
          <Badge tone="neutral">今日到期 {due.length}</Badge>
        </div>
      </div>

      <div className="placeholder-card">
        <EmptyState
          icon={<Icon name="calendar" size={20} />}
          title="今日视图占位"
          description="演示数据已就绪（收件箱、下一步、排期、SOP 运行记录）。此页将由 appshell Worker 替换为时间线与聚焦面板。"
        />
        <p className="placeholder-note">TODO(module): src/modules/dashboard/DashboardPage.tsx</p>
      </div>
    </div>
  );
}
