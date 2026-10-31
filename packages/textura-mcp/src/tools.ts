import { McpError, ToolInputError } from './errors';
import type {
  CreateEdgeInput,
  CreateItemInput,
  ListItemsQuery,
  TexturaBridge,
  ToolCallResult,
  ToolDefinition,
  UpdateItemPatch,
} from './types';

export const ITEM_KINDS = [
  'objective',
  'keyresult',
  'project',
  'action',
  'sop',
  'step',
  'milestone',
  'note',
  'reference',
] as const;

export const ITEM_STATUSES = [
  'inbox',
  'next',
  'active',
  'waiting',
  'scheduled',
  'someday',
  'done',
  'dropped',
] as const;

export const EDGE_TYPES = ['okr', 'flow', 'depends', 'related'] as const;

export const MAX_LIMIT = 200;
export const DEFAULT_LIMIT = 50;

type Arguments = Record<string, unknown>;

function isRecord(value: unknown): value is Arguments {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function asArguments(value: unknown): Arguments {
  if (value === undefined || value === null) return {};
  if (!isRecord(value)) throw new ToolInputError('arguments 必须是 JSON 对象');
  return value;
}

function requireString(args: Arguments, key: string): string {
  const value = args[key];
  if (typeof value !== 'string' || value.trim() === '') {
    throw new ToolInputError(`参数 ${key} 必须是非空字符串`);
  }
  return value.trim();
}

function optionalString(args: Arguments, key: string): string | undefined {
  const value = args[key];
  if (value === undefined) return undefined;
  if (typeof value !== 'string') throw new ToolInputError(`参数 ${key} 必须是字符串`);
  return value;
}

function optionalNullableString(args: Arguments, key: string): string | null | undefined {
  const value = args[key];
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') throw new ToolInputError(`参数 ${key} 必须是字符串或 null`);
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function optionalStringArray(args: Arguments, key: string): string[] | undefined {
  const value = args[key];
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== 'string')) {
    throw new ToolInputError(`参数 ${key} 必须是字符串数组`);
  }
  return value.map((entry) => entry.trim()).filter((entry) => entry.length > 0);
}

function optionalLimit(args: Arguments): number | undefined {
  const value = args.limit;
  if (value === undefined) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new ToolInputError('参数 limit 必须是数字');
  }
  const limit = Math.trunc(value);
  if (limit < 1 || limit > MAX_LIMIT) {
    throw new ToolInputError(`参数 limit 必须在 1–${MAX_LIMIT} 之间`);
  }
  return limit;
}

function requireEnum<T extends string>(args: Arguments, key: string, allowed: readonly T[]): T {
  const value = args[key];
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw new ToolInputError(`参数 ${key} 必须是：${allowed.join(' / ')}`);
  }
  return value as T;
}

function optionalEnum<T extends string>(
  args: Arguments,
  key: string,
  allowed: readonly T[],
): T | undefined {
  if (args[key] === undefined) return undefined;
  return requireEnum(args, key, allowed);
}

function parsePatch(value: unknown): UpdateItemPatch {
  const raw = asArguments(value);
  const patch: UpdateItemPatch = {};
  if (raw.title !== undefined) patch.title = requireString(raw, 'title');
  if (raw.notes !== undefined) patch.notes = optionalString(raw, 'notes');
  if (raw.status !== undefined) patch.status = requireEnum(raw, 'status', ITEM_STATUSES);
  if (raw.tags !== undefined) patch.tags = optionalStringArray(raw, 'tags');
  if (raw.areaId !== undefined) patch.areaId = optionalNullableString(raw, 'areaId') ?? null;
  if (raw.parentId !== undefined) patch.parentId = optionalNullableString(raw, 'parentId') ?? null;
  if (Object.keys(patch).length === 0) {
    throw new ToolInputError('patch 至少需要包含一个可更新字段');
  }
  return patch;
}

function ok(value: unknown): ToolCallResult {
  return {
    content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
    structuredContent: value,
  };
}

function fail(message: string): ToolCallResult {
  return { content: [{ type: 'text', text: message }], isError: true };
}

