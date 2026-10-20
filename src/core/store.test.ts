import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item, Workspace } from './model';
import { WORKSPACE_VERSION } from './model';
import { useWorkspace } from './store';
import { emptyWorkspace, parseWorkspaceText } from './repo';
import { createSeedWorkspace } from './fixtures';

const NOW = '2026-01-01T00:00:00.000Z';

const saveWorkspaceMock = vi.hoisted(() => vi.fn());
const loadWorkspaceMock = vi.hoisted(() => vi.fn());

vi.mock('./repo', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./repo')>();
  return { ...actual, saveWorkspace: saveWorkspaceMock, loadWorkspace: loadWorkspaceMock };
});

beforeEach(() => {
  saveWorkspaceMock.mockReset();
  saveWorkspaceMock.mockResolvedValue({ savedAt: new Date().toISOString(), bytes: 1 });
  loadWorkspaceMock.mockReset();
  loadWorkspaceMock.mockResolvedValue({
    workspace: emptyWorkspace(),
    freshInstall: false,
    parentCycles: [],
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

function makeItem(id: string, extra: Partial<Item> = {}): Item {
  const createdAt = '2000-01-01T00:00:00.000Z';
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
    createdAt,
    updatedAt: createdAt,
    completedAt: null,
    ...extra,
  };
}

function makeWorkspace(marker: string, version = WORKSPACE_VERSION): Workspace {
  return {
    version,
    items: [
      makeItem(`item_${marker}`, { title: marker }),
      makeItem(`obj_${marker}`, {
        kind: 'objective',
        title: `目标 ${marker}`,
        order: 1,
        okr: { period: '2030-Q2', confidence: 5 },
      }),
    ],
    edges: [],
    areas: [
      { id: `area_${marker}`, name: `领域 ${marker}`, color: '#C0663A', order: 0 },
    ],
    runs: [],
    updatedAt: '2000-01-01T00:00:00.000Z',
  };
}

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

    loadWorkspaceMock.mockResolvedValue({
      workspace: seeded,
      freshInstall: false,
      parentCycles: [],
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

describe('store replaceWorkspace', () => {
  it('migrates, replaces content, resets selection and okr period, and awaits a real save', async () => {
    useWorkspace.setState({
      workspace: makeWorkspace('old'),
      status: 'ready',
      selectedId: 'item_old',
      saveState: 'idle',
      notices: [],
    });

    const next = makeWorkspace('new', 0);
    await useWorkspace.getState().replaceWorkspace(next);

    const state = useWorkspace.getState();
    expect(state.workspace.items.map((item) => item.id)).toEqual(['item_new', 'obj_new']);
    expect(state.workspace.areas.map((area) => area.id)).toEqual(['area_new']);
    expect(state.workspace.version).toBe(WORKSPACE_VERSION);
    expect(state.workspace.updatedAt).not.toBe(next.updatedAt);
    expect(state.selectedId).toBeNull();
    expect(state.ui.okrPeriod).toBe('2030-Q2');
    expect(state.saveState).toBe('saved');
    expect(saveWorkspaceMock).toHaveBeenCalledTimes(1);

    const persisted = saveWorkspaceMock.mock.calls[0][0] as Workspace;
    expect(persisted.version).toBe(WORKSPACE_VERSION);
    expect(persisted.items.map((item) => item.id)).toEqual(['item_new', 'obj_new']);
    expect(persisted.updatedAt).toBe(state.workspace.updatedAt);
  });

  it('records one history snapshot by default so undo restores the previous workspace', async () => {
    useWorkspace.setState({
      workspace: makeWorkspace('before'),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    await useWorkspace.getState().replaceWorkspace(makeWorkspace('after'));
    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_after');
    expect(useWorkspace.getState().canUndo()).toBe(true);

    useWorkspace.getState().undo();
    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_before');
  });

  it('does not add an undo entry when recordHistory is false', async () => {
    useWorkspace.setState({
      workspace: makeWorkspace('base'),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    await useWorkspace.getState().replaceWorkspace(makeWorkspace('previous'), {
      recordHistory: true,
    });
    // 此时历史栈顶部是 base。
    await useWorkspace.getState().replaceWorkspace(makeWorkspace('imported'), {
      recordHistory: false,
    });

    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_imported');
    useWorkspace.getState().undo();
    // 若 false 也记录快照，这里会回到 previous；实际应回到更早的 base。
    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_base');
  });

  it('notifies, sets saveState to error, and rejects when saving fails', async () => {
    saveWorkspaceMock.mockRejectedValueOnce(new Error('磁盘已满'));
    useWorkspace.setState({
      workspace: makeWorkspace('before'),
      status: 'ready',
      selectedId: 'item_before',
      saveState: 'idle',
      notices: [],
      error: null,
    });

    await expect(
      useWorkspace.getState().replaceWorkspace(makeWorkspace('failed')),
    ).rejects.toThrow('磁盘已满');

    const state = useWorkspace.getState();
    expect(state.workspace.items[0]?.id).toBe('item_failed');
    expect(state.saveState).toBe('error');
    expect(state.error).toContain('磁盘已满');
    expect(state.notices.at(-1)).toMatchObject({
      tone: 'error',
      message: expect.stringContaining('保存失败'),
    });
  });
});

describe('store fresh install / load safety', () => {
  it('does not seed a blank workspace when freshInstall is false', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
    });
    saveWorkspaceMock.mockClear();

    await useWorkspace.getState().load();

    expect(useWorkspace.getState().status).toBe('ready');
    expect(useWorkspace.getState().workspace.items).toHaveLength(0);
    expect(saveWorkspaceMock).not.toHaveBeenCalled();
  });

  it('seeds the demo workspace only on a true fresh install', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: true,
      parentCycles: [],
    });
    saveWorkspaceMock.mockClear();

    await useWorkspace.getState().load();

    expect(useWorkspace.getState().status).toBe('ready');
    expect(useWorkspace.getState().workspace.items.length).toBeGreaterThan(20);
    expect(saveWorkspaceMock).toHaveBeenCalledTimes(1);
  });

  it('reload() also waits for an in-flight save before loading', async () => {
    useWorkspace.setState({
      workspace: makeWorkspace('edited'),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    let resolveSave: ((value: { savedAt: string; bytes: number }) => void) | undefined;
    saveWorkspaceMock.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveSave = resolve;
        }),
    );
    const savePromise = useWorkspace.getState().save();
    await new Promise((resolve) => setTimeout(resolve, 0));

    loadWorkspaceMock.mockResolvedValue({
      workspace: makeWorkspace('reloaded'),
      freshInstall: false,
      parentCycles: [],
      corrections: { total: 0, entries: [] },
    });
    const reloadPromise = useWorkspace.getState().reload();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(loadWorkspaceMock).not.toHaveBeenCalled();

    resolveSave?.({ savedAt: new Date().toISOString(), bytes: 1 });
    await savePromise;
    await reloadPromise;
    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_reloaded');
  });

  it('notifies one correction summary when load normalization fixed data', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
      corrections: {
        total: 2,
        entries: [
          { itemId: 'a', field: 'okr.confidence', from: 200, to: 10 },
          { itemId: 'a', field: 'gantt.progress', from: 150, to: 100 },
        ],
      },
    });

    await useWorkspace.getState().load();

    expect(
      useWorkspace.getState().notices.filter((notice) => notice.message.includes('已修正 2 处')),
    ).toHaveLength(1);
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });

  it('notifies when load repaired parent cycles', async () => {
    const repairedPreview = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: () => null,
      setItem: (key: string, value: string) => {
        repairedPreview.set(key, value);
      },
      removeItem: () => undefined,
      clear: () => undefined,
    });
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [['a', 'b', 'a']],
    });

    await useWorkspace.getState().load();

    expect(useWorkspace.getState().notices.at(-1)).toMatchObject({
      tone: 'error',
      message: expect.stringContaining('父子环'),
    });
    expect(useWorkspace.getState().notices.at(-1)?.message).toContain('下次编辑会写回');
    expect(repairedPreview.size).toBe(1);
  });

  it('renders a readable version error and refuses to auto-save', async () => {
    loadWorkspaceMock.mockRejectedValue(
      new Error('工作区版本 99 高于当前应用支持的版本 1，请升级 Textura 后再打开。'),
    );
    saveWorkspaceMock.mockClear();

    await useWorkspace.getState().load();
    expect(useWorkspace.getState().status).toBe('error');
    expect(useWorkspace.getState().error).toContain('工作区版本 99');

    await useWorkspace.getState().save();
    expect(saveWorkspaceMock).not.toHaveBeenCalled();
  });
});

