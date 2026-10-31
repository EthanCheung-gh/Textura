import { describe, expect, it } from 'vitest';
import { createInProcessClient } from './client';
import { TexturaMcpServer } from './server';
import type {
  CreateEdgeInput,
  CreateItemInput,
  ListItemsQuery,
  McpItem,
  TexturaBridge,
  UpdateItemPatch,
} from './types';

function createFakeBridge(): TexturaBridge {
  const items = new Map<string, McpItem>();
  const edges: Array<{ id: string; from: string; to: string; type: string; label: string }> = [];
  let itemSeq = 0;
  let edgeSeq = 0;

  const update = (id: string, patch: UpdateItemPatch): McpItem | null => {
    const current = items.get(id);
    if (!current) return null;
    const next: McpItem = {
      ...current,
      ...patch,
      tags: patch.tags ? [...patch.tags] : current.tags,
      updatedAt: '2026-01-01T00:00:01.000Z',
    };
    items.set(id, next);
    return next;
  };

  return {
    listItems(query: ListItemsQuery = {}) {
      let list = [...items.values()];
      if (query.kind) list = list.filter((item) => item.kind === query.kind);
      if (query.status) list = list.filter((item) => item.status === query.status);
      if (query.parentId !== undefined) {
        list = list.filter((item) => item.parentId === query.parentId);
      }
      return list.slice(0, query.limit ?? 50);
    },
    searchItems(query, limit = 50) {
      const needle = query.trim().toLowerCase();
      if (!needle) return [];
      return [...items.values()]
        .filter(
          (item) =>
            item.title.toLowerCase().includes(needle) ||
            item.notes.toLowerCase().includes(needle) ||
            item.tags.some((tag) => tag.toLowerCase().includes(needle)),
        )
        .slice(0, limit);
    },
    createItem(input: CreateItemInput) {
      itemSeq += 1;
      const item: McpItem = {
        id: `item-${itemSeq}`,
        kind: input.kind,
        title: input.title,
        notes: input.notes ?? '',
        status: input.status ?? 'next',
        parentId: input.parentId ?? null,
        areaId: input.areaId ?? null,
        tags: input.tags ?? [],
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      };
      items.set(item.id, item);
      return item;
    },
    updateItem: update,
    setStatus(id, status) {
      return update(id, { status });
    },
    createEdge(input: CreateEdgeInput) {
      edgeSeq += 1;
      const edge = {
        id: `edge-${edgeSeq}`,
        from: input.from,
        to: input.to,
        type: input.type ?? 'related',
        label: input.label ?? '',
      };
      edges.push(edge);
      return { id: edge.id };
    },
    getStats() {
      const all = [...items.values()];
      const byKind: Record<string, number> = {};
      const byStatus: Record<string, number> = {};
      for (const item of all) {
        byKind[item.kind] = (byKind[item.kind] ?? 0) + 1;
        byStatus[item.status] = (byStatus[item.status] ?? 0) + 1;
      }
      return { items: all.length, byKind, byStatus };
    },
  };
}

function createServer(): TexturaMcpServer {
  return new TexturaMcpServer(createFakeBridge());
}

function toolText(result: unknown): string {
  const content = (result as { content: Array<{ text: string }> }).content;
  return content[0].text;
}

