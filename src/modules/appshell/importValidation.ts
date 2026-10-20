/**
 * 导入文件的形状校验与确认摘要（纯函数，便于单测）。
 *
 * `parseWorkspaceText` 对缺失字段非常宽容：`{"foo":1}` 会被迁移成空工作区。
 * 导入是破坏性操作，这里先要求文件至少包含一个工作区集合字段，避免误把
 * 任意 JSON 当成空工作区整份替换。
 */
import type { Workspace } from '../../core/model';
import { parseWorkspaceText } from '../../core/repo';

const COLLECTIONS = ['items', 'edges', 'areas', 'runs'] as const;

export interface ImportSummary {
  items: number;
  areas: number;
  edges: number;
  runs: number;
  version: number;
}

/** 文件是否看起来像 Textura 工作区（字段存在时类型必须正确）。 */
export function isWorkspaceShape(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const raw = value as Record<string, unknown>;
  const present = COLLECTIONS.filter((key) => key in raw);
  if (present.length === 0) return false;
  if (present.some((key) => !Array.isArray(raw[key]))) return false;
  if ('version' in raw && typeof raw.version !== 'number') return false;
  if ('updatedAt' in raw && typeof raw.updatedAt !== 'string') return false;
  return true;
}

/** 解析 + 形状校验 + 版本迁移；错误信息可直接展示给用户。 */
export function parseImportText(text: string): Workspace {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new Error('文件不是合法的 JSON');
  }
  if (!isWorkspaceShape(raw)) {
    throw new Error('不是 Textura 工作区文件：缺少 items / areas / runs 等集合字段');
  }
  return parseWorkspaceText(text);
}

/** 二次确认弹窗里的摘要。 */
export function summarizeImport(workspace: Workspace): ImportSummary {
  return {
    items: workspace.items.length,
    areas: workspace.areas.length,
    edges: workspace.edges.length,
    runs: workspace.runs.length,
    version: workspace.version,
  };
}
