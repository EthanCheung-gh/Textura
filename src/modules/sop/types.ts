import type { RunResult } from './runLogic';

/** 画布选中态（节点 / 连线），与 store 的 selectedId（条目选中）互不干扰。 */
export type SopSelection =
  | { kind: 'node'; id: string }
  | { kind: 'edge'; id: string }
  | null;

/** 一次运行会话。产生于「运行」按钮，结束于流程终点或手动退出。 */
export interface RunSession {
  currentId: string;
  visited: string[];
  failed: string[];
  startedAt: string;
  results: RunResult[];
}
