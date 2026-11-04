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
  NewReportInput,
  Report,
  ReportPatch,
  ReportPeriodKind,
  ReportSection,
  ReportSectionOrigin,
  ReportStatus,
  SopRunEntry,
  Workspace,
} from './model';
import { REPORT_TEMPLATE_BY_KIND, WORKSPACE_VERSION } from './model';
import { createHistory } from './history';
import { createDebouncer, areaPalette, currentQuarter, nowIso, uid } from './utils';
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
import { getWorkspaceIndex, itemById, okrPeriods } from './selectors';
import {
  itemIdFromSearch,
  readRouteMemory,
  resolveInitialRoute,
  syncBrowserRoute,
} from './routeState';

export type SaveState = 'idle' | 'saving' | 'saved' | 'error';

export type Route =
  | 'dashboard'
  | 'calendar'
  | 'sop'
  | 'okr'
  | 'gtd'
  | 'gantt'
  | 'reports'
  | 'settings';

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

  createReport(input: NewReportInput): Report;
  updateReport(id: string, patch: ReportPatch): void;
  finalizeReport(id: string): void;
  reopenReport(id: string): void;
  deleteReport(id: string): void;

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
  const siblings = getWorkspaceIndex(ws).children.get(parentId) ?? [];
  if (siblings.length === 0) return 0;
  return Math.max(...siblings.map((item) => item.order)) + 1;
}

/** 报告集合（v1 之前的工作区可能没有这个键）。 */
function reportsOf(ws: Workspace): Report[] {
  return ws.reports ?? [];
}

/** 季度中文数字（1→一 … 4→四），与聚合层 periodLabel 的季度形态对齐。 */
const QUARTER_CN_LABELS = ['一', '二', '三', '四'] as const;

/**
 * 默认标题：能解析出周期就写成中文「2026 年第 44 周报」，
 * 解析不了（含 period 为空串）就把 period 原样当标题，由上层决定是否允许生成。
 */
function defaultReportTitle(kind: ReportPeriodKind, period: string): string {
  const week = /^(\d{4})-W(\d{2})$/.exec(period);
  if (kind === 'week' && week) return `${week[1]} 年第 ${Number(week[2])} 周报`;
  const month = /^(\d{4})-(\d{2})$/.exec(period);
  if (kind === 'month' && month) return `${month[1]} 年 ${Number(month[2])} 月报`;
  const quarter = /^(\d{4})-Q([1-4])$/.exec(period);
  if (kind === 'quarter' && quarter) {
    // 季报用中文数字，与聚合层 `periodLabel('quarter', …)` 的「第四季度」同一形态：
    // 否则左栏标题写「第 4 季度报」、页头期次写「第四季度」，同一份报告两种口径。
    const label = QUARTER_CN_LABELS[Number(quarter[2]) - 1];
    if (label) return `${quarter[1]} 年第${label}季度报`;
  }
  return period;
}

/**
 * 章节整份替换：updatedAt 统一刷新为本次时间戳；
 * 调用方没给 origin 时按同 key 的旧章节回填（未传则保留原值）。
 */
function replaceSections(
  previous: ReportSection[],
  next: ReportSection[],
  timestamp: string,
): ReportSection[] {
  const byKey = new Map(previous.map((section) => [section.key, section]));
  return next.map((section) => {
    const inherited = byKey.get(section.key)?.origin;
    const origin: ReportSectionOrigin = section.origin ?? inherited ?? 'auto';
    return { ...section, origin, updatedAt: timestamp };
  });
}

const history = createHistory<Workspace>(80);

/**
 * 历史栈只保存工作区「外壳」的浅拷贝：items / edges / areas / runs 等数组与未变更的 Item
 * 仍然共享引用（结构共享不变），但快照对象本身是新的 —— 因此不会被 selectors 的
 * `WeakMap<Workspace, WorkspaceIndex>` 命中，也就不会把一整份索引（10k 条目下约 0.4–0.5 MB）
 * 钉在内存里。历史上限 80，实测可省约 40 MB。
 * 撤销/重做时 store 本来就会 `{...snapshot, updatedAt}` 换新身份并重建索引，语义不变。
 */
const historyShell = (ws: Workspace): Workspace => ({ ...ws });

