/**
 * GTD 的行内动作。全部通过 store 的公开动作落库，不直接改 workspace。
 */
import type { Item } from '../../core/model';
import { getWorkspace } from '../../core/store';
import { nowIso } from '../../core/utils';
import { appendTimestampedNote } from './gtdLogic';

/** 2 分钟规则：直接完成并给出提示。 */
export function completeInboxItem(item: Item): void {
  const store = getWorkspace();
  store.toggleDone(item.id);
  store.notify(`已完成「${item.title}」，2 分钟规则处理完毕`, 'success');
}

/** 收件箱删除：即时删除，提示可撤销（Ctrl/Cmd+Z）。 */
export function deleteInboxItem(item: Item): void {
  const store = getWorkspace();
  store.deleteItems([item.id]);
  store.notify(`已删除「${item.title}」，按 Ctrl/Cmd+Z 可撤销`, 'info');
}

/**
 * 把条目放入下一步。
 * action/project 直接改状态；note/reference 无法就地改 kind，
 * 因此新建 action 并把原条目归档（notes 记录来源）。
 */
export function promoteItemToNext(item: Item): Item {
  const store = getWorkspace();
  if (item.kind === 'action' || item.kind === 'project') {
    store.updateItem(item.id, { gtd: { clarified: true } });
    store.setStatus(item.id, 'next');
    store.notify(`已放入下一步「${item.title}」`, 'success');
    return item;
  }
  const created = store.createItem({
    kind: 'action',
    title: item.title,
    notes: item.notes,
    tags: item.tags,
    areaId: item.areaId,
    status: 'next',
    gtd: {
      capturedAt: item.gtd?.capturedAt ?? nowIso(),
      clarified: true,
      context: item.gtd?.context,
      energy: item.gtd?.energy,
      twoMinuteCandidate: false,
    },
  });
  store.updateItem(item.id, {
    notes: appendTimestampedNote(item.notes, `澄清：已转为下一步行动（${created.id}）`),
    gtd: { clarified: true },
  });
  store.setStatus(item.id, 'done');
  store.notify(`已转为下一步「${created.title}」`, 'success');
  return created;
}

/** 等待中的「催办」：在 notes 追加时间戳并提示。 */
export function nudgeWaitingItem(item: Item): void {
  const store = getWorkspace();
  const target = item.gtd?.waitingFor?.trim() || '对方';
  store.updateItem(item.id, {
    notes: appendTimestampedNote(item.notes, `催办：已提醒 ${target}，等待回复。`),
  });
  store.notify(`已记录催办：${item.title}`, 'success');
}

/** 停滞项目的一键补位：新建一个 next 子动作。 */
export function createNextActionForProject(project: Item): Item {
  const store = getWorkspace();
  const created = store.createItem({
    kind: 'action',
    title: `推进：${project.title}`,
    parentId: project.id,
    status: 'next',
    areaId: project.areaId,
    tags: project.tags,
    gtd: { capturedAt: nowIso(), clarified: true },
  });
  store.notify(`已为「${project.title}」补一个下一步动作`, 'success');
  return created;
}

/**
 * 某天 → 下一步：action/project 直接激活；note/reference 走「新建 + 归档」。
 */
export function activateSomedayItem(item: Item): Item {
  return promoteItemToNext(item);
}
