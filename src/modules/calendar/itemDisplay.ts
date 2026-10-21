/** 日历视图内的条目展示映射（图标 / 状态色 / 跳转路由）。 */
import type { ItemKind, ItemStatus } from '../../core/model';
import type { Route } from '../../core/store';
import type { BadgeTone } from '../../ui/Badge';
import type { IconName } from '../../ui/icons';

export function kindIcon(kind: ItemKind): IconName {
  switch (kind) {
    case 'objective':
    case 'keyresult':
      return 'target';
    case 'project':
      return 'folder';
    case 'action':
      return 'clock';
    case 'sop':
    case 'step':
      return 'workflow';
    case 'milestone':
      return 'flag';
    case 'reference':
      return 'link';
    case 'note':
    default:
      return 'edit';
  }
}

export function statusTone(status: ItemStatus): BadgeTone {
  switch (status) {
    case 'done':
      return 'ok';
    case 'waiting':
      return 'warn';
    case 'dropped':
      return 'danger';
    case 'scheduled':
      return 'info';
    case 'active':
      return 'accent';
    default:
      return 'neutral';
  }
}

/** 状态点颜色（语义令牌，不硬编码色值）。 */
export function statusColor(status: ItemStatus): string {
  switch (status) {
    case 'done':
      return 'var(--ok)';
    case 'waiting':
      return 'var(--warn)';
    case 'dropped':
      return 'var(--danger)';
    case 'scheduled':
      return 'var(--info)';
    case 'active':
      return 'var(--accent)';
    default:
      return 'var(--text-faint)';
  }
}

export function routeForKind(kind: ItemKind): Route {
  switch (kind) {
    case 'project':
    case 'action':
    case 'milestone':
      return 'gantt';
    case 'sop':
    case 'step':
      return 'sop';
    case 'objective':
    case 'keyresult':
      return 'okr';
    case 'note':
    case 'reference':
    default:
      return 'gtd';
  }
}