export const useWorkspace = create<WorkspaceStore>()((set, get) => {
  const scheduleSave = createDebouncer(() => {
    void get().save();
  }, 400);

  const commit = (recipe: (ws: Workspace) => Workspace): void => {
    const current = get().workspace;
    history.record(historyShell(current));
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
        history.record(historyShell(get().workspace));
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
      const existingIds = getWorkspaceIndex(current).byId;
      const patchById = new Map<string, ItemPatch>();
      for (const { id, patch } of patches) {
        if (existingIds.has(id)) patchById.set(id, patch);
      }
      if (patchById.size === 0) return;

      const recordHistory = options?.recordHistory ?? true;
      if (recordHistory) {
        history.record(historyShell(current));
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
        const queue = [...ids];
        const children = getWorkspaceIndex(ws).children;
        while (queue.length > 0) {
          const parentId = queue.pop()!;
          for (const child of children.get(parentId) ?? []) {
            if (doomed.has(child.id)) continue;
            doomed.add(child.id);
            queue.push(child.id);
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
      if (selectedId && !getWorkspaceIndex(get().workspace).byId.has(selectedId)) {
        set({ selectedId: null });
      }
    },

    moveItem(id, parentId, order) {
      commit((ws) => {
        const index = getWorkspaceIndex(ws);
        const moving = index.byId.get(id);
        if (!moving || parentId === id) return ws;
        if (parentId) {
          let cursor = index.byId.get(parentId);
          const seen = new Set<string>();
          while (cursor) {
            if (cursor.id === id) return ws; // 禁止移动到自身子孙下
            if (seen.has(cursor.id)) break;
            seen.add(cursor.id);
            cursor = cursor.parentId ? index.byId.get(cursor.parentId) : undefined;
          }
        }

        const oldParentId = moving.parentId;
        const timestamp = nowIso();
        const moved: Item = { ...moving, parentId, updatedAt: timestamp };
        const updates = new Map<string, Item>([[id, moved]]);
        const assignOrders = (pid: string | null, insertMoved: boolean) => {
          const siblings = (index.children.get(pid) ?? []).filter((item) => item.id !== id);
          if (!insertMoved) {
            siblings.forEach((sibling, position) => {
              if (sibling.order !== position) {
                updates.set(sibling.id, { ...sibling, order: position });
              }
            });
            return;
          }
          const insertAt =
            order === undefined
              ? siblings.length
              : Math.min(Math.max(Math.round(order), 0), siblings.length);
          siblings.splice(insertAt, 0, moved);
          siblings.forEach((sibling, position) => {
            if (sibling.id === id) {
              moved.order = position;
            } else if (sibling.order !== position) {
              updates.set(sibling.id, { ...sibling, order: position });
            }
          });
        };

        assignOrders(parentId, true);
        if (oldParentId !== parentId) assignOrders(oldParentId, false);

        return {
          ...ws,
          items: ws.items.map((item) => updates.get(item.id) ?? item),
        };
      });
    },

    toggleDone(id) {
      const item = itemById(get().workspace, id);
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
      const existing = getWorkspaceIndex(get().workspace).edgesFrom
        .get(input.from)
        ?.find((edge) => edge.to === input.to && edge.type === input.type);
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

    createReport(input) {
      const now = nowIso();
      const report: Report = {
        id: uid('r'),
        kind: input.kind,
        period: input.period,
        // 空白标题等于没填，走默认标题；只有显式给了非空标题才覆盖。
        title:
          input.title && input.title.trim()
            ? input.title
            : defaultReportTitle(input.kind, input.period),
        author: input.author ?? '',
        status: 'draft',
        templateId:
          input.templateId && input.templateId.trim()
            ? input.templateId
            : REPORT_TEMPLATE_BY_KIND[input.kind],
        sections: replaceSections([], input.sections ?? [], now),
        generatedAt: now,
        finalizedAt: null,
        createdAt: now,
        updatedAt: now,
      };
      commit((ws) => ({ ...ws, reports: [...reportsOf(ws), report] }));
      return report;
    },

    updateReport(id, patch) {
      // 与 finalize/reopen/delete 同一口径：不存在的 id 直接返回。
      // 页面层的防抖定时器可能拿着已经失效的 id 回调（例如刚撤销了删除），
      // 没有这道守卫就会把一次「什么都没变」写进历史栈，还会替换 workspace 触发落盘。
      if (!reportsOf(get().workspace).some((report) => report.id === id)) return;
      const timestamp = nowIso();
      commit((ws) => ({
        ...ws,
        reports: reportsOf(ws).map((report) => {
          if (report.id !== id) return report;
          const next: Report = { ...report, updatedAt: timestamp };
          if (patch.title !== undefined) next.title = patch.title;
          if (patch.author !== undefined) next.author = patch.author;
          if (patch.sections !== undefined) {
            next.sections = replaceSections(report.sections, patch.sections, timestamp);
          }
          return next;
        }),
      }));
    },

    finalizeReport(id) {
      if (!reportsOf(get().workspace).some((report) => report.id === id)) return;
      const timestamp = nowIso();
      commit((ws) => ({
        ...ws,
        reports: reportsOf(ws).map((report) =>
          report.id === id
            ? { ...report, status: 'final', finalizedAt: timestamp, updatedAt: timestamp }
            : report,
        ),
      }));
    },

    reopenReport(id) {
      if (!reportsOf(get().workspace).some((report) => report.id === id)) return;
      const timestamp = nowIso();
      commit((ws) => ({
        ...ws,
        reports: reportsOf(ws).map((report) =>
          report.id === id
            ? { ...report, status: 'draft', finalizedAt: null, updatedAt: timestamp }
            : report,
        ),
      }));
    },

    deleteReport(id) {
      if (!reportsOf(get().workspace).some((report) => report.id === id)) return;
      commit((ws) => ({ ...ws, reports: reportsOf(ws).filter((report) => report.id !== id) }));
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
      const snapshot = history.undo(historyShell(get().workspace));
      if (!snapshot) return;
      set({
        workspace: { ...snapshot, updatedAt: nowIso() },
        saveState: 'idle',
        error: null,
      });
      scheduleSave.schedule();
    },

    redo() {
      const snapshot = history.redo(historyShell(get().workspace));
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
export type {
  Item,
  Area,
  Edge,
  ItemStatus,
  NewItemInput,
  ItemPatch,
  Report,
  ReportSection,
  ReportPatch,
  NewReportInput,
  ReportPeriodKind,
  ReportStatus,
  ReportSectionOrigin,
};

/** 历史诊断（只读）：当前快照步数与上限。 */
export function getHistoryStats(): { steps: number; limit: number } {
  return { steps: history.size(), limit: history.limit };
}
