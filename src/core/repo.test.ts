import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  LOCAL_STORAGE_KEY,
  WorkspaceVersionError,
  emptyWorkspace,
  loadWorkspace,
  migrateWorkspace,
  migrateWorkspaceWithReport,
  parseWorkspaceText,
} from './repo';
import type { Workspace } from './model';
import { WORKSPACE_VERSION } from './model';
import { descendantsOf } from './selectors';

const NOW = '2026-01-01T00:00:00.000Z';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function stubStorage(value: string | null): void {
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => (key === LOCAL_STORAGE_KEY ? value : null),
    setItem: () => undefined,
    removeItem: () => undefined,
    clear: () => undefined,
  });
}

function baseWorkspace(overrides: Partial<Workspace> = {}): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items: [],
    edges: [],
    areas: [],
    runs: [],
    updatedAt: NOW,
    ...overrides,
  };
}

describe('migrateWorkspace normalization', () => {
  it('forces finite numbers, clamps domains, and replaces invalid enums', () => {
    const workspace = migrateWorkspace({
      version: 0,
      items: [
        {
          id: 'a',
          kind: 'garbage',
          title: 123,
          parentId: 42,
          order: '2',
          status: 'garbage',
          tags: ['x', 5, ''],
          areaId: 7,
          createdAt: 9,
          updatedAt: null,
          completedAt: 5,
          okr: {
            period: 5,
            confidence: 999,
            metric: { start: 'a', target: '20', current: Infinity, unit: 3 },
          },
          sop: {
            nodeType: 'bogus',
            canvas: { x: '1', y: null },
            checklist: [{ id: 1, text: 2, done: 'true' }],
            durationMin: -5,
          },
          gtd: {
            capturedAt: 7,
            clarified: 'yes',
            context: 5,
            energy: 'ultra',
            waitingFor: 3,
            twoMinuteCandidate: 'no',
          },
          gantt: { start: 3, end: '', progress: 'half' },
        },
      ],
      edges: [{ id: 1, from: 2, to: 3, type: 'bogus', label: 4 }],
      areas: [{ id: 1, name: 2, color: 3, order: '5' }],
      runs: [{ id: 1, sopId: 2, stepId: 3, at: 4, result: 'bogus', note: 5 }],
      updatedAt: [],
    });

    expect(workspace.version).toBe(WORKSPACE_VERSION);
    const item = workspace.items[0];
    expect(item.kind).toBe('note');
    expect(item.status).toBe('next');
    expect(item.title).toBe('未命名条目');
    expect(item.notes).toBe('');
    expect(item.parentId).toBeNull();
    expect(item.order).toBe(2);
    expect(item.tags).toEqual(['x']);
    expect(item.areaId).toBeNull();
    expect(item.completedAt).toBeNull();
    expect(Number.isNaN(Date.parse(item.createdAt))).toBe(false);
    expect(Number.isNaN(Date.parse(item.updatedAt))).toBe(false);

    expect(item.okr?.confidence).toBe(10);
    expect(item.okr?.period).toMatch(/^\d{4}-Q[1-4]$/);
    expect(item.okr?.metric).toEqual({ start: 0, target: 20, current: 0, unit: '' });
    expect(item.sop?.nodeType).toBe('action');
    expect(item.sop?.canvas).toEqual({ x: 1, y: 0 });
    expect(item.sop?.checklist[0]).toMatchObject({ text: '', done: false });
    expect(item.sop?.durationMin).toBe(0);
    expect(item.gtd?.clarified).toBe(false);
    expect(item.gtd?.energy).toBeUndefined();
    expect(item.gtd?.context).toBeUndefined();
    expect(item.gtd).not.toHaveProperty('twoMinuteCandidate');
    expect(item.gantt).toEqual({ start: null, end: null, progress: 0 });

    expect(workspace.edges[0].type).toBe('related');
    expect(typeof workspace.edges[0].from).toBe('string');
    expect(workspace.areas[0].order).toBe(5);
    expect(workspace.runs[0].result).toBe('skip');
    expect(Number.isNaN(Date.parse(workspace.runs[0].at))).toBe(false);
  });

  it('fills defaults for missing item fields', () => {
    const workspace = migrateWorkspace(baseWorkspace({ items: [{ id: 'b' }] as Workspace['items'] }));
    const item = workspace.items[0];
    expect(item.kind).toBe('note');
    expect(item.status).toBe('next');
    expect(item.notes).toBe('');
    expect(item.tags).toEqual([]);
    expect(item.areaId).toBeNull();
    expect(item.createdAt).toBeTruthy();
    expect(item.updatedAt).toBeTruthy();
    expect(item.completedAt).toBeNull();
  });

  it('throws a readable error when the parent graph has a cycle', () => {
    const cycle = baseWorkspace({
      items: [
        { id: 'a', kind: 'action', title: 'A', parentId: 'b' },
        { id: 'b', kind: 'action', title: 'B', parentId: 'a' },
      ] as Workspace['items'],
    });
    expect(() => migrateWorkspace(cycle)).toThrow(/父子环：A → B → A/);
    expect(() => parseWorkspaceText(JSON.stringify(cycle))).toThrow(/父子环：A → B → A，请修复后重试/);

    const self = baseWorkspace({
      items: [{ id: 'a', kind: 'action', title: 'A', parentId: 'a' }] as Workspace['items'],
    });
    expect(() => migrateWorkspace(self)).toThrow(/父子环：A → A/);
  });

  it('rejects future versions before normalizing', () => {
    expect(() => migrateWorkspace({ ...baseWorkspace(), version: 999 })).toThrow(
      /工作区版本 999 高于当前应用支持/,
    );
  });
});