export const TOOL_DEFINITIONS: ToolDefinition[] = [
  {
    name: 'list_items',
    description: '按类型、状态或父级列出工作区事项，最多返回 200 条。',
    inputSchema: {
      type: 'object',
      properties: {
        kind: { type: 'string', enum: ITEM_KINDS },
        status: { type: 'string', enum: ITEM_STATUSES },
        parentId: { type: ['string', 'null'], description: '传 null 只看顶层事项' },
        limit: { type: 'number', minimum: 1, maximum: MAX_LIMIT },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'search_items',
    description: '在标题、备注与标签中搜索关键词，返回匹配事项。',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', minLength: 1 },
        limit: { type: 'number', minimum: 1, maximum: MAX_LIMIT },
      },
      required: ['query'],
      additionalProperties: false,
    },
  },
  {
    name: 'create_item',
    description: '在工作区新增一个事项（目标、关键结果、项目、行动、SOP 步骤等）。',
    inputSchema: {
      type: 'object',
      properties: {
        kind: { type: 'string', enum: ITEM_KINDS },
        title: { type: 'string', minLength: 1 },
        notes: { type: 'string' },
        parentId: { type: ['string', 'null'] },
        status: { type: 'string', enum: ITEM_STATUSES },
        tags: { type: 'array', items: { type: 'string' } },
        areaId: { type: ['string', 'null'] },
      },
      required: ['kind', 'title'],
      additionalProperties: false,
    },
  },
  {
    name: 'update_item',
    description: '更新已有事项的标题、备注、状态、标签、领域或父级。',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', minLength: 1 },
        patch: {
          type: 'object',
          properties: {
            title: { type: 'string', minLength: 1 },
            notes: { type: 'string' },
            status: { type: 'string', enum: ITEM_STATUSES },
            tags: { type: 'array', items: { type: 'string' } },
            areaId: { type: ['string', 'null'] },
            parentId: { type: ['string', 'null'] },
          },
          additionalProperties: false,
        },
      },
      required: ['id', 'patch'],
      additionalProperties: false,
    },
  },
  {
    name: 'set_status',
    description: '设置事项状态；切到 done 时同步完成时间，切离 done 时清空完成时间。',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', minLength: 1 },
        status: { type: 'string', enum: ITEM_STATUSES },
      },
      required: ['id', 'status'],
      additionalProperties: false,
    },
  },
  {
    name: 'link_items',
    description: '在两个事项之间建立关联边（OKR 对齐、流程、依赖或普通关联）。',
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', minLength: 1 },
        to: { type: 'string', minLength: 1 },
        type: { type: 'string', enum: EDGE_TYPES },
        label: { type: 'string' },
      },
      required: ['from', 'to'],
      additionalProperties: false,
    },
  },
  {
    name: 'get_stats',
    description: '统计工作区事项总数，以及按类型、状态的分布。',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
  },
];

export function listToolDefinitions(): ToolDefinition[] {
  return TOOL_DEFINITIONS.map((tool) => ({
    ...tool,
    inputSchema: { ...tool.inputSchema },
  }));
}

export function callTool(
  bridge: TexturaBridge,
  name: string,
  rawArguments?: unknown,
): ToolCallResult {
  const known = TOOL_DEFINITIONS.some((tool) => tool.name === name);
  if (!known) throw new McpError(-32602, `未知工具：${name}`);

  try {
    const args = asArguments(rawArguments);
    switch (name) {
      case 'list_items': {
        const query: ListItemsQuery = {};
        const kind = optionalEnum(args, 'kind', ITEM_KINDS);
        if (kind) query.kind = kind;
        const status = optionalEnum(args, 'status', ITEM_STATUSES);
        if (status) query.status = status;
        const parentId = optionalNullableString(args, 'parentId');
        if (parentId !== undefined) query.parentId = parentId;
        const limit = optionalLimit(args);
        if (limit !== undefined) query.limit = limit;
        const items = bridge.listItems(query);
        return ok({ count: items.length, items });
      }
      case 'search_items': {
        const query = requireString(args, 'query');
        const items = bridge.searchItems(query, optionalLimit(args) ?? DEFAULT_LIMIT);
        return ok({ count: items.length, items });
      }
      case 'create_item': {
        const input: CreateItemInput = {
          kind: requireEnum(args, 'kind', ITEM_KINDS),
          title: requireString(args, 'title'),
        };
        const notes = optionalString(args, 'notes');
        if (notes !== undefined) input.notes = notes;
        const parentId = optionalNullableString(args, 'parentId');
        if (parentId !== undefined) input.parentId = parentId;
        const status = optionalEnum(args, 'status', ITEM_STATUSES);
        if (status !== undefined) input.status = status;
        const tags = optionalStringArray(args, 'tags');
        if (tags !== undefined) input.tags = tags;
        const areaId = optionalNullableString(args, 'areaId');
        if (areaId !== undefined) input.areaId = areaId;
        return ok({ item: bridge.createItem(input) });
      }
      case 'update_item': {
        const id = requireString(args, 'id');
        const item = bridge.updateItem(id, parsePatch(args.patch));
        if (!item) return fail(`未找到事项：${id}`);
        return ok({ item });
      }
      case 'set_status': {
        const id = requireString(args, 'id');
        const status = requireEnum(args, 'status', ITEM_STATUSES);
        const item = bridge.setStatus(id, status);
        if (!item) return fail(`未找到事项：${id}`);
        return ok({ item });
      }
      case 'link_items': {
        const input: CreateEdgeInput = {
          from: requireString(args, 'from'),
          to: requireString(args, 'to'),
        };
        const type = optionalEnum(args, 'type', EDGE_TYPES);
        if (type !== undefined) input.type = type;
        const label = optionalString(args, 'label');
        if (label !== undefined) input.label = label;
        return ok({ edge: bridge.createEdge(input) });
      }
      case 'get_stats':
      default:
        return ok({ stats: bridge.getStats() });
    }
  } catch (error) {
    if (error instanceof ToolInputError) return fail(error.message);
    return fail(error instanceof Error ? error.message : String(error));
  }
}