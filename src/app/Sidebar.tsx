import { format } from 'date-fns';
import { useMemo } from 'react';
import { useWorkspace } from '../core/store';
import { Icon } from '../ui/icons';
import { routeCounts } from './navCounts';
import type { NavRouteId } from './navCounts';
import { ROUTES } from './routes';

const SAVE_LABELS: Record<string, string> = {
  idle: '自动保存已开启',
  saving: '正在保存…',
  saved: '已保存',
  error: '保存失败',
};

/** 徽标的语义说明（title / aria-label），口径见 navCounts.ts 文件头。 */
const COUNT_LABELS: Record<NavRouteId, (count: number) => string> = {
  dashboard: (count) => `今日焦点 ${count} 项`,
  calendar: (count) => `近 7 天排程 ${count} 项`,
  okr: (count) => `当前周期目标 ${count} 个`,
  gtd: (count) => `收件箱 ${count} 条待澄清`,
  gantt: (count) => `时间轴上未完成 ${count} 条`,
  sop: (count) => `SOP ${count} 个`,
  reports: (count) => `草稿 ${count} 篇`,
};

export function Sidebar() {
  const ui = useWorkspace((state) => state.ui);
  const setUi = useWorkspace((state) => state.setUi);
  const workspace = useWorkspace((state) => state.workspace);
  const okrPeriod = useWorkspace((state) => state.ui.okrPeriod);
  const saveState = useWorkspace((state) => state.saveState);

  // 日期键只在挂载时取一次：放渲染期会每帧变值，进而让下面的 useMemo 每帧重算。
  const today = useMemo(() => format(new Date(), 'yyyy-MM-dd'), []);
  const counts = useMemo(
    () => routeCounts(workspace, { today, okrPeriod }),
    [workspace, today, okrPeriod],
  );

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
            const routeId = route.id;
            // 'settings' 没有徽标；0 值同样不渲染（与改动前一致）。
            const count = routeId === 'settings' ? 0 : counts[routeId];
            const countLabel = routeId === 'settings' ? '' : COUNT_LABELS[routeId](count);
            return (
              <button
                key={route.id}
                type="button"
                className="sidebar-link"
                data-route={route.id}
                aria-current={active ? 'page' : undefined}
                onClick={() => setUi({ route: route.id })}
              >
                <span className="sidebar-link-icon">
                  <Icon name={route.icon} size={16} />
                </span>
                <span className="sidebar-link-label">{route.label}</span>
                {count ? (
                  <span className="sidebar-link-count" title={countLabel} aria-label={countLabel}>
                    {count}
                  </span>
                ) : null}
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
