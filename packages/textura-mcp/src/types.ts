export interface McpItem {
  id: string;
  kind: string;
  title: string;
  notes: string;
  status: string;
  parentId: string | null;
  areaId: string | null;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

export interface ListItemsQuery {
  kind?: string;
  status?: string;
  parentId?: string | null;
  limit?: number;
}

export interface CreateItemInput {
  kind: string;
  title: string;
  notes?: string;
  parentId?: string | null;
  status?: string;
  tags?: string[];
  areaId?: string | null;
}

export interface UpdateItemPatch {
  title?: string;
  notes?: string;
  status?: string;
  tags?: string[];
  areaId?: string | null;
  parentId?: string | null;
}

export interface CreateEdgeInput {
  from: string;
  to: string;
  type?: string;
  label?: string;
}

export interface WorkspaceStats {
  items: number;
  byKind: Record<string, number>;
  byStatus: Record<string, number>;
}

export interface TexturaBridge {
  listItems(query?: ListItemsQuery): McpItem[];
  searchItems(query: string, limit?: number): McpItem[];
  createItem(input: CreateItemInput): McpItem;
  updateItem(id: string, patch: UpdateItemPatch): McpItem | null;
  setStatus(id: string, status: string): McpItem | null;
  createEdge(input: CreateEdgeInput): { id: string };
  getStats(): WorkspaceStats;
}

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export interface ToolTextContent {
  type: 'text';
  text: string;
}

export interface ToolCallResult {
  content: ToolTextContent[];
  structuredContent?: unknown;
  isError?: boolean;
}

export interface JsonRpcRequest {
  jsonrpc: '2.0';
  id?: string | number;
  method: string;
  params?: unknown;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

export interface JsonRpcSuccessResponse {
  jsonrpc: '2.0';
  id: string | number;
  result: unknown;
}

export interface JsonRpcErrorResponse {
  jsonrpc: '2.0';
  id: string | number;
  error: JsonRpcError;
}

export type JsonRpcResponse = JsonRpcSuccessResponse | JsonRpcErrorResponse;

export interface InitializeResult {
  protocolVersion: string;
  capabilities: { tools: { listChanged: boolean } };
  serverInfo: { name: string; version: string };
}