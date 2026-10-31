import { ITEM_KINDS, ITEM_STATUSES } from '../../core/model';
import type {
  Edge,
  EdgeType,
  Item,
  ItemKind,
  ItemPatch,
  ItemStatus,
  NewItemInput,
  Workspace,
} from '../../core/model';
import { getWorkspace } from '../../core/store';
import type {
  CreateItemInput,
  ListItemsQuery,
  McpItem,
  TexturaBridge,
  UpdateItemPatch,
} from '@textura/mcp';
import { DEFAULT_LIMIT, MAX_LIMIT } from '@textura/mcp';

const EDGE_TYPES: EdgeType[] = ['okr', 'flow', 'depends', 'related'];

export interface WorkspaceAccess {
  workspace: Workspace;
  createItem(input: NewItemInput): Item;
  updateItem(id: string, patch: ItemPatch): void;
  setStatus(id: string, status: ItemStatus): void;
  createEdge(input: { from: string; to: string; type: EdgeType; label?: string }): Edge;
}

function isItemKind(value: string): value is ItemKind {
  return (ITEM_KINDS as readonly string[]).includes(value);
}

function isItemStatus(value: string): value is ItemStatus {
  return (ITEM_STATUSES as readonly string[]).includes(value);
}

function isEdgeType(value: string): value is EdgeType {
  return (EDGE_TYPES as readonly string[]).includes(value);
}

function clampLimit(limit: number | undefined): number {
  if (limit === undefined || !Number.isFinite(limit)) return DEFAULT_LIMIT;
  return Math.min(MAX_LIMIT, Math.max(1, Math.trunc(limit)));
}

function toMcpItem(item: Item): McpItem {
  return {
    id: item.id,
    kind: item.kind,
    title: item.title,
    notes: item.notes,
    status: item.status,
    parentId: item.parentId,
    areaId: item.areaId,
    tags: [...item.tags],
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
  };
}

function matchesSearch(item: Item, needle: string): boolean {
  if (item.title.toLowerCase().includes(needle)) return true;
  if (item.notes.toLowerCase().includes(needle)) return true;
  return item.tags.some((tag) => tag.toLowerCase().includes(needle));
}

export function createWorkspaceBridge(
  getAccess: () => WorkspaceAccess = getWorkspace,
): TexturaBridge {
  return {
    listItems(query: ListItemsQuery = {}) {
      let items = getAccess().workspace.items;
      if (query.kind) items = items.filter((item) => item.kind === query.kind);
      if (query.status) items = items.filter((item) => item.status === query.status);
      if (query.parentId !== undefined) {
        items = items.filter((item) => item.parentId === query.parentId);
      }
      return items.slice(0, clampLimit(query.limit)).map(toMcpItem);
    },

    searchItems(query: string, limit?: number) {
      const needle = query.trim().toLowerCase();
      if (!needle) return [];
      return getAccess()
        .workspace.items.filter((item) => matchesSearch(item, needle))
        .slice(0, clampLimit(limit))
        .map(toMcpItem);
    },

    createItem(input: CreateItemInput) {
      if (!isItemKind(input.kind)) throw new Error(`未知的事项类型：${input.kind}`);
      if (input.status !== undefined && !isItemStatus(input.status)) {
        throw new Error(`未知的事项状态：${input.status}`);
      }
      const status = input.status as ItemStatus | undefined;
      const created = getAccess().createItem({
        kind: input.kind,
        title: input.title,
        notes: input.notes,
        parentId: input.parentId,
        status,
        tags: input.tags,
        areaId: input.areaId,
      });
      return toMcpItem(created);
    },

    updateItem(id: string, patch: UpdateItemPatch) {
      const access = getAccess();
      if (!access.workspace.items.some((item) => item.id === id)) return null;
      const next: ItemPatch = {};
      if (patch.title !== undefined) next.title = patch.title;
      if (patch.notes !== undefined) next.notes = patch.notes;
      if (patch.status !== undefined) {
        const status = patch.status;
        if (!isItemStatus(status)) throw new Error(`未知的事项状态：${status}`);
        next.status = status;
      }
      if (patch.tags !== undefined) next.tags = [...patch.tags];
      if (patch.areaId !== undefined) next.areaId = patch.areaId;
      if (patch.parentId !== undefined) next.parentId = patch.parentId;
      access.updateItem(id, next);
      const updated = access.workspace.items.find((item) => item.id === id);
      return updated ? toMcpItem(updated) : null;
    },

    setStatus(id: string, status: string) {
      const access = getAccess();
      if (!access.workspace.items.some((item) => item.id === id)) return null;
      if (!isItemStatus(status)) throw new Error(`未知的事项状态：${status}`);
      access.setStatus(id, status);
      const updated = access.workspace.items.find((item) => item.id === id);
      return updated ? toMcpItem(updated) : null;
    },

    createEdge(input) {
      const type = input.type ?? 'related';
      if (!isEdgeType(type)) throw new Error(`未知的关联类型：${type}`);
      const edge = getAccess().createEdge({
        from: input.from,
        to: input.to,
        type,
        label: input.label,
      });
      return { id: edge.id };
    },

    getStats() {
      const items = getAccess().workspace.items;
      const byKind: Record<string, number> = {};
      const byStatus: Record<string, number> = {};
      for (const item of items) {
        byKind[item.kind] = (byKind[item.kind] ?? 0) + 1;
        byStatus[item.status] = (byStatus[item.status] ?? 0) + 1;
      }
      return { items: items.length, byKind, byStatus };
    },
  };
}