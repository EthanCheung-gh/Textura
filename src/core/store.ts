/**
 * 唯一的全局 store。所有写操作：
 *   1) 先向历史栈推入快照（最多 80 步）
 *   2) 以不可变方式更新 workspace
 *   3) 400ms 防抖自动保存
 */
import { create } from 'zustand';
import type {
  Area,
  Edge,
  Item,
  ItemPatch,
  ItemStatus,
  NewItemInput,
  SopRunEntry,
  Workspace,
} from './model';
import { WORKSPACE_VERSION } from './model';
import { createHistory } from './history';
import { createDebouncer, areaPalette, cloneWorkspace, currentQuarter, nowIso, uid } from './utils';
import {
  emptyWorkspace,
  loadWorkspace,
  mergeCorrectionSummaries,
  migrateWorkspaceWithReport,
  takeWorkspaceCorrectionReport,
} from './repo';
import type { CorrectionSummary } from './repo';
import * as repo from './repo';
import { createSeedWorkspace } from './fixtures';
import { okrPeriods } from './selectors';
import {
  itemIdFromSearch,
  readRouteMemory,
  resolveInitialRoute,
  syncBrowserRoute,
} from './routeState';

export type SaveState = 'idle' | 'saving' | 'saved' | 'error';

export type Route = 'dashboard' | 'sop' | 'okr' | 'gtd' | 'gantt' | 'settings';

export interface UiState {
  route: Route;
  theme: 'light' | 'dark';
  okrPeriod: string;
  ganttZoom: 'day' | 'week' | 'month';
  gtdContext: string | null;
  search: string;
  inspectorOpen: boolean;
  paletteOpen: boolean;
  quickCaptureOpen: boolean;
  shortcutsOpen: boolean;
}

export interface Notice {
  id: string;
  message: string;
  tone: 'info' | 'success' | 'error';
  at: string;
}

export interface WorkspaceStore {
  workspace: Workspace;
  status: 'loading' | 'ready' | 'error';
  saveState: SaveState;
  error: string | null;
  selectedId: string | null;
  ui: UiState;
  notices: Notice[];

  load(): Promise<void>;
  save(): Promise<void>;
  reload(): Promise<void>;
  replaceWorkspace(next: Workspace, options?: { recordHistory?: boolean }): Promise<void>;

  createItem(input: NewItemInput): Item;
  updateItem(id: string, patch: ItemPatch): void;
  updateItems(patches: Array<{ id: string; patch: ItemPatch }>, options?: { recordHistory?: boolean }): void;
  deleteItems(ids: string[]): void;
  moveItem(id: string, parentId: string | null, order?: number): void;
  toggleDone(id: string): void;
  setStatus(id: string, status: ItemStatus): void;

  createEdge(input: { from: string; to: string; type: Edge['type']; label?: string }): Edge;
  updateEdge(id: string, patch: Partial<Omit<Edge, 'id'>>): void;
  deleteEdge(id: string): void;

  createArea(name: string): Area;
  updateArea(id: string, patch: Partial<Omit<Area, 'id'>>): void;
  deleteArea(id: string): void;

  logRun(input: { sopId: string; stepId: string; result: SopRunEntry['result']; note?: string }): SopRunEntry;

  undo(): void;
  redo(): void;
  canUndo(): boolean;
  canRedo(): boolean;

  setUi(patch: Partial<UiState>): void;
  select(id: string | null): void;
  notify(message: string, tone?: Notice['tone']): void;
}

const THEME_KEY = 'textura.theme';

