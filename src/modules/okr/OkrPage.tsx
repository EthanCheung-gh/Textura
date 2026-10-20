// TODO(module): 由 okr Worker 重写为 OKR 视图（目标树 + KR 指标 + 信心指数）。
import { useWorkspace } from '../../core/store';
import { objectivesOfPeriod, rollupProgress } from '../../core/selectors';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';

export function OkrPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const period = useWorkspace((state) => state.ui.okrPeriod);
  const objectives = objectivesOfPeriod(workspace, period);

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>OKR · {period}</h1>
          <p>目标与关键结果的季度视图。</p>
        </div>
      </div>

      <div className="placeholder-card">
        <EmptyState
          icon={<Icon name="target" size={20} />}
          title="OKR 视图占位"
          description={
            objectives.length > 0
              ? `当前周期有 ${objectives.length} 个目标，整体进度 ${rollupProgress(workspace, objectives[0].id)}%。`
              : '当前周期暂无目标。'
          }
        />
        <p className="placeholder-note">TODO(module): src/modules/okr/OkrPage.tsx</p>
      </div>
    </div>
  );
}
