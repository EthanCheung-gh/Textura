import { McpError } from './errors';
import { callTool, listToolDefinitions } from './tools';
import type {
  InitializeResult,
  JsonRpcRequest,
  JsonRpcResponse,
  TexturaBridge,
} from './types';

export const MCP_PROTOCOL_VERSION = '2024-11-05';
export const MCP_SERVER_NAME = 'textura-mcp';
export const MCP_SERVER_VERSION = '0.1.0';

export interface TexturaMcpServerOptions {
  name?: string;
  version?: string;
}

function success(id: string | number, result: unknown): JsonRpcResponse {
  return { jsonrpc: '2.0', id, result };
}

function failure(id: string | number, code: number, message: string): JsonRpcResponse {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

export class TexturaMcpServer {
  private readonly bridge: TexturaBridge;
  private readonly name: string;
  private readonly version: string;

  constructor(bridge: TexturaBridge, options: TexturaMcpServerOptions = {}) {
    this.bridge = bridge;
    this.name = options.name ?? MCP_SERVER_NAME;
    this.version = options.version ?? MCP_SERVER_VERSION;
  }

  get serverInfo(): { name: string; version: string } {
    return { name: this.name, version: this.version };
  }

  listTools() {
    return listToolDefinitions();
  }

  handle(request: JsonRpcRequest): JsonRpcResponse | null {
    if (request.id === undefined) return null;
    if (request.jsonrpc !== '2.0' || typeof request.method !== 'string') {
      return failure(request.id, -32600, 'Invalid Request');
    }

    try {
      switch (request.method) {
        case 'initialize': {
          const result: InitializeResult = {
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: { tools: { listChanged: false } },
            serverInfo: this.serverInfo,
          };
          return success(request.id, result);
        }
        case 'ping':
          return success(request.id, {});
        case 'tools/list':
          return success(request.id, { tools: this.listTools() });
        case 'tools/call': {
          const params = request.params;
          if (!params || typeof params !== 'object' || Array.isArray(params)) {
            throw new McpError(-32602, 'tools/call 缺少 params 对象');
          }
          const { name, arguments: toolArguments } = params as {
            name?: unknown;
            arguments?: unknown;
          };
          if (typeof name !== 'string' || name.trim() === '') {
            throw new McpError(-32602, 'tools/call 缺少工具名');
          }
          return success(request.id, callTool(this.bridge, name, toolArguments));
        }
        default:
          return failure(request.id, -32601, `未知方法：${request.method}`);
      }
    } catch (error) {
      if (error instanceof McpError) {
        return failure(request.id, error.code, error.message);
      }
      return failure(
        request.id,
        -32603,
        error instanceof Error ? error.message : String(error),
      );
    }
  }
}