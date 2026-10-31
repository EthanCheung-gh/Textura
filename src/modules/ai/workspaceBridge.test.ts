import { describe, expect, it } from 'vitest';
import { WORKSPACE_VERSION } from '../../core/model';
import type {
  Edge,
  EdgeType,
  Item,
  ItemPatch,
  ItemStatus,
  NewItemInput,
  Workspace,
} from '../../core/model';
import { createWorkspaceBridge } from './workspaceBridge';
import type { WorkspaceAccess } from './workspaceBridge';

const ISO = '2026-01-01T00:00:00.000Z';

function createHarness() {
  let workspace: Workspace = {
    version: WORKSPACE_VERSION,
    items: [],
    edges: [],
    areas: [],
    runs: [],
    updatedAt: ISO,
  };
  let seq = 0;

  const access: WorkspaceAccess = {
    get workspace() {
      return workspace;
    },
    createItem(input: NewItemInput) {
      seq += 1;
      const status = input.status ?? 'next';
      const item: Item = {
        id: `item-${seq}`,
        kind: input.kind,
        title: input.title,
        notes: input.notes ?? '',
        parentId: input.parentId ?? null,
        order: seq,
        status,
        tags: input.tags ?? [],
        areaId: input.areaId ?? null,
        createdAt: ISO,
        updatedAt: ISO,
        completedAt: status === 'done' ? ISO : null,
      };
      workspace = { ...workspace, items: [...workspace.items, item] };
      return item;
    },
    updateItem(id: string, patch: ItemPatch) {
      workspace = {
        ...workspace,
        items: workspace.items.map((item) =>
          item.id === id
            ? {
                ...item,
                title: patch.title ?? item.title,
                notes: patch.notes ?? item.notes,
                status: patch.status ?? item.status,
                tags: patch.tags ?? item.tags,
                parentId: patch.parentId !== undefined ? patch.parentId : item.parentId,
                areaId: patch.areaId !== undefined ? patch.areaId : item.areaId,
                updatedAt: '2026-01-01T00:00:01.000Z',
              }
            : item,
        ),
      };
    },
    setStatus(id: string, status: ItemStatus) {
      workspace = {
        ...workspace,
        items: workspace.items.map((item) =>
          item.id === id
            ? {
                ...item,
                status,
                completedAt: status === 'done' ? '2026-01-01T00:00:02.000Z' : null,
                updatedAt: '2026-01-01T00:00:02.000Z',
              }
            : item,
        ),
      };
    },
    createEdge(input: { from: string; to: string; type: EdgeType; label?: string }) {
      const edge: Edge = {
        id: `edge-${workspace.edges.length + 1}`,
        from: input.from,
        to: input.to,
        type: input.type,
        label: input.label ?? '',
      };
      workspace = { ...workspace, edges: [...workspace.edges, edge] };
      return edge;
    },
  };

  return { access, read: () => workspace };
}

describe('createWorkspaceBridge', () => {
  it('新增事项后可列出并带上默认值', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);

    const created = bridge.createItem({
      kind: 'action',
      title: '整理会议纪要',
      notes: '把结论写清楚',
      tags: ['会议'],
    });

    expect(created).toMatchObject({
      id: 'item-1',
      kind: 'action',
      title: '整理会议纪要',
      notes: '把结论写清楚',
      status: 'next',
      parentId: null,
      tags: ['会议'],
    });
    expect(bridge.listItems()).toHaveLength(1);
  });

  it('按类型、状态、父级与上限过滤', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);

    bridge.createItem({ kind: 'objective', title: 'O1' });
    bridge.createItem({ kind: 'action', title: 'A1', status: 'done' });
    bridge.createItem({ kind: 'action', title: 'A2', parentId: 'item-1' });

    expect(bridge.listItems({ kind: 'action' }).map((item) => item.title)).toEqual(['A1', 'A2']);
    expect(bridge.listItems({ status: 'done' }).map((item) => item.title)).toEqual(['A1']);
    expect(bridge.listItems({ parentId: null }).map((item) => item.title)).toEqual(['O1', 'A1']);
    expect(bridge.listItems({ limit: 1 })).toHaveLength(1);
    expect(bridge.listItems({ limit: 9999 })).toHaveLength(3);
  });

  it('搜索标题、备注与标签', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);

    bridge.createItem({ kind: 'action', title: '写周报', notes: '包含复盘结论' });
    bridge.createItem({ kind: 'note', title: '随手记', tags: ['复盘'] });
    bridge.createItem({ kind: 'action', title: '打电话' });

    expect(bridge.searchItems('复盘').map((item) => item.title)).toEqual(['写周报', '随手记']);
    expect(bridge.searchItems('  ')).toEqual([]);
    expect(bridge.searchItems('电话', 1)).toHaveLength(1);
  });

  it('更新不存在的事项返回 null 且不写入', () => {
    const { access, read } = createHarness();
    const bridge = createWorkspaceBridge(() => access);
    expect(bridge.updateItem('missing', { title: 'x' })).toBeNull();
    expect(read().items).toHaveLength(0);
  });

  it('更新事项标题与状态', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);
    bridge.createItem({ kind: 'action', title: '旧标题' });

    const updated = bridge.updateItem('item-1', { title: '新标题', status: 'done', tags: ['已完成'] });
    expect(updated).toMatchObject({ title: '新标题', status: 'done', tags: ['已完成'] });
  });

  it('set_status 维护完成时间', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);
    bridge.createItem({ kind: 'action', title: '任务' });

    const done = bridge.setStatus('item-1', 'done');
    expect(done?.status).toBe('done');
    const reopened = bridge.setStatus('item-1', 'next');
    expect(reopened?.status).toBe('next');
    expect(bridge.setStatus('missing', 'done')).toBeNull();
    expect(() => bridge.setStatus('item-1', 'bogus')).toThrow(/未知的事项状态/);
  });

  it('拒绝未知的事项类型', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);
    expect(() => bridge.createItem({ kind: 'bogus', title: 'x' })).toThrow(/未知的事项类型/);
  });

  it('建立关联边，默认类型为 related', () => {
    const { access, read } = createHarness();
    const bridge = createWorkspaceBridge(() => access);

    const edge = bridge.createEdge({ from: 'a', to: 'b' });
    expect(edge).toEqual({ id: 'edge-1' });
    expect(read().edges[0]).toMatchObject({ from: 'a', to: 'b', type: 'related' });

    expect(() => bridge.createEdge({ from: 'a', to: 'b', type: 'bogus' })).toThrow(
      /未知的关联类型/,
    );
  });

  it('统计按类型与状态分布', () => {
    const { access } = createHarness();
    const bridge = createWorkspaceBridge(() => access);

    bridge.createItem({ kind: 'objective', title: 'O1' });
    bridge.createItem({ kind: 'action', title: 'A1', status: 'done' });
    bridge.createItem({ kind: 'action', title: 'A2' });

    expect(bridge.getStats()).toEqual({
      items: 3,
      byKind: { objective: 1, action: 2 },
      byStatus: { next: 2, done: 1 },
    });
  });
});