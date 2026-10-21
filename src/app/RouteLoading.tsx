import type { Route } from '../core/store';
import { routeMeta } from './routes';
import './RouteLoading.css';

interface RouteLoadingProps {
  route: Route;
}

/**
 * 路由懒加载骨架：`RouteView` 的 Suspense fallback。
 * 语义：role="status" + aria-live="polite" 让读屏播报；data-route 供自动化断言当前意图视图。
 * 首屏（dashboard）不走这里，只在首次打开某个 lazy 视图时出现。
 */
export function RouteLoading({ route }: RouteLoadingProps) {
  const { label } = routeMeta(route);

  return (
    <div
      className="route-loading"
      role="status"
      aria-live="polite"
      aria-busy="true"
      data-route={route}
    >
      <div className="route-loading-head">
        <div className="route-loading-mark" aria-hidden="true" />
        <span className="route-loading-text">正在织理「{label}」…</span>
      </div>
      <div className="route-loading-body" aria-hidden="true">
        <div className="route-loading-bar" data-width="title" />
        <div className="route-loading-bar" data-width="subtitle" />
        <div className="route-loading-cards">
          <div className="route-loading-card" />
          <div className="route-loading-card" />
          <div className="route-loading-card" />
        </div>
      </div>
    </div>
  );
}
