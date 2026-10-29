import { describe, expect, it } from 'vitest';
import type { Edge, Item, Workspace } from '../../core/model';
import { WORKSPACE_VERSION } from '../../core/model';
import { resolveEditorObjective, summarizeEditor } from './okrEditor';

const NOW = '2026-10-08T09:00:00.000Z';

function makeItem(partial: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: NOW,
    updatedAt: NOW,
    completedAt: null,
    ...partial,
  };
}

function makeWorkspace(items: Item[] = [], edges: Edge[] = []): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items,
    edges,
    areas: [],
    runs: [],
    updatedAt: NOW,
  };
}

const objective = makeItem({
  id: 'obj_a',
  kind: 'objective',
  title: '让新用户第一周就爱上织理',
  status: 'active',
  okr: { period: '2026-Q4', confidence: 6 },
});

const kr1 = makeItem({ id: 'kr_1', kind: 'keyresult', title: 'NPS 42 → 60', parentId: 'obj_a' });
const kr2 = makeItem({ id: 'kr_2', kind: 'keyresult', title: '周活跃 1200 → 2000', parentId: 'obj_a' });
const kr3 = makeItem({
  id: 'kr_3',
  kind: 'keyresult',
  title: '付费转化 2.1% → 3%',
  parentId: 'obj_a',
  status: 'done',
});

describe('resolveEditorObjective', () => {
  it('returns the objective for a valid id', () => {
    const ws = makeWorkspace([objective, kr1]);
    expect(resolveEditorObjective(ws, 'obj_a')?.id).toBe('obj_a');
  });

  it('returns null for a missing id', () => {
    const ws = makeWorkspace([objective]);
    expect(resolveEditorObjective(ws, 'obj_missing')).toBeNull();
  });

  it('returns null for null / empty ids', () => {
    const ws = makeWorkspace([objective]);
    expect(resolveEditorObjective(ws, null)).toBeNull();
    expect(resolveEditorObjective(ws, undefined)).toBeNull();
    expect(resolveEditorObjective(ws, '')).toBeNull();
  });

  it('rejects non-objective kinds', () => {
    const action = makeItem({ id: 'act_1', kind: 'action', title: '整理 onboarding 文案' });
    const project = makeItem({ id: 'prj_1', kind: 'project', title: '官网改版' });
    const ws = makeWorkspace([objective, kr1, action, project]);
    expect(resolveEditorObjective(ws, 'kr_1')).toBeNull();
    expect(resolveEditorObjective(ws, 'act_1')).toBeNull();
    expect(resolveEditorObjective(ws, 'prj_1')).toBeNull();
  });
});

describe('summarizeEditor', () => {
  it('counts KRs, done KRs and execution items', () => {
    const childDone = makeItem({
      id: 'act_child',
      kind: 'action',
      title: '访谈 5 位新用户',
      parentId: 'kr_1',
      status: 'done',
    });
    const childProject = makeItem({
      id: 'prj_child',
      kind: 'project',
      title: '新手引导改版',
      parentId: 'kr_2',
    });
    const linked = makeItem({ id: 'act_linked', kind: 'action', title: '投放落地页' });
    const ws = makeWorkspace(
      [objective, kr1, kr2, kr3, childDone, childProject, linked],
      [{ id: 'edge_1', from: 'kr_3', to: 'act_linked', type: 'okr', label: '' }],
    );

    expect(summarizeEditor(ws, 'obj_a')).toEqual({
      keyResults: 3,
      doneKeyResults: 1,
      executionItems: 3,
      doneExecutionItems: 1,
    });
  });

  it('returns zeros for an objective without KRs or execution items', () => {
    const empty = makeItem({ id: 'obj_empty', kind: 'objective', title: '空目标' });
    const ws = makeWorkspace([empty]);
    expect(summarizeEditor(ws, 'obj_empty')).toEqual({
      keyResults: 0,
      doneKeyResults: 0,
      executionItems: 0,
      doneExecutionItems: 0,
    });
  });

  it('returns zeros for a missing / non-objective id', () => {
    const ws = makeWorkspace([objective, kr1]);
    expect(summarizeEditor(ws, 'obj_missing')).toEqual({
      keyResults: 0,
      doneKeyResults: 0,
      executionItems: 0,
      doneExecutionItems: 0,
    });
    expect(summarizeEditor(ws, 'kr_1').keyResults).toBe(0);
  });

  it('counts partially completed key results', () => {
    const partial = makeItem({ id: 'obj_partial', kind: 'objective', title: '部分完成' });
    const doneKr = makeItem({
      id: 'kr_done',
      kind: 'keyresult',
      title: '已完成的 KR',
      parentId: 'obj_partial',
      status: 'done',
    });
    const openKr = makeItem({ id: 'kr_open', kind: 'keyresult', title: '进行中的 KR', parentId: 'obj_partial' });
    const doneItem = makeItem({
      id: 'act_done',
      kind: 'action',
      title: '已完成行动',
      parentId: 'kr_done',
      status: 'done',
    });
    const openItem = makeItem({
      id: 'act_open',
      kind: 'action',
      title: '进行中行动',
      parentId: 'kr_open',
    });
    const ws = makeWorkspace([partial, doneKr, openKr, doneItem, openItem]);

    expect(summarizeEditor(ws, 'obj_partial')).toEqual({
      keyResults: 2,
      doneKeyResults: 1,
      executionItems: 2,
      doneExecutionItems: 1,
    });
  });

  it('deduplicates an execution item reached via both an edge and a child path', () => {
    const shared = makeItem({
      id: 'act_shared',
      kind: 'action',
      title: '同一条行动',
      parentId: 'kr_1',
      status: 'done',
    });
    const ws = makeWorkspace(
      [objective, kr1, kr2, kr3, shared],
      [
        // 同一执行项同时经 kr_2 / kr_3 的 okr 边关联，且经 parentId 挂在 kr_1 下。
        { id: 'edge_2', from: 'kr_2', to: 'act_shared', type: 'okr', label: '' },
        { id: 'edge_3', from: 'kr_3', to: 'act_shared', type: 'okr', label: '' },
      ],
    );

    expect(summarizeEditor(ws, 'obj_a')).toEqual({
      keyResults: 3,
      doneKeyResults: 1,
      executionItems: 1,
      doneExecutionItems: 1,
    });
  });
});
