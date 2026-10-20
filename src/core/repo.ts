/**
 * 持久化适配层。
 * - Tauri：调用 Rust 命令（单文档原子写 + 轮换备份）
 * - 浏览器（无 __TAURI_INTERNALS__）：降级到 localStorage，保证 vite preview 可调试
 */
import type { Workspace } from './model';
import { WORKSPACE_VERSION } from './model';
import { nowIso } from './utils';

export const LOCAL_STORAGE_KEY = 'textura.workspace.v1';

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

/**
 * 版本迁移 + 反序列化兜底。当前只有 v1，
 * 但保留迁移入口，未来版本在此逐级 upgrade。
 */
export function migrateWorkspace(input: unknown): Workspace {
  if (!input || typeof input !== 'object') throw new Error('工作区数据不是对象');
  const raw = input as Partial<Workspace> & Record<string, unknown>;
  let version = typeof raw.version === 'number' ? raw.version : 0;

  if (version > WORKSPACE_VERSION) {
    throw new Error(`工作区版本 ${version} 高于当前支持的版本 ${WORKSPACE_VERSION}`);
  }

  // v0 -> v1：历史版本没有结构差异，仅补齐缺失集合。
  if (version < 1) {
    raw.edges ??= [];
    raw.areas ??= [];
    raw.runs ??= [];
    version = 1;
  }

  const items = Array.isArray(raw.items) ? raw.items : [];
  return {
    version: WORKSPACE_VERSION,
    items: items.map((item, index) => normalizeItem(item, index)),
    edges: Array.isArray(raw.edges) ? raw.edges : [],
    areas: Array.isArray(raw.areas) ? raw.areas : [],
    runs: Array.isArray(raw.runs) ? raw.runs : [],
    updatedAt: typeof raw.updatedAt === 'string' ? raw.updatedAt : nowIso(),
  };
}

function normalizeItem(input: unknown, index: number): Workspace['items'][number] {
  const item = (input ?? {}) as Record<string, unknown>;
  const now = nowIso();
  return {
    id: typeof item.id === 'string' ? item.id : `i_recovered_${index}`,
    kind: (item.kind as Workspace['items'][number]['kind']) ?? 'note',
    title: typeof item.title === 'string' ? item.title : '未命名条目',
    notes: typeof item.notes === 'string' ? item.notes : '',
    parentId: typeof item.parentId === 'string' ? item.parentId : null,
    order: typeof item.order === 'number' ? item.order : index,
    status: (item.status as Workspace['items'][number]['status']) ?? 'next',
    tags: Array.isArray(item.tags) ? (item.tags as string[]) : [],
    areaId: typeof item.areaId === 'string' ? item.areaId : null,
    createdAt: typeof item.createdAt === 'string' ? item.createdAt : now,
    updatedAt: typeof item.updatedAt === 'string' ? item.updatedAt : now,
    completedAt: typeof item.completedAt === 'string' ? item.completedAt : null,
    okr: item.okr as Workspace['items'][number]['okr'],
    sop: item.sop as Workspace['items'][number]['sop'],
    gtd: item.gtd as Workspace['items'][number]['gtd'],
    gantt: item.gantt as Workspace['items'][number]['gantt'],
  };
}

/** 解析导入的 JSON 文本，失败时抛出带中文说明的错误。 */
export function parseWorkspaceText(text: string): Workspace {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('文件不是合法的 JSON');
  }
  return migrateWorkspace(data);
}

function readLocal(): Workspace | null {
  if (typeof localStorage === 'undefined') return null;
  const text = localStorage.getItem(LOCAL_STORAGE_KEY);
  if (!text) return null;
  try {
    return migrateWorkspace(JSON.parse(text));
  } catch (error) {
    console.warn('[textura] localStorage 工作区损坏，已回退为空库', error);
    return null;
  }
}

function writeLocal(ws: Workspace): SaveInfo {
  const json = JSON.stringify(ws);
  localStorage.setItem(LOCAL_STORAGE_KEY, json);
  return { savedAt: nowIso(), bytes: new TextEncoder().encode(json).length };
}

export async function loadWorkspace(): Promise<Workspace> {
  if (isTauri()) return invoke<Workspace>('load_workspace');
  return readLocal() ?? emptyWorkspace();
}

export async function saveWorkspace(workspace: Workspace): Promise<SaveInfo> {
  if (isTauri()) return invoke<SaveInfo>('save_workspace', { workspace });
  return writeLocal(workspace);
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