describe('TexturaMcpServer', () => {
  it('initialize 返回协议版本与服务信息', () => {
    const server = createServer();
    const response = server.handle({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    expect(response).not.toBeNull();
    if (!response || 'error' in response) throw new Error('initialize 失败');
    expect(response.result).toMatchObject({
      protocolVersion: '2024-11-05',
      serverInfo: { name: 'textura-mcp', version: '0.1.0' },
      capabilities: { tools: { listChanged: false } },
    });
  });

  it('通知不产生响应', () => {
    const server = createServer();
    expect(
      server.handle({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }),
    ).toBeNull();
  });

  it('tools/list 暴露全部内置工具', () => {
    const server = createServer();
    const response = server.handle({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} });
    if (!response || 'error' in response) throw new Error('tools/list 失败');
    const tools = (response.result as { tools: Array<{ name: string }> }).tools;
    expect(tools.map((tool) => tool.name)).toEqual([
      'list_items',
      'search_items',
      'create_item',
      'update_item',
      'set_status',
      'link_items',
      'get_stats',
    ]);
  });

  it('tools/call 可以新增事项并搜索到', () => {
    const server = createServer();
    const created = server.handle({
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: {
        name: 'create_item',
        arguments: { kind: 'action', title: '整理季度复盘', tags: ['复盘'], status: 'next' },
      },
    });
    if (!created || 'error' in created) throw new Error('create_item 失败');
    expect(created.result).not.toHaveProperty('isError');
    expect(toolText(created.result)).toContain('整理季度复盘');

    const searched = server.handle({
      jsonrpc: '2.0',
      id: 4,
      method: 'tools/call',
      params: { name: 'search_items', arguments: { query: '复盘' } },
    });
    if (!searched || 'error' in searched) throw new Error('search_items 失败');
    expect(toolText(searched.result)).toContain('item-1');
  });

  it('tools/call 参数非法时返回 isError', () => {
    const server = createServer();
    const response = server.handle({
      jsonrpc: '2.0',
      id: 5,
      method: 'tools/call',
      params: { name: 'create_item', arguments: { kind: 'action' } },
    });
    if (!response || 'error' in response) throw new Error('调用失败');
    expect(response.result).toMatchObject({ isError: true });
    expect(toolText(response.result)).toContain('title');
  });

  it('未知工具返回 JSON-RPC -32602', () => {
    const server = createServer();
    const response = server.handle({
      jsonrpc: '2.0',
      id: 6,
      method: 'tools/call',
      params: { name: 'drop_database', arguments: {} },
    });
    expect(response).toMatchObject({ error: { code: -32602 } });
  });

  it('update_item 与 set_status 更新已有事项', () => {
    const server = createServer();
    server.handle({
      jsonrpc: '2.0',
      id: 7,
      method: 'tools/call',
      params: { name: 'create_item', arguments: { kind: 'action', title: '写周报' } },
    });
    const updated = server.handle({
      jsonrpc: '2.0',
      id: 8,
      method: 'tools/call',
      params: { name: 'update_item', arguments: { id: 'item-1', patch: { title: '写月报' } } },
    });
    if (!updated || 'error' in updated) throw new Error('update_item 失败');
    expect(toolText(updated.result)).toContain('写月报');

    const status = server.handle({
      jsonrpc: '2.0',
      id: 9,
      method: 'tools/call',
      params: { name: 'set_status', arguments: { id: 'item-1', status: 'done' } },
    });
    if (!status || 'error' in status) throw new Error('set_status 失败');
    expect(toolText(status.result)).toContain('"status": "done"');
  });

  it('link_items 与 get_stats 可用', () => {
    const server = createServer();
    server.handle({
      jsonrpc: '2.0',
      id: 10,
      method: 'tools/call',
      params: { name: 'create_item', arguments: { kind: 'objective', title: 'O1' } },
    });
    const linked = server.handle({
      jsonrpc: '2.0',
      id: 11,
      method: 'tools/call',
      params: { name: 'link_items', arguments: { from: 'item-1', to: 'item-1' } },
    });
    if (!linked || 'error' in linked) throw new Error('link_items 失败');
    expect(toolText(linked.result)).toContain('"id": "edge-1"');

    const stats = server.handle({
      jsonrpc: '2.0',
      id: 12,
      method: 'tools/call',
      params: { name: 'get_stats', arguments: {} },
    });
    if (!stats || 'error' in stats) throw new Error('get_stats 失败');
    expect(toolText(stats.result)).toContain('"items": 1');
  });
});

describe('createInProcessClient', () => {
  it('可以在进程内完成 initialize / listTools / callTool', async () => {
    const client = createInProcessClient(createServer());
    const initialized = await client.initialize();
    expect(initialized.serverInfo.name).toBe('textura-mcp');
    expect((await client.listTools()).length).toBe(7);
    const result = await client.callTool('create_item', { kind: 'note', title: '想法' });
    expect(result.structuredContent).toMatchObject({ item: { title: '想法' } });
  });

  it('未知方法抛出 McpError', async () => {
    const client = createInProcessClient(createServer());
    await expect(client.request('resources/list', {})).rejects.toMatchObject({ code: -32601 });
  });
});