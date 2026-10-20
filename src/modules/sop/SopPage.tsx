// TODO(module): 由 sop Worker 重写为图形化 SOP 画布。
import { useWorkspace } from '../../core/store';
import { itemsOfKind, sopGraph } from '../../core/selectors';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';

export function SopPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const sops = itemsOfKind(workspace, 'sop');
  const first = sops[0];
  const graph = first ? sopGraph(workspace, first.id) : { nodes: [], edges: [] };

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>SOP</h1>
          <p>把流程画成可执行的图。</p>
        </div>
      </div>

      <div className="placeholder-card">
        <EmptyState
          icon={<Icon name="workflow" size={20} />}
          title="图形化 SOP 画布"
          description={
            first
              ? `「${first.title}」含 ${graph.nodes.length} 个节点、${graph.edges.length} 条 flow 边，画布坐标已布好。`
              : '暂无 SOP。'
          }
        />
        <p className="placeholder-note">TODO(module): src/modules/sop/SopPage.tsx</p>
      </div>
    </div>
  );
}
