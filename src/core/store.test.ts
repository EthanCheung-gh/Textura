import { afterEach, describe, expect, it, vi } from 'vitest';
import { useWorkspace } from './store';
import { emptyWorkspace } from './repo';
import { createSeedWorkspace } from './fixtures';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('store undo/redo', () => {
  it('restores the workspace before a mutation and reapplies it on redo', () => {
    const store = useWorkspace;
    store.setState({
      workspace: { ...emptyWorkspace(), items: [] },
      status: 'ready',
      selectedId: null,
    });

    const created = store.getState().createItem({ kind: 'action', title: '撤销测试' });
    expect(store.getState().workspace.items).toHaveLength(1);
    expect(store.getState().canUndo()).toBe(true);

    store.getState().undo();
    expect(store.getState().workspace.items).toHaveLength(0);
    expect(store.getState().canRedo()).toBe(true);

    store.getState().redo();
    expect(store.getState().workspace.items.map((item) => item.id)).toEqual([created.id]);
  });

  it('fills kind defaults and stamps completedAt when moving to done', () => {
    const store = useWorkspace;
    store.setState({ workspace: { ...emptyWorkspace(), items: [] }, status: 'ready' });

    const objective = store.getState().createItem({ kind: 'objective', title: '默认目标' });
    expect(objective.okr).toMatchObject({ confidence: 5 });
    expect(objective.okr?.period).toMatch(/^\d{4}-Q[1-4]$/);

    const step = store.getState().createItem({ kind: 'step', title: '步骤' });
    expect(step.sop).toMatchObject({ nodeType: 'action', canvas: { x: 0, y: 0 }, checklist: [] });

    const action = store.getState().createItem({ kind: 'action', title: '动作' });
    expect(action.gantt?.progress).toBe(0);
    expect(action.status).toBe('next');

    store.getState().updateItem(action.id, { status: 'done' });
    const done = store.getState().workspace.items.find((item) => item.id === action.id);
    expect(done?.status).toBe('done');
    expect(done?.completedAt).toBeTruthy();
  });
});

describe('store deep link load', () => {
  it('prefers the URL route over route memory and selects an existing item', async () => {
    const seeded = createSeedWorkspace();
    const storage = new Map<string, string>([
      ['textura.workspace.v1', JSON.stringify(seeded)],
      ['textura.route', 'gtd'],
    ]);
    const dataset: Record<string, string> = {};
    const replaceState = vi.fn();

    vi.stubGlobal('window', {
      location: {
        search: '?route=okr&item=obj_activation',
        pathname: '/',
        hash: '',
        state: null,
      },
      history: { state: null, replaceState },
    });
    vi.stubGlobal('document', { documentElement: { dataset } });
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => {
        storage.set(key, value);
      },
      removeItem: (key: string) => {
        storage.delete(key);
      },
      clear: () => {
        storage.clear();
      },
    });

    await useWorkspace.getState().load();

    expect(useWorkspace.getState().status).toBe('ready');
    expect(useWorkspace.getState().ui.route).toBe('okr');
    expect(useWorkspace.getState().selectedId).toBe('obj_activation');
    expect(dataset.route).toBe('okr');
    expect(storage.get('textura.route')).toBe('okr');
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?route=okr&item=obj_activation');
  });
});
