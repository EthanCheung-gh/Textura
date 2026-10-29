/**
 * 目标编辑视图（独立页面式）的纯函数。
 *
 * 只做「视图层派生」：目标解析与编辑页汇总。领域进度一律复用
 * `core/selectors` 与 `okrMath.executionItemsOf`，不复制 rollup / 树遍历逻辑。
 */
import type { Item, Workspace } from '../../core/model';
import { childrenOf, itemById } from '../../core/selectors';
import { executionItemsOf } from './okrMath';

/**
 * 编辑视图要展示的目标：id 必须存在且 `kind === 'objective'`。
 * 缺失 id、已被删除、非目标（keyresult/action/…）一律返回 null，由 UI 渲染空态。
 */
export function resolveEditorObjective(
  workspace: Workspace,
  id: string | null | undefined,
): Item | null {
  if (!id) return null;
  const item = itemById(workspace, id);
  if (!item || item.kind !== 'objective') return null;
  return item;
}

export interface EditorSummary {
  keyResults: number;
  doneKeyResults: number;
  /** 通过 okr 边或 KR 子项关联的执行项（project / action）去重后的数量。 */
  executionItems: number;
  doneExecutionItems: number;
}

const EMPTY_SUMMARY: EditorSummary = {
  keyResults: 0,
  doneKeyResults: 0,
  executionItems: 0,
  doneExecutionItems: 0,
};

/**
 * 编辑页汇总：KR 数 / 已完成 KR 数 / 关联执行项数 / 已完成执行项数。
 *
 * 执行项复用 `executionItemsOf`（每条 KR 内已按 edge → child 去重），
 * 这里再按 item id 跨 KR 去重：同一个执行项经不同 KR 的两条路径出现时只算一次。
 */
export function summarizeEditor(workspace: Workspace, objectiveId: string): EditorSummary {
  const objective = resolveEditorObjective(workspace, objectiveId);
  if (!objective) return { ...EMPTY_SUMMARY };

  const keyResults = childrenOf(workspace, objective.id).filter(
    (item) => item.kind === 'keyresult',
  );
  const seen = new Set<string>();
  let doneKeyResults = 0;
  let doneExecutionItems = 0;

  for (const kr of keyResults) {
    if (kr.status === 'done') doneKeyResults += 1;
    for (const entry of executionItemsOf(workspace, kr.id)) {
      if (seen.has(entry.item.id)) continue;
      seen.add(entry.item.id);
      if (entry.item.status === 'done') doneExecutionItems += 1;
    }
  }

  return {
    keyResults: keyResults.length,
    doneKeyResults,
    executionItems: seen.size,
    doneExecutionItems,
  };
}
