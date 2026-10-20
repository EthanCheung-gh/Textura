import { useWorkspace } from '../core/store';
import { countByStatus } from '../core/selectors';
import { Icon } from '../ui/icons';
import { ROUTES } from './routes';

const SAVE_LABELS: Record<string, string> = {
  idle: '自动保存已开启',
  saving: '正在保存…',
  saved: '已保存',
  error: '保存失败',
};

export function Sidebar() {
  const ui = useWorkspace((state) => state.ui);
  const setUi = useWorkspace((state) => state.setUi);
  const workspace = useWorkspace((state) => state.workspace);
  const saveState = useWorkspace((state) => state.saveState);
  const counts = countByStatus(workspace);

  return (
    <aside className="sidebar" aria-label="主导航">
      <div className="sidebar-brand">
        <div className="sidebar-brand-mark" aria-hidden="true">
          <Icon name="workflow" size={17} />
        </div>
        <div className="sidebar-brand-text">
          <span className="sidebar-brand-name">Textura</span>
          <span className="sidebar-brand-sub">织理</span>
        </div>
      </div>

      <div className="sidebar-scroll">
        <nav className="sidebar-nav" aria-label="视图">
          {ROUTES.map((route) => {
            const active = ui.route === route.id;
            const count = route.id === 'gtd' ? counts.inbox : null;
            return (
              <button
                key={route.id}
                type="button"
                className="sidebar-link"
                aria-current={active ? 'page' : undefined}
                onClick={() => setUi({ route: route.id })}
              >
                <span className="sidebar-link-icon">
                  <Icon name={route.icon} size={16} />
                </span>
                <span className="sidebar-link-label">{route.label}</span>
                {count ? <span className="sidebar-link-count">{count}</span> : null}
              </button>
            );
          })}
        </nav>

        <div>
          <div className="sidebar-section-title">领域</div>
          <div className="sidebar-areas">
            {workspace.areas.length === 0 ? (
              <div className="sidebar-area faint">暂无领域</div>
            ) : (
              workspace.areas.map((area) => (
                <div key={area.id} className="sidebar-area">
                  <span className="sidebar-area-dot" style={{ background: area.color }} />
                  <span className="sidebar-area-name">{area.name}</span>
                  <span className="sidebar-area-count">
                    {
                      workspace.items.filter(
                        (item) =>
                          item.areaId === area.id &&
                          item.status !== 'done' &&
                          item.status !== 'dropped',
                      ).length
                    }
                  </span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="sidebar-footer">
        <div className="storage-status" role="status">
          <span className="storage-dot" data-state={saveState} />
          {SAVE_LABELS[saveState] ?? '自动保存已开启'}
        </div>
        <div className="storage-status faint">
          {workspace.items.length} 条记录 · v{workspace.version}
        </div>
      </div>
    </aside>
  );
}
