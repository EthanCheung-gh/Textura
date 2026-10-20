/**
 * SOP 执行推进的纯函数层：单出边直行、多出边分支、无出边结束、运行统计。
 * 不依赖 store / React，便于单测。
 */
import type { SopNodeType } from '../../core/model';

export type RunResult = 'pass' | 'fail' | 'skip';

export interface FlowEdgeLike {
  id: string;
  from: string;
  to: string;
  label?: string;
}

export interface StepLike {
  id: string;
  nodeType?: SopNodeType;
}

export interface BranchOption {
  edgeId: string;
  to: string;
  label: string;
}

export type AdvanceResult =
  | { status: 'next'; stepId: string; viaEdgeId: string }
  | { status: 'branch'; options: BranchOption[] }
  | { status: 'end' };

/** 当前步骤的所有出边（按 edges 原顺序，保证分支选项稳定）。 */
export function nextCandidates(stepId: string, edges: readonly FlowEdgeLike[]): FlowEdgeLike[] {
  return edges.filter((edge) => edge.from === stepId);
}

/**
 * 起点：优先 `start` 节点；否则取入度为 0 的第一个节点；都没有时退化为第一个节点。
 */
export function startStepId(steps: readonly StepLike[], edges: readonly FlowEdgeLike[]): string | null {
  const start = steps.find((step) => step.nodeType === 'start');
  if (start) return start.id;
  const withIncoming = new Set(edges.map((edge) => edge.to));
  const root = steps.find((step) => !withIncoming.has(step.id));
  if (root) return root.id;
  return steps[0]?.id ?? null;
}

export interface AdvanceInput {
  /** 刚记录结果的步骤 */
  stepId: string;
  edges: readonly FlowEdgeLike[];
  result: RunResult;
  /** 分支选择：选中的边 id；仅多出边时使用 */
  choice?: string | null;
  /** 已访问步骤，用于把未走过的分支排在前面 */
  visited?: readonly string[];
}

/**
 * 结果记录后的推进：
 * - 无出边 → 结束；
 * - 单出边 → 直接进入目标；
 * - 多出边 → 未指定 choice 时返回分支选项；指定了合法 choice 时进入对应目标。
 *
 * 通过 / 未通过 / 跳过都按流程前进；「未通过」的语义交给分支选择与运行历史。
 */
export function advance(input: AdvanceInput): AdvanceResult {
  const candidates = nextCandidates(input.stepId, input.edges);
  if (candidates.length === 0) return { status: 'end' };

  if (candidates.length === 1) {
    const edge = candidates[0];
    return { status: 'next', stepId: edge.to, viaEdgeId: edge.id };
  }

  if (input.choice) {
    const chosen = candidates.find((edge) => edge.id === input.choice);
    if (chosen) return { status: 'next', stepId: chosen.to, viaEdgeId: chosen.id };
  }

  const visited = new Set(input.visited ?? []);
  const options: BranchOption[] = candidates.map((edge) => ({
    edgeId: edge.id,
    to: edge.to,
    label: edge.label ?? '',
  }));
  // 稳定排序：未访问的分支优先，其余保持原顺序。
  options.sort((a, b) => Number(visited.has(a.to)) - Number(visited.has(b.to)));
  return { status: 'branch', options };
}

export interface RunStats {
  pass: number;
  fail: number;
  skip: number;
  total: number;
}

export function summarizeResults(results: readonly RunResult[]): RunStats {
  const stats: RunStats = { pass: 0, fail: 0, skip: 0, total: results.length };
  for (const result of results) stats[result] += 1;
  return stats;
}

/** 两个 ISO 时间之间的分钟数（不小于 0，四舍五入到整数）。 */
export function elapsedMinutes(startISO: string, endISO: string): number {
  const start = new Date(startISO).getTime();
  const end = new Date(endISO).getTime();
  if (Number.isNaN(start) || Number.isNaN(end)) return 0;
  return Math.max(0, Math.round((end - start) / 60000));
}
