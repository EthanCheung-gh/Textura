import { describe, expect, it, vi } from 'vitest';
import type { Item, Workspace } from './model';
import { WORKSPACE_VERSION } from './model';
import { emptyWorkspace } from './repo';
import { createSeedWorkspace } from './fixtures';
import {
  childrenOf,
  getWorkspaceIndex,
  itemById,
  itemPathTitles,
  rollupProgress,
  scheduledItemsInRange,
} from './selectors';
import { getHistoryStats, useWorkspace } from './store';

function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value as Record<string, unknown>)) {
      deepFreeze(child);
    }
  }
  return value;
}

function makeItem(id: string, extra: Partial<Item> = {}): Item {
  const now = '2026-01-01T00:00:00.000Z';
  return {
    id,
    kind: 'action',
    title: id,
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: now,
    updatedAt: now,
    completedAt: null,
    ...extra,
  };
}

function smallWorkspace(): Workspace {
  return {
    ...emptyWorkspace(),
    items: [
      makeItem('a', { title: 'A' }),
      makeItem('b', { title: 'B', order: 1 }),
    ],
  };
}

describe('workspace immutability invariant', () => {
  it('never mutates a deeply frozen workspace across all store actions', () => {
    vi.useFakeTimers();
    try {
      const seed = deepFreeze(createSeedWorkspace());
    const before = JSON.stringify(seed);
    useWorkspace.setState({
      workspace: seed,
      status: 'ready',
      selectedId: null,
      notices: [],
    });
    const store = useWorkspace.getState();

    expect(() => {
      store.updateItem('kr_nps', { title: 'NPS（更新）' });
      store.updateItems([
        { id: 'kr_wau', patch: { okr: { confidence: 7 } } },
        { id: 'kr_conversion', patch: { notes: '批量更新' } },
      ]);
      const created = store.createItem({ kind: 'action', title: '临时条目' });
      store.moveItem('step_welcome', 'step_collect');
      store.toggleDone('kr_nps');
      store.setStatus('kr_nps', 'active');
      const edge = store.createEdge({
        from: 'obj_activation',
        to: 'proj_website',
        type: 'related',
      });
      store.updateEdge(edge.id, { label: '临时边' });
      store.deleteEdge(edge.id);
      const area = store.createArea('测试领域');
      store.updateArea(area.id, { color: '#123456' });
      store.deleteArea('area_personal');
      store.logRun({
        sopId: 'sop_onboarding',
        stepId: 'step_welcome',
        result: 'pass',
      });
      store.deleteItems([created.id]);
      store.undo();
      store.redo();
    }).not.toThrow();

      expect(JSON.stringify(seed)).toBe(before);
      expect(getHistoryStats().limit).toBe(80);
      expect(getHistoryStats().steps).toBeGreaterThan(0);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('structural sharing', () => {
  it('keeps untouched item references and restores the same reference on undo', () => {
    const workspace = smallWorkspace();
    const a = workspace.items.find((item) => item.id === 'a')!;
    const b = workspace.items.find((item) => item.id === 'b')!;
    useWorkspace.setState({
      workspace,
      status: 'loading',
      selectedId: null,
      notices: [],
    });
    const store = useWorkspace.getState();

    store.updateItem('a', { title: 'A2' });
    const updated = useWorkspace.getState().workspace;
    expect(updated.items.find((item) => item.id === 'a')).not.toBe(a);
    expect(updated.items.find((item) => item.id === 'b')).toBe(b);

    store.undo();
    const restored = useWorkspace.getState().workspace;
    expect(restored.items.find((item) => item.id === 'a')).toBe(a);
    expect(restored.items.find((item) => item.id === 'b')).toBe(b);
  });
});

function dayKey(offset: number): string {
  return new Date(Date.UTC(2026, 0, 1 + offset)).toISOString().slice(0, 10);
}

function largeWorkspace(count = 10_000): Workspace {
  const now = '2026-01-01T00:00:00.000Z';
  const items: Item[] = [];
  for (let index = 0; index < count; index += 1) {
    const id = `i${index}`;
    const kind =
      index % 17 === 0 ? 'project' : index % 11 === 0 ? 'keyresult' : 'action';
    items.push(
      makeItem(id, {
        kind,
        title: `条目 ${index}`,
        parentId: index < 100 ? null : `i${index % 100}`,
        order: index,
        status: index % 9 === 0 ? 'inbox' : index % 7 === 0 ? 'waiting' : 'next',
        createdAt: now,
        gantt:
          index < 5_000
            ? { start: dayKey(index % 365), end: dayKey((index % 365) + 3), progress: index % 101 }
            : undefined,
      }),
    );
  }
  const edges = Array.from({ length: 1_000 }, (_, index) => ({
    id: `e${index}`,
    from: `i${index}`,
    to: `i${index + 1}`,
    type: 'related' as const,
    label: '',
  }));
  return {
    version: WORKSPACE_VERSION,
    items,
    edges,
    areas: [],
    runs: [],
    updatedAt: now,
  };
}

describe('10k scale benchmark', () => {
  it('keeps index-backed selectors and write paths within broad budgets', () => {
    const ws = largeWorkspace();
    const buildStart = performance.now();
    const firstIndex = getWorkspaceIndex(ws);
    const indexBuildMs = performance.now() - buildStart;
    expect(getWorkspaceIndex(ws)).toBe(firstIndex);
    expect(Object.isFrozen(childrenOf(ws, 'i0'))).toBe(true);
    expect(Object.isFrozen(itemPathTitles(ws, 'i9000'))).toBe(true);

    const timings: Record<string, number> = { indexBuild: indexBuildMs };
    const measure = (name: string, fn: () => void) => {
      const start = performance.now();
      fn();
      timings[name] = performance.now() - start;
    };

    measure('childrenOf', () => {
      for (let index = 0; index < 2_000; index += 1) childrenOf(ws, 'i0');
    });
    measure('itemById', () => {
      for (let index = 0; index < 20_000; index += 1) itemById(ws, `i${index % 10_000}`);
    });
    measure('rollupProgress', () => {
      for (let index = 0; index < 1_000; index += 1) rollupProgress(ws, `i${index}`);
    });
    measure('itemPathTitles', () => {
      for (let index = 0; index < 1_000; index += 1) itemPathTitles(ws, `i${index + 5_000}`);
    });
    measure('scheduledItemsInRange', () => {
      for (let index = 0; index < 200; index += 1) {
        scheduledItemsInRange(ws, dayKey(index), dayKey(index + 5));
      }
    });

    useWorkspace.setState({
      workspace: ws,
      status: 'loading',
      selectedId: null,
      notices: [],
    });
    const store = useWorkspace.getState();
    const unaffected = ws.items.find((item) => item.id === 'i9001')!;
    const affected = ws.items.find((item) => item.id === 'i9000')!;

    measure('updateItem', () => {
      for (let index = 0; index < 30; index += 1) {
        store.updateItem('i9000', { title: `更新 ${index}` });
      }
    });
    const afterWrite = useWorkspace.getState().workspace;
    expect(afterWrite.items.find((item) => item.id === 'i9001')).toBe(unaffected);
    expect(afterWrite.items.find((item) => item.id === 'i9000')).not.toBe(affected);

    const patches = Array.from({ length: 1_000 }, (_, index) => ({
      id: `i${index}`,
      patch: { notes: `patch ${index}` },
    }));
    measure('updateItems', () => {
      store.updateItems(patches, { recordHistory: true });
    });

    console.info('[perf:10k]', timings);
    expect(timings.childrenOf, JSON.stringify(timings)).toBeLessThan(150);
    expect(timings.itemById, JSON.stringify(timings)).toBeLessThan(30);
    expect(timings.rollupProgress, JSON.stringify(timings)).toBeLessThan(200);
    expect(timings.itemPathTitles, JSON.stringify(timings)).toBeLessThan(250);
    expect(timings.scheduledItemsInRange, JSON.stringify(timings)).toBeLessThan(200);
    expect(timings.updateItem, JSON.stringify(timings)).toBeLessThan(400);
    expect(timings.updateItems, JSON.stringify(timings)).toBeLessThan(150);
  });
});