describe('store structural mutations', () => {
  it('cascades deleteItems through descendants, edges, runs and selectedId', () => {
    const workspace: Workspace = {
      ...emptyWorkspace(),
      items: [
        makeItem('parent'),
        makeItem('child', { parentId: 'parent', order: 0 }),
        makeItem('grand', { parentId: 'child', order: 0 }),
        makeItem('other'),
      ],
      edges: [
        { id: 'e1', from: 'parent', to: 'other', type: 'related', label: '' },
        { id: 'e2', from: 'child', to: 'other', type: 'related', label: '' },
      ],
      runs: [
        { id: 'r1', sopId: 'parent', stepId: 'grand', at: NOW, result: 'pass', note: '' },
      ],
    };
    useWorkspace.setState({
      workspace,
      status: 'ready',
      selectedId: 'grand',
      notices: [],
    });

    useWorkspace.getState().deleteItems(['parent']);

    const state = useWorkspace.getState();
    expect(state.workspace.items.map((item) => item.id)).toEqual(['other']);
    expect(state.workspace.edges).toEqual([]);
    expect(state.workspace.runs).toEqual([]);
    expect(state.selectedId).toBeNull();
  });

  it('rejects moving an item into itself or its descendants', () => {
    const workspace: Workspace = {
      ...emptyWorkspace(),
      items: [
        makeItem('parent'),
        makeItem('child', { parentId: 'parent' }),
        makeItem('grand', { parentId: 'child' }),
      ],
    };
    useWorkspace.setState({ workspace, status: 'ready', selectedId: null });

    useWorkspace.getState().moveItem('parent', 'grand');
    useWorkspace.getState().moveItem('child', 'child');

    const parent = useWorkspace.getState().workspace.items.find((item) => item.id === 'parent');
    const child = useWorkspace.getState().workspace.items.find((item) => item.id === 'child');
    expect(parent?.parentId).toBeNull();
    expect(child?.parentId).toBe('parent');
  });

  it('deduplicates createEdge without adding another history step', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
    });
    await useWorkspace.getState().load();

    const first = useWorkspace.getState().createEdge({
      from: 'a',
      to: 'b',
      type: 'related',
    });
    const second = useWorkspace.getState().createEdge({
      from: 'a',
      to: 'b',
      type: 'related',
    });
    expect(second.id).toBe(first.id);
    expect(useWorkspace.getState().workspace.edges).toHaveLength(1);

    useWorkspace.getState().undo();
    expect(useWorkspace.getState().workspace.edges).toHaveLength(0);
  });

  it('nulls item.areaId when deleting an area', () => {
    useWorkspace.setState({
      workspace: {
        ...emptyWorkspace(),
        items: [makeItem('a', { areaId: 'area_1' }), makeItem('b')],
        areas: [{ id: 'area_1', name: '领域', color: '#C0663A', order: 0 }],
      },
      status: 'ready',
    });

    useWorkspace.getState().deleteArea('area_1');

    const state = useWorkspace.getState();
    expect(state.workspace.areas).toEqual([]);
    expect(state.workspace.items.find((item) => item.id === 'a')?.areaId).toBeNull();
    expect(state.workspace.items.find((item) => item.id === 'b')?.areaId).toBeNull();
  });
});

