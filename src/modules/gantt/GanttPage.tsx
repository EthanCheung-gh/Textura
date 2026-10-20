// TODO(module): 由 gantt Worker 重写为时间轴 / 依赖视图。
import { useWorkspace } from '../../core/store';
import { itemsOfKind } from '../../core/selectors';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';

export function GanttPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const scheduled = workspace.items.filter((item) => Boolean(item.gantt?.start));

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>甘特</h1>
          <p>时间轴上的承诺与依赖。</p>
        </div>
      </div>

      <div className="placeholder-card">
        <EmptyState
          icon={<Icon name="timeline" size={20} />}
          title="甘特视图占位"
          description={`${scheduled.length} 条已排期条目、${itemsOfKind(workspace, 'project').length} 个项目、2 条依赖边，可支撑时间轴渲染。`}
        />
        <p className="placeholder-note">TODO(module): src/modules/gantt/GanttPage.tsx</p>
      </div>
    </div>
  );
}
