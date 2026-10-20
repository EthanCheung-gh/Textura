/**
 * 条目 kind → 视图的跳转约定（应用级界面共享，不引入路由库）。
 */
import type { ItemKind } from '../../core/model';
import type { Route } from '../../core/store';

export function routeForItemKind(kind: ItemKind): Route {
  switch (kind) {
    case 'objective':
    case 'keyresult':
      return 'okr';
    case 'sop':
    case 'step':
      return 'sop';
    case 'project':
    case 'action':
    case 'milestone':
      return 'gantt';
    case 'note':
    case 'reference':
      return 'gtd';
    default:
      return 'gtd';
  }
}