describe('store updateItems batching', () => {
  it('records one snapshot for the whole batch (1 vs N)', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
    });
    await useWorkspace.getState().load();
    useWorkspace.setState({
      workspace: {
        ...emptyWorkspace(),
        items: [makeItem('a'), makeItem('b', { order: 1 })],
      },
      status: 'ready',
    });

    useWorkspace.getState().updateItems([
      { id: 'a', patch: { title: 'A2' } },
      { id: 'b', patch: { title: 'B2' } },
    ]);

    let state = useWorkspace.getState();
    expect(state.workspace.items.map((item) => item.title)).toEqual(['A2', 'B2']);
    expect(state.workspace.items[0].updatedAt).toBe(state.workspace.updatedAt);
    expect(state.workspace.items[1].updatedAt).toBe(state.workspace.updatedAt);

    state.undo();
    state = useWorkspace.getState();
    expect(state.workspace.items.map((item) => item.title)).toEqual(['a', 'b']);
  });

  it('takes N undo steps when updateItem is called N times', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
    });
    await useWorkspace.getState().load();
    useWorkspace.setState({
      workspace: {
        ...emptyWorkspace(),
        items: [makeItem('a'), makeItem('b', { order: 1 })],
      },
      status: 'ready',
    });

    useWorkspace.getState().updateItem('a', { title: 'A2' });
    useWorkspace.getState().updateItem('b', { title: 'B2' });

    useWorkspace.getState().undo();
    let state = useWorkspace.getState();
    expect(state.workspace.items.map((item) => item.title)).toEqual(['A2', 'b']);
    state.undo();
    expect(useWorkspace.getState().workspace.items.map((item) => item.title)).toEqual(['a', 'b']);
  });

  it('debounces a single save for the whole batch', async () => {
    loadWorkspaceMock.mockResolvedValue({
      workspace: emptyWorkspace(),
      freshInstall: false,
      parentCycles: [],
    });
    await useWorkspace.getState().load();
    useWorkspace.setState({
      workspace: {
        ...emptyWorkspace(),
        items: [makeItem('a'), makeItem('b', { order: 1 })],
      },
      status: 'ready',
    });
    saveWorkspaceMock.mockClear();

    useWorkspace.getState().updateItems([
      { id: 'a', patch: { title: 'A2' } },
      { id: 'b', patch: { title: 'B2' } },
    ]);
    expect(saveWorkspaceMock).not.toHaveBeenCalled();

    await new Promise((resolve) => setTimeout(resolve, 450));
    expect(saveWorkspaceMock).toHaveBeenCalledTimes(1);
  });

  it('ignores empty batches and missing ids', () => {
    useWorkspace.setState({
      workspace: { ...emptyWorkspace(), items: [makeItem('a')] },
      status: 'ready',
    });
    const before = useWorkspace.getState().workspace.updatedAt;

    useWorkspace.getState().updateItems([]);
    useWorkspace.getState().updateItems([{ id: 'missing', patch: { title: 'x' } }]);

    expect(useWorkspace.getState().workspace.updatedAt).toBe(before);
    expect(useWorkspace.getState().workspace.items[0].title).toBe('a');
  });
});

