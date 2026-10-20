/**
 * 持久化适配层。
 * - Tauri：调用 Rust 命令（单文档原子写 + 轮换备份）
 * - 浏览器（无 __TAURI_INTERNALS__）：降级到 localStorage，保证 vite preview 可调试
 *
 * 导入路径使用 `migrateWorkspace`（严格）：字段归一化 + 父子环拒绝。
 * 加载路径使用 `normalizeForLoad`：字段归一化 + 切断父子环并记录警告，避免脏数据导致白屏。
 */
import type {
  Area,
  ChecklistEntry,
  Edge,
  EdgeType,
  Energy,
  GanttData,
  GtdData,
  Item,
  ItemKind,
  ItemStatus,
  OkrData,
  SopData,
  SopNodeType,
  SopRunEntry,
  Workspace,
} from './model';
import { ITEM_KINDS, ITEM_STATUSES, WORKSPACE_VERSION } from './model';
import { findParentCycles } from './selectors';
import { currentQuarter, nowIso } from './utils';

export const LOCAL_STORAGE_KEY = 'textura.workspace.v1';
export const REPAIRED_LOCAL_KEY = 'textura.workspace.repaired.preview';

export interface SaveInfo {
  savedAt: string;
  bytes: number;
}

export interface StorageInfo {
  dataDir: string;
  workspacePath: string;
  backupCount: number;
  revision: number;
}

export interface BackupInfo {
  name: string;
  size: number;
  createdAt: string;
}

/** Rust `load_workspace` 的返回结构。 */
export interface LoadResult {
  workspace: Workspace;
  freshInstall: boolean;
}

/** 前端加载结果：额外带出被切断的父子环，供 store warn。 */
export interface LoadedWorkspace extends LoadResult {
  parentCycles: string[][];
  corrections: CorrectionSummary;
}

export interface NormalizationCorrection {
  itemId: string | null;
  field: string;
  from: unknown;
  to: unknown;
}

export interface CorrectionSummary {
  /** 实际发生修正的总数（可能大于 entries.length） */
  total: number;
  /** 最多保留 20 条，供通知/日志使用 */
  entries: NormalizationCorrection[];
}

const MAX_CORRECTION_ENTRIES = 20;
const pendingCorrectionReports = new WeakMap<Workspace, CorrectionSummary>();

function emptyCorrectionSummary(): CorrectionSummary {
  return { total: 0, entries: [] };
}

export function mergeCorrectionSummaries(
  first: CorrectionSummary,
  second: CorrectionSummary,
): CorrectionSummary {
  return {
    total: first.total + second.total,
    entries: [...first.entries, ...second.entries].slice(0, MAX_CORRECTION_ENTRIES),
  };
}

/** 取出 parseWorkspaceText 暂存的修正摘要（用于 appshell 预校验后再 replaceWorkspace 的流程）。 */
export function takeWorkspaceCorrectionReport(
  workspace: Workspace,
): CorrectionSummary | undefined {
  const report = pendingCorrectionReports.get(workspace);
  if (report) pendingCorrectionReports.delete(workspace);
  return report;
}

export class WorkspaceVersionError extends Error {
  readonly version: number;

  constructor(version: number) {
    super(
      `工作区版本 ${version} 高于当前应用支持的版本 ${WORKSPACE_VERSION}，请升级 Textura 后再打开。`,
    );
    this.name = 'WorkspaceVersionError';
    this.version = version;
  }
}

export function isTauri(): boolean {
  if (typeof window === 'undefined') return false;
  const w = window as unknown as { __TAURI_INTERNALS__?: unknown };
  return w.__TAURI_INTERNALS__ !== undefined;
}

export function emptyWorkspace(): Workspace {
  return {
    version: WORKSPACE_VERSION,
    items: [],
    edges: [],
    areas: [],
    runs: [],
    updatedAt: nowIso(),
  };
}

async function invoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  const api = await import('@tauri-apps/api/core');
  return api.invoke<T>(command, args);
}

