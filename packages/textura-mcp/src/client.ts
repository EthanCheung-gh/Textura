import { McpError } from './errors';
import type { TexturaMcpServer } from './server';
import type {
  InitializeResult,
  JsonRpcResponse,
  ToolCallResult,
  ToolDefinition,
} from './types';

export interface McpClient {
  initialize(params?: Record<string, unknown>): Promise<InitializeResult>;
  listTools(): Promise<ToolDefinition[]>;
  callTool(name: string, args?: Record<string, unknown>): Promise<ToolCallResult>;
  request<T = unknown>(method: string, params?: unknown): Promise<T>;
}

export function createInProcessClient(server: TexturaMcpServer): McpClient {
  let nextId = 1;

  const send = (method: string, params?: unknown): JsonRpcResponse => {
    const id = nextId;
    nextId += 1;
    const response = server.handle({ jsonrpc: '2.0', id, method, params });
    if (!response) throw new McpError(-32603, `方法 ${method} 未返回响应`);
    return response;
  };

  const request = async <T = unknown>(method: string, params?: unknown): Promise<T> => {
    const response = send(method, params);
    if ('error' in response) throw new McpError(response.error.code, response.error.message);
    return response.result as T;
  };

  return {
    request,
    initialize: (params = {}) =>
      request<InitializeResult>('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'textura-builtin', version: '0.1.0' },
        ...params,
      }),
    listTools: async () => {
      const result = await request<{ tools: ToolDefinition[] }>('tools/list', {});
      return result.tools;
    },
    callTool: (name, args = {}) =>
      request<ToolCallResult>('tools/call', { name, arguments: args }),
  };
}