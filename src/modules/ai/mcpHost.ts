import { createInProcessClient, TexturaMcpServer } from '@textura/mcp';
import type { McpClient } from '@textura/mcp';
import { createWorkspaceBridge } from './workspaceBridge';

export interface BuiltinMcpRuntime {
  server: TexturaMcpServer;
  client: McpClient;
}

let runtime: BuiltinMcpRuntime | null = null;

export function getBuiltinMcp(): BuiltinMcpRuntime {
  if (!runtime) {
    const server = new TexturaMcpServer(createWorkspaceBridge());
    runtime = { server, client: createInProcessClient(server) };
  }
  return runtime;
}

declare global {
  interface Window {
    __texturaMcp?: BuiltinMcpRuntime;
  }
}

export function installBuiltinMcpOnWindow(): BuiltinMcpRuntime {
  const next = getBuiltinMcp();
  if (typeof window !== 'undefined') window.__texturaMcp = next;
  return next;
}