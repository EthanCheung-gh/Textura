// TODO(module): 由 gtd Worker 重写为收集 / 澄清 / 下一步的 GTD 工作流。
import { useWorkspace } from '../../core/store';
import { inboxItems, nextActions, waitingItems } from '../../core/selectors';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';

export function GtdPage() {
  const workspace = useWorkspace((state) => state.workspace);

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>GTD</h1>
          <p>收集、澄清、推进下一步。</p>
        </div>
      </div>

      <div className="placeholder-card">
        <EmptyState
          icon={<Icon name="inbox" size={20} />}
          title="GTD 视图占位"
          description={`收件箱 ${inboxItems(workspace).length} 条 · 下一步 ${nextActions(workspace).length} 条 · 等待 ${waitingItems(workspace).length} 条，演示数据已就绪。`}
        />
        <p className="placeholder-note">TODO(module): src/modules/gtd/GtdPage.tsx</p>
      </div>
    </div>
  );
}