describe('loadWorkspace parent-cycle repair', () => {
  it('cuts one parentId per cycle, reports it, and keeps the workspace usable', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    stubStorage(
      JSON.stringify({
        version: WORKSPACE_VERSION,
        items: [
          { id: 'a', kind: 'action', title: 'A', parentId: 'b' },
          { id: 'b', kind: 'action', title: 'B', parentId: 'a' },
          { id: 'c', kind: 'action', title: 'C', parentId: 'b' },
        ],
        edges: [],
        areas: [],
        runs: [],
        updatedAt: NOW,
      }),
    );

    const result = await loadWorkspace();
    expect(result.freshInstall).toBe(false);
    expect(result.parentCycles).toHaveLength(1);
    expect(result.parentCycles[0]).toEqual(['a', 'b', 'a']);
    const byId = new Map(result.workspace.items.map((item) => [item.id, item]));
    expect(byId.get('a')?.parentId).toBe('b');
    expect(byId.get('b')?.parentId).toBeNull();
    expect(() => descendantsOf(result.workspace, 'a')).not.toThrow();
    expect(warn).toHaveBeenCalled();
    expect(JSON.stringify(warn.mock.calls)).not.toContain('originalWorkspace');
    expect(JSON.stringify(warn.mock.calls)).toContain('detectedAt');
  });

  it('reports freshInstall only when the localStorage key is absent', async () => {
    stubStorage(null);
    const absent = await loadWorkspace();
    expect(absent.freshInstall).toBe(true);
    expect(absent.workspace.items).toHaveLength(0);

    stubStorage(JSON.stringify(emptyWorkspace()));
    const existing = await loadWorkspace();
    expect(existing.freshInstall).toBe(false);
    expect(existing.workspace.items).toHaveLength(0);
  });

  it('propagates future-version errors instead of silently clearing the workspace', async () => {
    stubStorage(JSON.stringify({ ...emptyWorkspace(), version: 99 }));
    await expect(loadWorkspace()).rejects.toBeInstanceOf(WorkspaceVersionError);
  });
});

describe('normalization correction summary (N8)', () => {
  it('reports clamped values with item id and field, capped at 20', () => {
    const items = Array.from({ length: 25 }, (_, index) => ({
      id: `i${index}`,
      kind: 'keyresult',
      title: `KR ${index}`,
      okr: { period: '2026-Q1', confidence: 200 },
      gantt: { progress: 150 },
    }));
    const { workspace, corrections } = migrateWorkspaceWithReport(
      baseWorkspace({ items: items as Workspace['items'] }),
    );

    expect(workspace.items[0].okr?.confidence).toBe(10);
    expect(workspace.items[0].gantt?.progress).toBe(100);
    expect(corrections.total).toBe(50);
    expect(corrections.entries).toHaveLength(20);
    expect(corrections.entries[0]).toMatchObject({
      itemId: 'i0',
      field: 'okr.confidence',
      from: 200,
      to: 10,
    });
    expect(corrections.entries[1]).toMatchObject({
      itemId: 'i0',
      field: 'gantt.progress',
      from: 150,
      to: 100,
    });
    expect(corrections.total).toBeGreaterThan(corrections.entries.length);
  });
});
