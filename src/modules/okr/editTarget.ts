/**
 * 目标编辑视图的「单一编辑目标」状态机。
 *
 * 编辑视图默认只读：标题 / 领域 / 状态 / 信心 / 备注 / 每条 KR / 新增 KR 各自
 * 只在被点开时挂载输入控件。为保证任何时刻 DOM 里最多一处输入，编辑目标用
 * 一个可空值表示，点开另一个目标时上一个自动结束（失焦提交 / Esc 取消）。
 *
 * 这里只放纯函数，UI 侧用 `useState<EditTarget>` + `nextEditTarget` 驱动。
 */

export type EditTarget =
  | { kind: 'title' }
  | { kind: 'notes' }
  | { kind: 'area' }
  | { kind: 'status' }
  | { kind: 'confidence' }
  | { kind: 'kr'; id: string }
  | { kind: 'add-kr' }
  | null;

/** 两个编辑目标是否指向同一处（KR 按 id 比较）。 */
export function isSameTarget(a: EditTarget, b: EditTarget): boolean {
  if (a === null || b === null) return a === b;
  if (a.kind === 'kr' && b.kind === 'kr') return a.id === b.id;
  return a.kind === b.kind;
}

/**
 * 切换到下一个编辑目标：与当前相同则收起（再点一次同一支铅笔），否则替换。
 * 返回值永远最多一个目标，`null` 表示回到纯展示态。
 */
export function nextEditTarget(current: EditTarget, next: EditTarget): EditTarget {
  return isSameTarget(current, next) ? null : next;
}

/**
 * 编辑目标的稳定键：铅笔按钮的 `data-edit-target` 与「结束时归还焦点」共用。
 * 目标级字段用字段名，KR 用 `kr:<id>`，新增 KR 用 `add-kr`。
 */
export function editTargetKey(target: EditTarget): string {
  if (target === null) return '';
  return target.kind === 'kr' ? `kr:${target.id}` : target.kind;
}

/** 该 KR 是否处于编辑态（父组件按行计算 `editing`）。 */
export function isEditingKr(target: EditTarget, krId: string): boolean {
  return target?.kind === 'kr' && target.id === krId;
}