describe('store save queue and correction notices', () => {
  it('waits for an in-flight save before load() proceeds', async () => {
    useWorkspace.setState({
      workspace: makeWorkspace('old'),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    let resolveSave: ((value: { savedAt: string; bytes: number }) => void) | undefined;
    saveWorkspaceMock.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveSave = resolve;
        }),
    );

    const savePromise = useWorkspace.getState().save();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(saveWorkspaceMock).toHaveBeenCalledTimes(1);

    loadWorkspaceMock.mockResolvedValue({
      workspace: makeWorkspace('loaded'),
      freshInstall: false,
      parentCycles: [],
      corrections: { total: 0, entries: [] },
    });
    const loadPromise = useWorkspace.getState().load();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(loadWorkspaceMock).not.toHaveBeenCalled();
    expect(useWorkspace.getState().ui.route).not.toBe('__never__');

    resolveSave?.({ savedAt: new Date().toISOString(), bytes: 1 });
    await savePromise;
    await loadPromise;

    expect(loadWorkspaceMock).toHaveBeenCalledTimes(1);
    expect(useWorkspace.getState().workspace.items[0]?.id).toBe('item_loaded');
  });

  it('notifies one correction summary and does not spam console', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const invalid: Workspace = {
      ...emptyWorkspace(),
      items: [
        makeItem('bad', {
          kind: 'keyresult',
          okr: { period: '2026-Q1', confidence: 200 },
          gantt: { start: null, end: null, progress: 150 },
        }),
      ],
    };
    useWorkspace.setState({
      workspace: emptyWorkspace(),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    await useWorkspace.getState().replaceWorkspace(invalid);

    const state = useWorkspace.getState();
    expect(state.workspace.items[0].okr?.confidence).toBe(10);
    expect(state.workspace.items[0].gantt?.progress).toBe(100);
    expect(state.notices.filter((notice) => notice.message.includes('已修正'))).toHaveLength(1);
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });
});

describe('store import normalization report', () => {
  it('reports corrections once when appshell pre-parsed the file', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const text = JSON.stringify({
      version: 1,
      items: [
        {
          id: 'bad-kr',
          kind: 'keyresult',
          title: 'KR',
          okr: { period: '2026-Q1', confidence: 200 },
          gantt: { progress: 150 },
        },
      ],
      edges: [],
      areas: [],
      runs: [],
      updatedAt: '2026-01-01T00:00:00.000Z',
    });
    const prepared = parseWorkspaceText(text);
    useWorkspace.setState({
      workspace: emptyWorkspace(),
      status: 'ready',
      selectedId: null,
      notices: [],
    });

    await useWorkspace.getState().replaceWorkspace(prepared);

    const state = useWorkspace.getState();
    expect(state.workspace.items[0].okr?.confidence).toBe(10);
    expect(state.workspace.items[0].gantt?.progress).toBe(100);
    expect(state.notices.filter((notice) => notice.message.includes('已修正'))).toHaveLength(1);
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });
});
