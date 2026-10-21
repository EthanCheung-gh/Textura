import type { Route } from '../core/store';
import type { IconName } from '../ui/icons';

export interface RouteMeta {
  id: Route;
  label: string;
  title: string;
  subtitle: string;
  icon: IconName;
}

/** 侧栏导航顺序即产品主流程：今日 → 日历 → OKR → GTD → 甘特 → SOP → 设置。 */
export const ROUTES: RouteMeta[] = [
  {
    id: 'dashboard',
    label: '今日',
    title: '今日',
    subtitle: '今天要推进的事，一屏看完',
    icon: 'home',
  },
  {
    id: 'calendar',
    label: '日历',
    title: '日历',
    subtitle: '公历、农历与节气的日程视图',
    icon: 'calendar-grid',
  },
  {
    id: 'okr',
    label: 'OKR',
    title: 'OKR',
    subtitle: '目标与关键结果的季度视图',
    icon: 'target',
  },
  {
    id: 'gtd',
    label: 'GTD',
    title: 'GTD',
    subtitle: '收集、澄清、推进下一步',
    icon: 'inbox',
  },
  {
    id: 'gantt',
    label: '甘特',
    title: '甘特',
    subtitle: '时间轴上的承诺与依赖',
    icon: 'timeline',
  },
  {
    id: 'sop',
    label: 'SOP',
    title: 'SOP',
    subtitle: '把流程画成可执行的图',
    icon: 'workflow',
  },
  {
    id: 'settings',
    label: '设置',
    title: '设置',
    subtitle: '存储、备份与工作区',
    icon: 'settings',
  },
];

export function routeMeta(route: Route): RouteMeta {
  return ROUTES.find((entry) => entry.id === route) ?? ROUTES[0];
}
