/**
 * 工作区历史栈（快照式 undo/redo）。
 * 快照由调用方负责深拷贝；默认上限 80 步。
 */

export const DEFAULT_HISTORY_LIMIT = 80;

export interface History<T> {
  /** 写操作前记录当前状态 */
  record(current: T): void;
  /** 返回上一个状态；无历史时返回 null */
  undo(current: T): T | null;
  /** 返回被撤销的状态；无重做时返回 null */
  redo(current: T): T | null;
  canUndo(): boolean;
  canRedo(): boolean;
  /** 仅清空重做栈，保留撤销历史 */
  clearRedo(): void;
  clear(): void;
  size(): number;
  limit: number;
}

export function createHistory<T>(limit: number = DEFAULT_HISTORY_LIMIT): History<T> {
  let past: T[] = [];
  let future: T[] = [];

  return {
    limit,
    record(current: T) {
      past.push(current);
      if (past.length > limit) past = past.slice(past.length - limit);
      future = [];
    },
    undo(current: T): T | null {
      const previous = past.pop();
      if (previous === undefined) return null;
      future.push(current);
      if (future.length > limit) future = future.slice(future.length - limit);
      return previous;
    },
    redo(current: T): T | null {
      const next = future.pop();
      if (next === undefined) return null;
      past.push(current);
      if (past.length > limit) past = past.slice(past.length - limit);
      return next;
    },
    canUndo() {
      return past.length > 0;
    },
    canRedo() {
      return future.length > 0;
    },
    clearRedo() {
      future = [];
    },
    clear() {
      past = [];
      future = [];
    },
    size() {
      return past.length;
    },
  };
}