const SOP_NODE_TYPES: SopNodeType[] = ['start', 'action', 'decision', 'check', 'end', 'note'];
const ENERGIES: Energy[] = ['low', 'medium', 'high'];
const EDGE_TYPES: EdgeType[] = ['okr', 'flow', 'depends', 'related'];
const RUN_RESULTS: SopRunEntry['result'][] = ['pass', 'fail', 'skip'];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function asNonEmptyString(value: unknown, fallback: string): string {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

function asOptionalText(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function asOptionalId(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null;
}

function asNumber(value: unknown, fallback: number): number {
  if (typeof value !== 'number' && typeof value !== 'string') return fallback;
  if (typeof value === 'string' && !value.trim()) return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clampNumber(value: unknown, min: number, max: number, fallback: number): number {
  return Math.min(max, Math.max(min, asNumber(value, fallback)));
}

function asEnum<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return typeof value === 'string' && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : fallback;
}

function asOptionalEnum<T extends string>(value: unknown, allowed: readonly T[]): T | undefined {
  return typeof value === 'string' && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : undefined;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asIsoOrFallback(value: unknown, fallback: string): string {
  return asNonEmptyString(value, fallback);
}

function asDateOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null;
}

function normalizeChecklist(value: unknown, itemIndex: number): ChecklistEntry[] {
  return asArray(value).map((entry, index) => {
    const raw = isRecord(entry) ? entry : {};
    return {
      id: asNonEmptyString(raw.id, `chk_${itemIndex}_${index}`),
      text: asString(raw.text),
      done: raw.done === true,
    };
  });
}

function normalizeOkr(value: unknown): OkrData {
  const raw = isRecord(value) ? value : {};
  const okr: OkrData = {
    period: asNonEmptyString(raw.period, currentQuarter()),
    confidence: Math.round(clampNumber(raw.confidence, 1, 10, 5)),
  };
  if (isRecord(raw.metric)) {
    okr.metric = {
      start: asNumber(raw.metric.start, 0),
      target: asNumber(raw.metric.target, 0),
      current: asNumber(raw.metric.current, 0),
      unit: asString(raw.metric.unit),
    };
  }
  const owner = asOptionalText(raw.krOwner);
  if (owner !== undefined) okr.krOwner = owner;
  return okr;
}

function normalizeSop(value: unknown, itemIndex: number): SopData {
  const raw = isRecord(value) ? value : {};
  const canvas = isRecord(raw.canvas) ? raw.canvas : {};
  const sop: SopData = {
    nodeType: asEnum(raw.nodeType, SOP_NODE_TYPES, 'action'),
    canvas: { x: asNumber(canvas.x, 0), y: asNumber(canvas.y, 0) },
    checklist: normalizeChecklist(raw.checklist, itemIndex),
  };
  const owner = asOptionalText(raw.owner);
  if (owner !== undefined) sop.owner = owner;
  if (raw.durationMin !== undefined && raw.durationMin !== null) {
    sop.durationMin = Math.max(0, asNumber(raw.durationMin, 0));
  }
  return sop;
}

function normalizeGtd(value: unknown, fallbackCapturedAt: string): GtdData {
  const raw = isRecord(value) ? value : {};
  const gtd: GtdData = {
    capturedAt: asIsoOrFallback(raw.capturedAt, fallbackCapturedAt),
    clarified: raw.clarified === true,
  };
  const context = asOptionalText(raw.context);
  if (context !== undefined) gtd.context = context;
  const energy = asOptionalEnum(raw.energy, ENERGIES);
  if (energy !== undefined) gtd.energy = energy;
  const waitingFor = asOptionalText(raw.waitingFor);
  if (waitingFor !== undefined) gtd.waitingFor = waitingFor;
  if (typeof raw.twoMinuteCandidate === 'boolean') {
    gtd.twoMinuteCandidate = raw.twoMinuteCandidate;
  }
  return gtd;
}

function normalizeGantt(value: unknown): GanttData {
  const raw = isRecord(value) ? value : {};
  return {
    start: asDateOrNull(raw.start),
    end: asDateOrNull(raw.end),
    progress: clampNumber(raw.progress, 0, 100, 0),
  };
}

function normalizeItem(input: unknown, index: number): Item {
  const raw = isRecord(input) ? input : {};
  const now = nowIso();
  const kind: ItemKind = asEnum(raw.kind, ITEM_KINDS, 'note');
  const status: ItemStatus = asEnum(raw.status, ITEM_STATUSES, 'next');
  const item: Item = {
    id: asNonEmptyString(raw.id, `i_recovered_${index}`),
    kind,
    title: asString(raw.title, '未命名条目'),
    notes: asString(raw.notes),
    parentId: asOptionalId(raw.parentId),
    order: asNumber(raw.order, index),
    status,
    tags: asArray(raw.tags)
      .map((tag) => asString(tag).trim())
      .filter((tag) => tag.length > 0),
    areaId: asOptionalId(raw.areaId),
    createdAt: asIsoOrFallback(raw.createdAt, now),
    updatedAt: asIsoOrFallback(raw.updatedAt, now),
    completedAt: typeof raw.completedAt === 'string' && raw.completedAt.trim() ? raw.completedAt : null,
  };

  if (isRecord(raw.okr)) item.okr = normalizeOkr(raw.okr);
  if (isRecord(raw.sop)) item.sop = normalizeSop(raw.sop, index);
  if (isRecord(raw.gtd)) item.gtd = normalizeGtd(raw.gtd, item.createdAt);
  if (isRecord(raw.gantt)) item.gantt = normalizeGantt(raw.gantt);

  return item;
}

function normalizeEdge(input: unknown, index: number): Edge {
  const raw = isRecord(input) ? input : {};
  return {
    id: asNonEmptyString(raw.id, `edge_recovered_${index}`),
    from: asString(raw.from),
    to: asString(raw.to),
    type: asEnum(raw.type, EDGE_TYPES, 'related'),
    label: asString(raw.label),
  };
}

function normalizeArea(input: unknown, index: number): Area {
  const raw = isRecord(input) ? input : {};
  return {
    id: asNonEmptyString(raw.id, `area_recovered_${index}`),
    name: asString(raw.name, '未命名领域'),
    color: asString(raw.color, '#C0663A'),
    order: asNumber(raw.order, index),
  };
}

function normalizeRun(input: unknown, index: number): SopRunEntry {
  const raw = isRecord(input) ? input : {};
  const now = nowIso();
  return {
    id: asNonEmptyString(raw.id, `run_recovered_${index}`),
    sopId: asString(raw.sopId),
    stepId: asString(raw.stepId),
    at: asIsoOrFallback(raw.at, now),
    result: asEnum(raw.result, RUN_RESULTS, 'skip'),
    note: asString(raw.note),
  };
}

function normalizeWorkspace(input: unknown): Workspace {
  if (!isRecord(input)) throw new Error('工作区数据不是对象');

  const version = Number.isFinite(Number(input.version)) ? Math.trunc(Number(input.version)) : 0;
  if (version > WORKSPACE_VERSION) {
    throw new WorkspaceVersionError(version);
  }

  const items = asArray(input.items).map((item, index) => normalizeItem(item, index));
  return {
    version: WORKSPACE_VERSION,
    items,
    edges: asArray(input.edges).map((edge, index) => normalizeEdge(edge, index)),
    areas: asArray(input.areas).map((area, index) => normalizeArea(area, index)),
    runs: asArray(input.runs).map((run, index) => normalizeRun(run, index)),
    updatedAt: asIsoOrFallback(input.updatedAt, nowIso()),
  };
}

function valuesEqual(a: unknown, b: unknown): boolean {
  if (Object.is(a, b)) return true;
  if (Array.isArray(a) || Array.isArray(b) || isRecord(a) || isRecord(b)) {
    try {
      return JSON.stringify(a) === JSON.stringify(b);
    } catch {
      return false;
    }
  }
  return false;
}

class CorrectionCollector {
  private readonly entries: NormalizationCorrection[] = [];
  private total = 0;

  record(itemId: string | null, field: string, from: unknown, to: unknown): void {
    if (from === undefined || valuesEqual(from, to)) return;
    this.total += 1;
    if (this.entries.length < MAX_CORRECTION_ENTRIES) {
      this.entries.push({ itemId, field, from, to });
    }
  }

  summary(): CorrectionSummary {
    return { total: this.total, entries: this.entries };
  }
}

/**
 * 归一化后的差异摘要：只记录「原值存在但被修正」的字段，最多 20 条。
 * 用于加载/导入后一次性提示 + console.warn，不记录完整工作区。
 */
function collectCorrections(input: Record<string, unknown>, workspace: Workspace): CorrectionSummary {
  const collector = new CorrectionCollector();
  const rawItems = asArray(input.items);
  const diff = (itemId: string | null, field: string, from: unknown, to: unknown) =>
    collector.record(itemId, field, from, to);

  workspace.items.forEach((item, index) => {
    const raw = isRecord(rawItems[index]) ? (rawItems[index] as Record<string, unknown>) : {};
    const id = item.id;
    diff(id, 'kind', raw.kind, item.kind);
    diff(id, 'status', raw.status, item.status);
    diff(id, 'title', raw.title, item.title);
    diff(id, 'notes', raw.notes, item.notes);
    diff(id, 'parentId', raw.parentId, item.parentId);
    diff(id, 'order', raw.order, item.order);
    diff(id, 'tags', raw.tags, item.tags);
    diff(id, 'areaId', raw.areaId, item.areaId);
    diff(id, 'createdAt', raw.createdAt, item.createdAt);
    diff(id, 'updatedAt', raw.updatedAt, item.updatedAt);
    diff(id, 'completedAt', raw.completedAt, item.completedAt);

    const rawOkr = isRecord(raw.okr) ? raw.okr : undefined;
    if (rawOkr && item.okr) {
      diff(id, 'okr.period', rawOkr.period, item.okr.period);
      diff(id, 'okr.confidence', rawOkr.confidence, item.okr.confidence);
      if (isRecord(rawOkr.metric) && item.okr.metric) {
        diff(id, 'okr.metric.start', rawOkr.metric.start, item.okr.metric.start);
        diff(id, 'okr.metric.target', rawOkr.metric.target, item.okr.metric.target);
        diff(id, 'okr.metric.current', rawOkr.metric.current, item.okr.metric.current);
        diff(id, 'okr.metric.unit', rawOkr.metric.unit, item.okr.metric.unit);
      } else if (rawOkr.metric !== undefined) {
        diff(id, 'okr.metric', rawOkr.metric, item.okr.metric);
      }
      diff(id, 'okr.krOwner', rawOkr.krOwner, item.okr.krOwner);
    } else if (raw.okr !== undefined) {
      diff(id, 'okr', raw.okr, item.okr);
    }

    const rawSop = isRecord(raw.sop) ? raw.sop : undefined;
    if (rawSop && item.sop) {
      diff(id, 'sop.nodeType', rawSop.nodeType, item.sop.nodeType);
      if (isRecord(rawSop.canvas)) {
        diff(id, 'sop.canvas.x', rawSop.canvas.x, item.sop.canvas.x);
        diff(id, 'sop.canvas.y', rawSop.canvas.y, item.sop.canvas.y);
      } else if (rawSop.canvas !== undefined) {
        diff(id, 'sop.canvas', rawSop.canvas, item.sop.canvas);
      }
      diff(id, 'sop.checklist', rawSop.checklist, item.sop.checklist);
      diff(id, 'sop.owner', rawSop.owner, item.sop.owner);
      diff(id, 'sop.durationMin', rawSop.durationMin, item.sop.durationMin);
    } else if (raw.sop !== undefined) {
      diff(id, 'sop', raw.sop, item.sop);
    }

    const rawGtd = isRecord(raw.gtd) ? raw.gtd : undefined;
    if (rawGtd && item.gtd) {
      diff(id, 'gtd.capturedAt', rawGtd.capturedAt, item.gtd.capturedAt);
      diff(id, 'gtd.clarified', rawGtd.clarified, item.gtd.clarified);
      diff(id, 'gtd.context', rawGtd.context, item.gtd.context);
      diff(id, 'gtd.energy', rawGtd.energy, item.gtd.energy);
      diff(id, 'gtd.waitingFor', rawGtd.waitingFor, item.gtd.waitingFor);
      diff(id, 'gtd.twoMinuteCandidate', rawGtd.twoMinuteCandidate, item.gtd.twoMinuteCandidate);
    } else if (raw.gtd !== undefined) {
      diff(id, 'gtd', raw.gtd, item.gtd);
    }

    const rawGantt = isRecord(raw.gantt) ? raw.gantt : undefined;
    if (rawGantt && item.gantt) {
      diff(id, 'gantt.start', rawGantt.start, item.gantt.start);
      diff(id, 'gantt.end', rawGantt.end, item.gantt.end);
      diff(id, 'gantt.progress', rawGantt.progress, item.gantt.progress);
    } else if (raw.gantt !== undefined) {
      diff(id, 'gantt', raw.gantt, item.gantt);
    }
  });

  const rawEdges = asArray(input.edges);
  workspace.edges.forEach((edge, index) => {
    const raw = isRecord(rawEdges[index]) ? (rawEdges[index] as Record<string, unknown>) : {};
    for (const field of ['id', 'from', 'to', 'type', 'label'] as const) {
      diff(null, `edges[${index}].${field}`, raw[field], edge[field]);
    }
  });

  const rawAreas = asArray(input.areas);
  workspace.areas.forEach((area, index) => {
    const raw = isRecord(rawAreas[index]) ? (rawAreas[index] as Record<string, unknown>) : {};
    for (const field of ['id', 'name', 'color', 'order'] as const) {
      diff(null, `areas[${index}].${field}`, raw[field], area[field]);
    }
  });

  const rawRuns = asArray(input.runs);
  workspace.runs.forEach((run, index) => {
    const raw = isRecord(rawRuns[index]) ? (rawRuns[index] as Record<string, unknown>) : {};
    for (const field of ['id', 'sopId', 'stepId', 'at', 'result', 'note'] as const) {
      diff(null, `runs[${index}].${field}`, raw[field], run[field]);
    }
  });

  return collector.summary();
}

function normalizeWorkspaceWithCorrections(input: unknown): {
  workspace: Workspace;
  corrections: CorrectionSummary;
} {
  const workspace = normalizeWorkspace(input);
  const corrections = isRecord(input)
    ? collectCorrections(input, workspace)
    : emptyCorrectionSummary();
  return { workspace, corrections };
}

function cycleLabels(ws: Workspace, cycles: string[][]): string[] {
  const byId = new Map(ws.items.map((item) => [item.id, item]));
  return cycles.map((cycle) =>
    cycle.map((id) => byId.get(id)?.title || id).join(' → '),
  );
}

function parentCycleError(ws: Workspace, cycles: string[][]): Error {
  return new Error(`数据中存在父子环：${cycleLabels(ws, cycles).join('；')}，请修复后重试`);
}

/**
 * 加载路径专用：归一化后切断造成环的 parentId，并记录原始 parentId。
 * 不在这里落盘，原文件仍保留在磁盘上，直到用户下一次主动保存。
 */
function normalizeForLoad(input: unknown): {
  workspace: Workspace;
  parentCycles: string[][];
  corrections: CorrectionSummary;
} {
  const { workspace, corrections } = normalizeWorkspaceWithCorrections(input);
  const parentCycles = findParentCycles(workspace);
  if (parentCycles.length === 0) return { workspace, parentCycles, corrections };

  const originalParents = new Map(workspace.items.map((item) => [item.id, item.parentId]));
  const cutIds = new Set(parentCycles.map((cycle) => cycle[cycle.length - 2]));
  console.warn('[textura] 检测到父子环，已切断 parentId；原文件未自动覆盖', {
    detectedAt: nowIso(),
    cycles: cycleLabels(workspace, parentCycles),
    cut: [...cutIds].map((id) => ({ id, parentId: originalParents.get(id) })),
  });

  return {
    workspace: {
      ...workspace,
      items: workspace.items.map((item) =>
        cutIds.has(item.id) ? { ...item, parentId: null } : item,
      ),
    },
    parentCycles,
    corrections,
  };
}

/**
 * 版本迁移 + 严格字段归一化。当前只有 v1。
 * 导入路径会拒绝父子环；load 路径请使用 normalizeForLoad 的修复语义。
 */
export function migrateWorkspaceWithReport(input: unknown): {
  workspace: Workspace;
  corrections: CorrectionSummary;
} {
  const { workspace, corrections } = normalizeWorkspaceWithCorrections(input);
  const cycles = findParentCycles(workspace);
  if (cycles.length > 0) throw parentCycleError(workspace, cycles);
  return { workspace, corrections };
}

export function migrateWorkspace(input: unknown): Workspace {
  return migrateWorkspaceWithReport(input).workspace;
}

/** 解析导入的 JSON 文本，失败时抛出带中文说明的错误。 */
export function parseWorkspaceText(text: string): Workspace {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('文件不是合法的 JSON');
  }
  const { workspace, corrections } = migrateWorkspaceWithReport(data);
  if (corrections.total > 0) pendingCorrectionReports.set(workspace, corrections);
  return workspace;
}

function loadLocalResult(): LoadedWorkspace {
  if (typeof localStorage === 'undefined') {
    return { workspace: emptyWorkspace(), freshInstall: true, parentCycles: [], corrections: emptyCorrectionSummary() };
  }
  const text = localStorage.getItem(LOCAL_STORAGE_KEY);
  if (text === null) {
    return { workspace: emptyWorkspace(), freshInstall: true, parentCycles: [], corrections: emptyCorrectionSummary() };
  }
  try {
    const prepared = normalizeForLoad(JSON.parse(text));
    return { ...prepared, freshInstall: false };
  } catch (error) {
    if (error instanceof WorkspaceVersionError) throw error;
    console.warn('[textura] localStorage 工作区无法读取，已保留原始值并回退为空库', error);
    return { workspace: emptyWorkspace(), freshInstall: false, parentCycles: [], corrections: emptyCorrectionSummary() };
  }
}

function writeLocal(ws: Workspace): SaveInfo {
  const json = JSON.stringify(ws);
  localStorage.setItem(LOCAL_STORAGE_KEY, json);
  return { savedAt: nowIso(), bytes: new TextEncoder().encode(json).length };
}

export async function loadWorkspace(): Promise<LoadedWorkspace> {
  if (isTauri()) {
    const result = await invoke<LoadResult>('load_workspace');
    return { ...normalizeForLoad(result.workspace), freshInstall: result.freshInstall };
  }
  return loadLocalResult();
}

export async function saveWorkspace(workspace: Workspace): Promise<SaveInfo> {
  if (isTauri()) return invoke<SaveInfo>('save_workspace', { workspace });
  return writeLocal(workspace);
}

/**
 * 保存一份"环修复后"的诊断副本；不触碰主文件。
 * 返回文件路径（Tauri）或浏览器预览用的 localStorage key。
 */
export async function saveRepairedWorkspace(workspace: Workspace): Promise<string> {
  if (isTauri()) {
    return invoke<string>('save_repaired_workspace', { workspace });
  }
  if (typeof localStorage === 'undefined') return '';
  localStorage.setItem(REPAIRED_LOCAL_KEY, JSON.stringify(workspace));
  return REPAIRED_LOCAL_KEY;
}

export async function storageInfo(): Promise<StorageInfo> {
  if (isTauri()) return invoke<StorageInfo>('storage_info');
  const raw = typeof localStorage === 'undefined' ? null : localStorage.getItem(LOCAL_STORAGE_KEY);
  return {
    dataDir: 'localStorage',
    workspacePath: LOCAL_STORAGE_KEY,
    backupCount: 0,
    revision: raw ? 1 : 0,
  };
}

export async function listBackups(): Promise<BackupInfo[]> {
  if (isTauri()) return invoke<BackupInfo[]>('list_backups');
  return [];
}

export async function restoreBackup(name: string): Promise<Workspace> {
  if (isTauri()) return invoke<Workspace>('restore_backup', { name });
  throw new Error(`浏览器调试模式不支持备份恢复（${name}）`);
}

export async function exportWorkspace(json: string, path: string): Promise<void> {
  if (isTauri()) {
    await invoke<void>('export_workspace', { json, path });
    return;
  }
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = path.split('/').pop() || 'textura-workspace.json';
  anchor.click();
  URL.revokeObjectURL(url);
}

export async function importWorkspace(path: string): Promise<string> {
  if (isTauri()) return invoke<string>('import_workspace', { path });
  throw new Error(`浏览器调试模式不支持按路径导入（${path}）`);
}