function initialTheme(): 'light' | 'dark' {
  if (typeof window !== 'undefined' && typeof localStorage !== 'undefined') {
    const stored = localStorage.getItem(THEME_KEY);
    if (stored === 'dark' || stored === 'light') return stored;
  }
  return 'light';
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function defaultUi(): UiState {
  return {
    route: 'dashboard',
    theme: initialTheme(),
    okrPeriod: currentQuarter(),
    ganttZoom: 'week',
    gtdContext: null,
    search: '',
    inspectorOpen: false,
    paletteOpen: false,
    quickCaptureOpen: false,
    shortcutsOpen: false,
  };
}

function mergeDefined<T extends object>(base: T, patch: Partial<T>): T {
  const result: T = { ...base };
  for (const key of Object.keys(patch) as (keyof T)[]) {
    const value = patch[key];
    if (value !== undefined) {
      (result as unknown as Record<string, unknown>)[key as string] = value;
    }
  }
  return result;
}

function applyItemPatch(item: Item, patch: ItemPatch, timestamp: string = nowIso()): Item {
  const { okr, sop, gtd, gantt, ...rest } = patch;
  const next: Item = { ...item };
  for (const key of Object.keys(rest) as (keyof typeof rest)[]) {
    const value = rest[key];
    if (value !== undefined) {
      (next as unknown as Record<string, unknown>)[key] = value;
    }
  }
  next.updatedAt = timestamp;
  if (rest.status !== undefined && rest.status !== item.status) {
    next.completedAt = rest.status === 'done' ? timestamp : null;
  }
  if (okr) {
    next.okr = mergeDefined(item.okr ?? { period: currentQuarter(), confidence: 5 }, okr);
  }
  if (sop) {
    next.sop = {
      nodeType: sop.nodeType ?? item.sop?.nodeType ?? 'action',
      canvas: { ...(item.sop?.canvas ?? { x: 0, y: 0 }), ...(sop.canvas ?? {}) },
      checklist: sop.checklist ?? item.sop?.checklist ?? [],
      owner: sop.owner ?? item.sop?.owner,
      durationMin: sop.durationMin ?? item.sop?.durationMin,
    };
  }
  if (gtd) {
    next.gtd = mergeDefined(item.gtd ?? { capturedAt: timestamp, clarified: true }, gtd);
  }
  if (gantt) {
    next.gantt = mergeDefined(item.gantt ?? { start: null, end: null, progress: 0 }, gantt);
  }
  return next;
}

/** 与 load 共用：当前季度优先，否则取工作区最新季度。 */
function initialOkrPeriod(ws: Workspace): string {
  const periods = okrPeriods(ws);
  const quarter = currentQuarter();
  return periods.includes(quarter) ? quarter : (periods[0] ?? quarter);
}

function nextSiblingOrder(ws: Workspace, parentId: string | null): number {
  const siblings = ws.items.filter((item) => item.parentId === parentId);
  if (siblings.length === 0) return 0;
  return Math.max(...siblings.map((item) => item.order)) + 1;
}

const history = createHistory<Workspace>(80);

export const useWorkspace = create<WorkspaceStore>()((set, get) => {
  const scheduleSave = createDebouncer(() => {
    void get().save();
  }, 400);

  const commit = (recipe: (ws: Workspace) => Workspace): void => {
    const current = get().workspace;
    history.record(cloneWorkspace(current));
    const next = { ...recipe(current), updatedAt: nowIso() };
    set({ workspace: next, saveState: 'idle', error: null });
    if (get().status === 'ready') scheduleSave.schedule();
  };

  // 串行化所有落盘，避免 replaceWorkspace 与在途 save 交错写入。
  let saveQueue: Promise<void> = Promise.resolve();
  const persistWorkspace = (
    workspace: Workspace,
    throwOnError: boolean,
  ): Promise<void> => {
    const run = async (): Promise<void> => {
      set({ saveState: 'saving' });
      try {
        await repo.saveWorkspace(workspace);
        set({ saveState: 'saved', error: null });
      } catch (error) {
        const message = errorMessage(error);
        set({ saveState: 'error', error: message });
        if (throwOnError) throw error instanceof Error ? error : new Error(message);
      }
    };
    const result = saveQueue.then(run, run);
    saveQueue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  };

  const notifyCorrections = (summary: CorrectionSummary): void => {
    if (summary.total === 0) return;
    console.warn(`[textura] 已修正 ${summary.total} 处非法数据`, summary.entries);
    notify(`已修正 ${summary.total} 处非法数据（详见控制台）`, 'info');
  };

  const notify = (message: string, tone: Notice['tone'] = 'info'): void => {
    const notice: Notice = { id: uid('notice'), message, tone, at: nowIso() };
    set({ notices: [...get().notices, notice].slice(-4) });
    if (tone !== 'error') {
      setTimeout(() => {
        set({ notices: get().notices.filter((item) => item.id !== notice.id) });
      }, 3500);
    }
  };

  return {
    workspace: emptyWorkspace(),
    status: 'loading',
    saveState: 'idle',
    error: null,
    selectedId: null,
    ui: defaultUi(),
    notices: [],

    async load() {
      scheduleSave.cancel();
      // 先让在途保存完成，避免 reload 丢弃尚未落盘的编辑。
      await saveQueue;
      // 在 await 之前同步读取深链，避免任何异步副作用覆盖 URL/记忆。
      const search = typeof window === 'undefined' ? '' : window.location.search;
      const initialRoute = resolveInitialRoute(search, readRouteMemory());
      const deepItemId = itemIdFromSearch(search);
      set({ status: 'loading', error: null });
      try {
        const loaded = await loadWorkspace();
        let ws = loaded.workspace;
        const isBlank = ws.items.length === 0 && ws.areas.length === 0 && ws.runs.length === 0;
        // 只有「首次安装」才播种；用户主动清空/导入空工作区后重启保持为空。
        if (isBlank && loaded.freshInstall) {
          ws = createSeedWorkspace();
          await repo.saveWorkspace(ws);
        }
        history.clear();
        const initialPeriod = initialOkrPeriod(ws);
        const selectedId =
          deepItemId && ws.items.some((item) => item.id === deepItemId) ? deepItemId : null;
        set({
          workspace: { ...ws, version: WORKSPACE_VERSION },
          status: 'ready',
          saveState: 'idle',
          error: null,
          selectedId,
          ui: { ...get().ui, okrPeriod: initialPeriod, route: initialRoute },
        });
        syncBrowserRoute(initialRoute);
        notifyCorrections(loaded.corrections ?? { total: 0, entries: [] });
        if (loaded.parentCycles.length > 0) {
          let repairedPath = '';
          try {
            repairedPath = await repo.saveRepairedWorkspace(ws);
          } catch (error) {
            console.warn('[textura] 保存环修复副本失败', error);
          }
          notify(
            `检测到父子环（${loaded.parentCycles.length} 处），已自动切断 parentId；修复副本：${
              repairedPath || '保存失败'
            }。原始文件未被覆盖；下次编辑会写回修复结果。`,
            'error',
          );
        }
      } catch (error) {
        set({
          status: 'error',
          error: errorMessage(error),
          workspace: emptyWorkspace(),
          saveState: 'error',
        });
      }
    },

    async save() {
      const state = get();
      if (state.status !== 'ready') return;
      await persistWorkspace(state.workspace, false);
    },

    async reload() {
      await saveQueue;
      history.clear();
      await get().load();
    },

    async replaceWorkspace(next, options) {
      const recordHistory = options?.recordHistory ?? true;
      // appshell 会先用 parseWorkspaceText 预校验；沿用当时暂存的修正摘要，
      // 否则二次归一化会看不到原始非法值。
      const carried = takeWorkspaceCorrectionReport(next);
      const migrated = migrateWorkspaceWithReport(next);
      const corrections = carried
        ? mergeCorrectionSummaries(carried, migrated.corrections)
        : migrated.corrections;
      const normalized: Workspace = {
        ...migrated.workspace,
        updatedAt: nowIso(),
      };

      scheduleSave.cancel();
      // 先等待在途保存完成，避免旧内容晚于替换内容 rename 到主文件。
      await saveQueue;

      if (recordHistory) {
        history.record(cloneWorkspace(get().workspace));
      } else {
        // 即使不记录本次替换，也要让旧的重做栈失效。
        history.clearRedo();
      }

      set({
        workspace: normalized,
        selectedId: null,
        saveState: 'idle',
        error: null,
        ui: { ...get().ui, okrPeriod: initialOkrPeriod(normalized) },
      });

      try {
        await persistWorkspace(normalized, true);
      } catch (error) {
        notify(`保存失败：${errorMessage(error)}`, 'error');
        throw error;
      }
      notifyCorrections(corrections);
    },

    createItem(input) {
      const ws = get().workspace;
      const now = nowIso();
      const status: ItemStatus =
        input.status ?? (input.kind === 'note' || input.kind === 'reference' ? 'inbox' : 'next');
      const parentId = input.parentId ?? null;
      const item: Item = {
        id: uid(input.kind.slice(0, 3)),
        kind: input.kind,
        title: input.title,
        notes: input.notes ?? '',
        parentId,
        order: input.order ?? nextSiblingOrder(ws, parentId),
        status,
        tags: input.tags ?? [],
        areaId: input.areaId ?? null,
        createdAt: now,
        updatedAt: now,
        completedAt: status === 'done' ? now : null,
      };
      if (input.kind === 'objective' || input.kind === 'keyresult') {
        item.okr = {
          period: input.okr?.period ?? currentQuarter(),
          confidence: input.okr?.confidence ?? 5,
          metric: input.okr?.metric,
          krOwner: input.okr?.krOwner,
        };
      }
      if (input.kind === 'sop' || input.kind === 'step') {
        item.sop = {
          nodeType: input.sop?.nodeType ?? 'action',
          canvas: input.sop?.canvas ?? { x: 0, y: 0 },
          checklist: input.sop?.checklist ?? [],
          owner: input.sop?.owner,
          durationMin: input.sop?.durationMin,
        };
      }
      if (input.kind === 'action' || input.kind === 'project') {
        item.gantt = {
          start: input.gantt?.start ?? null,
          end: input.gantt?.end ?? null,
          progress: input.gantt?.progress ?? 0,
        };
      }
      if (input.kind === 'action') {
        item.gtd = {
          capturedAt: input.gtd?.capturedAt ?? now,
          clarified: input.gtd?.clarified ?? status !== 'inbox',
          context: input.gtd?.context,
          energy: input.gtd?.energy,
          waitingFor: input.gtd?.waitingFor,
          twoMinuteCandidate: input.gtd?.twoMinuteCandidate,
        };
      } else if (input.gtd) {
        item.gtd = {
          capturedAt: input.gtd.capturedAt ?? now,
          clarified: input.gtd.clarified ?? true,
          context: input.gtd.context,
          energy: input.gtd.energy,
          waitingFor: input.gtd.waitingFor,
          twoMinuteCandidate: input.gtd.twoMinuteCandidate,
        };
      }
      commit((current) => ({ ...current, items: [...current.items, item] }));
      return item;
    },

    updateItem(id, patch) {
      commit((ws) => ({
        ...ws,
        items: ws.items.map((item) => (item.id === id ? applyItemPatch(item, patch) : item)),
      }));
    },

    updateItems(patches, options) {
      if (patches.length === 0) return;
      const current = get().workspace;
      const existingIds = new Set(current.items.map((item) => item.id));
      const patchById = new Map<string, ItemPatch>();
      for (const { id, patch } of patches) {
        if (existingIds.has(id)) patchById.set(id, patch);
      }
      if (patchById.size === 0) return;

      const recordHistory = options?.recordHistory ?? true;
      if (recordHistory) {
        history.record(cloneWorkspace(current));
      } else {
        history.clearRedo();
      }

      const timestamp = nowIso();
      const items = current.items.map((item) => {
        const patch = patchById.get(item.id);
        return patch ? applyItemPatch(item, patch, timestamp) : item;
      });
      set({
        workspace: { ...current, items, updatedAt: timestamp },
        saveState: 'idle',
        error: null,
      });
      if (get().status === 'ready') scheduleSave.schedule();
    },

    deleteItems(ids) {
      if (ids.length === 0) return;
      commit((ws) => {
        const doomed = new Set(ids);
        for (const id of ids) {
          for (const child of ws.items.filter((item) => item.parentId === id)) doomed.add(child.id);
        }
        // 迭代闭包，确保深层子孙也被级联删除。
        let changed = true;
        while (changed) {
          changed = false;
          for (const item of ws.items) {
            if (item.parentId && doomed.has(item.parentId) && !doomed.has(item.id)) {
              doomed.add(item.id);
              changed = true;
            }
          }
        }
        return {
          ...ws,
          items: ws.items.filter((item) => !doomed.has(item.id)),
          edges: ws.edges.filter((edge) => !doomed.has(edge.from) && !doomed.has(edge.to)),
          runs: ws.runs.filter((run) => !doomed.has(run.sopId) && !doomed.has(run.stepId)),
        };
      });
      const selectedId = get().selectedId;
      if (selectedId && !get().workspace.items.some((item) => item.id === selectedId)) {
        set({ selectedId: null });
      }
    },

    moveItem(id, parentId, order) {
      commit((ws) => {
        const moving = ws.items.find((item) => item.id === id);
        if (!moving || parentId === id) return ws;
        if (parentId) {
          let cursor = ws.items.find((item) => item.id === parentId);
          const seen = new Set<string>();
          while (cursor) {
            if (cursor.id === id) return ws; // 禁止移动到自身子孙下
            if (seen.has(cursor.id)) break;
            seen.add(cursor.id);
            cursor = cursor.parentId ? ws.items.find((item) => item.id === cursor!.parentId) : undefined;
          }
        }
        const items = ws.items.map((item) =>
          item.id === id ? { ...item, parentId, updatedAt: nowIso() } : { ...item },
        );
        const moved = items.find((item) => item.id === id)!;
        const oldParentId = moving.parentId;

        const reindex = (pid: string | null) => {
          const siblings = items
            .filter((item) => item.parentId === pid)
            .sort((a, b) => a.order - b.order || a.createdAt.localeCompare(b.createdAt));
          siblings.forEach((sibling, index) => {
            sibling.order = index;
          });
          return siblings;
        };
        const siblings = reindex(parentId).filter((item) => item.id !== id);
        const insertAt =
          order === undefined ? siblings.length : Math.min(Math.max(Math.round(order), 0), siblings.length);
        siblings.splice(insertAt, 0, moved);
        siblings.forEach((sibling, index) => {
          sibling.order = index;
        });
        if (oldParentId !== parentId) reindex(oldParentId);
        return { ...ws, items };
      });
    },

    toggleDone(id) {
      const item = get().workspace.items.find((entry) => entry.id === id);
      if (!item) return;
      get().setStatus(id, item.status === 'done' ? 'next' : 'done');
    },

    setStatus(id, status) {
      commit((ws) => ({
        ...ws,
        items: ws.items.map((item) =>
          item.id === id
            ? {
                ...item,
                status,
                completedAt: status === 'done' ? nowIso() : null,
                updatedAt: nowIso(),
              }
            : item,
        ),
      }));
    },

    createEdge(input) {
      const existing = get().workspace.edges.find(
        (edge) => edge.from === input.from && edge.to === input.to && edge.type === input.type,
      );
      if (existing) return existing;
      const edge: Edge = {
        id: uid('edge'),
        from: input.from,
        to: input.to,
        type: input.type,
        label: input.label ?? '',
      };
      commit((ws) => ({ ...ws, edges: [...ws.edges, edge] }));
      return edge;
    },

    updateEdge(id, patch) {
      commit((ws) => ({
        ...ws,
        edges: ws.edges.map((edge) => (edge.id === id ? { ...edge, ...patch } : edge)),
      }));
    },

    deleteEdge(id) {
      commit((ws) => ({ ...ws, edges: ws.edges.filter((edge) => edge.id !== id) }));
    },

    createArea(name) {
      const ws = get().workspace;
      const area: Area = {
        id: uid('area'),
        name,
        color: areaPalette(ws.areas.length),
        order: ws.areas.length === 0 ? 0 : Math.max(...ws.areas.map((item) => item.order)) + 1,
      };
      commit((current) => ({ ...current, areas: [...current.areas, area] }));
      return area;
    },

    updateArea(id, patch) {
      commit((ws) => ({
        ...ws,
        areas: ws.areas.map((area) => (area.id === id ? { ...area, ...patch } : area)),
      }));
    },

    deleteArea(id) {
      commit((ws) => ({
        ...ws,
        areas: ws.areas.filter((area) => area.id !== id),
        items: ws.items.map((item) => (item.areaId === id ? { ...item, areaId: null } : item)),
      }));
    },

    logRun(input) {
      const run: SopRunEntry = {
        id: uid('run'),
        sopId: input.sopId,
        stepId: input.stepId,
        at: nowIso(),
        result: input.result,
        note: input.note ?? '',
      };
      commit((ws) => ({ ...ws, runs: [...ws.runs, run] }));
      return run;
    },

    undo() {
      const snapshot = history.undo(cloneWorkspace(get().workspace));
      if (!snapshot) return;
      set({
        workspace: { ...snapshot, updatedAt: nowIso() },
        saveState: 'idle',
        error: null,
      });
      scheduleSave.schedule();
    },

    redo() {
      const snapshot = history.redo(cloneWorkspace(get().workspace));
      if (!snapshot) return;
      set({
        workspace: { ...snapshot, updatedAt: nowIso() },
        saveState: 'idle',
        error: null,
      });
      scheduleSave.schedule();
    },

    canUndo() {
      return history.canUndo();
    },

    canRedo() {
      return history.canRedo();
    },

    setUi(patch) {
      const ui = { ...get().ui, ...patch };
      set({ ui });
      if (patch.theme) {
        document.documentElement.dataset.theme = patch.theme;
        if (typeof localStorage !== 'undefined') localStorage.setItem(THEME_KEY, patch.theme);
      }
      if (patch.route) syncBrowserRoute(patch.route);
    },

    select(id) {
      set({ selectedId: id });
    },

    notify,
  };
});

/** 非 React 环境（命令、工具函数）读取 store。 */
export function getWorkspace(): WorkspaceStore {
  return useWorkspace.getState();
}

/** 供模块按需使用的持久化能力（设置页导入/导出等）。 */
export { repo };
export type { Item, Area, Edge, ItemStatus, NewItemInput, ItemPatch };
