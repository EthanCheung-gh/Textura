/**
 * 深链与视图记忆的纯函数 + 浏览器同步。
 * URL 是唯一可分享的入口：?route=okr&item=obj_activation
 */
import type { Route } from './store';

export const ROUTE_STORAGE_KEY = 'textura.route';

export const ROUTE_IDS: Route[] = ['dashboard', 'calendar', 'okr', 'gtd', 'gantt', 'sop', 'settings'];

export function isRoute(value: unknown): value is Route {
  return typeof value === 'string' && (ROUTE_IDS as string[]).includes(value);
}

function paramsFrom(search: string): URLSearchParams {
  return new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
}

/** 从查询串读取合法 route；缺失或非法返回 null。 */
export function routeFromSearch(search: string): Route | null {
  const value = paramsFrom(search).get('route');
  return isRoute(value) ? value : null;
}

/** 从查询串读取条目 id；空白返回 null。 */
export function itemIdFromSearch(search: string): string | null {
  const value = paramsFrom(search).get('item')?.trim();
  return value ? value : null;
}

/** 校验持久化的视图 id。 */
export function routeFromStored(value: string | null | undefined): Route | null {
  return isRoute(value) ? value : null;
}

/** 启动视图优先级：合法 URL 深链 > 上次记忆 > dashboard。 */
export function resolveInitialRoute(search: string, stored: string | null): Route {
  return routeFromSearch(search) ?? routeFromStored(stored) ?? 'dashboard';
}

/** 写入 route 查询参数，保留 item 等其它参数。 */
export function routeWithSearch(search: string, route: Route): string {
  const params = paramsFrom(search);
  params.set('route', route);
  const next = params.toString();
  return next ? `?${next}` : '';
}

/** 读取 localStorage 中的视图记忆；不可用时返回 null。 */
export function readRouteMemory(): string | null {
  if (typeof window === 'undefined') return null;
  try {
    return localStorage.getItem(ROUTE_STORAGE_KEY);
  } catch {
    return null;
  }
}

/**
 * 浏览器侧同步：dataset（自动化断言）+ replaceState（不产生历史）+ localStorage。
 * 只在有 window 的环境执行；Tauri / 普通浏览器行为一致。
 */
export function syncBrowserRoute(route: Route): void {
  if (typeof window === 'undefined') return;

  document.documentElement.dataset.route = route;

  try {
    const search = routeWithSearch(window.location.search, route);
    const url = `${window.location.pathname}${search}${window.location.hash}`;
    window.history.replaceState(window.history.state, '', url);
  } catch {
    // file:// 或受限 WebView 中 replaceState 可能不可用，不影响应用运行。
  }

  try {
    localStorage.setItem(ROUTE_STORAGE_KEY, route);
  } catch {
    // 隐私模式 / 禁用存储时静默降级。
  }
}
